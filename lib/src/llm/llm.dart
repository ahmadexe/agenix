// All LLM classes should implement this interface
// This allows for easy swapping of LLMs (e.g., Gemini, Claude, etc.) without changing the core logic of the agent's memory management.

import 'dart:typed_data';

import 'package:agenix/src/llm/_gemini.dart';

abstract class LLM {
  Future<String> generate({required String prompt, Uint8List? rawData});

  String get modelId;

  // Add more methods as needed, such as for OpenAI, Claude, etc.
  static geminiLLM({required String apiKey, required String modelName}) =>
      Gemini(apiKey: apiKey, modelName: modelName);
}
