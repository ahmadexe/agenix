import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_llm.dart';
import '../helpers/fixtures.dart';
import '../helpers/system_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    stubSystemData(defaultSystemData());
  });

  test(
    'agent passes systemInstruction via LLM param, not in the prompt',
    () async {
      final scope = AgentScope();
      final llm = FakeLLM.alwaysResponds('hello');
      final store = DataStore.inMemory();

      final agent = await Agent.create(
        dataStore: store,
        llm: llm,
        name: 'sys-instr-agent',
        role: 'test',
        scope: scope,
      );

      await agent.generateResponse(convoId: 'c1', userMessage: userMsg('hi'));

      expect(llm.systemInstructionsReceived, isNotEmpty);
      expect(llm.systemInstructionsReceived.first, isNotNull);

      // The system instruction should contain the system data
      final sysInstr = llm.systemInstructionsReceived.first!;
      expect(sysInstr, contains('helpful test assistant'));

      // The user prompt should NOT contain the old "System Instruction:" prefix
      final prompt = llm.prompts.first;
      expect(prompt, isNot(contains('System Instruction:')));

      agent.dispose();
    },
  );

  test('FakeLLM records mimeType', () async {
    final llm = FakeLLM.alwaysResponds('ok');
    await llm.generate(prompt: 'test', mimeType: 'image/png');
    expect(llm.mimeTypesReceived.first, 'image/png');
  });

  test('FakeLLM config getter returns provided config', () {
    final cfg = LlmConfig(temperature: 0.7);
    final llm = FakeLLM(config: cfg);
    expect(llm.config.temperature, 0.7);
  });
}
