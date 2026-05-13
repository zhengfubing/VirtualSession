import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import '../services/chat_agent_service.dart';
import '../services/chat_state_service.dart';
import '../services/context_builder_service.dart';
import '../services/prompt_builder_service.dart';
import '../services/file_storage_service.dart';
import '../services/dialog_parser_service.dart';
import '../services/app_config_service.dart';
import '../services/tts_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_colors.dart';

/// 展示消息类型
enum DisplayMessageType { user, assistant, system, reasoning }

/// 展示消息
class DisplayMessage {
  final String id;
  final DisplayMessageType type;
  String senderName;
  String content;
  final String scene;
  final List<String> status;
  final String statusType;
  final String statusContent;
  bool isStreaming;
  bool isExpanded; // for reasoning
  final DateTime createdAt;
  String? dbMessageId; // 对应的 DB messages 表 ID，用于删除轮次

  DisplayMessage({
    required this.id,
    required this.type,
    this.senderName = '',
    required this.content,
    this.scene = '',
    this.status = const [],
    this.statusType = '',
    this.statusContent = '',
    this.isStreaming = false,
    this.isExpanded = false,
    DateTime? createdAt,
    this.dbMessageId,
  }) : createdAt = createdAt ?? DateTime.now();
}

class ChatPage extends StatefulWidget {
  final String? initialChatId;

  const ChatPage({super.key, this.initialChatId});

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  final _db = DatabaseHelper.instance;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _fileStorage = FileStorageService();
  static const _uuid = Uuid();
  final _ttsPlayer = AudioPlayer();

  // 会话状态
  List<Map<String, dynamic>> _chats = [];
  String? _currentChatId;
  Map<String, dynamic>? _currentChat;
  final List<DisplayMessage> _displayMessages = [];

  // 模型
  AIModel? _currentModel;

  // 设置选项
  String _selectedScene = 'empty';
  String _selectedSender = 'empty';
  List<String> _selectedRoles = [];
  String _currentModeId = 'ensemble';

  // 流式状态
  bool _isStreaming = false;

  // TTS 状态
  String? _ttsMessageId;
  bool _ttsLoading = false;
  StreamSubscription<ChatStreamEvent>? _streamSub;


  /// 外部调用：加载指定会话
  void loadChat(String chatId) {
    _loadChats().then((_) => _selectChat(chatId));
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
    _loadChats();
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

  // ==================== 数据加载 ====================

  Future<void> _loadModel() async {
    final modelName = AppConfigService.instance.agentModelChat;
    final modelMap = await _db.getModelByName(modelName);
    if (modelMap != null && mounted) {
      setState(() => _currentModel = AIModel.fromMap(modelMap));
    }
  }

  Future<void> _loadChats() async {
    final chats = await ChatStateService.instance.listChats();
    if (!mounted) return;
    setState(() => _chats = chats);
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
    final chat = await ChatStateService.instance.getChat(chatId);
    if (chat == null || !mounted) return;

    final roleIdsJson = chat['role_setting_prompt_ids_json'] as String? ?? '[]';
    List<String> roleIds;
    try {
      roleIds = (jsonDecode(roleIdsJson) as List).cast<String>();
    } catch (_) {
      roleIds = [];
    }

    setState(() {
      _currentChatId = chatId;
      _currentChat = chat;
      _selectedScene = chat['scene_prompt_id'] as String? ?? 'empty';
      _selectedSender = chat['sender_id'] as String? ?? 'empty';
      _selectedRoles = roleIds;
      _currentModeId = chat['mode_id'] as String? ?? 'ensemble';
    });

    await _loadDisplayHistory(chatId);
  }

  Future<void> _loadDisplayHistory(String chatId) async {
    final messages = await ChatStateService.instance.getDisplayHistory(chatId);
    if (!mounted) return;

    final display = <DisplayMessage>[];
    for (var msg in messages) {
      final role = msg['role'] as String? ?? 'user';
      final content = msg['content'] as String? ?? '';
      final senderName = msg['sender_name'] as String?;

      final dbId = msg['id'] as String?;
      if (role == 'user') {
        display.add(
          DisplayMessage(
            id: dbId ?? _uuid.v4(),
            type: DisplayMessageType.user,
            senderName: senderName ?? '',
            content: _extractUserDisplayText(content),
            dbMessageId: dbId,
          ),
        );
      } else if (role == 'assistant') {
        // 尝试解析结构化对话
        final items = DialogParserService.instance.parseDialogItemsFromText(
          content,
        );
        if (items != null && items.isNotEmpty) {
          for (var item in items) {
            display.add(
              DisplayMessage(
                id: _uuid.v4(),
                type: DisplayMessageType.assistant,
                senderName: item.senderName,
                content: item.messageContent,
                scene: item.scene,
                status: item.status,
                statusType: item.statusType,
                statusContent: item.statusContent,
                dbMessageId: dbId,
              ),
            );
          }
        } else {
          display.add(
            DisplayMessage(
              id: dbId ?? _uuid.v4(),
              type: DisplayMessageType.assistant,
              senderName: senderName ?? '',
              content: _stripDisplayFence(content),
              dbMessageId: dbId,
            ),
          );
        }
      } else if (role == 'system') {
        display.add(
          DisplayMessage(
            id: dbId ?? _uuid.v4(),
            type: DisplayMessageType.system,
            content: _extractSystemDisplayText(content),
            dbMessageId: dbId,
          ),
        );
      }
    }

    setState(() => _displayMessages.clear());
    setState(() => _displayMessages.addAll(display));
    _scrollToBottom();
  }

  /// 显示层防护：去除 markdown JSON 围栏，尝试提取 message_content
  String _stripDisplayFence(String content) {
    var clean = content.trim();
    // 去除 ```json ... ``` 围栏
    if (clean.startsWith('```')) {
      final firstNewline = clean.indexOf('\n');
      if (firstNewline != -1) {
        clean = clean.substring(firstNewline + 1);
      }
    }
    if (clean.endsWith('```')) {
      clean = clean.substring(0, clean.length - 3).trimRight();
    }
    // 尝试解析 JSON 提取 message_content
    try {
      final data = jsonDecode(clean);
      if (data is Map<String, dynamic>) {
        final payload = data['payload'];
        if (payload is Map<String, dynamic>) {
          final messages = payload['messages'];
          if (messages is List && messages.isNotEmpty) {
            final first = messages.first;
            if (first is Map<String, dynamic>) {
              return (first['message_content'] ?? clean).toString();
            }
          }
        }
        return (data['message_content'] ?? clean).toString();
      }
    } catch (_) {}
    return clean;
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
    // 系统消息可能是多层JSON转义的字符串，需要解码
    String decoded = content;
    // 尝试多次解码，处理多层转义
    for (var i = 0; i < 3; i++) {
      try {
        final result = jsonDecode(decoded);
        if (result is String) {
          decoded = result;
        } else if (result is Map<String, dynamic>) {
          // 如果是对象，尝试提取message_content
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

  // ==================== 发送消息 ====================

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentModel == null || _isStreaming) return;
    if (_currentChatId == null) {
      // 自动创建会话
      final chatId = await ChatStateService.instance.createChat(
        name: '对话 ${_chats.length + 1}',
      );
      await _loadChats();
      _selectChat(chatId);
    }

    _messageController.clear();

    // 添加用户消息到展示
    final senderLabel = _selectedSender != 'empty' ? _selectedSender : 'user';
    final userMsg = DisplayMessage(
      id: _uuid.v4(),
      type: DisplayMessageType.user,
      senderName: senderLabel,
      content: text,
    );
    setState(() => _displayMessages.add(userMsg));
    _scrollToBottom();

    // 保存用户消息到 DB（display 存纯文本，context 存 JSON）
    final userMsgJson = DialogParserService.instance.buildUserMessageJson(
      senderName: _selectedSender,
      userInput: text,
      sceneName: _selectedScene != 'empty' ? _selectedScene : '',
    );
    await ChatStateService.instance.addMessage(
      chatId: _currentChatId!,
      role: 'user',
      content: text,
      senderName: _selectedSender != 'empty' ? _selectedSender : null,
    );
    await ChatStateService.instance.addContextItem(
      chatId: _currentChatId!,
      role: 'user',
      content: userMsgJson,
    );

    // 构建上下文
    final chatState = await ChatStateService.instance.ensureChatState(
      _currentChatId!,
    );
    final contextMessages = ContextBuilderService.instance
        .buildEffectiveContext(chatState: chatState, recentKeep: 12);

    // 创建流式助手消息占位
    final streamingMsg = DisplayMessage(
      id: _uuid.v4(),
      type: DisplayMessageType.assistant,
      senderName: '',
      content: '',
      isStreaming: true,
    );
    setState(() {
      _displayMessages.add(streamingMsg);
      _isStreaming = true;
    });

    // 调用 chat agent
    // Solo 模式：预构建系统提示词
    String? soloSystemPrompt;
    if (_currentModeId == 'solo' && _selectedRoles.length >= 2) {
      final promptResult = await PromptBuilderService.buildSoloSystemPrompt(
        userRoleName: _selectedRoles[0],
        aiRoleName: _selectedRoles[1],
        scenePromptId: _selectedScene,
      );
      soloSystemPrompt = promptResult['full_system_prompt'] as String?;
    }

    final config = ChatConfig(
      roleSettingPromptIds: _selectedRoles,
      scenePromptId: _selectedScene,
      senderName: _selectedSender,
      userInput: text,
      model: _currentModel!,
      enableThinking: AppConfigService.instance.enableThinking,
      chatId: _currentChatId!,
      historyMessages: contextMessages,
      userMessageJson: userMsgJson,
      fullSystemPrompt: soloSystemPrompt,
    );

    String accumulatedAnswer = '';
    String accumulatedReasoning = '';
    final streamingBaseId = streamingMsg.id;
    final shownToastKeys = <String>{};

    _streamSub = ChatAgentService.instance
        .chatStream(config)
        .listen(
          (event) {
            if (!mounted) return;
            switch (event.type) {
              case ChatStreamEventType.content:
                accumulatedAnswer += event.content ?? '';
                _applyStreamedDelta(
                  streamingBaseId,
                  streamingMsg,
                  accumulatedAnswer,
                  shownToastKeys,
                );
                _scrollToBottom();
                break;
              case ChatStreamEventType.reasoning:
                accumulatedReasoning += event.reasoning ?? '';
                _updateReasoningDisplay(accumulatedReasoning);
                break;
              case ChatStreamEventType.done:
                _handleStreamDone(
                  event.result!,
                  streamingMsg,
                  accumulatedAnswer,
                );
                break;
              case ChatStreamEventType.error:
                setState(() {
                  streamingMsg.content = '错误: ${event.error}';
                  streamingMsg.isStreaming = false;
                  _isStreaming = false;
                });
                break;
            }
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              streamingMsg.content = '错误: $error';
              streamingMsg.isStreaming = false;
              _isStreaming = false;
            });
          },
        );
  }

  DisplayMessage _ensureAssistantAtOffset(
    String baseId,
    DisplayMessage anchor,
    int offset,
  ) {
    if (offset == 0) return anchor;
    final anchorIdx = _displayMessages.indexOf(anchor);
    if (anchorIdx < 0) return anchor;
    final targetIdx = anchorIdx + offset;
    if (targetIdx < _displayMessages.length) {
      final existing = _displayMessages[targetIdx];
      if (existing.type == DisplayMessageType.assistant &&
          existing.id.startsWith(baseId)) {
        return existing;
      }
    }
    final newMsg = DisplayMessage(
      id: '$baseId-a-$offset',
      type: DisplayMessageType.assistant,
      senderName: '',
      content: '',
      isStreaming: true,
    );
    _displayMessages.insert(targetIdx, newMsg);
    return newMsg;
  }

  void _applyStreamedDelta(
    String baseId,
    DisplayMessage anchor,
    String rawText,
    Set<String> shownToastKeys,
  ) {
    final items = DialogParserService.instance.parseStreamedReplyItems(rawText);
    if (items.isEmpty) return;

    final pendingToasts = <(String, String)>[];

    setState(() {
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final msgRef = _ensureAssistantAtOffset(baseId, anchor, i);
        if (item.senderName.isNotEmpty) {
          msgRef.senderName = item.senderName;
          msgRef.isStreaming = false;
        }
        msgRef.content = item.content;
        if (item.status.contains('toast') &&
            item.statusType.isNotEmpty &&
            item.statusContent.isNotEmpty &&
            item.complete) {
          final toastKey = '$baseId-$i-${item.statusContent}';
          if (!shownToastKeys.contains(toastKey)) {
            shownToastKeys.add(toastKey);
            pendingToasts.add((item.statusType, item.statusContent));
          }
        }
      }
    });

    for (final (type, content) in pendingToasts) {
      _showToastDialog(type, content);
    }
  }

  void _updateReasoningDisplay(String reasoning) {
    final existingIdx = _displayMessages.lastIndexWhere(
      (m) => m.type == DisplayMessageType.reasoning,
    );
    if (existingIdx >= 0) {
      setState(() {
        _displayMessages[existingIdx].content = reasoning;
      });
    } else {
      setState(() {
        _displayMessages.insert(
          _displayMessages.length - 1,
          DisplayMessage(
            id: _uuid.v4(),
            type: DisplayMessageType.reasoning,
            content: reasoning,
            isExpanded: false,
          ),
        );
      });
    }
  }

  Future<void> _handleStreamDone(
    ChatResult result,
    DisplayMessage streamingMsg,
    String finalAnswer,
  ) async {
    final items = DialogParserService.instance.parseDialogItemsFromText(
      finalAnswer,
    );

    setState(() {
      for (final msg in _displayMessages) {
        if (msg.type == DisplayMessageType.assistant && msg.isStreaming) {
          msg.isStreaming = false;
        }
      }
      _isStreaming = false;
    });

    if (items != null && items.isNotEmpty) {
      final anchorIdx = _displayMessages.indexOf(streamingMsg);
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (anchorIdx + i < _displayMessages.length) {
          final msg = _displayMessages[anchorIdx + i];
          msg.senderName = item.senderName;
          msg.content = item.messageContent;
        }
      }

      await ChatStateService.instance.addMessage(
        chatId: _currentChatId!,
        role: 'assistant',
        content: finalAnswer,
        senderName: items.first.senderName,
      );
      await ChatStateService.instance.addContextItem(
        chatId: _currentChatId!,
        role: 'assistant',
        content: finalAnswer,
      );
    } else {
      streamingMsg.senderName = '';
      streamingMsg.content = finalAnswer.isEmpty ? '(无回复)' : _stripDisplayFence(finalAnswer);

      await ChatStateService.instance.addMessage(
        chatId: _currentChatId!,
        role: 'assistant',
        content: finalAnswer,
      );
      await ChatStateService.instance.addContextItem(
        chatId: _currentChatId!,
        role: 'assistant',
        content: finalAnswer,
      );
    }

    _scrollToBottom();
    _loadChats();
  }

  void _showToastDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
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

  void _copyToClipboard(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  void _showMessageActions(DisplayMessage msg) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.copy, color: cs.onSurface),
                title: Text('复制消息', style: TextStyle(color: cs.onSurface)),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyToClipboard(
                    msg.type == DisplayMessageType.assistant
                        ? _stripDisplayFence(msg.content)
                        : msg.content,
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('删除此轮对话', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteCurrentRound(msg);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteCurrentRound(DisplayMessage msg) async {
    if (_currentChatId == null) return;
    if (_isStreaming) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请等待回复完成后再删除'), duration: Duration(seconds: 1)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除此轮对话吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final targetId = msg.dbMessageId ?? msg.id;
    final roundIds = await ChatStateService.instance.getRoundMessageIds(
      _currentChatId!,
      targetId,
    );

    if (roundIds.isEmpty) return;

    await ChatStateService.instance.deleteRound(
      chatId: _currentChatId!,
      messageIds: roundIds,
    );

    await _loadDisplayHistory(_currentChatId!);
  }

  // ==================== 设置弹窗 ====================

  Future<void> _showSettingsDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('对话设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_currentModeId != 'solo') ...[
                  const Text(
                    '当前发送者',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSender,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(value: 'empty', child: Text('user')),
                      ..._selectedRoles.map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.replaceAll('.md', '')),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setDialogState(() => _selectedSender = v ?? 'empty');
                      _saveChatSettings();
                    },
                  ),
                ] else ...[
                  Text(
                    '发送者：${_selectedSender.replaceAll('.md', '')}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '独幕模式发送角色在创建时固定，不可切换',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveChatSettings() async {
    if (_currentChatId == null) return;
    await ChatStateService.instance.updateChatSettings(
      chatId: _currentChatId!,
      scenePromptId: _selectedScene,
      senderId: _selectedSender,
      roleSettingPromptIds: _selectedRoles,
    );
  }

  // ==================== 长按标题触发 Debug ====================

  Timer? _longPressTimer;

  void _onTitleLongPressStart(LongPressStartDetails details) {
    _longPressTimer = Timer(const Duration(seconds: 5), () {
      _showContextDebug();
    });
  }

  // ==================== 角色选择器 ====================

  Widget _buildRoleSelector() {
    final cs = Theme.of(context).colorScheme;
    final allSenders = ['empty', ..._selectedRoles];

    return PopupMenuButton<String>(
      onSelected: (roleId) {
        setState(() => _selectedSender = roleId);
        _saveChatSettings();
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (context) => allSenders.map((r) {
        final display = r == 'empty' ? 'User' : r.replaceAll('.md', '');
        final isSelected = _selectedSender == r;
        return PopupMenuItem<String>(
          value: r,
          child: Row(
            children: [
              _buildAvatarCircle(r == 'empty' ? 'User' : r, cs, radius: 14),
              const SizedBox(width: 10),
              Text(
                display,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? cs.primary : cs.onSurface,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(Icons.check, size: 16, color: cs.primary),
              ],
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAvatarCircle(
              _selectedSender == 'empty' ? 'User' : _selectedSender,
              cs,
              radius: 14,
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 16, color: cs.onSurfaceVariant),
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
          ? [Text('  (空)', style: TextStyle(color: AppColors.subText))]
          : items
                .map(
                  (item) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.divider.withAlpha(25),
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

  // ==================== UI 构建 ====================

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
          onTap: _currentChatId != null ? _showSettingsDialog : null,
          onLongPressStart: _currentChatId != null
              ? (details) => _onTitleLongPressStart(details)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentChat?['name'] ?? 'AI 聊天',
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
          if (_currentChatId != null && _currentModeId != 'solo') _buildRoleSelector(),
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
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppColors.subText,
            ),
            const SizedBox(height: 12),
            Text(
              '开始对话吧',
              style: TextStyle(color: AppColors.subText, fontSize: 15),
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

  Widget _buildMessageItem(DisplayMessage msg) {
    switch (msg.type) {
      case DisplayMessageType.user:
        return _buildUserBubble(msg);
      case DisplayMessageType.assistant:
        return _buildAssistantBubble(msg);
      case DisplayMessageType.system:
        return _buildSystemBubble(msg);
      case DisplayMessageType.reasoning:
        return _buildReasoningBubble(msg);
    }
  }

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

  Widget _buildUserBubble(DisplayMessage msg) {
    final cs = Theme.of(context).colorScheme;
    final senderName = msg.senderName.isNotEmpty ? msg.senderName : 'user';
    final displayName = senderName.replaceAll('.md', '');
    final isSolo = _currentModeId == 'solo';

    if (isSolo) {
      // Solo: right-aligned, avatar on right
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 48),
        child: GestureDetector(
          onLongPress: () => _showMessageActions(msg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 4),
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
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(4),
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
              const SizedBox(width: 8),
              _buildAvatarCircle(senderName, cs),
            ],
          ),
        ),
      );
    }

    // Ensemble: left-aligned, avatar on left
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(msg),
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

  Widget _buildAssistantBubble(DisplayMessage msg) {
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
                              : () => _playTts(senderName, _stripDisplayFence(msg.content), msg.id),
                          onLongPress: () => _showMessageActions(msg),
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
                                        _stripDisplayFence(msg.content),
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

  Widget _buildSystemBubble(DisplayMessage msg) {
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

  Widget _buildReasoningBubble(DisplayMessage msg) {
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
