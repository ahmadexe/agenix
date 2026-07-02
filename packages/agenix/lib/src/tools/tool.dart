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
  final List<ParameterSpecification> parameters;

  /// Constructs a Tool with the required fields.
  Tool({
    required this.name,
    required this.description,
    this.parameters = const [],
  });

  /// Executes the tool with the given validated parameters.
  ///
  /// **Idempotency contract:** if this tool has observable side effects
  /// (writes to a database, sends a message, charges a card), implementations
  /// SHOULD be idempotent — use upsert semantics, a natural key, or an
  /// explicit idempotency token in the parameters. The framework guards
  /// against duplicate `(name, params)` invocations within a single turn,
  /// but it cannot detect semantically-equivalent calls with different
  /// parameter shapes, so this contract is the final line of defence.
  Future<ToolResponse> run(Map<String, dynamic> params);
}
