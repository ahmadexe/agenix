// Reproduction test — runs the demo topology end-to-end against the real
// Gemini API and prints every event so we can pinpoint what's breaking.

import 'dart:io';

import 'package:agenix/agenix.dart';
import 'package:agenix_example/src/agents/agent_setup.dart';
import 'package:agenix_example/src/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'coordinator chain runs end-to-end',
    () async {
      const apiKey = String.fromEnvironment('GEMINI_API_KEY');
      if (apiKey.isEmpty) {
        fail('Pass --dart-define=GEMINI_API_KEY=...');
      }

      final events = <AgentEvent>[];
      final sub = AgentEventBus.instance.stream.listen((e) {
        events.add(e);
        // ignore: avoid_print
        print(
          '[${e.kind.name}] src=${e.source} tgt=${e.target ?? "-"} '
          'detail=${e.detail == null ? "-" : _peek(e.detail!)}',
        );
      });

      final topology = await buildDemoTopology(apiKey: apiKey);

      // Raw LLM smoke test first.
      final smoke = await LLM
          .geminiLLM(apiKey: apiKey, modelName: 'gemini-flash-latest')
          .generate(prompt: 'Reply with {"response": "ok"}');
      // ignore: avoid_print
      print('SMOKE: $smoke');

      final reply = await topology.coordinator.generateResponse(
        convoId: 'repro',
        userMessage: AgentMessage(
          content:
              'Brief me on Rust adoption in backend web development. Research '
              'what teams are saying, run the numbers on the adoption trend, '
              'and write it up as a short executive briefing.',
          generatedAt: DateTime.now(),
          isFromAgent: false,
        ),
      );

      // ignore: avoid_print
      print('\n========= FINAL REPLY =========\n${reply.content}\n');

      await sub.cancel();
      topology.disposeAll();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _peek(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
