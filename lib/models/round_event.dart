class RoundEvent {
  final String id;
  final String chatId;
  final String roundId;
  final int seq;
  final String kind;
  final String stage;
  final String direction;
  final String? modelName;
  final String payloadJson;
  final int promptTokens;
  final int completionTokens;
  final double createdAt;

  RoundEvent({
    required this.id,
    required this.chatId,
    required this.roundId,
    required this.seq,
    required this.kind,
    required this.stage,
    required this.direction,
    this.modelName,
    required this.payloadJson,
    this.promptTokens = 0,
    this.completionTokens = 0,
    required this.createdAt,
  });

  factory RoundEvent.fromMap(Map<String, dynamic> map) {
    return RoundEvent(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      roundId: map['round_id'] as String,
      seq: map['seq'] as int,
      kind: map['kind'] as String,
      stage: map['stage'] as String,
      direction: map['direction'] as String,
      modelName: map['model_name'] as String?,
      payloadJson: map['payload_json'] as String,
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
      'seq': seq,
      'kind': kind,
      'stage': stage,
      'direction': direction,
      'model_name': modelName,
      'payload_json': payloadJson,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'created_at': createdAt,
    };
  }
}
