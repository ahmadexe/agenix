import 'package:agenix/agenix.dart';
import 'package:agenix/src/tools/tool_registry.dart';
import 'package:agenix/src/tools/_tool_runner.dart';
import 'package:agenix/src/tools/_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/spy_tool.dart';

PromptParserResult toolCall(
  List<String> tools, [
  Map<String, Map<String, dynamic>> params = const {},
]) => PromptParserResult(
  outcome: ParseOutcome.tools,
  toolNames: tools,
  params: params,
  agentNames: const [],
);

class _ThrowingAgenixTool extends Tool {
  _ThrowingAgenixTool() : super(name: 'agenix-throw', description: 'throws');

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    throw const DataStoreException('db down');
  }
}

void main() {
  group('ToolRunner', () {
    late ToolRegistry reg;
    final runner = ToolRunner();
    setUp(() => reg = ToolRegistry());

    test('runs a registered tool and returns its response', () async {
      reg.registerTool(SpyTool(name: 'a'));
      final out = await runner.runTools(toolCall(['a']), reg);
      expect(out, hasLength(1));
      expect(out.first.toolName, 'a');
    });

    test('validated params reach the tool (number coercion)', () async {
      final spy = SpyTool(
        name: 'calc',
        parameters: [
          ParameterSpecification(
            name: 'n',
            type: 'number',
            description: 'a number',
          ),
        ],
      );
      reg.registerTool(spy);
      await runner.runTools(
        toolCall(
          ['calc'],
          {
            'calc': {'n': '5'},
          },
        ),
        reg,
      );
      expect(spy.calls.first['n'], 5);
    });

    test('throws ToolNotFoundException for unknown tool', () {
      expect(
        () => runner.runTools(toolCall(['ghost']), reg),
        throwsA(isA<ToolNotFoundException>()),
      );
    });

    test('throws ToolExecutionException on validation failure', () {
      reg.registerTool(
        SpyTool(
          name: 'strict',
          parameters: [
            ParameterSpecification(
              name: 'q',
              type: 'string',
              description: 'required',
              required: true,
            ),
          ],
        ),
      );
      expect(
        () => runner.runTools(toolCall(['strict']), reg),
        throwsA(isA<ToolExecutionException>()),
      );
    });

    test('wraps generic tool error in ToolExecutionException', () async {
      reg.registerTool(SpyTool(name: 'boom', throwOnRun: true));
      await expectLater(
        runner.runTools(toolCall(['boom']), reg),
        throwsA(
          isA<ToolExecutionException>().having(
            (e) => e.cause,
            'cause',
            isNotNull,
          ),
        ),
      );
    });

    test('rethrows AgenixException from tool as-is', () async {
      reg.registerTool(_ThrowingAgenixTool());
      await expectLater(
        runner.runTools(toolCall(['agenix-throw']), reg),
        throwsA(isA<DataStoreException>()),
      );
    });

    test('multiple tools run in order', () async {
      final a = SpyTool(name: 'a');
      final b = SpyTool(name: 'b');
      reg.registerTool(a);
      reg.registerTool(b);
      final out = await runner.runTools(toolCall(['a', 'b']), reg);
      expect(out, hasLength(2));
      expect(out[0].toolName, 'a');
      expect(out[1].toolName, 'b');
      expect(a.callCount, 1);
      expect(b.callCount, 1);
    });
  });
}
