class AIModel {
  final int? id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final bool isActive;
  final DateTime createdAt;

  AIModel({
    this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.isActive = false,
    required this.createdAt,
  });

  factory AIModel.fromMap(Map<String, dynamic> map) {
    return AIModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      baseUrl: map['base_url'] as String,
      apiKey: map['api_key'] as String,
      isActive: map['is_active'] == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'api_key': apiKey,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AIModel copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return AIModel(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'AIModel(id: $id, name: $name, baseUrl: $baseUrl, isActive: $isActive)';
  }
}
