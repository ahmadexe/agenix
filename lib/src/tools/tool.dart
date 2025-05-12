import 'package:agenix/src/tools/param_spec.dart';

abstract class Tool {
  final String name;
  final String description;
  final List<ParamSpec?>? parameters;

  Tool({required this.name, required this.description, this.parameters});

  Future<Map<String, dynamic>?> run(Map<String, dynamic> params);
}
