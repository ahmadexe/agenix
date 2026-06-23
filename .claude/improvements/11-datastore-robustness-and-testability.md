# 11 — DataStore Robustness & Testability

## Summary
`FirebaseDataStore` hardcodes `FirebaseFirestore.instance`, `FirebaseAuth.instance`, and
`FirebaseStorage.instance`, force-unwraps `_auth.currentUser!` in four places, wraps every
error in a stringly-typed `Exception`, and ignores the `metaData` pass-through that the
whole API was designed to carry. There is no in-memory `DataStore`, so **the agent cannot
be unit-tested without Firebase**. For a package that markets itself as "pluggable," the
default store is tightly coupled and untestable.

## Severity & impact
**Medium-High.** Coupling to Firebase singletons + force-unwrapped auth = crashes for
unauthenticated users and zero test coverage of the core flow without a live backend.

## Affected files
- `lib/src/memory/data_sources/_firebase.dart` (entire file)
- `lib/src/memory/data/data_store.dart` (interface; `getConversations` arg; factory)
- New file: `lib/src/memory/data_sources/_in_memory.dart` (test/default-light store)

## Current behavior
```dart
class FirebaseDataStore extends DataStore {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // hardcoded
  final FirebaseAuth _auth = FirebaseAuth.instance;                // hardcoded
  final FirebaseStorage _storage = FirebaseStorage.instance;       // hardcoded
  ...
  final userId = _auth.currentUser!.uid; // null-check crash if signed out (x4)
  ...
  } catch (e) { throw Exception('Error saving message: $e'); } // stringly-typed
}
```
- `metaData` is accepted by every method and **never used** — yet `metaData` is documented
  as the mechanism for tenant/auth context. The Firebase store should at minimum be able to
  use it to resolve the user id instead of relying solely on `currentUser`.
- `getConversations(String conversationId, ...)` takes a `conversationId` but lists **all**
  conversations and ignores it (see doc 12).

## Target design

### 1. Dependency injection for the Firebase instances
Accept the three Firebase services via the constructor with defaults:
```dart
FirebaseDataStore({
  FirebaseFirestore? firestore,
  FirebaseAuth? auth,
  FirebaseStorage? storage,
}) : _firestore = firestore ?? FirebaseFirestore.instance,
     _auth = auth ?? FirebaseAuth.instance,
     _storage = storage ?? FirebaseStorage.instance;
```
This enables `fake_cloud_firestore` / `firebase_auth_mocks` in tests and multi-app setups.
Thread these optional params through `DataStore.firestoreDataStore(...)`.

### 2. Safe auth resolution + `metaData`
Add a private `_resolveUserId(Object? metaData)`:
- If `metaData` carries a user id (define a small typed contract, e.g. a
  `AgenixRequestContext { String userId; }` the consumer can pass), use it.
- Else fall back to `_auth.currentUser?.uid`.
- If still null → throw `NotAuthenticatedException` (doc 03), never `!`.

### 3. Typed errors
Replace `throw Exception('Error ...: $e')` with `DataStoreException(message, cause: e,
causeStack: st)` (doc 03), preserving the original error.

### 4. An in-memory DataStore
Add `InMemoryDataStore` implementing the full interface with simple `Map`-backed storage,
honoring `limit`/ordering (doc 04). Expose via `DataStore.inMemory()`. This becomes the
default for tests and a zero-dependency option for prototyping (no Firebase required).

### 5. Honor pagination/limit
Implement the `limit`/cursor params from doc 04 in both stores.

## Step-by-step implementation
1. **Firebase DI**: add the optional constructor params + defaults as above; update the
   `DataStore.firestoreDataStore` factory to forward them.
2. **`_resolveUserId`**: implement and replace all four `currentUser!` usages. Define the
   `AgenixRequestContext` (or documented `metaData` shape) and read it here.
3. **Typed errors**: swap all `throw Exception(...)` for `DataStoreException`/
   `NotAuthenticatedException` with cause + stack.
4. **MIME / image**: when saving image data, prefer the message's content type if available
   (coordinate with doc 01's MIME handling) instead of hardcoding `.jpg`.
5. **In-memory store**: create `_in_memory.dart`; back conversations + messages with maps
   keyed by `convoId`; implement ordering by `generatedAt` and `limit`. Add
   `DataStore.inMemory()` factory; export nothing internal but expose the factory via the
   `DataStore` public class.
6. **Limit/cursor**: implement doc-04's signature in both stores.
7. **Tests**: rewrite/add agent flow tests against `InMemoryDataStore` and a fake LLM; add
   Firebase tests using `fake_cloud_firestore` + `firebase_auth_mocks` (dev_dependencies).
8. **`getConversations` arg**: remove or repurpose the unused `conversationId` (doc 12).

## Acceptance criteria
- The agent's full flow can be unit-tested with `DataStore.inMemory()` and a fake LLM, no
  Firebase initialization required.
- An unauthenticated call (no `currentUser`, no context user id) throws
  `NotAuthenticatedException`, not a null-check crash.
- Firebase services are injectable; tests use mocks.
- `metaData`/context can supply the user id and is actually consulted.
- DataStore errors are `DataStoreException` with the original cause attached.

## Related docs
- [03 — error handling](03-error-handling-and-exceptions.md) (DataStore/auth exceptions)
- [04 — memory management](04-memory-management.md) (limit/pagination signature)
- [05 — registry lifecycle](05-agent-registry-lifecycle.md) (test isolation companion)
- [12 — dead args & cleanup](12-dead-arguments-and-api-cleanup.md) (`getConversations` arg, unused `metaData`)
