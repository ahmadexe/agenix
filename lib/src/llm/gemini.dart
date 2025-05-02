import 'package:agenix/src/llm/llm.dart';

class Gemini extends LLM {
  @override
  Future<String> generate({required String prompt}) {
    // TODO: implement generate
    throw UnimplementedError();
  }

  @override
  String get modelId => 'gemini';
  
}