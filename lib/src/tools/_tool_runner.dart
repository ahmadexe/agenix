import 'package:agenix/src/tools/_parser.dart';
import 'package:agenix/src/tools/tool_registry.dart';

// This class is responsible for running tools based on the parsed prompt.
// It takes the parsed result from the PromptParser and executes the tools with the provided parameters.
// The output from each tool is collected and returned as a list of maps.
class ToolRunner {
  Future<List<Map<String, dynamic>>> runTools(PromptParserResult result) async {
    final registry = ToolRegistry();
    final List<Map<String, dynamic>> responses = [];

    for (final toolName in result.toolNames) {
      final tool = registry.getTool(toolName);
      if (tool == null) {
        throw Exception("Tool $toolName not found in registry");
      }
      if (result.params[toolName] == null) {
        throw Exception("No parameters provided for tool $toolName");
      }
      final toolParams = result.params[toolName] ?? {};
      final output = await tool.run(toolParams);
      responses.add({toolName: output});
    }

    return responses;
  }
}
