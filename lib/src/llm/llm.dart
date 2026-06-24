import 'dart:typed_data';

import 'package:agenix/src/llm/_gemini.dart';
import 'package:agenix/src/llm/llm_config.dart';

/// The LLM interface defines the contract for all large language models used in the agent.
abstract class LLM {
  /// Generates a response based on the provided prompt and optional raw data.
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType,
  });

  /// Returns the unique identifier for the model.
  String get modelId;

  /// Provider-neutral generation config.
  LlmConfig get config;

  static LLM geminiLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    Object? safetySettings,
  }) => Gemini(
    apiKey: apiKey,
    modelName: modelName,
    config: config,
    safetySettings: safetySettings,
  );
}
