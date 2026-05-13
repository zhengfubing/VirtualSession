class Summary {
  final String id;
  final String chatId;
  final String level;
  final String status;
  final int sourceStartSeq;
  final int sourceEndSeq;
  final String sourceMessageIdsJson;
  final int basedOnContextVersion;
  final int tokenEstimateBefore;
  final int tokenEstimateAfter;
  final String summaryText;
  final String factsJson;
  final String decisionsJson;
  final String roleStateJson;
  final String toolMemoryRefsJson;
  final double createdAt;

  Summary({
    required this.id,
    required this.chatId,
    required this.level,
    this.status = 'active',
    this.sourceStartSeq = 0,
    this.sourceEndSeq = 0,
    required this.sourceMessageIdsJson,
    this.basedOnContextVersion = 0,
    this.tokenEstimateBefore = 0,
    this.tokenEstimateAfter = 0,
    required this.summaryText,
    required this.factsJson,
    required this.decisionsJson,
    required this.roleStateJson,
    required this.toolMemoryRefsJson,
    required this.createdAt,
  });

  factory Summary.fromMap(Map<String, dynamic> map) {
    return Summary(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      level: map['level'] as String,
      status: map['status'] as String? ?? 'active',
      sourceStartSeq: map['source_start_seq'] as int? ?? 0,
      sourceEndSeq: map['source_end_seq'] as int? ?? 0,
      sourceMessageIdsJson: map['source_message_ids_json'] as String,
      basedOnContextVersion: map['based_on_context_version'] as int? ?? 0,
      tokenEstimateBefore: map['token_estimate_before'] as int? ?? 0,
      tokenEstimateAfter: map['token_estimate_after'] as int? ?? 0,
      summaryText: map['summary_text'] as String,
      factsJson: map['facts_json'] as String,
      decisionsJson: map['decisions_json'] as String,
      roleStateJson: map['role_state_json'] as String,
      toolMemoryRefsJson: map['tool_memory_refs_json'] as String,
      createdAt: map['created_at'] as double,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'level': level,
      'status': status,
      'source_start_seq': sourceStartSeq,
      'source_end_seq': sourceEndSeq,
      'source_message_ids_json': sourceMessageIdsJson,
      'based_on_context_version': basedOnContextVersion,
      'token_estimate_before': tokenEstimateBefore,
      'token_estimate_after': tokenEstimateAfter,
      'summary_text': summaryText,
      'facts_json': factsJson,
      'decisions_json': decisionsJson,
      'role_state_json': roleStateJson,
      'tool_memory_refs_json': toolMemoryRefsJson,
      'created_at': createdAt,
    };
  }
}
