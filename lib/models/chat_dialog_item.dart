import 'dart:convert';

/// 单条角色回复固定对象
/// 对应 Python: ChatDialogItem (TypedDict)
class ChatDialogItem {
  final String senderName;
  final List<String> status;
  final String statusType;
  final String statusContent;
  final String scene;
  final String messageContent;

  ChatDialogItem({
    required this.senderName,
    this.status = const [],
    this.statusType = '',
    this.statusContent = '',
    this.scene = '',
    required this.messageContent,
  });

  /// 从 Map 创建对象
  factory ChatDialogItem.fromJson(Map<String, dynamic> json) {
    return ChatDialogItem(
      senderName: json['sender_name'] as String? ?? '',
      status: _parseStatusList(json['status']),
      statusType: json['status_type'] as String? ?? '',
      statusContent: json['status_content'] as String? ?? '',
      scene: json['scene'] as String? ?? '',
      messageContent: json['message_content'] as String? ?? '',
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toJson() {
    return {
      'sender_name': senderName,
      'status': status,
      'status_type': statusType,
      'status_content': statusContent,
      'scene': scene,
      'message_content': messageContent,
    };
  }

  /// 转换为 JSON 字符串
  String toJsonString() => jsonEncode(toJson());

  /// 从 JSON 字符串解析
  factory ChatDialogItem.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return ChatDialogItem.fromJson(json);
  }

  /// 是否是 toast 弹窗消息
  bool get isToast => status.contains('toast');

  /// 是否是跨场景通讯
  bool get isCrossSceneCall =>
      status.any((s) => s.toLowerCase().contains('calls'));

  ChatDialogItem copyWith({
    String? senderName,
    List<String>? status,
    String? statusType,
    String? statusContent,
    String? scene,
    String? messageContent,
  }) {
    return ChatDialogItem(
      senderName: senderName ?? this.senderName,
      status: status ?? this.status,
      statusType: statusType ?? this.statusType,
      statusContent: statusContent ?? this.statusContent,
      scene: scene ?? this.scene,
      messageContent: messageContent ?? this.messageContent,
    );
  }

  /// 解析 status 字段（可能是 List 或 JSON 字符串）
  static List<String> _parseStatusList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final parsed = jsonDecode(value);
        if (parsed is List) {
          return parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
      return [value];
    }
    return [];
  }
}
