// INTERNAL: Changes here affect prompt structure and downstream LLM behaviors.

part of 'agent.dart';

class _PromptBuilder {
  final Map<String, dynamic> systemPrompt;
  final ToolRegistry registry;
  final AgentScope scope;

  _PromptBuilder({
    required this.systemPrompt,
    required this.registry,
    required this.scope,
  });

  String buildTextPrompt({
    List<AgentMessage>? memoryMessages,
    required AgentMessage userMessage,
    bool isPartOfChain = false,
    String? input,
  }) {
    final buffer = StringBuffer();

    // --- System context ---
    buffer.writeln('System Instruction: ${json.encode(systemPrompt)}\n');

    // --- Agents in scope ---
    if (!isPartOfChain) {
      final agents = _AgentRegistry.instance.getAllAgents(scope: scope);
      if (agents.isNotEmpty) {
        buffer.writeln(
          'Agents in the System: ${agents.map((e) => e.toString()).join(", ")}',
        );
      }
    }

    // --- Chat history (excludes error messages) ---
    if (memoryMessages != null && memoryMessages.isNotEmpty) {
      buffer.writeln('Chat History:');
      for (final msg in memoryMessages) {
        if (msg.isError) continue;
        buffer.writeln(
          "${msg.isFromAgent ? 'Chatbot' : 'User'}: ${msg.content}",
        );
      }
    }

    // --- Available tools (as a JSON array) ---
    final tools = registry.getAllTools();
    if (tools.isNotEmpty) {
      final toolSpecs = tools.map((tool) => {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.parameters.map((e) => e.toJson()).toList(),
      }).toList();
      buffer.writeln('Available Tools: ${json.encode(toolSpecs)}\n');
    } else {
      buffer.writeln('Available Tools: none\n');
    }

    // --- Output format specification ---
    buffer.writeln('''
Output format — reply with ONLY a single JSON object, no prose, no markdown fences.

If you can answer directly:
{"response": "<your answer>"}

If tools should be used:
{"tools": "<tool_name1>, <tool_name2>", "parameters": {"<tool_name1>": {"<param>": "<value>"}}}''');

    if (!isPartOfChain) {
      buffer.writeln('''
If the task requires multiple agents:
{"agents_chain": ["<agent_name1>", "<agent_name2>"]}''');
    }

    // --- Rules ---
    buffer.writeln('''

RULES:
1. Check all available tools first. If a tool matches the prompt, output it in the JSON format above.
2. For required tool parameters, deduce them from the prompt and any provided data. Only ask the user for a required parameter if it cannot be deduced at all — explain why you need it in the "response" field.
3. Do NOT ask for optional parameters. Do NOT mention tool names to the user.''');

    if (!isPartOfChain) {
      buffer.writeln(
        '4. If the task needs multiple agents, output them as an agents_chain in logical order.\n'
        '5. If no tools or agents apply, generate the response yourself.',
      );
    } else {
      buffer.writeln(
        '4. If no tools apply, generate the response yourself.',
      );
    }

    // --- Chain input from previous agent ---
    if (input != null && input.isNotEmpty && isPartOfChain) {
      buffer.writeln(
        '\nProvided Data from previous agent (use this to extract parameters '
        'and fulfill the task — do NOT ask the user for additional information):\n$input',
      );
    }

    // --- User prompt (rendered exactly once) ---
    buffer.writeln('\nUser prompt: ${userMessage.content}');

    return buffer.toString().trim();
  }
}
