import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import 'ai_service.dart';
import 'app_config_service.dart';
import 'chat_state_service.dart';
import 'solo_memory_service.dart';
import 'token_usage_service.dart';

/// 单级压缩服务
class CompressionService {
  static final CompressionService instance = CompressionService._();
  CompressionService._();

  static const _uuid = Uuid();

  /// 正在执行压缩的 chatId 集合（内存锁，防止并发压缩）
  final Set<String> _runningChats = {};

  // ==================== 摘要请求构建 ====================

  Map<String, dynamic> _buildSummaryRequest(List<Map<String, dynamic>> messages) {
    final chunk = messages.map(_normalizeHistoryMessage).toList();
    final payload = jsonEncode(chunk);
    const systemPrompt =
        '你是结构化摘要器。\n'
        '任务：基于输入的连续消息，输出结构化摘要 JSON。\n'
        '要求：只基于输入，不得添加输入中不存在的新事实。\n'
        '返回 JSON 对象，字段必须包含：\n'
        '- summary_text: string\n'
        '- facts: string[]\n'
        '- decisions: string[]\n'
        '- role_state: [{role: string, state: string, intent?: string}]\n'
        '不要输出 JSON 以外内容。';
    return {
      'system_prompt': systemPrompt,
      'messages': [
        jsonEncode({'role': 'user', 'content': payload}),
      ],
      'normalized_chunk': chunk,
    };
  }

  // ==================== 摘要执行 ====================

  Future<Map<String, dynamic>> summarize({
    required AIModel model,
    required List<Map<String, dynamic>> messages,
    String chatId = '',
  }) async {
    final req = _buildSummaryRequest(messages);
    final msgList = (req['messages'] as List).cast<String>();

    final result = await AIService.chatCompletion(
      model: model,
      messages: msgList,
      systemPrompt: req['system_prompt'] as String,
      extraBody: {'enable_thinking': false},
    );

    if (chatId.isNotEmpty && result.usage != null) {
      await TokenUsageService.instance.addTokenUsage(
        chatId: chatId,
        agentType: 'compression_agent',
        promptTokens: (result.usage!['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens:
            (result.usage!['completion_tokens'] as num?)?.toInt() ?? 0,
        modelName: model.name,
      );
    }

    final data = _safeParseJson(result.answer);
    if (data is Map<String, dynamic>) {
      return _normalizeSummaryObj(data);
    }
    return {
      'summary_text': result.answer,
      'facts': <String>[],
      'decisions': <String>[],
      'role_state': <Map<String, dynamic>>[],
    };
  }

  // ==================== 压缩调度 ====================

  /// 调度压缩（公开 API）
  Future<void> scheduleCompression({
    required String chatId,
    required AIModel model,
  }) async {
    final cfg = AppConfigService.instance;
    final recentRawMessagesKeep = cfg.compressionRecentKeep;
    final maxSourceMsgs = cfg.compressionABatch;

    if (_runningChats.contains(chatId)) return;

    final state = await ChatStateService.instance.ensureChatState(chatId);

    final snapshot = _buildSnapshot(
      state,
      maxSourceMsgs: maxSourceMsgs,
      recentRawMessagesKeep: recentRawMessagesKeep,
    );
    if (snapshot == null) return;

    _runningChats.add(chatId);

    try {
      final sourceMessages = (snapshot['source_messages'] as List)
          .cast<Map<String, dynamic>>();
      final payloadMessages = sourceMessages
          .map(
            (m) => {
              'role': (m['role'] ?? '').toString(),
              'content': (m['content'] ?? '').toString(),
            },
          )
          .toList();

      final summaryCore = await summarize(
        model: model,
        messages: payloadMessages,
        chatId: chatId,
      );

      final sourceIds = (snapshot['source_ids'] as List).cast<String>();

      final summaryObj = {
        'id': 'sum_${_uuid.v4().substring(0, 12)}',
        'level': 'S',
        'status': 'active',
        'source_start_seq': snapshot['source_start_seq'],
        'source_end_seq': snapshot['source_end_seq'],
        'source_message_ids': sourceIds,
        'based_on_context_version': snapshot['based_on_context_version'],
        'token_estimate_before': 0,
        'token_estimate_after': 0,
        'summary_text': summaryCore['summary_text'] ?? '',
        'facts': summaryCore['facts'] ?? [],
        'decisions': summaryCore['decisions'] ?? [],
        'role_state': summaryCore['role_state'] ?? [],
        'tool_memory_refs': <dynamic>[],
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      };

      final summaryRef = _newSummaryRef(summaryObj);

      // 使用精准更新：只停用源 items + 插入 summary_ref，不触碰压缩期间新增的 items
      await ChatStateService.instance.saveCompressionResult(
        chatId: chatId,
        deactivateSourceIds: sourceIds,
        summaryRefItem: summaryRef,
        summaryObj: summaryObj,
        newContextVersion:
            ((state['context_version'] as num?)?.toInt() ?? 0) + 1,
      );

      // Solo 模式：检查是否需要记忆提取
      await _maybeTriggerMemoryExtraction(chatId);
    } catch (e) {
      // 压缩失败不影响主流程
    } finally {
      _runningChats.remove(chatId);
    }
  }

  // ==================== 内部辅助方法 ====================

  /// Solo 模式：检查是否需要触发记忆提取
  Future<void> _maybeTriggerMemoryExtraction(String chatId) async {
    final db = DatabaseHelper.instance;
    final session = await db.query(
      'solo_sessions',
      where: 'id = ?',
      whereArgs: [chatId],
    );
    if (session.isEmpty) return;

    await SoloMemoryService.instance.checkAndExtract(sessionId: chatId);
  }

  /// 构建压缩快照
  Map<String, dynamic>? _buildSnapshot(
    Map<String, dynamic> state, {
    required int maxSourceMsgs,
    required int recentRawMessagesKeep,
  }) {
    final rawMessages = _compressibleRawMessages(state);
    if (rawMessages.length <= recentRawMessagesKeep) return null;

    final candidates = rawMessages.sublist(
      0,
      rawMessages.length - recentRawMessagesKeep,
    );
    if (candidates.length < maxSourceMsgs) return null;

    final selected = candidates.sublist(0, maxSourceMsgs);
    final sourceIds = selected.map((m) => (m['id'] ?? '').toString()).toList();
    if (sourceIds.any((id) => id.isEmpty)) return null;

    return {
      'source_ids': sourceIds,
      'source_messages': selected,
      'based_on_context_version':
          (state['context_version'] as num?)?.toInt() ?? 0,
      'source_start_seq': (selected.first['seq'] as num?)?.toInt() ?? 0,
      'source_end_seq': (selected.last['seq'] as num?)?.toInt() ?? 0,
    };
  }

  /// 获取可压缩的原始消息
  List<Map<String, dynamic>> _compressibleRawMessages(
    Map<String, dynamic> state,
  ) {
    final items =
        (state['context_history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = items
        .where(
          (x) =>
              (x['type'] ?? x['item_type'] ?? '') == 'message' &&
              (x['compressible'] == null || x['compressible'] == true || x['compressible'] == 1),
        )
        .toList();
    out.sort(
      (a, b) => ((a['seq'] ?? 0) as num).compareTo((b['seq'] ?? 0) as num),
    );
    return out;
  }

  /// 创建摘要引用对象
  Map<String, dynamic> _newSummaryRef(Map<String, dynamic> summaryObj) {
    return {
      'type': 'summary_ref',
      'id': _uuid.v4(),
      'summary_id': summaryObj['id'],
      'level': summaryObj['level'],
      'seq': (summaryObj['source_start_seq'] as num?)?.toInt() ?? 0,
      'role': 'system',
      'content': (summaryObj['summary_text'] ?? '').toString(),
      'ts':
          summaryObj['created_at'] ??
          DateTime.now().millisecondsSinceEpoch / 1000,
      'priority': 'high',
      'compressible': false,
    };
  }

  /// 标准化历史消息（用于摘要输入）
  Map<String, dynamic> _normalizeHistoryMessage(Map<String, dynamic> message) {
    var role = (message['role'] ?? 'user').toString();
    var content = (message['content'] ?? '').toString();

    if (role == 'user') {
      final payload = _safeParseUserPayload(content);
      if (payload != null) {
        final msgText = _extractMessageContent(payload);
        if (msgText.isNotEmpty) {
          final senderText = _extractSender(payload);
          if (senderText.isNotEmpty) {
            content = '发送者名称：$senderText\n消息内容：$msgText';
          } else {
            content = '消息内容：$msgText';
          }
        }
      }
    } else if (role == 'assistant') {
      final parsed = _parseAssistantMultiSpeaker(content);
      if (parsed.isNotEmpty) {
        final blocks = <String>[];
        for (var it in parsed) {
          final sender = (it['sender'] ?? '').toString().trim();
          final msg = (it['content'] ?? '').toString().trim();
          if (sender.isNotEmpty) {
            blocks.add('回复用户：$sender\n消息内容：$msg');
          } else {
            blocks.add('消息内容：$msg');
          }
        }
        content = blocks.join('\n\n');
      }
    }

    return {'role': role, 'content': content};
  }

  /// 标准化摘要对象
  Map<String, dynamic> _normalizeSummaryObj(Map<String, dynamic> data) {
    return {
      'summary_text': (data['summary_text'] ?? '').toString().trim(),
      'facts': data['facts'] is List ? data['facts'] : <String>[],
      'decisions': data['decisions'] is List ? data['decisions'] : <String>[],
      'role_state': data['role_state'] is List
          ? data['role_state']
          : <Map<String, dynamic>>[],
    };
  }

  /// 安全解析 JSON
  dynamic _safeParseJson(String text) {
    var s = text.trim();
    if (s.startsWith('```json')) s = s.substring(7);
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    s = s.trim();
    if (s.isEmpty) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// 安全解析用户消息 payload
  Map<String, dynamic>? _safeParseUserPayload(String text) {
    try {
      final data = jsonDecode(text);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  /// 提取发送者
  String _extractSender(Map<String, dynamic> data) {
    for (var key in ['回复用户', '发送者名称', '昵称', 'sender_name', 'sender', 'name']) {
      if (data.containsKey(key) && data[key] != null) {
        return data[key].toString().trim();
      }
    }
    return '';
  }

  /// 提取消息内容
  String _extractMessageContent(Map<String, dynamic> data) {
    for (var key in ['消息内容', 'message_content', 'content', 'message', 'text']) {
      if (data.containsKey(key) && data[key] != null) {
        return data[key].toString().trim();
      }
    }
    return '';
  }

  /// 解析助手多说话者内容
  List<Map<String, String>> _parseAssistantMultiSpeaker(String content) {
    final data = _safeParseJson(content);
    final items = <Map<String, String>>[];
    if (data == null) return items;

    // 处理 {消息列表list: [...]} 格式
    if (data is Map<String, dynamic> && data['消息列表list'] is List) {
      for (var it in data['消息列表list'] as List) {
        if (it is Map<String, dynamic>) {
          final sender = _extractSender(it);
          final msg = _extractMessageContent(it);
          if (msg.isNotEmpty) {
            items.add({'sender': sender, 'content': msg});
          }
        } else if (it is String && it.trim().isNotEmpty) {
          items.add({'sender': '', 'content': it.trim()});
        }
      }
      return items;
    }

    // 处理 list 或单个对象格式
    final listData = data is List ? data : [data];
    for (var it in listData) {
      if (it is! Map<String, dynamic>) continue;
      final sender = _extractSender(it);
      final msg = _extractMessageContent(it);
      if (msg.isNotEmpty) {
        items.add({'sender': sender, 'content': msg});
      }
    }
    return items;
  }
}
