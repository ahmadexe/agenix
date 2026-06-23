# 10 — Serialization Correctness

## Summary
There are concrete data-corruption bugs in the model serialization. The worst: a
**timestamp unit mismatch** between how a conversation's `lastMessageTime` is written and
how it's read — written in **milliseconds** but read as **microseconds** — producing
timestamps off by 1000×. Separately, `ToolResponse.toMap` drops `needsFurtherReasoning`
while `fromMap` reads it (asymmetric round-trip), and `AgentMessage` equality compares
`Uint8List imageData` by reference so two equal image messages are never equal. These are
silent correctness bugs that surface as "wrong dates" and "broken dedupe/caching."

## Severity & impact
**High** for the timestamp bug (visible wrong data in any conversation list), **Medium**
for the others.

## Affected files
- `lib/src/memory/data/conversation.dart` (`toMap` writes `microsecondsSinceEpoch`,
  lines 39–45; `fromMap` reads `microsecondsSinceEpoch`, lines 48–56)
- `lib/src/memory/data/agent_message.dart` (`toMap` writes `millisecondsSinceEpoch`,
  line 62; `==`/`hashCode` use `imageData` by reference, lines 96–116)
- `lib/src/memory/data_sources/_firebase.dart` (writes the conversation doc using the
  message's millisecond `generatedAt` into a field later read as microseconds, lines
  126–135; orders messages by `generatedAt`, line 86)
- `lib/src/tools/tool_response.dart` (`toMap` omits `needsFurtherReasoning`, lines 58–65;
  `fromMap` reads it, line 74)

## Current behavior — the timestamp bug (root cause)
`AgentMessage.toMap` (line 62):
```dart
'generatedAt': generatedAt.millisecondsSinceEpoch, // MILLIS
```
`FirebaseDataStore.saveMessage` (lines 126–135) writes the **conversation** summary doc:
```dart
.set({
  'lastMessage': payload['content'],
  'lastMessageTime': payload['generatedAt'], // <-- this is MILLIS (from AgentMessage.toMap)
  'conversationId': conversationId,
}, SetOptions(merge: true));
```
`Conversation.fromMap` (lines 51–53):
```dart
lastMessageTime: DateTime.fromMicrosecondsSinceEpoch(map['lastMessageTime'] as int), // MICROS
```
So a value stored as milliseconds is interpreted as microseconds → the conversation's
`lastMessageTime` is wrong by a factor of 1000 (dates in ~1970). `Conversation.toMap`
itself also uses `microsecondsSinceEpoch`, which is internally consistent **only** if
conversations are written via `Conversation.toMap` — but the Firebase layer writes the raw
millisecond field instead, so the two paths disagree.

## Target design
Pick **one** epoch unit for all timestamps across the package and use it everywhere.
**Recommend milliseconds** (matches `AgentMessage`, is the common Firestore/JS convention,
and avoids precision-overflow concerns). Then:
- `Conversation.toMap`/`fromMap` → milliseconds.
- The Firebase conversation-summary write already uses the message's millisecond
  `generatedAt`; once `Conversation` is milliseconds, both paths agree.
- (Optional, more idiomatic) store Firestore `Timestamp` objects instead of int epochs and
  convert at the boundary — but only if you standardize the read path too.

## Step-by-step implementation
1. **Conversation** (`conversation.dart`):
   - `toMap`: `'lastMessageTime': lastMessageTime.millisecondsSinceEpoch`.
   - `fromMap`: `DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'] as int)`.
2. **Firebase** (`_firebase.dart`): confirm the conversation-summary write stores the same
   millisecond unit (it currently copies `payload['generatedAt']`, which is millis — good
   once step 1 lands). Add a brief comment naming the unit to prevent regressions.
3. **Migration note:** existing stored conversation docs (if any) used the millisecond
   value but were read as micros; after the fix they'll read correctly for **new** writes.
   For existing data, either backfill or accept that historical `lastMessageTime` was
   already wrong. Document this in the CHANGELOG.
4. **ToolResponse** (`tool_response.dart`): add `'needsFurtherReasoning':
   needsFurtherReasoning` to `toMap` so the round-trip is symmetric (or consciously decide
   it's transient and remove it from `fromMap` — but symmetric is safer).
5. **AgentMessage equality** (`agent_message.dart`): compare `imageData` by **content**,
   not reference. Use `package:collection`'s `listEquals`/`ListEquality` (or
   `foundation.listEquals`) for `Uint8List`, and fold a content hash (e.g. length +
   sampled bytes, or `Object.hashAll`) into `hashCode`. Same care for the `data` map (use
   `mapEquals`, as `ToolResponse` already does, instead of `==` on the map at line 104).
6. **Consider immutability of `ToolResponse.needsFurtherReasoning`**: it's currently a
   mutable `bool` field on an otherwise value-like class; make it `final` for consistency
   with the value-object pattern (its `copyWith` already supports changing it).
7. Add round-trip unit tests: `fromMap(toMap(x)) == x` for `AgentMessage`, `Conversation`,
   and `ToolResponse`, including image and tool-data cases.

## Acceptance criteria
- A conversation written and then read back reports the correct, current `lastMessageTime`
  (not 1970).
- `ToolResponse.fromMap(toMap(r))` preserves `needsFurtherReasoning`.
- Two `AgentMessage`s with byte-identical `imageData`/equal `data` compare equal and share
  a hash code.
- Round-trip tests pass for all three models.

## Related docs
- [04 — memory management](04-memory-management.md) (adding `summary` to Conversation —
  do it in the same unit pass)
- [11 — datastore robustness](11-datastore-robustness-and-testability.md) (where the write
  path lives)
- [12 — dead args & cleanup](12-dead-arguments-and-api-cleanup.md) (the `ToolResponse.data`
  "later versions" comment, mutable field)
