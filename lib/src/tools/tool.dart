// This is the blueprint for the Tool class.
// It defines the structure and behavior that all tools should implement.
// It includes the name, description, and parameters of the tool.
// The run method is an abstract method that must be implemented by all tools.

import 'package:agenix/src/tools/param_spec.dart';

abstract class Tool {
  final String name;
  final String description;
  final List<ParamSpec?>? parameters;

  Tool({required this.name, required this.description, this.parameters});

  Future<Map<String, dynamic>?> run(Map<String, dynamic> params);
}
