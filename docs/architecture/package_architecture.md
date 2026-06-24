# Agenix Package Architecture

> A guide to how the agenix monorepo is structured, why it's structured that way,
> and how to work on it. Written for you (the maintainer) and any new engineer
> joining the project.

---

## 1. The big idea in one sentence

**Agenix is split into a small dependency-free core (`agenix`) plus optional
backend packages (`agenix_firebase`, later `agenix_supabase`, …), so an app only
pulls in the heavy dependencies for the backend it actually uses.**

Before the split, every consumer of `agenix` was forced to download the entire
Firebase suite (`firebase_core`, `firebase_auth`, `cloud_firestore`,
`firebase_storage`) even if they only used the in-memory store. That's the problem
this architecture fixes.

---

## 2. Why a monorepo (and not something simpler)

Dart/pub gives us no good alternative:

- **There are no "optional dependencies" in pub.** If a package declares a
  dependency, every consumer gets it, transitively, in their lockfile.
- **Conditional imports** (`if (dart.library.io)`) solve platform differences, not
  "the user chose a backend." They cannot remove a package from the dependency graph.
- **Runtime plugin loading via reflection** is not idiomatic in Dart and still
  requires the dependency to be present at build time.

So the only real way to make Firebase optional is to **put it in a separate
package**. Once you have more than one package that share code and release together,
a **monorepo** managed by **Melos** + **pub workspaces** is the standard tooling.

This is exactly the pattern used by FlutterFire, Riverpod, Drift, and `build_runner`.
We are following a well-trodden path, not inventing one.

---

## 3. Repository layout

```
agenix/                              # repo root = Melos workspace
├── melos.yaml                       # workspace scripts (analyze/test/format)
├── pubspec.yaml                     # workspace root: lists members, dev-dep on melos
├── codecov.yml                      # coverage config (repo-level)
├── README.md                        # monorepo landing page (package table)
├── docs/
│   └── architecture/
│       └── package_architecture.md  # ← you are here
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                   # Melos-driven analyze + test + coverage
│   │   └── publish.yml              # per-package tag → pub.dev
│   └── dependabot.yml               # one pub entry per package
└── packages/
    ├── agenix/                      # CORE — no backend deps
    │   ├── lib/
    │   │   ├── agenix.dart          # public barrel
    │   │   └── src/
    │   │       ├── agent/           # Agent + part-file helpers
    │   │       ├── llm/             # LLM interface + Gemini
    │   │       ├── memory/          # DataStore + InMemoryDataStore + models
    │   │       ├── tools/           # Tool, registry, parser, runner
    │   │       └── static/          # constants + exceptions
    │   ├── test/
    │   ├── example/                 # minimal, Firebase-free
    │   ├── pubspec.yaml             # version 5.x, deps: gemini + uuid only
    │   ├── README.md
    │   └── CHANGELOG.md
    └── agenix_firebase/             # OPTIONAL Firebase backend
        ├── lib/
        │   ├── agenix_firebase.dart # exports FirebaseDataStore
        │   └── src/firebase_data_store.dart
        ├── test/
        │   ├── firebase_store_test.dart
        │   └── datastore_contract.dart   # duplicated from core (see §6)
        ├── example/                 # the Firebase demo app
        ├── pubspec.yaml             # version 1.x, deps: agenix + firebase suite
        ├── README.md
        └── CHANGELOG.md
```

---

## 4. The core package (`agenix`)

This is the brain. It has four domains under `lib/src/`, unchanged by the migration:

| Domain | What lives there | Key types |
|---|---|---|
| `agent/` | The orchestration core | `Agent`, and `part` files `_MemoryManager`, `_PromptBuilder`, `_AgentRegistry` |
| `llm/` | Language-model abstraction | `LLM` (abstract), `_GeminiLLM`, `LLMConfig` |
| `memory/` | Persistence abstraction + models | `DataStore` (abstract), `InMemoryDataStore`, `AgentMessage`, `Conversation` |
| `tools/` | The tool system | `Tool`, `ToolRegistry`, `ParameterSpecification`, `ToolResponse`, `PromptParser`, `ToolRunner` |
| `static/` | Cross-cutting constants & errors | `kLLMResponseOnFailure`, `AgenixException` family |

**Public API surface** is whatever `lib/agenix.dart` exports — nothing else.
Internal files are underscore-prefixed (`_gemini.dart`, `_parser.dart`, …) and the
agent's helpers are `part` files so they can touch `Agent`'s private fields without
becoming public.

The single most important class for this architecture is the **`DataStore`**
abstraction in `lib/src/memory/data/data_store.dart`:

```dart
abstract class DataStore {
  Future<void> saveMessage(String convoId, AgentMessage msg, {Object? metaData});
  Future<List<AgentMessage>> getMessages(String conversationId, {int? limit, Object? metaData});
  Future<void> deleteConversation(String conversationId, {Object? metaData});
  Future<List<Conversation>> getConversations({Object? metaData});

  static DataStore inMemory() => InMemoryDataStore();   // ships in core
  // NOTE: firestoreDataStore() was REMOVED in v5 — it lives in agenix_firebase now.
}
```

`Agent` only ever talks to this interface (via `_MemoryManager`). It has **no idea**
whether the bytes end up in RAM, Firestore, Supabase, or a file. That decoupling is
what makes the whole split possible — and it already existed before the migration.
The migration just took advantage of it.

### The `metaData` pass-through
Every `DataStore` method takes an optional `Object? metaData`. It's an opaque
pass-through the `Agent` forwards untouched. A concrete store can use it for
auth tokens, tenant IDs, etc. Core doesn't interpret it.

---

## 5. The Firebase package (`agenix_firebase`)

A thin package whose entire job is to provide one class:

```dart
class FirebaseDataStore extends DataStore { ... }
```

It depends on `agenix` (for `DataStore`, `AgentMessage`, `Conversation`, and the
exception types) plus the Firebase suite. Because `FirebaseDataStore` is now public
API (not an internal `_firebase.dart`), it lives in `lib/src/firebase_data_store.dart`
and is exported from `lib/agenix_firebase.dart`.

Consumer usage:

```dart
import 'package:agenix/agenix.dart';
import 'package:agenix_firebase/agenix_firebase.dart';

final agent = await Agent.create(
  dataStore: FirebaseDataStore(),   // was DataStore.firestoreDataStore()
  llm: LLM.geminiLLM(apiKey: '...'),
  name: 'support',
  role: 'Customer support agent',
);
```

What it stores, for reference:
- Firestore path: `chats/{uid}/conversations/{conversationId}/messages/{auto}`
- Conversation summary doc carries `lastMessage`, `lastMessageTime`, `conversationId`.
- Images go to Firebase Storage (`messages/{uuid}.{ext}`), URL saved on the message.
- Requires an authenticated user; throws `NotAuthenticatedException` otherwise.

---

## 6. How the two packages share code

### Source dependency
`agenix_firebase` depends on `agenix` and imports only its **public barrel**
(`package:agenix/agenix.dart`) — never `package:agenix/src/...`. If `FirebaseDataStore`
needs a type, that type must be exported from core. This is a healthy constraint: it
keeps the public API honest.

### Test sharing — the one duplication
`datastore_contract.dart` is a reusable test suite (`runDataStoreContract(...)`) that
asserts any `DataStore` behaves correctly: save/get ordering, `limit` semantics,
delete, empty-conversation handling. Both `InMemoryDataStore` and `FirebaseDataStore`
must pass it.

A test helper in one package's `test/` directory **cannot** be imported by another
package. So the contract file is **intentionally duplicated** into both packages.
It's ~60 lines with no dependencies and changes rarely, so duplication is cheaper
than introducing a third (unpublished) `agenix_test_support` package.

> If a third or fourth backend appears and the contract starts drifting between
> copies, promote it to an unpublished `packages/agenix_test_support` package and
> have every backend depend on it as a dev-dependency. Until then, keep the copies
> in sync by hand (they're tiny).

---

## 7. Tooling: Melos + pub workspaces

Two layers cooperate:

- **pub workspaces** (the `workspace:` list in the root `pubspec.yaml`, plus
  `resolution: workspace` in each member) do **dependency resolution**. Locally,
  `agenix_firebase`'s `agenix: ^4.0.0` resolves to the in-repo copy automatically —
  no `path:` overrides, no stale links. One `dart pub get` at the root resolves
  everything.
- **Melos** provides **multi-package commands** (`melos run analyze`,
  `melos run test`, `melos run format-check`) and version/tag management. The scripts
  live in `melos.yaml`.

Day-to-day commands:

```bash
dart pub get                       # resolve the whole workspace
dart pub global run melos run analyze
dart pub global run melos run test
dart pub global run melos run test:coverage
```

To work on a single package, just `cd packages/agenix` and use normal `flutter`
commands — they work in isolation, which is the best way to catch a package
accidentally leaning on another's transitive deps.

---

## 8. CI/CD model

- **`ci.yml`** — on every push/PR to `main`: sets up Flutter, `dart pub get`
  (resolves the workspace), then runs Melos `format-check` → `analyze --fatal-infos`
  → `test:coverage`. Each package writes its own `coverage/lcov.info`; CI merges
  them with `lcov -a` and enforces a 50% floor, then uploads to Codecov.
- **`publish.yml`** — triggered by **per-package tags**, because one tag scheme
  can't target two packages:
  - `agenix-v5.0.0` → publishes `packages/agenix`
  - `agenix_firebase-v1.0.0` → publishes `packages/agenix_firebase`
  The workflow parses the tag, verifies it matches that package's pubspec version,
  runs `pub publish --dry-run`, enforces a pana score >= 150, then publishes via
  pub.dev OIDC (no stored tokens).
- **`dependabot.yml`** — one `pub` entry per package directory (root `/` no longer
  covers them) plus the GitHub-Actions entry.

**Release ordering matters:** publish `agenix` first (because `agenix_firebase`
depends on `agenix ^5.0.0` existing on pub.dev), then `agenix_firebase`.

---

## 9. Versioning policy

Packages are versioned **independently**:
- `agenix` — bump major when you break the public API (e.g., changing `DataStore`).
- `agenix_firebase` — bump on its own cadence; its `agenix: ^5.0.0` constraint
  controls which core versions it accepts. Widen that constraint (e.g.
  `>=5.0.0 <7.0.0`) when you've verified compatibility with a new core major.

A backend package should not force a lockstep major bump on every consumer just
because core moved — keep the constraint as wide as is safe.

---

## 10. How to do common tasks

### Add a new data-store backend (e.g. Supabase)
1. `mkdir packages/agenix_supabase`, add it to the root `pubspec.yaml` `workspace:`.
2. Implement `class SupabaseDataStore extends DataStore` against
   `package:agenix/agenix.dart` only.
3. Add the barrel `agenix_supabase.dart` exporting the public store.
4. Copy `datastore_contract.dart`, write `supabase_store_test.dart` using it.
5. Add a Dependabot entry and a `publish.yml` tag pattern.
6. Ship `1.0.0` depending on `agenix: ^5.0.0`. **No core changes needed.**

### Add a new public type to core
Add the file under `lib/src/...`, then export it from `lib/agenix.dart`. If a
backend package needs it, it's now reachable via the barrel. (If you forget to
export, the backend package won't compile — a useful guardrail.)

### Add a new LLM provider
Mirror the `DataStore`/Gemini pattern: abstract `LLM` already exists; add a concrete
`_yourLLM.dart` under `lib/src/llm/` and a factory static on `LLM`. LLMs are
currently all in core (they're light, pure-Dart HTTP clients). If one ever drags a
heavy SDK, split it into its own package using the same recipe as backends.

### Change the `DataStore` interface
This is the high-blast-radius change. Editing the abstract methods breaks **every**
backend package and is a **core major bump**. Update `InMemoryDataStore`, every
backend's store, and the shared contract together, then release core first.

---

## 11. Mental model / TL;DR

- **`agenix`** = the framework. Light. Depends on nothing heavy. Ships an in-memory
  store so it works out of the box.
- **`agenix_<backend>`** = a plug. Implements `DataStore`. Brings the heavy deps,
  but only into apps that ask for it.
- **`DataStore`** = the socket they all plug into. The reason any of this works.
- **Melos + pub workspaces** = the tooling that lets these develop and release
  together from one repo.
- **Per-package tags** = how releases stay independent.

If you remember one rule: **backend packages depend on core's public barrel, never
the reverse, and never on each other.** Keep that arrow pointing one way and the
architecture stays clean.
