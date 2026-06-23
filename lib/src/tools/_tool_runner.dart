import 'package:agenix/agenix.dart';
import 'package:agenix/src/tools/_parser.dart';
import 'package:agenix/src/tools/tool_registry.dart';

/// This class is responsible for running tools based on the parsed prompt.
/// It takes the parsed result from the PromptParser and executes the tools with the provided parameters.
/// The output from each tool is collected and returned as a list of maps.
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
      final toolParams = result.params[toolName] ?? {};
      try {
        final output = await tool.run(toolParams);
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
