class Message {
  final String id;
  final String chatId;
  final String role;
  final String? senderName;
  final String content;
  final String scene;
  final String payloadJson;
  final double? deletedAt;
  final double createdAt;

  Message({
    required this.id,
    required this.chatId,
    required this.role,
    this.senderName,
    required this.content,
    this.scene = '',
    required this.payloadJson,
    this.deletedAt,
    required this.createdAt,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      role: map['role'] as String,
      senderName: map['sender_name'] as String?,
      content: map['content'] as String,
      scene: map['scene'] as String? ?? '',
      payloadJson: map['payload_json'] as String,
      deletedAt: map['deleted_at'] as double?,
      createdAt: map['created_at'] as double,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'role': role,
      'sender_name': senderName,
      'content': content,
      'scene': scene,
      'payload_json': payloadJson,
      'deleted_at': deletedAt,
      'created_at': createdAt,
    };
  }
}
