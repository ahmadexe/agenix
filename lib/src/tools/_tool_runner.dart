import 'package:agenix/src/tools/_parser.dart';
import 'package:agenix/src/tools/tool_registry.dart';

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
