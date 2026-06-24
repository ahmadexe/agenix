import 'package:agenix/src/tools/_param_validator.dart';
import 'package:agenix/src/tools/param_spec.dart';
import 'package:flutter_test/flutter_test.dart';

ParameterSpecification spec(
  String name, {
  String type = 'string',
  bool required = false,
  dynamic defaultValue,
  List<String>? enumValues,
}) => ParameterSpecification(
  name: name,
  type: type,
  description: 'test param',
  required: required,
  defaultValue: defaultValue,
  enumValues: enumValues,
);

void main() {
  group('validateParams', () {
    test('required present passes', () {
      final r = validateParams([spec('name', required: true)], {'name': 'Sam'});
      expect(r.isValid, isTrue);
      expect(r.values['name'], 'Sam');
    });

    test('required missing fails', () {
      final r = validateParams([spec('name', required: true)], {});
      expect(r.isValid, isFalse);
      expect(r.errors.first, contains('name'));
    });

    test('optional missing with no default is valid and absent', () {
      final r = validateParams([spec('opt')], {});
      expect(r.isValid, isTrue);
      expect(r.values.containsKey('opt'), isFalse);
    });

    test('default injection when missing', () {
      final r = validateParams([
        spec('n', type: 'number', defaultValue: 5),
      ], {});
      expect(r.isValid, isTrue);
      expect(r.values['n'], 5);
    });

    test('provided value wins over default', () {
      final r = validateParams(
        [spec('n', type: 'number', defaultValue: 5)],
        {'n': 10},
      );
      expect(r.values['n'], 10);
    });

    test('enum pass', () {
      final r = validateParams(
        [
          spec('c', enumValues: ['red', 'green']),
        ],
        {'c': 'red'},
      );
      expect(r.isValid, isTrue);
    });

    test('enum fail', () {
      final r = validateParams(
        [
          spec('c', enumValues: ['red', 'green']),
        ],
        {'c': 'blue'},
      );
      expect(r.isValid, isFalse);
      expect(r.errors.first, contains('blue'));
    });

    test('number coercion from string', () {
      final r = validateParams([spec('n', type: 'number')], {'n': '42'});
      expect(r.isValid, isTrue);
      expect(r.values['n'], 42);
    });

    test('number coercion failure', () {
      final r = validateParams([spec('n', type: 'number')], {'n': 'abc'});
      expect(r.isValid, isFalse);
    });

    test('boolean coercion', () {
      expect(
        validateParams([spec('b', type: 'boolean')], {'b': 'true'}).values['b'],
        isTrue,
      );
      expect(
        validateParams(
          [spec('b', type: 'boolean')],
          {'b': 'FALSE'},
        ).values['b'],
        isFalse,
      );
      expect(
        validateParams([spec('b', type: 'boolean')], {'b': true}).values['b'],
        isTrue,
      );
    });

    test('boolean coercion failure', () {
      final r = validateParams([spec('b', type: 'boolean')], {'b': 'maybe'});
      expect(r.isValid, isFalse);
    });

    test('object coercion', () {
      final r = validateParams(
        [spec('o', type: 'object')],
        {
          'o': {'k': 'v'},
        },
      );
      expect(r.isValid, isTrue);
      expect(r.values['o'], isA<Map<String, dynamic>>());
    });

    test('object coercion failure', () {
      final r = validateParams([spec('o', type: 'object')], {'o': 'x'});
      expect(r.isValid, isFalse);
    });

    test('array coercion', () {
      final r = validateParams(
        [spec('a', type: 'array')],
        {
          'a': [1, 2],
        },
      );
      expect(r.isValid, isTrue);
      expect(r.values['a'], [1, 2]);
    });

    test('array coercion failure', () {
      final r = validateParams([spec('a', type: 'array')], {'a': 'x'});
      expect(r.isValid, isFalse);
    });

    test('unknown type passes through unchanged', () {
      final r = validateParams([spec('w', type: 'weird')], {'w': 'anything'});
      expect(r.isValid, isTrue);
      expect(r.values['w'], 'anything');
    });

    test('unknown param passthrough', () {
      final r = validateParams([spec('a')], {'a': 'val', 'extra': 42});
      expect(r.isValid, isTrue);
      expect(r.values['extra'], 42);
    });

    test('null value treated as missing for required param', () {
      final r = validateParams([spec('name', required: true)], {'name': null});
      expect(r.isValid, isFalse);
    });

    test('multiple errors accumulate', () {
      final r = validateParams(
        [
          spec('a', type: 'number', required: true),
          spec('b', type: 'boolean', required: true),
        ],
        {'a': 'abc', 'b': 'maybe'},
      );
      expect(r.isValid, isFalse);
      expect(r.errors.length, 2);
    });
  });
}
