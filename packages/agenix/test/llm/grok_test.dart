import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.grokLLM returns a usable LLM', () {
    final llm = LLM.grokLLM(apiKey: 'k', modelName: 'grok-4');
    expect(llm.modelId, 'grok-4');
  });
}
