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
        buffer.writeln(
          "{${tool.name}: Description: ${tool.description}, Parameters: ${tool.parameters?.map((e) => e!.toJson())}},",
        );
      }
    }

    buffer.writeln('''
    Output format if tools are available for the prompt:
    {
      "tools": "<tool_name>, <tool2_name>, ...",
      "parameters": {
        "<tool_name>": {
          "<param_name>": "<param_value>",
          ...
        },
        ...
      },
    }
    Output if parameters are required but are not given:
    {
      "tools": "<tool_name>, <tool2_name>, ...",
      "parameters": {
        "<tool_name>": {
          "<param_name>": "<param_value>",
          ...
        },
        ...
      },
      "response": "<reponse: asking for the parameters>"
    }
    Output format if no tools are available for the prompt:
    {
      "response": "<response>"
    }
    ''');

    buffer.writeln(
      "If a tool can be used, just give the name of the tool, and the parameters required for the tool, if no parameters are required, do not include them. If tools need to be used do not include the response field in the JSON. Based on the description of the tools, decide if tools should be used.",
    );

    buffer.writeln(
      "${"\nBased on the system instruction, chat history, and tools, generate a response for the user. If a tool should be used for the response, include the tool name in the response. If multiple tools need to be used in order, include the name of multiple tools, seperated by commas, make sure the names are included in the correct order, if parameters are required for a tool, include them in the response, if no parameters are required, do not include them. If no tool is available for the prompt, generate the response yourself. Give the response strictly in JSON, do not add anything extra to the response, just the parsable JSON. Do not include any text outside of the JSON. Order of action should be as follows: 1. Check all the available tools. \n2. If a tool or tools are found to respond to the prompt then output them in the provided JSON format. \n3. If no tool is available for the prompt, generate the response yourself. \nThis is the prompt: "}: ${userMessage.content}",
    );

    return buffer.toString().trim();
  }
}
