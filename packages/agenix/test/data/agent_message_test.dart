import 'dart:typed_data';
import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentMessage', () {
    final base = AgentMessage(
      content: 'hello',
      isFromAgent: true,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000123),
      data: {'k': 'v'},
    );

    test(
      'round-trips through toMap/fromMap preserving timestamp to the ms',
      () {
        final back = AgentMessage.fromMap(base.toMap());
        expect(back, equals(base));
        expect(back.generatedAt.millisecondsSinceEpoch, 1700000000123);
      },
    );

    test('round-trips through toJson/fromJson', () {
      final back = AgentMessage.fromJson(base.toJson());
      expect(back, equals(base));
    });

    test('does not serialize imageData', () {
      final withImg = base.copyWith(imageData: Uint8List.fromList([1, 2, 3]));
      expect(withImg.toMap().containsKey('imageData'), isFalse);
      final roundTripped = AgentMessage.fromMap(withImg.toMap());
      expect(roundTripped.imageData, isNull);
      expect(roundTripped, isNot(equals(withImg)));
    });

    test('defaults isError to false when absent in map', () {
      final map = base.toMap()..remove('isError');
      expect(AgentMessage.fromMap(map).isError, isFalse);
    });

    test('isError true survives round-trip', () {
      final errMsg = base.copyWith(isError: true);
      expect(AgentMessage.fromMap(errMsg.toMap()).isError, isTrue);
    });

    test('equality compares data maps by value', () {
      final a = base.copyWith(data: {'k': 'v'});
      final b = base.copyWith(data: {'k': 'v'});
      expect(a, equals(b));
    });

    test('inequality when data differs', () {
      final a = base.copyWith(data: {'k': 'v'});
      final b = base.copyWith(data: {'k': 'other'});
      expect(a, isNot(equals(b)));
    });

    test('equality compares imageData by value', () {
      final a = base.copyWith(imageData: Uint8List.fromList([9, 8, 7]));
      final b = base.copyWith(imageData: Uint8List.fromList([9, 8, 7]));
      expect(a, equals(b));
    });

    test('copyWith with no args yields equal object', () {
      final copy = base.copyWith();
      expect(copy, equals(base));
      expect(identical(copy, base), isFalse);
    });

    test('copyWith changes only specified field', () {
      final copy = base.copyWith(content: 'changed');
      expect(copy.content, 'changed');
      expect(copy.isFromAgent, base.isFromAgent);
      expect(copy.generatedAt, base.generatedAt);
    });

    test('toString contains content', () {
      expect(base.toString(), contains('hello'));
    });
  });
}
