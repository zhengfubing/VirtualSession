class ChatMode {
  final String id;
  final String name;
  final String description;
  final String icon;
  final bool multiScene;
  final bool multiRole;
  final int minRoles;
  final int maxRoles;
  final bool memoryEnabled;
  final String memoryType;
  final String systemPromptTemplate;
  final int sortOrder;

  ChatMode({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.multiScene = false,
    this.multiRole = false,
    this.minRoles = 1,
    this.maxRoles = 1,
    this.memoryEnabled = false,
    this.memoryType = 'none',
    this.systemPromptTemplate = '',
    this.sortOrder = 0,
  });

  factory ChatMode.fromMap(Map<String, dynamic> map) {
    return ChatMode(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      icon: map['icon'] as String? ?? 'chat_bubble_outline',
      multiScene: (map['multi_scene'] as int? ?? 0) == 1,
      multiRole: (map['multi_role'] as int? ?? 0) == 1,
      minRoles: map['min_roles'] as int? ?? 1,
      maxRoles: map['max_roles'] as int? ?? 1,
      memoryEnabled: (map['memory_enabled'] as int? ?? 0) == 1,
      memoryType: map['memory_type'] as String? ?? 'none',
      systemPromptTemplate: map['system_prompt_template'] as String? ?? '',
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'multi_scene': multiScene ? 1 : 0,
      'multi_role': multiRole ? 1 : 0,
      'min_roles': minRoles,
      'max_roles': maxRoles,
      'memory_enabled': memoryEnabled ? 1 : 0,
      'memory_type': memoryType,
      'system_prompt_template': systemPromptTemplate,
      'sort_order': sortOrder,
    };
  }
}
