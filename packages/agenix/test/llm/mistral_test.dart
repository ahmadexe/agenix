import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.mistralLLM returns a usable LLM', () {
    final llm = LLM.mistralLLM(apiKey: 'k', modelName: 'mistral-large-latest');
    expect(llm.modelId, 'mistral-large-latest');
  });
}
