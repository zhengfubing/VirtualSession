import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import '../services/ai_service.dart';
import '../services/file_storage_service.dart';
import '../services/dialog_parser_service.dart';
import '../services/prompt_builder_service.dart';
import '../services/app_config_service.dart';
import '../services/context_builder_service.dart';
import '../services/chat_state_service.dart';
import '../services/compression_service.dart';
import '../services/tts_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_colors.dart';

/// 展示消息类型
enum _MsgType { user, assistant, system, reasoning }

/// 展示消息
class _DisplayMessage {
  final String id;
  final _MsgType type;
  String senderName;
  String content;
  final String scene;
  final List<String> status;
  final String statusType;
  final String statusContent;
  bool isStreaming;
  bool isExpanded;

  _DisplayMessage({
    required this.id,
    required this.type,
    this.senderName = '',
    required this.content,
    this.scene = '',
    this.status = const [],
    this.statusType = '',
    this.statusContent = '',
    this.isStreaming = false,
  }) : isExpanded = false;
}

class WorldChatPage extends StatefulWidget {
  final String? initialChatId;

  const WorldChatPage({super.key, this.initialChatId});

  @override
  State<WorldChatPage> createState() => WorldChatPageState();
}

class WorldChatPageState extends State<WorldChatPage> {
  final _db = DatabaseHelper.instance;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _fileStorage = FileStorageService();
  static const _uuid = Uuid();
  final _ttsPlayer = AudioPlayer();

  // 世界聊天会话
  List<Map<String, dynamic>> _worldChats = [];
  String? _currentChatId;

  // 模型
  AIModel? _currentModel;

  // 世界/场景/角色配置
  List<String> _allWorlds = [];
  List<String> _allScenes = [];
  List<String> _allRoles = [];
  String _selectedWorld = '';
  String _currentScene = '';
  List<String> _sceneRoles = []; // 当前场景的角色
  Map<String, String> _roleLocations = {}; // 角色位置映射

  // 消息
  final List<_DisplayMessage> _displayMessages = [];
  bool _isStreaming = false;

  // TTS 状态
  String? _ttsMessageId;
  bool _ttsLoading = false;
  StreamSubscription<AIStreamEvent>? _streamSub;

  // 长按标题触发 Debug
  Timer? _longPressTimer;

  /// 外部调用：加载指定世界会话
  void loadChat(String chatId) {
    _loadData().then((_) => _selectChat(chatId));
  }

  @override
  void initState() {
    super.initState();
    _ttsPlayer.onPlayerComplete.listen((_) {
      if (mounted)
        setState(() {
          _ttsMessageId = null;
          _ttsLoading = false;
        });
    });
    _loadModel();
    _loadData();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _streamSub?.cancel();
    _ttsPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadModel() async {
    final modelName = AppConfigService.instance.agentModelChat;
    final modelMap = await _db.getModelByName(modelName);
    if (modelMap != null && mounted) {
      setState(() => _currentModel = AIModel.fromMap(modelMap));
    }
  }

  Future<void> _loadData() async {
    final worlds = await _fileStorage.getAllWorlds();
    final scenes = await _fileStorage.getAllScenes();
    final roles = await _fileStorage.getAllRoles();

    // 加载世界聊天会话
    final chats = await _db.query(
      'world_chats',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );

    if (!mounted) return;
    setState(() {
      _allWorlds = worlds;
      _allScenes = scenes;
      _allRoles = roles;
      _worldChats = chats;
    });

    if (chats.isNotEmpty && _currentChatId == null) {
      final targetId = widget.initialChatId;
      if (targetId != null && chats.any((c) => c['id'] == targetId)) {
        _selectChat(targetId);
      } else {
        _selectChat(chats.first['id'] as String);
      }
    }
  }

  Future<void> _selectChat(String chatId) async {
    final results = await _db.query(
      'world_chats',
      where: 'id = ?',
      whereArgs: [chatId],
    );
    if (results.isEmpty || !mounted) return;

    final chat = results.first;
    setState(() {
      _currentChatId = chatId;
      _selectedWorld = chat['world_scene_id'] as String? ?? '';
      _currentScene = _allScenes.isNotEmpty ? _allScenes.first : _selectedWorld;
    });

    await _loadDisplayHistory(chatId);
    await _loadSceneRoles();
  }

  Future<void> _loadDisplayHistory(String chatId) async {
    final messages = await _db.query(
      'messages',
      where: 'chat_id = ? AND deleted_at IS NULL',
      whereArgs: [chatId],
      orderBy: 'created_at ASC',
    );
    if (!mounted) return;

    final display = <_DisplayMessage>[];
    for (var msg in messages) {
      final role = msg['role'] as String? ?? 'user';
      final content = msg['content'] as String? ?? '';

      if (role == 'user') {
        display.add(
          _DisplayMessage(
            id: msg['id'] as String? ?? _uuid.v4(),
            type: _MsgType.user,
            senderName: msg['sender_name'] as String? ?? '',
            content: _extractUserDisplayText(content),
          ),
        );
      } else if (role == 'assistant') {
        final items = DialogParserService.instance.parseDialogItemsFromText(
          content,
        );
        if (items != null && items.isNotEmpty) {
          for (var item in items) {
            display.add(
              _DisplayMessage(
                id: _uuid.v4(),
                type: _MsgType.assistant,
                senderName: item.senderName,
                content: item.messageContent,
                scene: item.scene,
                status: item.status,
                statusType: item.statusType,
                statusContent: item.statusContent,
              ),
            );
          }
        } else {
          display.add(
            _DisplayMessage(
              id: msg['id'] as String? ?? _uuid.v4(),
              type: _MsgType.assistant,
              content: content,
            ),
          );
        }
      } else {
        display.add(
          _DisplayMessage(
            id: msg['id'] as String? ?? _uuid.v4(),
            type: _MsgType.system,
            content: _extractSystemDisplayText(content),
          ),
        );
      }
    }

    setState(() {
      _displayMessages.clear();
      _displayMessages.addAll(display);
    });
    _scrollToBottom();
  }

  String _extractUserDisplayText(String content) {
    try {
      final data = jsonDecode(content);
      if (data is Map<String, dynamic>) {
        return (data['message_content'] ?? content).toString();
      }
    } catch (_) {}
    return content;
  }

  String _extractSystemDisplayText(String content) {
    String decoded = content;
    for (var i = 0; i < 3; i++) {
      try {
        final result = jsonDecode(decoded);
        if (result is String) {
          decoded = result;
        } else if (result is Map<String, dynamic>) {
          return (result['message_content'] ?? decoded).toString();
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
    return decoded;
  }

  Future<void> _loadSceneRoles() async {
    if (_currentChatId == null || _currentChatId!.isEmpty) return;

    final rows = await _db.query(
      'world_chat_roles',
      where: 'world_chat_id = ?',
      whereArgs: [_currentChatId],
    );

    if (rows.isNotEmpty) {
      setState(() {
        _sceneRoles = rows.map((r) => r['role_name'] as String).toList();
        _roleLocations = {
          for (var r in rows)
            r['role_name'] as String: r['scene_name'] as String,
        };
      });
    } else {
      setState(() {
        _sceneRoles = List.from(_allRoles);
        _roleLocations = {for (var r in _allRoles) r: _currentScene};
      });
    }
  }

  Future<void> _saveSceneRoles() async {
    if (_currentChatId == null || _currentChatId!.isEmpty) return;

    await _db.delete(
      'world_chat_roles',
      where: 'world_chat_id = ?',
      whereArgs: [_currentChatId],
    );

    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    for (final role in _sceneRoles) {
      await _db.insert('world_chat_roles', {
        'id': _uuid.v4(),
        'world_chat_id': _currentChatId,
        'role_name': role,
        'scene_name': _roleLocations[role] ?? _currentScene,
        'created_at': now,
      });
    }
  }

  // ==================== 会话操作 ====================

  Future<void> _createChat() async {
    if (_selectedWorld.isEmpty && _allWorlds.isNotEmpty) {
      setState(() => _selectedWorld = _allWorlds.first);
    }

    final nameController = TextEditingController(
      text: '世界对话 ${_worldChats.length + 1}',
    );

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建世界对话'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '对话名称'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedWorld.isEmpty ? null : _selectedWorld,
              decoration: const InputDecoration(
                labelText: '世界场景',
                border: OutlineInputBorder(),
              ),
              items: _allWorlds
                  .map(
                    (w) => DropdownMenuItem(
                      value: w,
                      child: Text(w.replaceAll('.md', '')),
                    ),
                  )
                  .toList(),
              onChanged: (v) => _selectedWorld = v ?? '',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || _selectedWorld.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final chatId = _uuid.v4();
    await _db.insert('world_chats', {
      'id': chatId,
      'name': name,
      'world_scene_id': _selectedWorld,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    });

    for (final role in _sceneRoles) {
      await _db.insert('world_chat_roles', {
        'id': _uuid.v4(),
        'world_chat_id': chatId,
        'role_name': role,
        'scene_name': _roleLocations[role] ?? _currentScene,
        'created_at': now,
      });
    }

    await _loadData();
    _selectChat(chatId);
  }

  // ==================== 发送消息 ====================

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentModel == null || _isStreaming) return;
    if (_currentChatId == null) {
      await _createChat();
      if (_currentChatId == null) return;
    }

    _messageController.clear();

    // 用户消息展示
    final senderLabel = _selectedSender != 'empty' ? _selectedSender : 'user';
    final userMsg = _DisplayMessage(
      id: _uuid.v4(),
      type: _MsgType.user,
      senderName: senderLabel,
      content: text,
    );
    setState(() => _displayMessages.add(userMsg));
    _scrollToBottom();

    // 保存用户消息（display 存纯文本，context 存 JSON）
    final actualSender = _selectedSender != 'empty' ? _selectedSender : 'user';
    final userMsgMap = {
      'sender_name': actualSender,
      'status': <String>[],
      'status_type': '',
      'status_content': '',
      'scene': _currentScene,
      'message_content': text,
    };
    final userMsgContentJson = jsonEncode(userMsgMap);
    await _db.insert('messages', {
      'id': _uuid.v4(),
      'chat_id': _currentChatId!,
      'role': 'user',
      'sender_name': actualSender,
      'content': text,
      'scene': _currentScene,
      'payload_json': '{}',
      'deleted_at': null,
      'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
    });
    // 保存 context item
    final userMaxSeqResult = await _db.rawQuery(
      'SELECT COALESCE(MAX(seq), 0) + 1 as next_seq FROM context_items WHERE chat_id = ?',
      [_currentChatId],
    );
    final userSeq = userMaxSeqResult.first['next_seq'] as int;
    await _db.insert('context_items', {
      'id': _uuid.v4(),
      'chat_id': _currentChatId,
      'seq': userSeq,
      'item_type': 'message',
      'role': 'user',
      'content': userMsgContentJson,
      'priority': 'normal',
      'compressible': 1,
      'active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
    });

    // 构建世界系统提示词
    final systemPrompt = await PromptBuilderService.buildWorldSystemPrompt(
      worldSceneId: _selectedWorld,
      currentScene: _currentScene,
      roleNames: _allRoles,
      sceneRoles: _sceneRoles,
      roleLocations: _roleLocations,
    );

    // 获取上下文历史
    final contextRows = await _db.query(
      'context_items',
      where: 'chat_id = ? AND active = 1',
      whereArgs: [_currentChatId],
      orderBy: 'seq ASC',
    );
    final contextMessages = contextRows.map((r) {
      // 转换为 JSON 字符串格式
      return jsonEncode({
        'role': r['role'] as String,
        'content': r['content'] as String,
      });
    }).toList();

    // 流式助手消息占位
    final streamingMsg = _DisplayMessage(
      id: _uuid.v4(),
      type: _MsgType.assistant,
      content: '',
      isStreaming: true,
    );
    setState(() {
      _displayMessages.add(streamingMsg);
      _isStreaming = true;
    });

    // 构建消息（所有消息都是JSON字符串）
    final messages = <String>[
      ...contextMessages,
      jsonEncode({'role': 'user', 'content': jsonEncode(userMsgMap)}),
    ];

    // 调用模型（流式）
    String accumulatedAnswer = '';
    String accumulatedReasoning = '';

    _streamSub =
        AIService.streamChatCompletion(
          model: _currentModel!,
          messages: messages,
          systemPrompt: systemPrompt,
          extraBody: {
            'enable_thinking': AppConfigService.instance.enableThinking,
            'enable_search': AppConfigService.instance.enableSearch,
          },
        ).listen(
          (event) {
            if (!mounted) return;
            if (event.content != null && event.content!.isNotEmpty) {
              accumulatedAnswer += event.content!;
              setState(() => streamingMsg.content = accumulatedAnswer);
              _scrollToBottom();
            }
            if (event.reasoningContent != null &&
                event.reasoningContent!.isNotEmpty) {
              accumulatedReasoning += event.reasoningContent!;
              _updateReasoningDisplay(accumulatedReasoning);
            }
          },
          onDone: () => _handleStreamDone(streamingMsg, accumulatedAnswer),
          onError: (e) {
            if (!mounted) return;
            setState(() {
              streamingMsg.content = '错误: $e';
              streamingMsg.isStreaming = false;
              _isStreaming = false;
            });
          },
        );
  }

  void _updateReasoningDisplay(String reasoning) {
    final existingIdx = _displayMessages.lastIndexWhere(
      (m) => m.type == _MsgType.reasoning,
    );
    if (existingIdx >= 0) {
      setState(() => _displayMessages[existingIdx].content = reasoning);
    } else {
      setState(() {
        _displayMessages.insert(
          _displayMessages.length - 1,
          _DisplayMessage(
            id: _uuid.v4(),
            type: _MsgType.reasoning,
            content: reasoning,
          ),
        );
      });
    }
  }

  Future<void> _handleStreamDone(
    _DisplayMessage streamingMsg,
    String finalAnswer,
  ) async {
    final items = DialogParserService.instance.parseDialogItemsFromText(
      finalAnswer,
    );

    setState(() {
      streamingMsg.isStreaming = false;
      _isStreaming = false;
    });

    if (items != null && items.isNotEmpty) {
      final idx = _displayMessages.indexOf(streamingMsg);
      _displayMessages.removeAt(idx);

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        _displayMessages.insert(
          idx + i,
          _DisplayMessage(
            id: _uuid.v4(),
            type: _MsgType.assistant,
            senderName: item.senderName,
            content: item.messageContent,
            scene: item.scene,
            status: item.status,
            statusType: item.statusType,
            statusContent: item.statusContent,
          ),
        );
      }

      // 保存助手消息
      await _db.insert('messages', {
        'id': _uuid.v4(),
        'chat_id': _currentChatId!,
        'role': 'assistant',
        'sender_name': items.first.senderName,
        'content': finalAnswer,
        'scene': _currentScene,
        'payload_json': '{}',
        'deleted_at': null,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      });

      // 保存 context item
      final maxSeqResult = await _db.rawQuery(
        'SELECT COALESCE(MAX(seq), 0) + 1 as next_seq FROM context_items WHERE chat_id = ?',
        [_currentChatId],
      );
      final seq = maxSeqResult.first['next_seq'] as int;
      await _db.insert('context_items', {
        'id': _uuid.v4(),
        'chat_id': _currentChatId,
        'seq': seq,
        'item_type': 'message',
        'role': 'assistant',
        'content': finalAnswer,
        'priority': 'normal',
        'compressible': 1,
        'active': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      });

      // Toast 处理
      for (var item in items) {
        if (item.isToast && mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(item.statusType),
              content: Text(item.statusContent),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      }
    } else {
      streamingMsg.content = finalAnswer.isEmpty ? '(无回复)' : finalAnswer;

      await _db.insert('messages', {
        'id': _uuid.v4(),
        'chat_id': _currentChatId!,
        'role': 'assistant',
        'sender_name': '',
        'content': finalAnswer,
        'scene': _currentScene,
        'payload_json': '{}',
        'deleted_at': null,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      });

      // 保存 context item
      final maxSeqResult = await _db.rawQuery(
        'SELECT COALESCE(MAX(seq), 0) + 1 as next_seq FROM context_items WHERE chat_id = ?',
        [_currentChatId],
      );
      final seq = maxSeqResult.first['next_seq'] as int;
      await _db.insert('context_items', {
        'id': _uuid.v4(),
        'chat_id': _currentChatId,
        'seq': seq,
        'item_type': 'message',
        'role': 'assistant',
        'content': finalAnswer,
        'priority': 'normal',
        'compressible': 1,
        'active': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      });
    }

    // 异步触发 A/B 压缩（不阻塞主流程）
    _triggerCompression(_currentChatId!);

    // 更新会话时间
    await _db.update(
      'world_chats',
      {'updated_at': DateTime.now().millisecondsSinceEpoch / 1000},
      where: 'id = ?',
      whereArgs: [_currentChatId],
    );

    _scrollToBottom();
    _loadData();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 异步触发 A/B 压缩（不阻塞主流程）
  void _triggerCompression(String chatId) {
    final compressionModelName =
        AppConfigService.instance.agentModelCompression;
    DatabaseHelper.instance
        .getModelByName(compressionModelName)
        .then((modelMap) {
          if (modelMap == null) return;
          final model = AIModel.fromMap(modelMap);
          CompressionService.instance.scheduleCompression(
            chatId: chatId,
            model: model,
          );
        })
        .catchError((_) {});
  }

  void _copyToClipboard(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  // ==================== 场景切换 ====================

  Future<void> _showSceneSwitcher() async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('场景配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '当前场景',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _currentScene.isEmpty ? null : _currentScene,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: _allScenes
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.replaceAll('.md', '')),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setDialogState(() => _currentScene = v ?? '');
                    setState(() => _currentScene = v ?? '');
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  '场景角色',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _allRoles.map((role) {
                    final selected = _sceneRoles.contains(role);
                    return FilterChip(
                      label: Text(role.replaceAll('.md', '')),
                      selected: selected,
                      onSelected: (v) {
                        setDialogState(() {
                          if (v) {
                            _sceneRoles.add(role);
                            _roleLocations[role] = _currentScene;
                          } else {
                            _sceneRoles.remove(role);
                            _roleLocations.remove(role);
                          }
                        });
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _saveSceneRoles();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Context Debug ====================

  Future<void> _showContextDebug() async {
    if (_currentChatId == null) return;

    final chatState = await ChatStateService.instance.ensureChatState(
      _currentChatId!,
    );
    final contextHistory =
        (chatState['context_history'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
    final summaryHistory =
        (chatState['summary_history'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
    final activeSummaries = summaryHistory
        .where((s) => (s['status'] ?? 'active') == 'active')
        .toList();

    final effectiveContext = ContextBuilderService.instance
        .buildEffectiveContext(
          chatState: chatState,
          recentKeep: AppConfigService.instance.compressionRecentKeep,
        );

    // 统计信息（对齐 Python context-debug 端点）
    final coveredMessageIds = <String>{};
    for (var s in activeSummaries) {
      final sourceIds = s['source_message_ids'];
      if (sourceIds is List) {
        coveredMessageIds.addAll(sourceIds.map((e) => e.toString()));
      }
    }
    final rawContextMessages = contextHistory
        .where((x) => (x['type'] ?? x['item_type'] ?? '') == 'message')
        .toList();
    final activeSummaryCount = activeSummaries.length;
    final lastCompactionAt = chatState['last_compaction_at'];

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.bug_report_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('Context Debug'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.7,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _debugSection(
                  'effective_context (${effectiveContext.length})',
                  effectiveContext.map((e) => e.toString()).toList(),
                ),
                const SizedBox(height: 12),
                _debugSection(
                  'context_history (${contextHistory.length})',
                  contextHistory.map((e) => jsonEncode(e)).toList(),
                ),
                const SizedBox(height: 12),
                _debugSection(
                  'active_summaries (${activeSummaries.length})',
                  activeSummaries.map((e) => jsonEncode(e)).toList(),
                ),
                const SizedBox(height: 12),
                _debugSection(
                  'covered_message_ids (${coveredMessageIds.length})',
                  coveredMessageIds.map((e) => e).toList(),
                ),
                const SizedBox(height: 12),
                _debugSection('counts', [
                  'raw_context_messages: ${rawContextMessages.length}',
                  'summary_history_total: ${summaryHistory.length}',
                  'active_summary_count: $activeSummaryCount',
                  'covered_message_count: ${coveredMessageIds.length}',
                ]),
                const SizedBox(height: 12),
                _debugSection('last_context_token_estimate', [
                  '${(chatState['last_context_token_estimate'] as num?)?.toInt() ?? 0}',
                ]),
                const SizedBox(height: 12),
                _debugSection('last_compaction_at', [
                  lastCompactionAt?.toString() ?? 'null',
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _debugSection(String title, List<String> items) {
    return ExpansionTile(
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: items.isEmpty
          ? [const Text('  (空)', style: TextStyle(color: Colors.grey))]
          : items
                .map(
                  (item) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      item,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                )
                .toList(),
    );
  }

  // ==================== UI ====================

  // 当前发送者（世界聊天用场景角色列表）
  String _selectedSender = 'empty';

  Widget _buildAvatarCircle(
    String senderName,
    ColorScheme cs, {
    double radius = 16,
  }) {
    final roleName = senderName.replaceAll('.md', '');
    return FutureBuilder<String?>(
      future: _fileStorage.getRoleAvatarPath(senderName),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return CircleAvatar(
            radius: radius,
            backgroundImage: FileImage(File(snapshot.data!)),
          );
        }
        return CircleAvatar(
          radius: radius,
          backgroundColor: cs.primaryContainer,
          child: Text(
            roleName.isNotEmpty ? roleName[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: radius * 0.75,
              fontWeight: FontWeight.w600,
              color: cs.onPrimaryContainer,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleSelector() {
    final cs = Theme.of(context).colorScheme;
    final allSenders = ['empty', ..._sceneRoles];
    final displayName = _selectedSender == 'empty'
        ? 'User'
        : _selectedSender.replaceAll('.md', '');

    return PopupMenuButton<String>(
      onSelected: (value) {
        setState(() => _selectedSender = value);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      offset: const Offset(0, 40),
      itemBuilder: (ctx) => allSenders.map((r) {
        final name = r == 'empty' ? 'User' : r.replaceAll('.md', '');
        final isActive = _selectedSender == r;
        final scene = r == 'empty'
            ? ''
            : (_roleLocations[r]?.replaceAll('.md', '') ?? '');
        return PopupMenuItem<String>(
          value: r,
          child: Row(
            children: [
              _buildAvatarCircle(r == 'empty' ? 'User' : r, cs, radius: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isActive ? cs.primary : cs.onSurface,
                      ),
                    ),
                    if (scene.isNotEmpty)
                      Text(
                        scene,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (isActive) Icon(Icons.check, size: 16, color: cs.primary),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAvatarCircle(
              _selectedSender == 'empty' ? 'User' : _selectedSender,
              cs,
              radius: 14,
            ),
            const SizedBox(width: 6),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      appBar: AppBar(
        backgroundColor: AppColors.headerBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: AppColors.accent),
        title: GestureDetector(
          onTap: _currentChatId != null ? _showSceneSwitcher : null,
          onLongPressStart: _currentChatId != null
              ? (details) {
                  _longPressTimer = Timer(const Duration(seconds: 5), () {
                    _showContextDebug();
                  });
                }
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentChatId != null
                    ? (_worldChats.firstWhere(
                                (c) => c['id'] == _currentChatId,
                                orElse: () => {'name': '世界对话'},
                              )['name']
                              as String? ??
                          '世界对话')
                    : '世界对话',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_currentChatId != null) _buildRoleSelector(),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_displayMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              '选择世界和场景开始对话',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _displayMessages.length,
      itemBuilder: (ctx, i) => _buildMessageItem(_displayMessages[i]),
    );
  }

  Widget _buildMessageItem(_DisplayMessage msg) {
    switch (msg.type) {
      case _MsgType.user:
        return _buildUserBubble(msg);
      case _MsgType.assistant:
        return _buildAssistantBubble(msg);
      case _MsgType.system:
        return _buildSystemBubble(msg);
      case _MsgType.reasoning:
        return _buildReasoningBubble(msg);
    }
  }

  Future<void> _playTts(String roleName, String text, String msgId) async {
    if (_ttsLoading) return;
    await _ttsPlayer.stop();
    setState(() {
      _ttsMessageId = msgId;
      _ttsLoading = true;
    });
    try {
      final audioBytes = await TtsService.instance.synthesizeByRole(
        roleName: roleName,
        text: text,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_playback.wav');
      await file.writeAsBytes(audioBytes);
      setState(() => _ttsLoading = false);
      await _ttsPlayer.play(DeviceFileSource(file.path));
    } catch (e) {
      if (mounted) {
        setState(() {
          _ttsMessageId = null;
          _ttsLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('TTS 失败: $e')));
      }
    }
  }

  Widget _buildUserBubble(_DisplayMessage msg) {
    final cs = Theme.of(context).colorScheme;
    final senderName = msg.senderName.isNotEmpty ? msg.senderName : 'user';
    final displayName = senderName.replaceAll('.md', '');

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _copyToClipboard(msg.content),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8, right: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatarCircle(senderName, cs),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Text(
                        msg.content,
                        style: TextStyle(color: cs.onSurface, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(_DisplayMessage msg) {
    final cs = Theme.of(context).colorScheme;
    final senderName = msg.senderName.isNotEmpty ? msg.senderName : 'AI';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatarCircle(senderName, cs),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: msg.isStreaming
                              ? null
                              : () => _playTts(senderName, msg.content, msg.id),
                          onLongPress: () => _copyToClipboard(msg.content),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                            ),
                            child: Stack(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(4),
                                      topRight: Radius.circular(16),
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        msg.content,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                      if (msg.isStreaming)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (_ttsMessageId == msg.id)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _ttsLoading
                                            ? Colors.black.withValues(
                                                alpha: 0.35,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.15,
                                              ),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(4),
                                          topRight: Radius.circular(16),
                                          bottomLeft: Radius.circular(16),
                                          bottomRight: Radius.circular(16),
                                        ),
                                      ),
                                      child: Center(
                                        child: _ttsLoading
                                            ? SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.equalizer,
                                                color: Colors.white,
                                                size: 22,
                                              ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (msg.status.contains('toast'))
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_outlined,
                              size: 14,
                              color: cs.onTertiaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${msg.statusType}: ${msg.statusContent}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemBubble(_DisplayMessage msg) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _copyToClipboard(msg.content),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8, right: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: cs.primaryContainer,
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        '系统',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Text(
                        msg.content,
                        style: TextStyle(fontSize: 14, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasoningBubble(_DisplayMessage msg) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primaryContainer,
              child: Icon(
                Icons.psychology_outlined,
                size: 16,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => msg.isExpanded = !msg.isExpanded),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            msg.isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '思考过程',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (msg.isExpanded)
                    GestureDetector(
                      onLongPress: () => _copyToClipboard(msg.content),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Text(
                          msg.content,
                          style: TextStyle(fontSize: 14, color: cs.onSurface),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.footerBg,
        border: Border(
          top: BorderSide(color: AppColors.divider.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: _currentModel == null ? '请先配置模型' : '输入消息...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppColors.bodyBg.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 14),
                enabled: _currentModel != null && !_isStreaming,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                icon: _isStreaming
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      )
                    : Icon(Icons.arrow_upward, size: 18, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: _isStreaming
                      ? AppColors.divider
                      : AppColors.accent,
                  padding: EdgeInsets.zero,
                ),
                onPressed: _isStreaming ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
