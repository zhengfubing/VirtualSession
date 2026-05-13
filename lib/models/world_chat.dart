class WorldChat {
  final String id;
  final String name;
  final String worldSceneId;
  final double createdAt;
  final double updatedAt;
  final double? deletedAt;

  WorldChat({
    required this.id,
    required this.name,
    required this.worldSceneId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory WorldChat.fromMap(Map<String, dynamic> map) {
    return WorldChat(
      id: map['id'] as String,
      name: map['name'] as String,
      worldSceneId: map['world_scene_id'] as String,
      createdAt: map['created_at'] as double,
      updatedAt: map['updated_at'] as double,
      deletedAt: map['deleted_at'] as double?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'world_scene_id': worldSceneId,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }
}
