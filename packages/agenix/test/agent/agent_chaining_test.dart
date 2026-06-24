import 'package:agenix/agenix.dart';
import 'package:agenix/src/static/_pkg_constants.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_llm.dart';
import '../helpers/fixtures.dart';
import '../helpers/system_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AgentScope scope;
  late DataStore store;

  setUpAll(() => stubSystemData(defaultSystemData()));

  setUp(() {
    scope = AgentScope();
    store = DataStore.inMemory();
  });

  tearDown(() => scope.clear());

  Future<Agent> createAgent(String name, FakeLLM llm) => Agent.create(
    dataStore: store,
    llm: llm,
    name: name,
    role: '$name role',
    scope: scope,
    failureMode: FailureMode.throwError,
  );

  group('Agent chaining', () {
    test('two-agent chain returns downstream response', () async {
      final routerLlm = FakeLLM.scripted(['{"agents_chain":["worker"]}']);
      final workerLlm = FakeLLM.scripted(['{"response":"done"}']);

      final router = await createAgent('router', routerLlm);
      await createAgent('worker', workerLlm);

      final res = await router.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('route it'),
      );

      expect(res.content, 'done');
      expect(workerLlm.callCount, 1);
      router.dispose();
    });

    test('unknown agent throws AgentNotFoundException', () async {
      final llm = FakeLLM.scripted(['{"agents_chain":["ghost"]}']);
      final agent = await createAgent('router', llm);

      expect(
        () => agent.generateResponse(convoId: 'c1', userMessage: userMsg('go')),
        throwsA(isA<AgentNotFoundException>()),
      );
      agent.dispose();
    });

    test('cycle detection throws ConfigException', () async {
      final llmA = FakeLLM.scripted(['{"agents_chain":["b"]}']);
      final llmB = FakeLLM.scripted(['{"agents_chain":["a"]}']);

      final a = await createAgent('a', llmA);
      await createAgent('b', llmB);

      expect(
        () => a.generateResponse(convoId: 'c1', userMessage: userMsg('ping')),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message.toLowerCase(),
            'message',
            contains('cycle'),
          ),
        ),
      );
      a.dispose();
    });

    test('depth limit throws ConfigException', () async {
      // Create kMaxChainDepth + 2 agents in a linear chain (all unique names).
      // Each delegates to the next. Depth limit should trip before the chain ends.
      final depthScope = AgentScope();
      final depthStore = DataStore.inMemory();
      final totalAgents = kMaxChainDepth + 2;
      final agents = <Agent>[];
      for (var i = 0; i < totalAgents; i++) {
        final llm =
            i < totalAgents - 1
                ? FakeLLM.scripted(['{"agents_chain":["d${i + 1}"]}'])
                : FakeLLM.scripted(['{"response":"deep"}']);
        agents.add(
          await Agent.create(
            dataStore: depthStore,
            llm: llm,
            name: 'd$i',
            role: 'd$i role',
            scope: depthScope,
            failureMode: FailureMode.throwError,
          ),
        );
      }

      try {
        await agents.first.generateResponse(
          convoId: 'c1',
          userMessage: userMsg('go deep'),
        );
        fail('Expected ConfigException for depth limit');
      } on ConfigException catch (e) {
        expect(e.message.toLowerCase(), contains('depth'));
      }
      for (final a in agents) {
        a.dispose();
      }
    });

    test('chained agent prompt omits agents_chain instruction', () async {
      final routerLlm = FakeLLM.scripted(['{"agents_chain":["worker"]}']);
      final workerLlm = FakeLLM.scripted(['{"response":"ok"}']);

      final router = await createAgent('router', routerLlm);
      await createAgent('worker', workerLlm);

      await router.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('route'),
      );

      expect(workerLlm.prompts.first, isNot(contains('agents_chain')));
      router.dispose();
    });

    test('unknown agent in graceful mode returns error message', () async {
      final llm = FakeLLM.scripted(['{"agents_chain":["ghost"]}']);
      scope = AgentScope();
      store = DataStore.inMemory();
      final agent = await Agent.create(
        dataStore: store,
        llm: llm,
        name: 'router',
        role: 'router',
        scope: scope,
        failureMode: FailureMode.gracefulMessage,
      );

      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('go'),
      );

      expect(res.isError, isTrue);
      expect(res.content, kLLMResponseOnFailure);
      agent.dispose();
    });
  });
}
