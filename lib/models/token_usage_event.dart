class TokenUsageEvent {
  final int? id;
  final String? chatId;
  final String? roundId;
  final String agentType;
  final String? modelName;
  final int promptTokens;
  final int completionTokens;
  final double createdAt;

  TokenUsageEvent({
    this.id,
    this.chatId,
    this.roundId,
    required this.agentType,
    this.modelName,
    this.promptTokens = 0,
    this.completionTokens = 0,
    required this.createdAt,
  });

  factory TokenUsageEvent.fromMap(Map<String, dynamic> map) {
    return TokenUsageEvent(
      id: map['id'] as int?,
      chatId: map['chat_id'] as String?,
      roundId: map['round_id'] as String?,
      agentType: map['agent_type'] as String,
      modelName: map['model_name'] as String?,
      promptTokens: map['prompt_tokens'] as int? ?? 0,
      completionTokens: map['completion_tokens'] as int? ?? 0,
      createdAt: map['created_at'] as double,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'round_id': roundId,
      'agent_type': agentType,
      'model_name': modelName,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'created_at': createdAt,
    };
  }
}
