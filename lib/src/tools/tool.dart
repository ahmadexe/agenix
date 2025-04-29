abstract class Tool {
  final String name;
  final String description;

  Tool({
    required this.name,
    required this.description,
  });

  Future<Object?> run(Map<String, dynamic> params);
}
