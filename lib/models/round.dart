class Round {
  final String id;
  final String chatId;
  final String status;
  final String modelName;
  final int stream;
  final int enableThinking;
  final String currentSenderId;
  final String promptSnapshotJson;
  final String? finalAnswerMessageId;
  final String finalReasoning;
  final String? errorMessage;
  final double startedAt;
  final double? endedAt;

  Round({
    required this.id,
    required this.chatId,
    required this.status,
    required this.modelName,
    this.stream = 1,
    this.enableThinking = 0,
    this.currentSenderId = 'empty',
    required this.promptSnapshotJson,
    this.finalAnswerMessageId,
    this.finalReasoning = '',
    this.errorMessage,
    required this.startedAt,
    this.endedAt,
  });

  factory Round.fromMap(Map<String, dynamic> map) {
    return Round(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      status: map['status'] as String,
      modelName: map['model_name'] as String,
      stream: map['stream'] as int? ?? 1,
      enableThinking: map['enable_thinking'] as int? ?? 0,
      currentSenderId: map['current_sender_id'] as String? ?? 'empty',
      promptSnapshotJson: map['prompt_snapshot_json'] as String,
      finalAnswerMessageId: map['final_answer_message_id'] as String?,
      finalReasoning: map['final_reasoning'] as String? ?? '',
      errorMessage: map['error_message'] as String?,
      startedAt: map['started_at'] as double,
      endedAt: map['ended_at'] as double?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'status': status,
      'model_name': modelName,
      'stream': stream,
      'enable_thinking': enableThinking,
      'current_sender_id': currentSenderId,
      'prompt_snapshot_json': promptSnapshotJson,
      'final_answer_message_id': finalAnswerMessageId,
      'final_reasoning': finalReasoning,
      'error_message': errorMessage,
      'started_at': startedAt,
      'ended_at': endedAt,
    };
  }
}
