import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Conversation', () {
    final base = Conversation(
      lastMessage: 'hi',
      lastMessageTime: DateTime.fromMillisecondsSinceEpoch(1700000000456),
      conversationId: 'conv-1',
    );

    test(
      'round-trips through toMap/fromMap preserving timestamp to the ms',
      () {
        final back = Conversation.fromMap(base.toMap());
        expect(back, equals(base));
        expect(back.lastMessageTime.millisecondsSinceEpoch, 1700000000456);
      },
    );

    test('round-trips through toJson/fromJson', () {
      final back = Conversation.fromJson(base.toJson());
      expect(back, equals(base));
    });

    test('equality and hashCode for equal fields', () {
      final a = Conversation(
        lastMessage: 'hi',
        lastMessageTime: DateTime.fromMillisecondsSinceEpoch(1700000000456),
        conversationId: 'conv-1',
      );
      expect(a, equals(base));
      expect(a.hashCode, equals(base.hashCode));
    });

    test('inequality when any field differs', () {
      expect(base.copyWith(lastMessage: 'bye'), isNot(equals(base)));
      expect(base.copyWith(conversationId: 'conv-2'), isNot(equals(base)));
      expect(
        base.copyWith(
          lastMessageTime: DateTime.fromMillisecondsSinceEpoch(9999),
        ),
        isNot(equals(base)),
      );
    });

    test('copyWith with no args yields equal object', () {
      final copy = base.copyWith();
      expect(copy, equals(base));
      expect(identical(copy, base), isFalse);
    });

    test('toString contains conversationId', () {
      expect(base.toString(), contains('conv-1'));
    });
  });
}
