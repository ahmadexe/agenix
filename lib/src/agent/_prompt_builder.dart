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

    buffer.writeln(
      "${"\nBased on the system instruction and chat history (is present), respond to the prompt: "}: ${userMessage.content}",
    );

    return buffer.toString().trim();
  }
}
