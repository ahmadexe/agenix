import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolResponse', () {
    final base = ToolResponse(
      toolName: 'weather',
      isRequestSuccessful: true,
      message: 'sunny',
      data: {'temp': 22},
      needsFurtherReasoning: true,
    );

    test(
      'round-trips through toMap/fromMap including needsFurtherReasoning',
      () {
        final back = ToolResponse.fromMap(base.toMap());
        expect(back, equals(base));
        expect(back.needsFurtherReasoning, isTrue);
      },
    );

    test('round-trips through toJson/fromJson', () {
      final back = ToolResponse.fromJson(base.toJson());
      expect(back, equals(base));
    });

    test('fromMap with data absent yields null', () {
      final map = base.toMap()..remove('data');
      expect(ToolResponse.fromMap(map).data, isNull);
    });

    test('fromMap defaults needsFurtherReasoning to false when absent', () {
      final map = base.toMap()..remove('needsFurtherReasoning');
      expect(ToolResponse.fromMap(map).needsFurtherReasoning, isFalse);
    });

    test('equality compares data by value', () {
      final a = ToolResponse(
        toolName: 'weather',
        isRequestSuccessful: true,
        message: 'sunny',
        data: {'temp': 22},
        needsFurtherReasoning: true,
      );
      expect(a, equals(base));
    });

    test('inequality when data differs', () {
      final other = base.copyWith(data: {'temp': 99});
      expect(other, isNot(equals(base)));
    });

    test('copyWith with no args yields equal object', () {
      final copy = base.copyWith();
      expect(copy, equals(base));
      expect(identical(copy, base), isFalse);
    });

    test('copyWith changes only specified field', () {
      final copy = base.copyWith(message: 'rainy');
      expect(copy.message, 'rainy');
      expect(copy.toolName, base.toolName);
      expect(copy.needsFurtherReasoning, base.needsFurtherReasoning);
    });

    test('toString contains toolName', () {
      expect(base.toString(), contains('weather'));
    });
  });
}
