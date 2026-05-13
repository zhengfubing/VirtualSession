class Chat {
  final String id;
  final String name;
  final String status;
  final String scenePromptId;
  final String senderId;
  final String roleSettingPromptIdsJson;
  final String modeId;
  final String roleName;
  final double? lastCompactionAt;
  final double createdAt;
  final double updatedAt;
  final double? deletedAt;

  Chat({
    required this.id,
    required this.name,
    this.status = 'active',
    this.scenePromptId = 'empty',
    this.senderId = 'empty',
    required this.roleSettingPromptIdsJson,
    this.modeId = 'ensemble',
    this.roleName = '',
    this.lastCompactionAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      id: map['id'] as String,
      name: map['name'] as String,
      status: map['status'] as String? ?? 'active',
      scenePromptId: map['scene_prompt_id'] as String? ?? 'empty',
      senderId: map['sender_id'] as String? ?? 'empty',
      roleSettingPromptIdsJson: map['role_setting_prompt_ids_json'] as String,
      modeId: map['mode_id'] as String? ?? 'ensemble',
      roleName: map['role_name'] as String? ?? '',
      lastCompactionAt: map['last_compaction_at'] as double?,
      createdAt: map['created_at'] as double,
      updatedAt: map['updated_at'] as double,
      deletedAt: map['deleted_at'] as double?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'scene_prompt_id': scenePromptId,
      'sender_id': senderId,
      'role_setting_prompt_ids_json': roleSettingPromptIdsJson,
      'mode_id': modeId,
      'role_name': roleName,
      'last_compaction_at': lastCompactionAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }
}
