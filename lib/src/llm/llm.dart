// All LLM classes should implement this interface
// This allows for easy swapping of LLMs (e.g., Gemini, Claude, etc.) without changing the core logic of the agent's memory management.

abstract class LLM {
  Future<String> generate({
    required String prompt,
  });

  String get modelId;
}
