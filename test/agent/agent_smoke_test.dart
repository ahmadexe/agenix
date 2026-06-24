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

  test('agent returns the scripted LLM response', () async {
    final scope = AgentScope();
    final llm = FakeLLM.alwaysResponds('hello from fake');
    final store = DataStore.inMemory();

    final agent = await Agent.create(
      dataStore: store,
      llm: llm,
      name: 'smoke-agent',
      role: 'test agent',
      scope: scope,
    );

    final response = await agent.generateResponse(
      convoId: 'test-convo',
      userMessage: userMsg('hi'),
    );

    expect(response.content, 'hello from fake');
    expect(response.isFromAgent, isTrue);
    expect(llm.callCount, 1);

    agent.dispose();
  });
}
