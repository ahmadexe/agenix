import 'dart:typed_data';

import 'package:agenix/src/llm/_anthropic.dart';
import 'package:agenix/src/llm/_cohere.dart';
import 'package:agenix/src/llm/_gemini.dart';
import 'package:agenix/src/llm/_openai.dart';
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

  /// Creates a Gemini-backed [LLM] instance.
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

  /// Creates an Anthropic (Claude) backed [LLM] instance.
  ///
  /// [modelName] is the Claude model id, e.g. `claude-sonnet-4-5`.
  static LLM anthropicLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) => Anthropic(apiKey: apiKey, modelName: modelName, config: config);

  /// Creates an OpenAI Chat-Completions backed [LLM] instance.
  ///
  /// [modelName] is e.g. `gpt-4o`. Pass [baseUrl] to use an OpenAI-compatible
  /// endpoint such as DeepSeek, Grok, Groq, or OpenRouter.
  static LLM openAiLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    String baseUrl = 'https://api.openai.com/v1',
    Map<String, String> extraHeaders = const {},
  }) => OpenAI(
    apiKey: apiKey,
    modelName: modelName,
    config: config,
    baseUrl: baseUrl,
    extraHeaders: extraHeaders,
  );

  /// Creates a DeepSeek-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `deepseek-chat` or `deepseek-reasoner`.
  /// Backed by the OpenAI-compatible Chat Completions API.
  static LLM deepseekLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) => OpenAI(
    apiKey: apiKey,
    modelName: modelName,
    config: config,
    baseUrl: 'https://api.deepseek.com/v1',
  );

  /// Creates an xAI Grok-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `grok-4`, `grok-4-mini`, or `grok-vision-beta`.
  /// Backed by the OpenAI-compatible Chat Completions API.
  static LLM grokLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) => OpenAI(
    apiKey: apiKey,
    modelName: modelName,
    config: config,
    baseUrl: 'https://api.x.ai/v1',
  );

  /// Creates a Groq-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `llama-3.3-70b-versatile`, `mixtral-8x7b-32768`,
  /// or `llama-3.2-90b-vision-preview`.
  /// Backed by the OpenAI-compatible Chat Completions API.
  static LLM groqLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) => OpenAI(
    apiKey: apiKey,
    modelName: modelName,
    config: config,
    baseUrl: 'https://api.groq.com/openai/v1',
  );

  /// Creates a Mistral-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `mistral-large-latest`, `open-mistral-nemo`,
  /// or `pixtral-large-latest` (vision).
  /// Backed by the OpenAI-compatible Chat Completions API.
  static LLM mistralLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) => OpenAI(
    apiKey: apiKey,
    modelName: modelName,
    config: config,
    baseUrl: 'https://api.mistral.ai/v1',
  );

  /// Creates a Cohere-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `command-r-plus-08-2024`, `command-r-08-2024`,
  /// or `command-light`.
  /// Multimodal input is not supported.
  static LLM cohereLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) => Cohere(apiKey: apiKey, modelName: modelName, config: config);
}
