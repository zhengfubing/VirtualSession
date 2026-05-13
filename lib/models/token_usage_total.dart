class TokenUsageTotal {
  final String id;
  final String chatId;
  final String agentType;
  final int promptTokens;
  final int completionTokens;
  final double updatedAt;

  TokenUsageTotal({
    required this.id,
    required this.chatId,
    required this.agentType,
    this.promptTokens = 0,
    this.completionTokens = 0,
    required this.updatedAt,
  });

  factory TokenUsageTotal.fromMap(Map<String, dynamic> map) {
    return TokenUsageTotal(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      agentType: map['agent_type'] as String,
      promptTokens: map['prompt_tokens'] as int? ?? 0,
      completionTokens: map['completion_tokens'] as int? ?? 0,
      updatedAt: map['updated_at'] as double,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'agent_type': agentType,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'updated_at': updatedAt,
    };
  }
}
