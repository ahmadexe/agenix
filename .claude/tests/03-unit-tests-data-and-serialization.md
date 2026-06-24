# 03 — Unit Tests: Data Models & Serialization

## Summary
The three value objects — `AgentMessage`, `Conversation`, `ToolResponse` — are the package's
serialization and equality backbone. Doc 10 of the improvements backlog fixed real bugs here
(the microseconds→milliseconds timestamp bug, asymmetric `toMap`/`fromMap`, identity-based
`hashCode` on maps). Those fixes are currently unprotected by tests. This doc locks them in.

## Scope & priority
**High.** These are pure, synchronous, fast tests with no async or fakes — write them first
to build momentum and to guard the serialization contract that storage and chaining rely on.

## Files under test
- `lib/src/memory/data/agent_message.dart`
- `lib/src/memory/data/conversation.dart`
- `lib/src/tools/tool_response.dart`

## Files to create
- `test/data/agent_message_test.dart`
- `test/data/conversation_test.dart`
- `test/data/tool_response_test.dart`

## Test design

### `AgentMessage` (`agent_message_test.dart`)
Key contract facts to assert (from the source):
- `toMap()` writes `generatedAt` as **`millisecondsSinceEpoch`** and **omits `imageData`**
  (binary is not serialized; only `imageUrl` is).
- `fromMap()` reads `millisecondsSinceEpoch`, defaults `isError` to `false` when absent.
- Equality uses `listEquals` for `imageData` and `mapEquals` for `data`.
- `hashCode` is content-based (`Object.hashAll`).

Cases:
1. **Round-trip (no image):** build a message, `fromMap(toMap())` → equal to original.
   *Critical:* this is the regression guard for the timestamp-unit bug — assert the decoded
   `generatedAt` equals the original to the millisecond.
2. **Round-trip via JSON:** `AgentMessage.fromJson(m.toJson())` equals original.
3. **`imageData` is not serialized:** a message with `imageData` set → `toMap()` has no
   `imageData` key; the round-tripped message has `imageData == null`. (Document that this is
   intended: equality between original-with-bytes and round-tripped-without will be **false**;
   assert that explicitly so the behavior is pinned.)
4. **`isError` default:** `fromMap` of a map lacking `isError` yields `isError == false`.
   A map with `isError: true` yields `true`.
5. **Equality — identical content:** two independently built messages with equal fields are
   `==` and share a `hashCode`.
6. **Equality — `data` map by value:** two messages whose `data` maps are different
   instances but equal contents are `==`. Two with differing `data` are not.
7. **Equality — `imageData` by value:** two messages with equal `Uint8List` contents (but
   different instances) are `==` (covers the `listEquals` fix).
8. **`copyWith`:** changing one field preserves the rest; calling with no args yields an
   equal-but-distinct object.
9. **`toString`** contains the content (light smoke check; don't over-assert format).

```dart
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

    test('round-trips through toMap/fromMap preserving timestamp to the ms', () {
      final back = AgentMessage.fromMap(base.toMap());
      expect(back, equals(base));
      expect(back.generatedAt.millisecondsSinceEpoch, 1700000000123);
    });

    test('does not serialize imageData', () {
      final withImg = base.copyWith(imageData: Uint8List.fromList([1, 2, 3]));
      expect(withImg.toMap().containsKey('imageData'), isFalse);
      expect(AgentMessage.fromMap(withImg.toMap()).imageData, isNull);
    });

    test('defaults isError to false when absent in map', () {
      final map = base.toMap()..remove('isError');
      expect(AgentMessage.fromMap(map).isError, isFalse);
    });

    test('equality compares data maps by value', () {
      final a = base.copyWith(data: {'k': 'v'});
      final b = base.copyWith(data: {'k': 'v'});
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equality compares imageData by value', () {
      final a = base.copyWith(imageData: Uint8List.fromList([9, 8, 7]));
      final b = base.copyWith(imageData: Uint8List.fromList([9, 8, 7]));
      expect(a, equals(b));
    });
  });
}
```

### `Conversation` (`conversation_test.dart`)
Contract: `lastMessageTime` serialized as **`millisecondsSinceEpoch`** (this was the
microseconds bug). Equality over all three fields.
Cases:
1. Round-trip `toMap`/`fromMap` preserves `lastMessageTime` to the millisecond.
2. Round-trip via JSON.
3. `copyWith` semantics.
4. Equality + `hashCode` for equal field sets; inequality when any field differs.

### `ToolResponse` (`tool_response_test.dart`)
Contract: `needsFurtherReasoning` is now serialized (symmetric round-trip), `hashCode` is
content-based over `data`.
Cases:
1. Round-trip `toMap`/`fromMap` **including `needsFurtherReasoning`** (set it `true`, assert
   it survives — regression guard for the asymmetric-serialization fix).
2. Round-trip via JSON.
3. `fromMap` with `data` absent/null yields `data == null`; with a map yields a copied map.
4. `fromMap` defaults `needsFurtherReasoning` to `false` when the key is missing.
5. Equality compares `data` by value; equal-content responses share a `hashCode`.
6. `copyWith` semantics.

## Step-by-step implementation
1. Create the three test files above; one `group()` per class.
2. Use fixed-epoch `DateTime` values everywhere (no `DateTime.now()`).
3. For every model, include at minimum: a `toMap/fromMap` round-trip, a JSON round-trip, a
   value-equality test, and a `copyWith` test.
4. Add the specific **regression guards** called out above (ms timestamp; `imageData` not
   serialized; `needsFurtherReasoning` survives; value-based map/list equality).
5. Run `flutter test test/data` — all green. Run `flutter analyze`.

## Acceptance criteria
- Each of the three models has round-trip, JSON, equality/hashCode, and copyWith tests.
- The millisecond-timestamp behavior is asserted for both `AgentMessage` and `Conversation`.
- `ToolResponse.needsFurtherReasoning` is proven to survive serialization.
- Value-based (not identity-based) equality is proven for `data`/`imageData`.
- `flutter test test/data` passes; `flutter analyze` clean.

## Related docs
- [02 — fixtures](02-fakes-and-fixtures.md) (builders)
- improvements [10 — serialization correctness](../improvements/10-serialization-correctness.md) (the bugs these guard)
