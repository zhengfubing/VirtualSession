import 'dart:convert';

/// 用户消息内容对象
/// 对应 Python: build_user_message_json 函数返回的字典结构
class UserMessageContent {
  final String senderName;
  final List<String> status;
  final String statusType;
  final String statusContent;
  final String scene;
  final String messageContent;

  UserMessageContent({
    required this.senderName,
    this.status = const [],
    this.statusType = '',
    this.statusContent = '',
    this.scene = '',
    required this.messageContent,
  });

  /// 从 Map 创建对象
  factory UserMessageContent.fromJson(Map<String, dynamic> json) {
    return UserMessageContent(
      senderName: json['sender_name'] as String? ?? '',
      status: _parseStatusList(json['status']),
      statusType: json['status_type'] as String? ?? '',
      statusContent: json['status_content'] as String? ?? '',
      scene: json['scene'] as String? ?? '',
      messageContent: json['message_content'] as String? ?? '',
    );
  }

  /// 转换为 Map（用于 API 请求）
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

  /// 转换为 JSON 字符串（用于数据库存储）
  String toJsonString() => jsonEncode(toJson());

  /// 从 JSON 字符串解析（用于从数据库读取）
  factory UserMessageContent.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return UserMessageContent.fromJson(json);
  }

  /// 尝试解析，如果失败返回 null
  static UserMessageContent? tryFromJsonString(String jsonString) {
    try {
      return UserMessageContent.fromJsonString(jsonString);
    } catch (_) {
      return null;
    }
  }

  /// 构建用户消息（工厂方法）
  factory UserMessageContent.build({
    required String senderName,
    required String messageContent,
    List<String>? status,
    String? statusType,
    String? statusContent,
    String? scene,
  }) {
    return UserMessageContent(
      senderName: senderName.isNotEmpty && senderName != 'empty'
          ? senderName.replaceAll('.md', '')
          : 'user',
      status: status ?? [],
      statusType: statusType ?? '',
      statusContent: statusContent ?? '',
      scene: scene ?? '',
      messageContent: messageContent.trim(),
    );
  }

  UserMessageContent copyWith({
    String? senderName,
    List<String>? status,
    String? statusType,
    String? statusContent,
    String? scene,
    String? messageContent,
  }) {
    return UserMessageContent(
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
