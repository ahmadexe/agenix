// Internal File, not part of the Public API

import 'dart:async';
import 'dart:typed_data';

import 'package:agenix/src/llm/llm_config.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:agenix/src/llm/llm.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class Gemini extends LLM {
  final String _modelName;
  final String _apiKey;
  final LlmConfig _config;
  final List<SafetySetting>? _safety;

  Gemini({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    Object? safetySettings,
  }) : _modelName = modelName,
       _apiKey = apiKey,
       _config = config,
       _safety = safetySettings as List<SafetySetting>?;

  @override
  String get modelId => _modelName;

  @override
  LlmConfig get config => _config;

  GenerationConfig _genConfig() => GenerationConfig(
    temperature: _config.temperature,
    maxOutputTokens: _config.maxOutputTokens,
    topP: _config.topP,
    topK: _config.topK,
    stopSequences: _config.stopSequences ?? const [],
    responseMimeType: _config.jsonMode ? 'application/json' : null,
  );

  GenerativeModel _buildModel(String? systemInstruction) => GenerativeModel(
    model: _modelName,
    apiKey: _apiKey,
    generationConfig: _genConfig(),
    safetySettings: _safety ?? const [],
    systemInstruction:
        systemInstruction != null ? Content.system(systemInstruction) : null,
  );

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final model = _buildModel(systemInstruction);
      final content =
          rawData == null
              ? [Content.text(prompt)]
              : [
                Content.multi([TextPart(prompt), DataPart(mimeType, rawData)]),
              ];
      final response = await model
          .generateContent(content)
          .timeout(_config.timeout);
      return _extractText(response);
    } on TimeoutException catch (e, st) {
      throw LlmTimeoutException(
        'LLM request exceeded ${_config.timeout.inSeconds}s',
        cause: e,
        causeStack: st,
      );
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException('LLM call failed: $e', cause: e, causeStack: st);
    }
  }

  String _extractText(GenerateContentResponse response) {
    final text = response.text;
    if (text == null || text.isEmpty) {
      throw const LlmException(
        'LLM returned empty response (possible safety block or empty candidate)',
      );
    }
    return text;
  }
}
