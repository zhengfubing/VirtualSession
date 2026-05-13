import 'dart:async';
import 'dart:convert';
import '../database/database_helper.dart';
import '../models/ai_model.dart';
import 'ai_service.dart';
import 'app_config_service.dart';
import 'prompt_builder_service.dart';
import 'dialog_parser_service.dart';
import 'token_usage_service.dart';
import 'round_tracking_service.dart';
import 'compression_service.dart';
import 'solo_memory_service.dart';

/// 对话执行配置
class ChatConfig {
  final List<String> roleSettingPromptIds;
  final String scenePromptId;
  final String senderName;
  final String userInput;
  final AIModel model;
  final bool enableThinking;
  final String chatId;
  final String agentType;

  /// 预构建的系统提示词（world_chat 场景传入）
  final String? fullSystemPrompt;

  /// 预构建的历史消息 JSON 字符串列表（context_builder 输出）
  /// 每个元素是 JSON 字符串: '{"role":"user","content":"..."}'
  final List<String>? historyMessages;

  /// 预构建的用户消息 JSON 字符串（与 Python user_message_json 对齐）
  /// 格式: '{"sender_name":"...","message_content":"..."}'
  final String? userMessageJson;

  ChatConfig({
    this.roleSettingPromptIds = const [],
    this.scenePromptId = '',
    this.senderName = '',
    required this.userInput,
    required this.model,
    this.enableThinking = false,
    this.chatId = '',
    this.agentType = 'chat_agent',
    this.fullSystemPrompt,
    this.historyMessages,
    this.userMessageJson,
  });
}

/// 对话执行结果
class ChatResult {
  final String reasoning;
  final String answer;
  final Map<String, dynamic>? usage;
  final Map<String, dynamic> meta;
  final String? error;

  ChatResult({
    this.reasoning = '',
    this.answer = '',
    this.usage,
    this.meta = const {},
    this.error,
  });
}

/// 统一对话执行服务
/// 参考 Python chat/chat_agent.py
/// 从 system prompt 构建 -> context 获取 -> model 调用 -> 结果解析
class ChatAgentService {
  static final ChatAgentService instance = ChatAgentService._();
  ChatAgentService._();

  /// 检查历史消息中是否已包含当前用户消息
  /// 所有消息都是 JSON 字符串格式
  bool _historyAlreadyContainsCurrentUserMessage(
    List<String> messages,
    String userInput,
  ) {
    if (messages.isEmpty) return false;

    try {
      final lastMsgJson = jsonDecode(messages.last) as Map<String, dynamic>;
      if ((lastMsgJson['role'] ?? '') != 'user') return false;

      final content = lastMsgJson['content'];
      if (content is String) {
        // content 可能是 UserMessageContent 的 JSON 字符串
        if (content == userInput) return true;
        try {
          final decoded = jsonDecode(content) as Map<String, dynamic>;
          return (decoded['message_content'] ?? '').toString() == userInput;
        } catch (_) {
          return false;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 统一对话执行入口（流式）
  ///
  /// 返回 Stream，逐步产出内容 delta、reasoning 等。
  /// 最终通过 [ChatStreamEvent.done] 返回完整结果。
  Stream<ChatStreamEvent> chatStream(ChatConfig config) async* {
    if (config.userInput.trim().isEmpty) {
      yield ChatStreamEvent.error('用户输入不能为空');
      return;
    }

    // ── 1. 系统提示词 ──
    String systemPrompt;
    String sceneName = '';
    if (config.fullSystemPrompt != null &&
        config.fullSystemPrompt!.isNotEmpty) {
      systemPrompt = config.fullSystemPrompt!;
    } else {
      final promptContext = await PromptBuilderService.buildChatSystemPrompt(
        roleSettingPromptIds: config.roleSettingPromptIds,
        scenePromptId: config.scenePromptId,
        senderName: config.senderName,
        userInput: config.userInput,
      );
      systemPrompt = (promptContext['full_system_prompt'] as String?) ?? '';
      sceneName = (promptContext['scene_name'] as String?) ?? '';
    }

    // ── 2. 组装消息 ──
    // 所有消息都以 JSON 字符串形式传递
    final messages = <String>[];
    if (config.historyMessages != null) {
      messages.addAll(config.historyMessages!);
    }
    // 构建当前用户消息 JSON 字符串
    // content 使用纯文本 userInput，而不是 JSON 格式的 userMessageJson
    if (!_historyAlreadyContainsCurrentUserMessage(
      messages,
      config.userInput,
    )) {
      messages.add(jsonEncode({'role': 'user', 'content': config.userInput}));
    }

    // ── 4. Round 追踪 ──
    String? roundId;
    if (config.chatId.isNotEmpty) {
      try {
        roundId = await RoundTrackingService.instance.createRound(
          chatId: config.chatId,
          modelName: config.model.name,
          enableThinking: config.enableThinking,
          promptSnapshotJson: jsonEncode({
            'system_prompt_length': systemPrompt.length,
            'messages_count': messages.length,
          }),
        );
      } catch (_) {}
    }

    int totalPromptTokens = 0;
    int totalCompletionTokens = 0;

    try {
      // ── 5. 模型调用 ──
      final memoryTools = await _getMemoryTools(config.chatId);
      final stream = AIService.streamChatCompletion(
        model: config.model,
        messages: messages,
        systemPrompt: systemPrompt,
        extraBody: {
          'enable_thinking': config.enableThinking,
          'enable_search': AppConfigService.instance.enableSearch,
        },
        tools: memoryTools,
      );

      String finalAnswer = '';
      String finalReasoning = '';
      Map<String, dynamic>? currentUsage;

      await for (final event in stream) {
        if (event.reasoningContent != null &&
            event.reasoningContent!.isNotEmpty) {
          finalReasoning += event.reasoningContent!;
          yield ChatStreamEvent.reasoning(event.reasoningContent!);
        }
        if (event.content != null && event.content!.isNotEmpty) {
          finalAnswer += event.content!;
          yield ChatStreamEvent.content(event.content!);
        }
        if (event.usage != null) {
          currentUsage = event.usage;
        }
      }

      // 累计 token
      if (currentUsage != null) {
        totalPromptTokens +=
            (currentUsage['prompt_tokens'] as num?)?.toInt() ?? 0;
        totalCompletionTokens +=
            (currentUsage['completion_tokens'] as num?)?.toInt() ?? 0;
      }

      // ── 6. 解析结果 ──
      final parsedItems = DialogParserService.instance.parseDialogItemsFromText(
        finalAnswer,
      );
      final senderNickname = parsedItems != null && parsedItems.isNotEmpty
          ? parsedItems.first.senderName
          : '';
      final senderNicknameList =
          parsedItems?.map((item) => item.senderName).toList() ?? [];

      // ── 7. 记录 token ──
      if (config.chatId.isNotEmpty) {
        await TokenUsageService.instance.addTokenUsage(
          chatId: config.chatId,
          agentType: config.agentType,
          promptTokens: totalPromptTokens,
          completionTokens: totalCompletionTokens,
          roundId: roundId,
          modelName: config.model.name,
        );
      }

      // ── 8. 完成 round ──
      if (roundId != null) {
        try {
          await RoundTrackingService.instance.finishRound(
            roundId: roundId,
            status: 'completed',
            reasoning: finalReasoning,
          );
        } catch (_) {}
      }

      // ── 9. 异步触发压缩 ──
      if (config.chatId.isNotEmpty) {
        _triggerCompression(config.chatId, config.model);
      }

      // ── 10. 返回结果 ──
      final result = ChatResult(
        reasoning: finalReasoning,
        answer: finalAnswer,
        usage: {
          'prompt_tokens': totalPromptTokens,
          'completion_tokens': totalCompletionTokens,
        },
        meta: {
          'usage': {
            'prompt_tokens': totalPromptTokens,
            'completion_tokens': totalCompletionTokens,
          },
          'final_answer': finalAnswer,
          'sender_nickname': senderNickname,
          'sender_nickname_list': senderNicknameList,
        },
      );

      yield ChatStreamEvent.done(result);
    } catch (e) {
      if (roundId != null) {
        try {
          await RoundTrackingService.instance.finishRound(
            roundId: roundId,
            status: 'failed',
            errorMessage: e.toString(),
          );
        } catch (_) {}
      }
      yield ChatStreamEvent.error(e.toString());
    }
  }

  /// 非流式对话执行
  Future<ChatResult> chat(ChatConfig config) async {
    if (config.userInput.trim().isEmpty) {
      return ChatResult(error: '用户输入不能为空');
    }

    // ── 1. 系统提示词 ──
    String systemPrompt;
    String sceneName = '';
    if (config.fullSystemPrompt != null &&
        config.fullSystemPrompt!.isNotEmpty) {
      systemPrompt = config.fullSystemPrompt!;
    } else {
      final promptContext = await PromptBuilderService.buildChatSystemPrompt(
        roleSettingPromptIds: config.roleSettingPromptIds,
        scenePromptId: config.scenePromptId,
        senderName: config.senderName,
        userInput: config.userInput,
      );
      systemPrompt = (promptContext['full_system_prompt'] as String?) ?? '';
      sceneName = (promptContext['scene_name'] as String?) ?? '';
    }

    // ── 2. 组装消息 ──
    // 所有消息都以 JSON 字符串形式传递
    final messages = <String>[];
    if (config.historyMessages != null) {
      messages.addAll(config.historyMessages!);
    }
    // 构建当前用户消息 JSON 字符串
    // content 使用纯文本 userInput，而不是 JSON 格式的 userMessageJson
    if (!_historyAlreadyContainsCurrentUserMessage(
      messages,
      config.userInput,
    )) {
      messages.add(jsonEncode({'role': 'user', 'content': config.userInput}));
    }

    // ── 4. Round 追踪 ──
    String? roundId;
    if (config.chatId.isNotEmpty) {
      try {
        roundId = await RoundTrackingService.instance.createRound(
          chatId: config.chatId,
          modelName: config.model.name,
          enableThinking: config.enableThinking,
          promptSnapshotJson: jsonEncode({
            'system_prompt_length': systemPrompt.length,
            'messages_count': messages.length,
          }),
        );
      } catch (_) {}
    }

    int totalPromptTokens = 0;
    int totalCompletionTokens = 0;

    try {
      // ── 5. 模型调用 ──
      final memoryTools = await _getMemoryTools(config.chatId);
      final result = await AIService.chatCompletion(
        model: config.model,
        messages: messages,
        systemPrompt: systemPrompt,
        extraBody: {
          'enable_thinking': config.enableThinking,
          'enable_search': AppConfigService.instance.enableSearch,
        },
        tools: memoryTools,
      );

      if (result.usage != null) {
        totalPromptTokens +=
            (result.usage!['prompt_tokens'] as num?)?.toInt() ?? 0;
        totalCompletionTokens +=
            (result.usage!['completion_tokens'] as num?)?.toInt() ?? 0;
      }

      // 解析结果
      final parsedItems = DialogParserService.instance.parseDialogItemsFromText(
        result.answer,
      );
      final senderNickname = parsedItems != null && parsedItems.isNotEmpty
          ? parsedItems.first.senderName
          : '';
      final senderNicknameList =
          parsedItems?.map((item) => item.senderName).toList() ?? [];

      // 记录 token
      if (config.chatId.isNotEmpty) {
        await TokenUsageService.instance.addTokenUsage(
          chatId: config.chatId,
          agentType: config.agentType,
          promptTokens: totalPromptTokens,
          completionTokens: totalCompletionTokens,
          roundId: roundId,
          modelName: config.model.name,
        );
      }

      // 完成 round
      if (roundId != null) {
        try {
          await RoundTrackingService.instance.finishRound(
            roundId: roundId,
            status: 'completed',
            reasoning: result.reasoning,
          );
        } catch (_) {}
      }

      // 异步触发压缩
      if (config.chatId.isNotEmpty) {
        _triggerCompression(config.chatId, config.model);
      }

      return ChatResult(
        reasoning: result.reasoning,
        answer: result.answer,
        usage: result.usage,
        meta: {
          'usage': {
            'prompt_tokens': totalPromptTokens,
            'completion_tokens': totalCompletionTokens,
          },
          'final_answer': result.answer,
          'sender_nickname': senderNickname,
          'sender_nickname_list': senderNicknameList,
        },
      );
    } catch (e) {
      if (roundId != null) {
        try {
          await RoundTrackingService.instance.finishRound(
            roundId: roundId,
            status: 'failed',
            errorMessage: e.toString(),
          );
        } catch (_) {}
      }
      return ChatResult(error: e.toString());
    }
  }

  /// 获取记忆工具定义（仅 Solo 模式）
  Future<List<Map<String, dynamic>>?> _getMemoryTools(String chatId) async {
    if (chatId.isEmpty) return null;
    final db = DatabaseHelper.instance;
    final session = await db.query(
      'solo_sessions',
      where: 'id = ?',
      whereArgs: [chatId],
    );
    if (session.isEmpty) return null;
    return SoloMemoryService.getMemoryToolDefinitions();
  }

  /// 异步触发 A/B 压缩（不阻塞主流程）
  void _triggerCompression(String chatId, AIModel fallbackModel) {
    final db = DatabaseHelper.instance;
    final compressionModelName =
        AppConfigService.instance.agentModelCompression;
    db
        .getModelByName(compressionModelName)
        .then((modelMap) {
          final model = modelMap != null
              ? AIModel.fromMap(modelMap)
              : fallbackModel;
          return CompressionService.instance.scheduleCompression(
            chatId: chatId,
            model: model,
          );
        })
        .catchError((e) {
          // 压缩失败不影响主流程
        });
  }
}

/// 流式事件类型
class ChatStreamEvent {
  final ChatStreamEventType type;
  final String? content;
  final String? reasoning;
  final ChatResult? result;
  final String? error;

  ChatStreamEvent._({
    required this.type,
    this.content,
    this.reasoning,
    this.result,
    this.error,
  });

  factory ChatStreamEvent.content(String content) =>
      ChatStreamEvent._(type: ChatStreamEventType.content, content: content);

  factory ChatStreamEvent.reasoning(String reasoning) => ChatStreamEvent._(
    type: ChatStreamEventType.reasoning,
    reasoning: reasoning,
  );

  factory ChatStreamEvent.done(ChatResult result) =>
      ChatStreamEvent._(type: ChatStreamEventType.done, result: result);

  factory ChatStreamEvent.error(String error) =>
      ChatStreamEvent._(type: ChatStreamEventType.error, error: error);
}

enum ChatStreamEventType { content, reasoning, done, error }
