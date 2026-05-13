class Prompt {
  final int? id;
  final String fileName;
  final String promptType;

  Prompt({
    this.id,
    required this.fileName,
    required this.promptType,
  });

  factory Prompt.fromMap(Map<String, dynamic> map) {
    return Prompt(
      id: map['id'] as int?,
      fileName: map['file_name'] as String,
      promptType: map['prompt_type'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_name': fileName,
      'prompt_type': promptType,
    };
  }
}
