# 06 — Unit Tests: DataStores

## Summary
`DataStore` has two implementations: `InMemoryDataStore` (zero-dependency, used everywhere in
tests) and `FirebaseDataStore` (the default backend, now with injectable Firebase services
and `_resolveUserId` instead of force-unwraps). Both must satisfy the **same behavioral
contract**, so this doc defines a shared contract suite run against each, plus
implementation-specific tests (auth/error mapping for Firebase).

## Scope & priority
**High.** The in-memory store underpins every integration test; if its ordering/`limit`
semantics are wrong, doc 07's assertions are meaningless. The Firebase tests protect the
auth-safety and typed-error fixes from improvements docs 03/11.

## Files under test
- `lib/src/memory/data_sources/_in_memory.dart`
- `lib/src/memory/data_sources/_firebase.dart`
- `lib/src/memory/data/data_store.dart` (the `inMemory()` / `firestoreDataStore()` factories)

## Files to create
- `test/memory/datastore_contract.dart` — a reusable suite parameterized by a store factory.
- `test/memory/in_memory_store_test.dart`
- `test/memory/firebase_store_test.dart`

## The shared contract suite (`datastore_contract.dart`)
Define a function that, given a way to build a fresh store, asserts the common behavior. Run
it from both store test files.

```dart
import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the DataStore behavioral contract against the store built by [build].
/// [build] must return a *fresh, empty* store each call.
void runDataStoreContract(String label, Future<DataStore> Function() build) {
  group('DataStore contract: $label', () {
    late DataStore store;
    setUp(() async => store = await build());

    AgentMessage msg(String c, {required bool fromAgent, required int ms}) =>
        AgentMessage(
          content: c,
          isFromAgent: fromAgent,
          generatedAt: DateTime.fromMillisecondsSinceEpoch(ms),
        );

    test('saveMessage then getMessages returns it', () async {
      await store.saveMessage('c1', msg('hi', fromAgent: false, ms: 1000));
      final out = await store.getMessages('c1');
      expect(out.map((m) => m.content), ['hi']);
    });

    test('getMessages returns oldest-first', () async {
      await store.saveMessage('c1', msg('a', fromAgent: false, ms: 1000));
      await store.saveMessage('c1', msg('b', fromAgent: true, ms: 2000));
      final out = await store.getMessages('c1');
      expect(out.map((m) => m.content), ['a', 'b']);
    });

    test('getMessages honors limit (most recent N, still oldest-first)', () async {
      for (var i = 0; i < 5; i++) {
        await store.saveMessage('c1', msg('m$i', fromAgent: false, ms: 1000 + i));
      }
      final out = await store.getMessages('c1', limit: 2);
      expect(out.map((m) => m.content), ['m3', 'm4']);
    });

    test('getMessages on unknown conversation returns empty', () async {
      expect(await store.getMessages('nope'), isEmpty);
    });

    test('getConversations reflects the last saved message', () async {
      await store.saveMessage('c1', msg('first', fromAgent: false, ms: 1000));
      await store.saveMessage('c1', msg('last', fromAgent: true, ms: 2000));
      final convos = await store.getConversations();
      final c1 = convos.firstWhere((c) => c.conversationId == 'c1');
      expect(c1.lastMessage, 'last');
    });

    test('deleteConversation removes messages and the summary', () async {
      await store.saveMessage('c1', msg('x', fromAgent: false, ms: 1000));
      await store.deleteConversation('c1');
      expect(await store.getMessages('c1'), isEmpty);
      expect(
        (await store.getConversations()).where((c) => c.conversationId == 'c1'),
        isEmpty,
      );
    });
  });
}
```

> **Ordering caveat for the in-memory store:** the current `InMemoryDataStore` appends in
> insertion order and `getMessages(limit)` returns `sublist(length - limit)`. The contract
> above feeds messages in chronological order, so insertion order == time order. If you want
> the store to *sort* by `generatedAt` regardless of insertion order, that's an enhancement —
> note it, but write the contract to match current behavior (insertion order) and document
> the assumption. The Firebase store *does* sort by `generatedAt` via `orderBy`.

## `in_memory_store_test.dart`
```dart
import 'package:agenix/agenix.dart';
import 'datastore_contract.dart';

void main() {
  runDataStoreContract('InMemoryDataStore', () async => DataStore.inMemory());
}
```
Add in-memory-specific tests:
- Two different `convoId`s are isolated.
- A new `InMemoryDataStore()` instance starts empty (no cross-instance leakage).

## `firebase_store_test.dart`
Goal: exercise `FirebaseDataStore` **without real Firebase**, using the injected fakes.

```dart
import 'package:agenix/agenix.dart';
import 'package:agenix/src/memory/data_sources/_firebase.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'datastore_contract.dart';

void main() {
  // Contract suite against a signed-in fake user.
  runDataStoreContract('FirebaseDataStore', () async {
    return FirebaseDataStore(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(signedIn: true),
      storage: MockFirebaseStorage(),
    );
  });

  group('FirebaseDataStore specifics', () {
    test('throws NotAuthenticatedException when no user is signed in', () async {
      final store = FirebaseDataStore(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: false),
        storage: MockFirebaseStorage(),
      );
      expect(
        () => store.getConversations(),
        throwsA(isA<NotAuthenticatedException>()),
      );
    });

    // Optional: prove generic Firestore errors surface as DataStoreException.
    // Requires a way to force an error from the fake; if the fake can't simulate
    // failures, cover this path via the unit behavior of the catch block instead,
    // or skip with a documented TODO.
  });
}
```

> **Mock-compatibility fallback.** The Firebase mock packages must resolve against this
> repo's Firebase plugin majors (`cloud_firestore ^6`, `firebase_auth ^6`,
> `firebase_storage ^13`). If they don't resolve (a real risk, since these mocks lag the
> plugins), use this fallback instead of dropping coverage:
> - Skip `firebase_store_test.dart` (mark `@Skip('firebase mocks incompatible with v6/v13')`).
> - Still cover `_resolveUserId`/error-mapping intent by treating the **`DataStore` interface
>   as the seam** — the in-memory store already proves the contract, and `NotAuthenticatedException`
>   is exercised by a tiny hand-written `FirebaseAuth` stub via `mocktail` if feasible.
> Document whichever path you took at the top of the file.

## Step-by-step implementation
1. Create `datastore_contract.dart` with `runDataStoreContract`.
2. Create `in_memory_store_test.dart` calling the contract + 2 in-memory-specific tests.
3. Create `firebase_store_test.dart`: run the contract against the faked Firebase trio and
   add the not-authenticated test. If mocks won't resolve, apply the documented fallback.
4. Confirm `getMessages(limit:)` semantics match between both stores for the
   chronological-insertion case (the contract enforces this).
5. Run `flutter test test/memory`; `flutter analyze` clean.

## Acceptance criteria
- One contract suite runs green against **both** stores (or the Firebase run is explicitly
  skipped with a documented reason).
- `limit`, ordering, isolation, conversation-summary, and delete behaviors are all asserted.
- `FirebaseDataStore` throws `NotAuthenticatedException` (not a null crash) when signed out.
- No real Firebase initialization or network occurs.

## Related docs
- [02 — fixtures](02-fakes-and-fixtures.md)
- [07 — agent integration tests](07-integration-tests-agent-loop-and-chaining.md) (consumes in-memory store)
- improvements [11 — datastore robustness & testability](../improvements/11-datastore-robustness-and-testability.md)
- improvements [04 — memory management](../improvements/04-memory-management.md) (limit semantics)
