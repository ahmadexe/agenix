import 'package:agenix/src/tools/_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = PromptParser();

  group('PromptParser', () {
    test('parses a direct response', () {
      final r = parser.parse('{"response":"hi"}');
      expect(r.outcome, ParseOutcome.response);
      expect(r.fallbackResponse, 'hi');
    });

    test('response with non-string value calls toString', () {
      final r = parser.parse('{"response": 42}');
      expect(r.outcome, ParseOutcome.response);
      expect(r.fallbackResponse, '42');
    });

    test('tools as comma string with trimming', () {
      final r = parser.parse('{"tools":"a, b ,c"}');
      expect(r.outcome, ParseOutcome.tools);
      expect(r.toolNames, ['a', 'b', 'c']);
    });

    test('tools as list', () {
      final r = parser.parse('{"tools":["a"," b "]}');
      expect(r.outcome, ParseOutcome.tools);
      expect(r.toolNames, ['a', 'b']);
    });

    test('tools with params', () {
      final r = parser.parse(
        '{"tools":"w","parameters":{"w":{"city":"London"}}}',
      );
      expect(r.params['w'], {'city': 'London'});
    });

    test('tools missing params key yields empty map per tool', () {
      final r = parser.parse('{"tools":"w"}');
      expect(r.params['w'], <String, dynamic>{});
    });

    test('tools with non-map params entry yields empty map', () {
      final r = parser.parse('{"tools":"w","parameters":{"w":"oops"}}');
      expect(r.params['w'], <String, dynamic>{});
    });

    test('empty tools string yields tools outcome with empty list', () {
      final r = parser.parse('{"tools":" , "}');
      expect(r.outcome, ParseOutcome.tools);
      expect(r.toolNames, isEmpty);
    });

    test('agents_chain as list', () {
      final r = parser.parse('{"agents_chain":["x","y"]}');
      expect(r.outcome, ParseOutcome.agentsChain);
      expect(r.agentNames, ['x', 'y']);
    });

    test('agents_chain as single string', () {
      final r = parser.parse('{"agents_chain":"solo"}');
      expect(r.outcome, ParseOutcome.agentsChain);
      expect(r.agentNames, ['solo']);
    });

    test('agents_chain wins over tools when both present', () {
      final r = parser.parse('{"agents_chain":["x"],"tools":"a"}');
      expect(r.outcome, ParseOutcome.agentsChain);
    });

    test('strips markdown fences', () {
      final r = parser.parse('```json\n{"response":"hi"}\n```');
      expect(r.outcome, ParseOutcome.response);
      expect(r.fallbackResponse, 'hi');
    });

    test('extracts JSON embedded in prose', () {
      final r = parser.parse('Sure! {"response":"hi"} done');
      expect(r.outcome, ParseOutcome.response);
      expect(r.fallbackResponse, 'hi');
    });

    test('garbage returns unparseable', () {
      final r = parser.parse('not json at all');
      expect(r.outcome, ParseOutcome.unparseable);
      expect(r.rawOutput, 'not json at all');
    });

    test('empty string returns unparseable', () {
      expect(parser.parse('').outcome, ParseOutcome.unparseable);
      expect(parser.parse('   ').outcome, ParseOutcome.unparseable);
    });

    test('valid JSON array returns unparseable', () {
      expect(parser.parse('[1,2,3]').outcome, ParseOutcome.unparseable);
    });

    test('valid JSON object without known keys returns unparseable', () {
      expect(parser.parse('{"foo":"bar"}').outcome, ParseOutcome.unparseable);
    });

    test('never throws on any input', () {
      for (final bad in [
        '',
        '   ',
        'not json',
        '{{{{',
        '\x00\x01\x02',
        'a' * 10000,
      ]) {
        expect(() => parser.parse(bad), returnsNormally);
      }
    });
  });
}
