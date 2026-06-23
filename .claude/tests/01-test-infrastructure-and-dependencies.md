# 01 — Test Infrastructure & Dependencies

## Summary
Before a single assertion can be written, the project needs the test dependencies, a
predictable folder layout, and a documented way to run tests + measure coverage. Today the
only dev dependencies are `flutter_test` and `flutter_lints`, and the only test file is an
empty stub. This doc establishes the foundation every other test doc builds on.

## Scope & priority
**Critical — blocks everything else.** No fakes, no unit tests, no coverage gate can exist
until the harness is in place.

## Files to create / change
- `pubspec.yaml` — add `dev_dependencies`.
- `test/` — create the directory tree below.
- `test/README.md` — short "how to run" note for contributors (optional but recommended).
- Delete or repurpose `test/agenix_test.dart` (currently `void main() {}`).

## Current state
```yaml
# pubspec.yaml (dev_dependencies today)
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```
```dart
// test/agenix_test.dart
void main() {}
```

## Target design

### 1. Dev dependencies
Add the following to `pubspec.yaml` under `dev_dependencies`. Use current stable versions;
the constraints below are known-compatible with Dart `^3.7.2` / Flutter, but run
`flutter pub get` and bump if the resolver complains.

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

  # Mocking / fakes
  mocktail: ^1.0.4              # null-safe mocks without codegen

  # Firebase fakes (for _firebase.dart tests — see doc 06)
  fake_cloud_firestore: ^4.0.0 # in-memory Firestore
  firebase_auth_mocks: ^0.14.1 # in-memory FirebaseAuth
  firebase_storage_mocks: ^0.7.0 # in-memory FirebaseStorage

  # Coverage / quality (optional locally, used by CI — see ../ci-cd/)
  test: ^1.25.0                 # gives `--coverage` ergonomics if needed
```

> Why `mocktail` and not `mockito`: `mocktail` needs no build_runner/codegen, which keeps
> the test suite fast to iterate on and friendly to AI/human contributors who shouldn't have
> to run a generator. We still hand-write a `FakeLLM` (doc 02) because the LLM seam is small
> and a scripted fake is clearer than a mock.

> Firebase mock package versions move fast and are sometimes tightly pinned to the Firebase
> plugin majors (this repo uses `cloud_firestore: ^6`, `firebase_auth: ^6`,
> `firebase_storage: ^13`). If a mock package version is incompatible, pick the latest that
> resolves and adjust doc 06's examples accordingly. If no compatible mock exists for a given
> Firebase major, doc 06 explains the fallback (mock the store at the `DataStore` seam instead).

### 2. Folder layout
Mirror `lib/src/` so a reader can find the test for any file instantly.

```
test/
├── helpers/
│   ├── fake_llm.dart            # scriptable LLM double (doc 02)
│   ├── spy_tool.dart            # recording Tool double (doc 02)
│   ├── fixtures.dart            # AgentMessage/Conversation/ToolResponse builders (doc 02)
│   └── system_data.dart         # in-code system_data map + asset stub (doc 02)
├── data/
│   ├── agent_message_test.dart  # doc 03
│   ├── conversation_test.dart   # doc 03
│   └── tool_response_test.dart  # doc 03
├── tools/
│   ├── parser_test.dart         # doc 04
│   ├── param_validator_test.dart# doc 04
│   ├── tool_registry_test.dart  # doc 05
│   └── tool_runner_test.dart    # doc 05
├── agent/
│   ├── agent_scope_test.dart    # doc 05
│   ├── agent_loop_test.dart     # doc 07
│   └── agent_chaining_test.dart # doc 07
├── memory/
│   ├── in_memory_store_test.dart    # doc 06
│   ├── firebase_store_test.dart     # doc 06
│   └── datastore_contract.dart      # shared contract suite (doc 06)
└── llm/
    └── gemini_test.dart         # doc 06 of ../llm-coverage covers behavior; basic here
```

> `test/agenix_test.dart` can be deleted. If you prefer a single entrypoint, keep a thin
> `agenix_test.dart` that does nothing but document where the real tests live; `flutter test`
> discovers every `*_test.dart` regardless.

### 3. The `system_data.json` problem in tests
`Agent.create` calls `rootBundle.loadString(pathToSystemData)`. `rootBundle` resolves
against the Flutter asset bundle, which is awkward in a pure `flutter test` run.
Doc 02 gives the concrete solution (`TestWidgetsFlutterBinding` + a fake asset bundle, or a
helper that stubs the message-channel asset loader). Reference it; do not duplicate.

## Step-by-step implementation
1. Edit `pubspec.yaml`: add the dev dependencies above. Run `flutter pub get`. If any mock
   package fails to resolve against the Firebase v6/v13 plugins, drop that one and note it in
   doc 06 (use the `DataStore`-seam fallback for Firebase tests).
2. Create the `test/` subfolders from the layout above (empty for now).
3. Delete `test/agenix_test.dart` (or replace its body with a doc comment pointing to the
   subfolders).
4. Add a `test/README.md` with the run commands:
   ```bash
   flutter test                      # run everything
   flutter test test/tools           # run one folder
   flutter test --coverage           # emit coverage/lcov.info
   flutter test --name "cycle"       # run tests whose name matches
   ```
5. Confirm the empty harness works: `flutter test` should report "No tests ran" (or pass a
   trivial placeholder) with **no analyzer errors**.
6. Run `flutter analyze` — the new dev dependencies must not introduce warnings.

## Acceptance criteria
- `flutter pub get` resolves cleanly with the new dev dependencies.
- The `test/` tree exists matching the layout above.
- `flutter test` runs (even with no real tests yet) and exits 0.
- `flutter test --coverage` produces `coverage/lcov.info`.
- `flutter analyze` is clean.

## Related docs
- [02 — fakes and fixtures](02-fakes-and-fixtures.md) (what goes in `test/helpers/`)
- [06 — datastore tests](06-unit-tests-datastores.md) (Firebase mock decision)
- [08 — coverage and quality gates](08-coverage-and-quality-gates.md) (coverage tooling)
- [../ci-cd/01-github-actions-ci-workflow.md](../ci-cd/01-github-actions-ci-workflow.md) (runs all this in CI)
