import 'dart:convert';
import 'chat_dialog_item.dart';

/// 对话回复固定对象
/// 对应 Python: ChatDialogPayload (TypedDict)
class ChatDialogPayload {
  final int senderCount;
  final List<String> senderNames;
  final String? worldScene;
  final List<ChatDialogItem> messages;

  ChatDialogPayload({
    required this.senderCount,
    required this.senderNames,
    this.worldScene,
    required this.messages,
  });

  /// 从 Map 创建对象
  /// 支持两种格式：
  /// 1. {"type":"dialog", "payload":{...}}  （标准格式）
  /// 2. {"messages":[...], "sender_names":[...], ...}  （无 type 包装）
  factory ChatDialogPayload.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> payload;

    // 两种格式：{type: "dialog", payload: {...}} 或直接 {messages: [...]}
    if (json['type'] == 'dialog') {
      payload = json['payload'] as Map<String, dynamic>? ?? {};
    } else if (json['messages'] is List) {
      // 兼容：LLM 直接返回 payload 结构，没有 type 包装
      payload = json;
    } else {
      payload = {};
    }

    final rawMessages = payload['messages'] as List<dynamic>? ?? [];
    final messages = rawMessages
        .whereType<Map<String, dynamic>>()
        .map((m) => ChatDialogItem.fromJson(m))
        .toList();

    return ChatDialogPayload(
      senderCount: payload['sender_count'] as int? ?? messages.length,
      senderNames: (payload['sender_names'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      worldScene: payload['world_scene'] as String?,
      messages: messages,
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toJson() {
    return {
      'sender_count': senderCount,
      'sender_names': senderNames,
      'world_scene': worldScene,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }

  /// 转换为 JSON 字符串
  String toJsonString() => jsonEncode(toJson());

  /// 从 JSON 字符串解析
  factory ChatDialogPayload.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return ChatDialogPayload.fromJson(json);
  }

  /// 验证 payload 是否有效
  bool get isValid {
    if (senderCount <= 0) return false;
    if (senderCount != senderNames.length) return false;
    if (senderCount != messages.length) return false;
    // 验证所有消息的 sender_name 都在 sender_names 列表中
    for (final msg in messages) {
      if (!senderNames.contains(msg.senderName)) return false;
    }
    return true;
  }

  ChatDialogPayload copyWith({
    int? senderCount,
    List<String>? senderNames,
    String? worldScene,
    List<ChatDialogItem>? messages,
  }) {
    return ChatDialogPayload(
      senderCount: senderCount ?? this.senderCount,
      senderNames: senderNames ?? this.senderNames,
      worldScene: worldScene ?? this.worldScene,
      messages: messages ?? this.messages,
    );
  }
}
