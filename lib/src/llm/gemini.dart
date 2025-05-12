// Internal File, not part of the Public API

import 'package:agenix/src/static/_pkg_constants.dart';
import 'package:agenix/src/llm/llm.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class Gemini extends LLM {
  late final GenerativeModel _model;

  Gemini({required String apiKey, required String modelName}) {
    final model = GenerativeModel(model: modelName, apiKey: apiKey);

    _model = model;
  }

  @override
  String get modelId => 'gemini';

  @override
  Future<String> generate({required String prompt}) async {
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? kLLMResponseOnFailure;
  }
}
