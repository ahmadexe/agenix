part of 'agent.dart';

/// Builds the prompt for the LLM based on memory, system instructions,
/// THIS FILE IS NOT PART OF THE PUBLIC API
///
class _PromptBuilder {
  final Map<String, dynamic> systemPrompt;

  _PromptBuilder({required this.systemPrompt});

  String buildTextPrompt({
    List<AgentMessage>? memoryMessages,
    required AgentMessage userMessage,
  }) {
    final buffer = StringBuffer();

    buffer.writeln("RETURN THE RESPONSE IN JSON FORMAT ONLY, the ");

    buffer.writeln("System Instruction: $systemPrompt\n");

    if (memoryMessages != null && memoryMessages.isNotEmpty) {
      buffer.writeln("Chat History: ");
      for (final msg in memoryMessages) {
        buffer.writeln(
          "${msg.isFromAgent ? 'Chatbot' : 'User'}: ${msg.content}",
        );
      }
    }

    final tools = ToolRegistry().getAllTools();
    if (tools.isNotEmpty) {
      buffer.writeln("Tools: ");
      for (final tool in tools) {
        buffer.writeln("${tool.name}: ${tool.description}");
      }
    }

    buffer.writeln('''
    Output format if tools are available for the prompt:
    {
      "tools": "<tool_name>"
    }
    Output format if no tools are available for the prompt:
    {
      "response": "<response>"
    }
    ''');

    buffer.writeln(
      "${"\nBased on the system instruction, chat history, and tools, generate a response for the user. If a tool should be used for the response, include the tool name in the response. If multiple tools need to be used in order, include the name of multiple tools, seperated by commas, make sure the names are included in the correct order. If no tool is available for the prompt, generate the response yourself. This is the prompt: "}: ${userMessage.content}",
    );

    return buffer.toString().trim();
  }
}
