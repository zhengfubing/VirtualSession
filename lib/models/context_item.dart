class ContextItem {
  final String id;
  final String chatId;
  final int seq;
  final String itemType;
  final String role;
  final String content;
  final String priority;
  final int compressible;
  final int active;
  final double createdAt;

  ContextItem({
    required this.id,
    required this.chatId,
    required this.seq,
    this.itemType = 'message',
    required this.role,
    required this.content,
    this.priority = 'normal',
    this.compressible = 1,
    this.active = 1,
    required this.createdAt,
  });

  factory ContextItem.fromMap(Map<String, dynamic> map) {
    return ContextItem(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      seq: map['seq'] as int,
      itemType: map['item_type'] as String? ?? 'message',
      role: map['role'] as String,
      content: map['content'] as String,
      priority: map['priority'] as String? ?? 'normal',
      compressible: map['compressible'] as int? ?? 1,
      active: map['active'] as int? ?? 1,
      createdAt: map['created_at'] as double,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'seq': seq,
      'item_type': itemType,
      'role': role,
      'content': content,
      'priority': priority,
      'compressible': compressible,
      'active': active,
      'created_at': createdAt,
    };
  }
}
