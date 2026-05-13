import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';

/// Chat State 持久化服务
/// 管理 messages、context_items、summaries 三张表
/// 参考 Python db/chat_history.py
class ChatStateService {
  static final ChatStateService instance = ChatStateService._();
  ChatStateService._();

  final _db = DatabaseHelper.instance;
  static const _uuid = Uuid();

  // ==================== Chat CRUD ====================

  /// 创建一个新的 chat 会话
  Future<String> createChat({
    required String name,
    String scenePromptId = 'empty',
    String senderId = 'empty',
    List<String> roleSettingPromptIds = const [],
    String modeId = 'ensemble',
    String roleName = '',
  }) async {
    final chatId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await _db.insert('chats', {
      'id': chatId,
      'name': name,
      'status': 'active',
      'scene_prompt_id': scenePromptId,
      'sender_id': senderId,
      'role_setting_prompt_ids_json': jsonEncode(roleSettingPromptIds),
      'mode_id': modeId,
      'role_name': roleName,
      'last_compaction_at': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    });
    return chatId;
  }

  /// 获取所有活跃 chat
  Future<List<Map<String, dynamic>>> listChats() async {
    return await _db.query(
      'chats',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );
  }

  /// 获取单个 chat
  Future<Map<String, dynamic>?> getChat(String chatId) async {
    final results = await _db.query(
      'chats',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [chatId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// 更新 chat 设置（场景、角色、发送者）
  Future<void> updateChatSettings({
    required String chatId,
    String? scenePromptId,
    String? senderId,
    List<String>? roleSettingPromptIds,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().millisecondsSinceEpoch / 1000,
    };
    if (scenePromptId != null) updates['scene_prompt_id'] = scenePromptId;
    if (senderId != null) updates['sender_id'] = senderId;
    if (roleSettingPromptIds != null) {
      updates['role_setting_prompt_ids_json'] = jsonEncode(
        roleSettingPromptIds,
      );
    }
    await _db.update('chats', updates, where: 'id = ?', whereArgs: [chatId]);
  }

  /// 重命名 chat
  Future<void> renameChat(String chatId, String newName) async {
    await _db.update(
      'chats',
      {
        'name': newName,
        'updated_at': DateTime.now().millisecondsSinceEpoch / 1000,
      },
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  /// 软删除 chat
  Future<void> deleteChat(String chatId) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await _db.update(
      'chats',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  // ==================== Chat State ====================

  /// 获取完整的 chat state（context_history + summary_history）
  Future<Map<String, dynamic>?> getChatState(String chatId) async {
    // 检查是否有数据
    final ctxCount = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM context_items WHERE chat_id = ? AND active = 1',
      [chatId],
    );
    final msgCount = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM messages WHERE chat_id = ? AND deleted_at IS NULL',
      [chatId],
    );
    if ((ctxCount.first['c'] as int) == 0 &&
        (msgCount.first['c'] as int) == 0) {
      return null;
    }

    // 获取 chat 的 last_compaction_at
    final chat = await getChat(chatId);
    final lastCompactionAt = chat?['last_compaction_at'];

    // 加载 context history
    final contextRows = await _db.query(
      'context_items',
      where: 'chat_id = ? AND active = 1',
      whereArgs: [chatId],
      orderBy: 'seq ASC',
    );

    // 加载 summary history
    final summaryRows = await _db.query(
      'summaries',
      where: 'chat_id = ? AND status = ?',
      whereArgs: [chatId, 'active'],
      orderBy: 'created_at ASC',
    );

    // 加载 display history
    final displayRows = await _db.query(
      'messages',
      where: 'chat_id = ? AND deleted_at IS NULL',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );

    return {
      'context_history': contextRows,
      'summary_history': summaryRows,
      'display_history': displayRows,
      'last_compaction_at': lastCompactionAt,
      'context_version': contextRows.length,
      'compress_running': false,
    };
  }

  /// 确保 chat state 存在（已有或空白默认）
  Future<Map<String, dynamic>> ensureChatState(String chatId) async {
    final existing = await getChatState(chatId);
    if (existing != null) return existing;
    return {
      'context_history': <Map<String, dynamic>>[],
      'summary_history': <Map<String, dynamic>>[],
      'display_history': <Map<String, dynamic>>[],
      'last_compaction_at': null,
      'context_version': 0,
      'compress_running': false,
    };
  }

  /// 保存 chat state（同步三张表）
  Future<void> saveChatState(String chatId, Map<String, dynamic> state) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    // 保存 display history (messages)
    final displayHistory = state['display_history'] as List<dynamic>? ?? [];
    final existingMsgs = await _db.query(
      'messages',
      where: 'chat_id = ? AND deleted_at IS NULL',
      whereArgs: [chatId],
    );
    final existingMsgIds = existingMsgs.map((m) => m['id'] as String).toSet();
    final newMsgIds = displayHistory
        .map((m) => (m as Map<String, dynamic>)['id'] as String?)
        .where((id) => id != null)
        .toSet();

    for (var msg in displayHistory) {
      final m = msg as Map<String, dynamic>;
      final msgData = {
        'chat_id': chatId,
        'role': m['role'] ?? 'user',
        'sender_name': m['sender_name'],
        'content': m['content'] ?? '',
        'scene': m['scene'] ?? '',
        'payload_json': m['payload_json'] ?? '{}',
        'deleted_at': null,
        'created_at': m['created_at'] ?? now,
      };
      final existing = await _db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [m['id']],
      );
      if (existing.isNotEmpty) {
        await _db.update(
          'messages',
          msgData,
          where: 'id = ?',
          whereArgs: [m['id']],
        );
      } else {
        await _db.insert('messages', {'id': m['id'], ...msgData});
      }
    }

    // 软删除被移除的消息
    for (var id in existingMsgIds) {
      if (!newMsgIds.contains(id)) {
        await _db.update(
          'messages',
          {'deleted_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    // 保存 context history (context_items)
    final contextHistory = state['context_history'] as List<dynamic>? ?? [];
    final existingCtx = await _db.query(
      'context_items',
      where: 'chat_id = ? AND active = 1',
      whereArgs: [chatId],
    );
    final existingCtxIds = existingCtx.map((c) => c['id'] as String).toSet();
    final newCtxIds = contextHistory
        .map((c) => (c as Map<String, dynamic>)['id'] as String?)
        .where((id) => id != null)
        .toSet();

    for (var ctx in contextHistory) {
      final c = ctx as Map<String, dynamic>;
      final ctxData = {
        'chat_id': chatId,
        'seq': c['seq'] ?? 0,
        'item_type': c['type'] ?? c['item_type'] ?? 'message',
        'role': c['role'] ?? 'user',
        'content': c['content'] ?? '',
        'priority': c['priority'] ?? 'normal',
        'compressible': c['compressible'] ?? 1,
        'active': c['active'] ?? 1,
        'created_at': c['created_at'] ?? c['ts'] ?? now,
      };
      final existing = await _db.query(
        'context_items',
        where: 'id = ?',
        whereArgs: [c['id']],
      );
      if (existing.isNotEmpty) {
        await _db.update(
          'context_items',
          ctxData,
          where: 'id = ?',
          whereArgs: [c['id']],
        );
      } else {
        await _db.insert('context_items', {'id': c['id'], ...ctxData});
      }
    }

    // 停用被移除的 context items
    for (var id in existingCtxIds) {
      if (!newCtxIds.contains(id)) {
        await _db.update(
          'context_items',
          {'active': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    // 保存 summaries
    final summaryHistory = state['summary_history'] as List<dynamic>? ?? [];
    for (var s in summaryHistory) {
      final summary = s as Map<String, dynamic>;
      final summaryData = {
        'chat_id': chatId,
        'level': summary['level'] ?? 'A',
        'status': summary['status'] ?? 'active',
        'source_start_seq': summary['source_start_seq'] ?? 0,
        'source_end_seq': summary['source_end_seq'] ?? 0,
        'source_message_ids_json': jsonEncode(
          summary['source_message_ids'] ?? [],
        ),
        'based_on_context_version': summary['based_on_context_version'] ?? 0,
        'token_estimate_before': summary['token_estimate_before'] ?? 0,
        'token_estimate_after': summary['token_estimate_after'] ?? 0,
        'summary_text': summary['summary_text'] ?? '',
        'facts_json': jsonEncode(summary['facts'] ?? []),
        'decisions_json': jsonEncode(summary['decisions'] ?? []),
        'open_items_json': '[]',
        'role_state_json': jsonEncode(summary['role_state'] ?? []),
        'tool_memory_refs_json': jsonEncode(summary['tool_memory_refs'] ?? []),
        'created_at': summary['created_at'] ?? now,
      };
      final existing = await _db.query(
        'summaries',
        where: 'id = ?',
        whereArgs: [summary['id']],
      );
      if (existing.isNotEmpty) {
        await _db.update(
          'summaries',
          summaryData,
          where: 'id = ?',
          whereArgs: [summary['id']],
        );
      } else {
        await _db.insert('summaries', {'id': summary['id'], ...summaryData});
      }
    }

    // 更新 last_compaction_at
    if (state['last_compaction_at'] != null) {
      await _db.update(
        'chats',
        {'last_compaction_at': state['last_compaction_at'], 'updated_at': now},
        where: 'id = ?',
        whereArgs: [chatId],
      );
    } else {
      await _db.update(
        'chats',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [chatId],
      );
    }
  }

  /// 获取展示消息列表
  Future<List<Map<String, dynamic>>> getDisplayHistory(String chatId) async {
    return await _db.query(
      'messages',
      where: 'chat_id = ? AND deleted_at IS NULL',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );
  }

  /// 添加一条展示消息
  Future<void> addMessage({
    required String chatId,
    required String role,
    required String content,
    String? senderName,
    String scene = '',
    String payloadJson = '{}',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await _db.insert('messages', {
      'id': _uuid.v4(),
      'chat_id': chatId,
      'role': role,
      'sender_name': senderName,
      'content': content,
      'scene': scene,
      'payload_json': payloadJson,
      'deleted_at': null,
      'created_at': now,
    });
  }

  /// 保存压缩结果（精准更新，不触碰压缩期间新增的 context items）
  ///
  /// 只做三件事：
  /// 1. 停用被压缩的源 context items
  /// 2. 插入 summary_ref context item
  /// 3. 追加 summary 记录 + 更新 last_compaction_at
  Future<void> saveCompressionResult({
    required String chatId,
    required List<String> deactivateSourceIds,
    required Map<String, dynamic> summaryRefItem,
    required Map<String, dynamic> summaryObj,
    required int newContextVersion,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final summaryRefContextItemId = summaryRefItem['id'] as String;

    // 1. 删除被压缩的源 context items（释放 seq 以避免 UNIQUE 约束冲突）
    for (var id in deactivateSourceIds) {
      await _db.delete(
        'context_items',
        where: 'id = ? AND chat_id = ?',
        whereArgs: [id, chatId],
      );
    }

    // 2. 插入 summary_ref context item
    await _db.insert('context_items', {
      'id': summaryRefContextItemId,
      'chat_id': chatId,
      'seq': summaryRefItem['seq'] ?? 0,
      'item_type': summaryRefItem['type'] ?? 'summary_ref',
      'role': summaryRefItem['role'] ?? 'system',
      'content': summaryRefItem['content'] ?? '',
      'priority': summaryRefItem['priority'] ?? 'high',
      'compressible': summaryRefItem['compressible'] == false ? 0 : 1,
      'active': 1,
      'created_at': summaryRefItem['ts'] ?? now,
    });

    // 3. 追加 summary 记录（含 context_item_id，供记忆消费时查找）
    await _db.insert('summaries', {
      'id': summaryObj['id'],
      'chat_id': chatId,
      'level': summaryObj['level'] ?? 'S',
      'status': summaryObj['status'] ?? 'active',
      'source_start_seq': summaryObj['source_start_seq'] ?? 0,
      'source_end_seq': summaryObj['source_end_seq'] ?? 0,
      'source_message_ids_json': jsonEncode(
        summaryObj['source_message_ids'] ?? [],
      ),
      'based_on_context_version':
          summaryObj['based_on_context_version'] ?? 0,
      'token_estimate_before': summaryObj['token_estimate_before'] ?? 0,
      'token_estimate_after': summaryObj['token_estimate_after'] ?? 0,
      'summary_text': summaryObj['summary_text'] ?? '',
      'facts_json': jsonEncode(summaryObj['facts'] ?? []),
      'decisions_json': jsonEncode(summaryObj['decisions'] ?? []),
      'open_items_json': '[]',
      'role_state_json': jsonEncode(summaryObj['role_state'] ?? []),
      'tool_memory_refs_json': jsonEncode(
        summaryObj['tool_memory_refs'] ?? [],
      ),
      'memory_id': null,
      'context_item_id': summaryRefContextItemId,
      'created_at': summaryObj['created_at'] ?? now,
    });

    // 4. 更新 last_compaction_at
    await _db.update(
      'chats',
      {'last_compaction_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  /// 获取某个展示消息所在轮次的所有消息 ID
  ///
  /// 轮次定义：从一条 user 消息开始，到下一个 user 消息之前的所有 assistant 消息。
  Future<List<String>> getRoundMessageIds(
    String chatId,
    String targetMessageId,
  ) async {
    final allMessages = await _db.query(
      'messages',
      where: 'chat_id = ? AND deleted_at IS NULL',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );

    // 找到目标消息的索引
    int targetIndex = -1;
    for (var i = 0; i < allMessages.length; i++) {
      if (allMessages[i]['id'] == targetMessageId) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex == -1) return [];

    // 向上找到最近的 user 消息（轮次起点）
    int roundStart = targetIndex;
    for (var i = targetIndex; i >= 0; i--) {
      if (allMessages[i]['role'] == 'user') {
        roundStart = i;
        break;
      }
    }

    // 向下找到下一个 user 消息之前的所有消息（轮次终点）
    int roundEnd = targetIndex;
    for (var i = targetIndex + 1; i < allMessages.length; i++) {
      if (allMessages[i]['role'] == 'user') break;
      roundEnd = i;
    }

    final ids = <String>[];
    for (var i = roundStart; i <= roundEnd; i++) {
      ids.add(allMessages[i]['id'] as String);
    }
    return ids;
  }

  /// 根据消息 ID 列表获取这些消息的创建时间范围
  Future<({double minTime, double maxTime})?> getMessagesTimeRange(
    String chatId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return null;
    final placeholders = messageIds.map((_) => '?').join(',');
    final rows = await _db.rawQuery(
      'SELECT MIN(created_at) as min_t, MAX(created_at) as max_t '
      'FROM messages WHERE chat_id = ? AND id IN ($placeholders)',
      [chatId, ...messageIds],
    );
    if (rows.isEmpty) return null;
    final minT = (rows.first['min_t'] as num?)?.toDouble();
    final maxT = (rows.first['max_t'] as num?)?.toDouble();
    if (minT == null || maxT == null) return null;
    return (minTime: minT, maxTime: maxT);
  }

  /// 删除一轮对话（同时清理 messages 和 context_items）
  Future<void> deleteRound({
    required String chatId,
    required List<String> messageIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    // 获取时间范围用于匹配 context_items
    final timeRange = await getMessagesTimeRange(chatId, messageIds);
    final buffer = 2.0; // 2 秒容差

    // 软删除 messages
    for (var id in messageIds) {
      await _db.update(
        'messages',
        {'deleted_at': now},
        where: 'id = ? AND chat_id = ?',
        whereArgs: [id, chatId],
      );
    }

    // 停用对应时间范围内的 context_items（仅 type=message 的）
    if (timeRange != null) {
      await _db.update(
        'context_items',
        {'active': 0},
        where:
            'chat_id = ? AND item_type = ? AND active = 1 AND created_at >= ? AND created_at <= ?',
        whereArgs: [
          chatId,
          'message',
          timeRange.minTime - buffer,
          timeRange.maxTime + buffer,
        ],
      );
    }

    // 更新 chat 的 updated_at
    await _db.update(
      'chats',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  /// 添加一条 context item
  Future<void> addContextItem({
    required String chatId,
    required String role,
    required String content,
    String itemType = 'message',
    String priority = 'normal',
    int compressible = 1,
  }) async {
    // 获取最大 seq
    final maxSeqResult = await _db.rawQuery(
      'SELECT COALESCE(MAX(seq), 0) + 1 as next_seq FROM context_items WHERE chat_id = ?',
      [chatId],
    );
    final seq = maxSeqResult.first['next_seq'] as int;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;

    await _db.insert('context_items', {
      'id': _uuid.v4(),
      'chat_id': chatId,
      'seq': seq,
      'item_type': itemType,
      'role': role,
      'content': content,
      'priority': priority,
      'compressible': compressible,
      'active': 1,
      'created_at': now,
    });
  }
}
