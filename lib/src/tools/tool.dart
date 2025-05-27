// This is the blueprint for the Tool class.
// It defines the structure and behavior that all tools should implement.
// It includes the name, description, and parameters of the tool.
// The run method is an abstract method that must be implemented by all tools.

import 'package:agenix/src/tools/param_spec.dart';
import 'package:agenix/src/tools/tool_response.dart';

/// The Tool class is an abstract class that defines the structure and behavior of a tool.
/// It includes the name, description, and parameters of the tool.
abstract class Tool {
  /// The name of the tool.
  final String name;

  /// A short description of what the tool does.
  final String description;

  /// The parameters that the tool accepts.
  final List<ParameterSpecification?>? parameters;

  /// Constructs a Tool with the required fields.
  Tool({required this.name, required this.description, this.parameters});

  /// Returns a JSON representation of the tool.
  Future<ToolResponse> run(Map<String, dynamic> params);
}
