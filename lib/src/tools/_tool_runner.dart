import 'package:agenix/agenix.dart';
import 'package:agenix/src/tools/_param_validator.dart';
import 'package:agenix/src/tools/_parser.dart';

/// Runs tools based on the parsed LLM output, validating parameters first.
class ToolRunner {
  /// Runs the tools based on the parsed result from the PromptParser.
  Future<List<ToolResponse>> runTools(
    PromptParserResult result,
    ToolRegistry registry,
  ) async {
    final List<ToolResponse> responses = [];

    for (final toolName in result.toolNames) {
      final tool = registry.getTool(toolName);
      if (tool == null) {
        throw ToolNotFoundException(toolName);
      }

      final rawParams = result.params[toolName] ?? {};
      final validation = validateParams(tool.parameters, rawParams);

      if (!validation.isValid) {
        throw ToolExecutionException(
          toolName,
          'Parameter validation failed for tool $toolName: ${validation.errors.join("; ")}',
        );
      }

      try {
        final output = await tool.run(validation.values);
        responses.add(output);
      } catch (e, st) {
        if (e is AgenixException) rethrow;
        throw ToolExecutionException(
          toolName,
          'Tool $toolName threw during execution: $e',
          cause: e,
          causeStack: st,
        );
      }
    }

    return responses;
  }
}
