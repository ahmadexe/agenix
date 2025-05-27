// Internal File, not part of the Public API

import 'dart:typed_data';

import 'package:agenix/src/static/_pkg_constants.dart';
import 'package:agenix/src/llm/llm.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// The Gemini class is an implementation of the LLM interface that uses the Google Gemini model for generating text responses.
/// Using the same interface as other LLMs allows for a consistent API across different models.

class Gemini extends LLM {
  late final GenerativeModel _model;

  /// Creates an instance of the Gemini class with the provided API key and model name.
  Gemini({required String apiKey, required String modelName}) {
    final model = GenerativeModel(model: modelName, apiKey: apiKey);

    _model = model;
  }

  @override
  String get modelId => 'gemini';

  // The overridden method to generate a response using the Gemini model.
  // Every LLM implementation must implement this method.
  @override
  Future<String> generate({required String prompt, Uint8List? rawData}) async {
    if (rawData == null) {
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? kLLMResponseOnFailure;
    } else {
      final DataPart dataPart = DataPart('image/jpeg', rawData);
      final text = TextPart(prompt);
      final response = await _model.generateContent([
        Content.multi([text, dataPart]),
      ]);

      return response.text ?? kLLMResponseOnFailure;
    }
  }
}
