// Internal File, not part of the Public API

import 'dart:typed_data';

import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:agenix/src/llm/llm.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// The Gemini class is an implementation of the LLM interface that uses the Google Gemini model for generating text responses.
/// Using the same interface as other LLMs allows for a consistent API across different models.

class Gemini extends LLM {
  late final GenerativeModel _model;
  final String _modelName;

  /// Creates an instance of the Gemini class with the provided API key and model name.
  Gemini({required String apiKey, required String modelName})
    : _modelName = modelName {
    _model = GenerativeModel(model: modelName, apiKey: apiKey);
  }

  @override
  String get modelId => _modelName;

  @override
  Future<String> generate({required String prompt, Uint8List? rawData}) async {
    try {
      if (rawData == null) {
        final response = await _model.generateContent([Content.text(prompt)]);
        return _extractText(response);
      } else {
        final DataPart dataPart = DataPart('image/jpeg', rawData);
        final text = TextPart(prompt);
        final response = await _model.generateContent([
          Content.multi([text, dataPart]),
        ]);
        return _extractText(response);
      }
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException('LLM call failed: $e', cause: e, causeStack: st);
    }
  }

  String _extractText(GenerateContentResponse response) {
    final text = response.text;
    if (text == null || text.isEmpty) {
      throw LlmException(
        'LLM returned empty response (possible safety block or empty candidate)',
      );
    }
    return text;
  }
}
