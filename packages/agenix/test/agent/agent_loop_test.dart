import 'dart:typed_data';
import 'package:agenix/agenix.dart';
import 'package:agenix/src/static/_pkg_constants.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_llm.dart';
import '../helpers/fixtures.dart';
import '../helpers/spy_tool.dart';
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

  Future<Agent> buildAgent(
    FakeLLM llm, {
    FailureMode mode = FailureMode.gracefulMessage,
    void Function(AgenixException, StackTrace)? onError,
  }) => Agent.create(
    dataStore: store,
    llm: llm,
    name: 'tester',
    role: 'test agent',
    failureMode: mode,
    onError: onError,
    scope: scope,
  );

  group('Agent loop', () {
    test('direct response', () async {
      final llm = FakeLLM.scripted(['{"response":"hello there"}']);
      final agent = await buildAgent(llm);
      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('hi'),
      );
      expect(res.content, 'hello there');
      expect(res.isFromAgent, isTrue);
      expect(res.isError, isFalse);
      expect(llm.callCount, 1);
      agent.dispose();
    });

    test(
      'persistence on success: user and agent messages saved in order',
      () async {
        final llm = FakeLLM.scripted(['{"response":"yo"}']);
        final agent = await buildAgent(llm);
        final um = userMsg('hi');
        await agent.generateResponse(convoId: 'c1', userMessage: um);
        final msgs = await store.getMessages('c1');
        expect(msgs, hasLength(2));
        expect(msgs[0].isFromAgent, isFalse);
        expect(msgs[1].isFromAgent, isTrue);
        agent.dispose();
      },
    );

    test('single tool then synthesized response', () async {
      final llm = FakeLLM.scripted([
        '{"tools":"weather","parameters":{"weather":{"city":"Paris"}}}',
        '{"response":"It is sunny in Paris"}',
      ]);
      final agent = await buildAgent(llm);
      final spy = SpyTool(
        name: 'weather',
        response: okTool('weather', message: 'sunny'),
      );
      agent.toolRegistry.registerTool(spy);

      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('weather in Paris?'),
      );

      expect(spy.calls.single['city'], 'Paris');
      expect(res.content, 'It is sunny in Paris');
      expect(res.data?['observations'], isNotEmpty);
      expect(llm.callCount, 2);
      agent.dispose();
    });

    test('validated params reach the tool (number coercion)', () async {
      final llm = FakeLLM.scripted([
        '{"tools":"calc","parameters":{"calc":{"n":"42"}}}',
        '{"response":"done"}',
      ]);
      final agent = await buildAgent(llm);
      final spy = SpyTool(
        name: 'calc',
        parameters: [
          ParameterSpecification(
            name: 'n',
            type: 'number',
            description: 'a num',
          ),
        ],
      );
      agent.toolRegistry.registerTool(spy);

      await agent.generateResponse(convoId: 'c1', userMessage: userMsg('calc'));

      expect(spy.calls.single['n'], 42);
      agent.dispose();
    });

    test('reason-over-data path', () async {
      final llm = FakeLLM.scripted([
        '{"tools":"fetch","parameters":{"fetch":{}}}',
        'The data says everything is fine.',
      ]);
      final agent = await buildAgent(llm);
      agent.toolRegistry.registerTool(
        SpyTool(
          name: 'fetch',
          response: okTool(
            'fetch',
            message: 'raw data',
            data: {'x': 1},
            needsReasoning: true,
          ),
        ),
      );

      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('summarize'),
      );

      expect(res.content, contains('data says everything'));
      expect(res.data?['tools'], isNotEmpty);
      agent.dispose();
    });

    test('multi-step tool loop', () async {
      final llm = FakeLLM.scripted([
        '{"tools":"a","parameters":{"a":{}}}',
        '{"tools":"b","parameters":{"b":{}}}',
        '{"response":"all done"}',
      ]);
      final agent = await buildAgent(llm);
      final spyA = SpyTool(name: 'a');
      final spyB = SpyTool(name: 'b');
      agent.toolRegistry.registerTool(spyA);
      agent.toolRegistry.registerTool(spyB);

      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('do both'),
      );

      expect(spyA.callCount, 1);
      expect(spyB.callCount, 1);
      expect(res.content, 'all done');
      expect(llm.prompts[1], contains('ok from a'));
      agent.dispose();
    });

    test('duplicate tool call is deduplicated and returns observations', () async {
      // All responses request the same tool with identical params — dedup should
      // fire on the second call (step 1) and return early with the observation.
      final responses = List.generate(
        kMaxToolIterations,
        (_) => '{"tools":"t","parameters":{"t":{}}}',
      );
      final llm = FakeLLM.scripted(responses);
      final agent = await buildAgent(llm);
      agent.toolRegistry.registerTool(SpyTool(name: 't'));

      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('loop'),
      );

      // Dedup fires after second LLM call sees the same tool+params combo.
      expect(res.content, contains('ok from t'));
      expect(llm.callCount, 2);
      agent.dispose();
    });

    test('parse-retry recovery', () async {
      final llm = FakeLLM.scripted([
        'garbage not json',
        '{"response":"recovered"}',
      ]);
      final agent = await buildAgent(llm);

      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('hi'),
      );

      expect(res.content, 'recovered');
      expect(llm.prompts[1], contains(kParseRetryInstruction));
      agent.dispose();
    });

    test('unparseable after all retries - graceful mode', () async {
      final responses = List.generate(
        kMaxParseRetries + 1,
        (_) => 'still garbage',
      );
      final llm = FakeLLM.scripted(responses);
      final agent = await buildAgent(llm);

      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('hi'),
      );

      expect(res.content, kLLMResponseOnFailure);
      expect(res.isError, isTrue);
      expect(await store.getMessages('c1'), isEmpty);
      agent.dispose();
    });

    test('unparseable after all retries - throwError mode', () async {
      final responses = List.generate(
        kMaxParseRetries + 1,
        (_) => 'still garbage',
      );
      final llm = FakeLLM.scripted(responses);
      final agent = await buildAgent(llm, mode: FailureMode.throwError);

      expect(
        () => agent.generateResponse(convoId: 'c1', userMessage: userMsg('hi')),
        throwsA(isA<ResponseParseException>()),
      );
      agent.dispose();
    });

    test('onError callback fires on failure', () async {
      AgenixException? capturedError;
      final responses = List.generate(kMaxParseRetries + 1, (_) => 'garbage');
      final llm = FakeLLM.scripted(responses);
      final agent = await buildAgent(
        llm,
        onError: (e, st) => capturedError = e,
      );

      await agent.generateResponse(convoId: 'c1', userMessage: userMsg('hi'));

      expect(capturedError, isA<ResponseParseException>());
      agent.dispose();
    });

    test('LLM transport error wrapped in graceful mode', () async {
      final llm = FakeLLM(responses: [], throwWhenExhausted: true);
      final agent = await buildAgent(llm);

      final res = await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('hi'),
      );

      expect(res.isError, isTrue);
      expect(res.content, kLLMResponseOnFailure);
      agent.dispose();
    });

    test('rawData only on first LLM call', () async {
      final llm = FakeLLM.scripted([
        '{"tools":"t","parameters":{"t":{}}}',
        '{"response":"done"}',
      ]);
      final agent = await buildAgent(llm);
      agent.toolRegistry.registerTool(SpyTool(name: 't'));

      final um = userMsg(
        'hi',
      ).copyWith(imageData: Uint8List.fromList([1, 2, 3]));
      await agent.generateResponse(convoId: 'c1', userMessage: um);

      expect(llm.rawDataReceived[0], isNotNull);
      expect(llm.rawDataReceived[1], isNull);
      agent.dispose();
    });

    test('error messages excluded from chat history', () async {
      final errMsg = agentMsg('previous error', isError: true);
      await store.saveMessage('c1', errMsg);

      final llm = FakeLLM.scripted(['{"response":"ok"}']);
      final agent = await buildAgent(llm);

      await agent.generateResponse(
        convoId: 'c1',
        userMessage: userMsg('hello'),
      );

      expect(llm.prompts.first, isNot(contains('previous error')));
      agent.dispose();
    });
  });
}
