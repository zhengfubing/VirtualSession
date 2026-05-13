class PromptType {
  final int? id;
  final String typeName;

  PromptType({
    this.id,
    required this.typeName,
  });

  factory PromptType.fromMap(Map<String, dynamic> map) {
    return PromptType(
      id: map['id'] as int?,
      typeName: map['type_name'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type_name': typeName,
    };
  }
}
