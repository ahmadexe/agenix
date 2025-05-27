// All LLM classes should implement this interface
// This allows for easy swapping of LLMs (e.g., Gemini, Claude, etc.) without changing the core logic of the agent's memory management.

import 'dart:typed_data';

import 'package:agenix/src/llm/_gemini.dart';

/// The LLM interface defines the contract for all large language models used in the agent.
/// It provides a method to generate responses based on a prompt and optional raw data.
/// This allows for flexibility in using different LLM implementations while maintaining a consistent API.
/// To add a new LLM, simply implement this interface and provide the necessary methods.
abstract class LLM {
  /// Generates a response based on the provided prompt and optional raw data.
  Future<String> generate({required String prompt, Uint8List? rawData});

  /// Returns the unique identifier for the model.
  String get modelId;

  /// Add more methods as needed, such as for OpenAI, Claude, etc.
  static geminiLLM({required String apiKey, required String modelName}) =>
      Gemini(apiKey: apiKey, modelName: modelName);
}
