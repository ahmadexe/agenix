import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.groqLLM returns a usable LLM', () {
    final llm = LLM.groqLLM(apiKey: 'k', modelName: 'llama-3.3-70b-versatile');
    expect(llm.modelId, 'llama-3.3-70b-versatile');
  });
}
