import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.deepseekLLM returns a usable LLM with correct modelId', () {
    final llm = LLM.deepseekLLM(apiKey: 'k', modelName: 'deepseek-chat');
    expect(llm.modelId, 'deepseek-chat');
    expect(llm.config.jsonMode, true);
  });
}
