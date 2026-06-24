# Agenix Monorepo Migration Plan

> **Purpose:** Convert the single-package `agenix` repository into a Melos-managed
> monorepo so that consumers only pay for the dependencies they actually use.
> Firebase (and later Supabase, Hive, etc.) becomes an **opt-in** companion package.
>
> **Audience:** An AI agent or a human engineer executing the migration. Every step
> is procedural and verifiable. Do the steps **in order**. Do not skip the
> verification gate at the end of each phase.

---

## 0. Context & Goal

### The problem
Today `agenix` (v4.0.0) declares Firebase as a hard dependency in `pubspec.yaml`:

```yaml
firebase_core: ^4.0.0
firebase_auth: ^6.0.0
cloud_firestore: ^6.0.0
firebase_storage: ^13.0.0
```

Any app that depends on `agenix` is forced to pull the entire Firebase suite —
even if it only uses `DataStore.inMemory()`. The coupling lives in exactly one
source file:

- `lib/src/memory/data/data_store.dart` imports `_firebase.dart` and exposes the
  static factory `DataStore.firestoreDataStore(...)`.

That single import is what drags Firebase into every consumer's build.

### The goal
A Melos monorepo under `packages/`:

```
packages/
  agenix/            # core — in-memory store only, ZERO backend deps
  agenix_firebase/   # opt-in — FirebaseDataStore lives here
  (agenix_supabase/) # future
  (agenix_hive/)     # future
```

- `agenix` keeps the `DataStore` abstraction + `InMemoryDataStore`.
- `agenix_firebase` depends on `agenix` + the Firebase suite and provides
  `FirebaseDataStore`.
- Consumers add `agenix_firebase` only when they want Firebase.

### Why this is the right approach
This is the **federated / companion-package pattern** used by the Flutter
ecosystem itself (FlutterFire, Riverpod, Drift, `build_runner`). It is the
idiomatic solution. The alternatives are worse:
- *Optional dependencies* — Dart/pub has no concept of optional deps.
- *Conditional imports* — works for web-vs-native, not for "user picked a backend";
  it cannot strip a transitive dependency from the lockfile.
- *Reflection/DI plugin loading* — not idiomatic in Dart, and still requires the
  dep to be present.

So: **a monorepo with split packages is correct.** Proceed.

### Breaking-change note (READ THIS)
Removing `firestoreDataStore()` from the core package is an **API break**.
- Core `agenix` goes **3.0.0 -> 4.0.0**.
- `agenix_firebase` starts at **1.0.0** (or `4.0.0` to mirror core — see Phase 9).
- Existing users migrate by: adding `agenix_firebase` to `pubspec.yaml` and
  changing `DataStore.firestoreDataStore(...)` → `FirebaseDataStore(...)`.

---

## 1. Pre-flight (do not skip)

1. Ensure the working tree is clean and you are on a fresh branch:
   ```bash
   git checkout main && git pull
   git checkout -b chore/monorepo-migration
   ```
2. Confirm baseline is green so you have a known-good reference:
   ```bash
   flutter pub get
   flutter analyze --fatal-infos
   flutter test --coverage
   ```
   Record the test count and coverage % — you must match or beat these at the end.
3. Install Melos globally (used locally; CI installs its own copy):
   ```bash
   dart pub global activate melos
   ```
4. Take an inventory snapshot (used for verification later):
   ```bash
   git ls-files > .claude/monorepo_migration/_inventory_before.txt
   ```

### Current-state inventory (what moves where)

| Current path | Destination | Notes |
|---|---|---|
| `lib/**` (all except firebase) | `packages/agenix/lib/**` | core |
| `lib/src/memory/data_sources/_firebase.dart` | `packages/agenix_firebase/lib/src/_firebase.dart` | move |
| `test/**` (all except firebase) | `packages/agenix/test/**` | core |
| `test/memory/firebase_store_test.dart` | `packages/agenix_firebase/test/` | move |
| `test/memory/datastore_contract.dart` | **shared** — see Phase 5 | duplicated or exported |
| `example/**` | `packages/agenix_firebase/example/**` | it's a Firebase app |
| `pubspec.yaml` (root) | split into per-package pubspecs + root melos pubspec | |
| `.github/workflows/ci.yml` | rewritten for Melos | Phase 6 |
| `.github/workflows/publish.yml` | rewritten, per-package tags | Phase 6 |
| `analysis_options.yaml`, `codecov.yml`, `tool/` | root + per-package | Phase 6/7 |
| `README.md`, `CHANGELOG.md` | split per package + root | Phase 8 |

### Files that reference Firebase (the full coupling surface)
- `lib/src/memory/data/data_store.dart` — imports `_firebase.dart`, factory `firestoreDataStore()`
- `lib/src/memory/data_sources/_firebase.dart` — the implementation
- `test/memory/firebase_store_test.dart`
- `test/coverage_helper_test.dart` — imports `_firebase.dart`
- `example/lib/{main.dart, firebase_options.dart, services/firebase_service.dart}`
- root `pubspec.yaml` — the 4 firebase deps + 2 firebase dev-deps (`fake_cloud_firestore`, `firebase_auth_mocks`) + `false_secrets`

> Note: `grep -i firebase` also matches harmless doc comments in
> `tool_response.dart`, `conversation.dart`, `_in_memory.dart`, and `data_store.dart`.
> Those are comments mentioning Firebase as an example — leave the code, but
> update wording where it implies Firebase ships in core.

---

## 2. Phase 1 — Scaffold the monorepo skeleton

> No code moves yet. We build the empty structure and wire Melos.

1. Create directories:
   ```bash
   mkdir -p packages/agenix packages/agenix_firebase
   ```
2. Create the **root workspace pubspec** at repo root. This replaces the current
   root `pubspec.yaml` (which becomes the core package's pubspec — moved in Phase 3).
   Use the Dart **pub workspaces** feature (SDK >= 3.6) together with Melos 6+:

   `pubspec.yaml` (root):
   ```yaml
   name: agenix_workspace
   publish_to: none
   environment:
     sdk: ^3.7.2
   workspace:
     - packages/agenix
     - packages/agenix_firebase
   dev_dependencies:
     melos: ^6.3.0
   ```

3. Create `melos.yaml` at repo root:
   ```yaml
   name: agenix

   packages:
     - packages/**

   command:
     bootstrap:
       # Use pub workspaces resolution
       runPubGetInParallel: true
     version:
       # Per-package independent versioning; we tag manually in CI
       updateGitTagRefs: true

   scripts:
     analyze:
       run: melos exec -- flutter analyze --fatal-infos
       description: Analyze all packages.

     format-check:
       run: melos exec -- dart format --output=none --set-exit-if-changed .
       description: Fail if any package is unformatted.

     test:
       run: melos exec --dir-exists=test -- flutter test
       description: Run tests in every package that has a test/ dir.

     test:coverage:
       run: melos exec --dir-exists=test -- flutter test --coverage
       description: Run tests with coverage in every package.
   ```

   > **Decision point:** `pub` workspaces (SDK 3.6+) handle dependency resolution,
   > and Melos 6+ defers to them. If you prefer Melos to manage resolution itself
   > (older style with `melos bootstrap` doing path overrides), drop the
   > `workspace:` block from root pubspec and add `resolution: workspace` is NOT
   > needed. **Recommended: use pub workspaces** (less magic, future-proof). The
   > rest of this plan assumes pub workspaces. Each member pubspec must then
   > include `resolution: workspace`.

4. Verification gate:
   ```bash
   dart pub get   # must resolve the (currently empty) workspace without error
   ```
   It's fine that there are no packages with code yet; pub should still resolve.

---

## 3. Phase 2 — Move the core package (`agenix`)

1. Move all library + test + support files into `packages/agenix/`, **except** the
   Firebase pieces and the example app:
   ```bash
   git mv lib            packages/agenix/lib
   git mv test           packages/agenix/test
   git mv analysis_options.yaml packages/agenix/analysis_options.yaml
   git mv tool           packages/agenix/tool
   git mv CHANGELOG.md   packages/agenix/CHANGELOG.md
   git mv LICENSE        packages/agenix/LICENSE   # pub requires LICENSE per package
   ```
   > Keep a copy of `LICENSE` at the repo root too (`cp packages/agenix/LICENSE LICENSE`)
   > and in `agenix_firebase` (Phase 4). Each published package needs its own.

2. Move the **old root pubspec** into the core package and edit it:
   - The current root `pubspec.yaml` was moved to root-workspace in Phase 1, so
     write a fresh `packages/agenix/pubspec.yaml`:
   ```yaml
   name: agenix
   description: "Build smart AI agents in Flutter with memory, tools, and LLMs like Gemini. Fast, pluggable, and developer-friendly."
   version: 4.0.0           # MAJOR bump: firebase removed (breaking)
   homepage: https://github.com/ahmadexe/agenix
   repository: https://github.com/ahmadexe/agenix

   resolution: workspace

   environment:
     sdk: ^3.7.2
     flutter: ">=1.17.0"

   keywords:
     - flutter
     - ai
     - prompt
     - gemini
     - tools
     - llm
     - agentic

   dependencies:
     flutter:
       sdk: flutter
     google_generative_ai: ^0.4.7
     uuid: ^4.5.1

   dev_dependencies:
     flutter_test:
       sdk: flutter
     flutter_lints: ">=5.0.0 <7.0.0"
     mocktail: ^1.0.4

   flutter:
   ```
   > Removed: `firebase_core`, `firebase_auth`, `cloud_firestore`,
   > `firebase_storage`, `fake_cloud_firestore`, `firebase_auth_mocks`, and the
   > `false_secrets:` block (no firebase example here anymore).

3. **Remove Firebase from the core source.** Edit
   `packages/agenix/lib/src/memory/data/data_store.dart`:
   - Delete the import: `import 'package:agenix/src/memory/data_sources/_firebase.dart';`
   - Delete the static factory `firestoreDataStore(...)` entirely.
   - Keep `inMemory()` and the `import .../_in_memory.dart`.
   - Update the doc comment so it no longer implies Firebase ships by default;
     point users to `agenix_firebase`.

4. **Move** the Firebase implementation out of core (it goes to the new package in
   Phase 4 — stage it now):
   ```bash
   git mv packages/agenix/lib/src/memory/data_sources/_firebase.dart \
          packages/agenix_firebase/_firebase.dart.staged
   ```
   (Temporary name; finalized in Phase 4.)

5. Fix the core **coverage helper** — edit
   `packages/agenix/test/coverage_helper_test.dart` and delete the line:
   `import 'package:agenix/src/memory/data_sources/_firebase.dart';`

6. Move the Firebase test out of core (staged for Phase 5):
   ```bash
   git mv packages/agenix/test/memory/firebase_store_test.dart \
          packages/agenix_firebase/firebase_store_test.dart.staged
   ```

7. The shared contract `datastore_contract.dart`: see Phase 5. For now leave it in
   `packages/agenix/test/memory/datastore_contract.dart`.

8. Verification gate (core must be self-contained now):
   ```bash
   dart pub get
   cd packages/agenix && flutter analyze --fatal-infos && flutter test && cd ../..
   ```
   - Expect: **no reference to Firebase remains in core**. Confirm:
     ```bash
     grep -rinE "firebase|firestore|FirebaseDataStore" packages/agenix/lib packages/agenix/test \
       | grep -viE "// |/\*|example|see " || echo "CLEAN"
     ```
     Only doc-comment mentions (if any) should remain; no `import` / type usage.
   - `in_memory_store_test.dart` and `datastore_contract.dart` must still pass.

---

## 4. Phase 3 — Build the `agenix_firebase` package

1. Create the library layout:
   ```bash
   mkdir -p packages/agenix_firebase/lib/src packages/agenix_firebase/test
   git mv packages/agenix_firebase/_firebase.dart.staged \
          packages/agenix_firebase/lib/src/firebase_data_store.dart
   ```
   > Rename from the old underscore-internal name to a normal file, because in this
   > package `FirebaseDataStore` is now **public API**, not an internal detail.

2. Update imports inside `firebase_data_store.dart`: it currently imports core
   types via `package:agenix/src/...`. Change those to the **public** barrel:
   ```dart
   import 'package:agenix/agenix.dart';   // AgentMessage, Conversation, DataStore, AgenixException
   import 'package:cloud_firestore/cloud_firestore.dart';
   import 'package:firebase_auth/firebase_auth.dart';
   import 'package:firebase_storage/firebase_storage.dart';
   import 'package:uuid/uuid.dart';
   ```
   > All the types it needs (`DataStore`, `AgentMessage`, `Conversation`,
   > `NotAuthenticatedException`, `DataStoreException`, `AgenixException`) are
   > already exported from `lib/agenix.dart`. Verify after editing.

3. Create the barrel `packages/agenix_firebase/lib/agenix_firebase.dart`:
   ```dart
   /// Firebase data store for Agenix.
   library;

   export 'src/firebase_data_store.dart' show FirebaseDataStore;
   ```

4. Create `packages/agenix_firebase/pubspec.yaml`:
   ```yaml
   name: agenix_firebase
   description: "Firebase (Firestore + Storage + Auth) data store backend for the agenix AI agent framework."
   version: 1.0.0
   homepage: https://github.com/ahmadexe/agenix
   repository: https://github.com/ahmadexe/agenix/tree/main/packages/agenix_firebase

   resolution: workspace

   environment:
     sdk: ^3.7.2
     flutter: ">=1.17.0"

   keywords:
     - flutter
     - ai
     - agenix
     - firebase
     - firestore

   dependencies:
     flutter:
       sdk: flutter
     agenix: ^4.0.0          # path resolved via workspace locally; ^4.0.0 on pub.dev
     firebase_core: ^4.0.0
     firebase_auth: ^6.0.0
     cloud_firestore: ^6.0.0
     firebase_storage: ^13.0.0
     uuid: ^4.5.1

   dev_dependencies:
     flutter_test:
       sdk: flutter
     flutter_lints: ">=5.0.0 <7.0.0"
     mocktail: ^1.0.4
     fake_cloud_firestore: ^4.0.0
     firebase_auth_mocks: ^0.15.2

   false_secrets:
     - example/**/firebase_options.dart
     - example/**/google-services.json
     - example/**/GoogleService-Info.plist

   flutter:
   ```
   > **Important — the `agenix: ^4.0.0` constraint:** While developing in the
   > monorepo, pub workspaces resolve `agenix` from the local path automatically.
   > When `agenix_firebase` is published to pub.dev, the `^4.0.0` constraint is what
   > consumers get. Do **not** use a `path:` dependency in the committed pubspec —
   > pub.dev rejects path deps on publish. The workspace handles local linking.

5. Copy license + per-package analysis options:
   ```bash
   cp packages/agenix/LICENSE packages/agenix_firebase/LICENSE
   cp packages/agenix/analysis_options.yaml packages/agenix_firebase/analysis_options.yaml
   ```

6. Verification gate:
   ```bash
   dart pub get
   cd packages/agenix_firebase && flutter analyze --fatal-infos && cd ../..
   ```
   (Tests come in Phase 5.)

---

## 5. Phase 4 — Tests: split the shared contract

The reusable `datastore_contract.dart` is needed by **both** the core
(`in_memory_store_test.dart`) and `agenix_firebase` (`firebase_store_test.dart`).
A test helper in one package's `test/` dir is not importable from another package.

**Chosen approach (recommended): duplicate the contract.** It is ~60 lines, has no
dependencies beyond `agenix` + `flutter_test`, and changes rarely. Duplication keeps
each package self-contained and publishable with zero extra published packages.

> Alternative (rejected for now): create a third *unpublished* package
> `agenix_test_support` exporting the contract. More moving parts; only worth it if
> the contract grows large or a third backend appears. Note it in the architecture
> doc as a future option.

1. Core already has `packages/agenix/test/memory/datastore_contract.dart`. Leave it.
2. Copy it into the firebase package:
   ```bash
   mkdir -p packages/agenix_firebase/test
   cp packages/agenix/test/memory/datastore_contract.dart \
      packages/agenix_firebase/test/datastore_contract.dart
   ```
3. Finalize the firebase test:
   ```bash
   git mv packages/agenix_firebase/firebase_store_test.dart.staged \
          packages/agenix_firebase/test/firebase_store_test.dart
   ```
4. Edit `packages/agenix_firebase/test/firebase_store_test.dart`:
   - Change `import 'package:agenix/src/memory/data_sources/_firebase.dart';`
     → `import 'package:agenix_firebase/agenix_firebase.dart';`
   - Keep `import 'datastore_contract.dart';` (now local to this package).
   - Everything else (`FakeFirebaseFirestore`, `MockFirebaseAuth`, the mock
     storage) stays the same.
5. Add a coverage helper for the firebase package so coverage counts the file even
   if a path is untested — `packages/agenix_firebase/test/coverage_helper_test.dart`:
   ```dart
   // ignore_for_file: unused_import
   import 'package:agenix_firebase/agenix_firebase.dart';
   import 'package:agenix_firebase/src/firebase_data_store.dart';
   void main() {}
   ```
6. Verification gate (both packages green):
   ```bash
   dart pub get
   dart pub global run melos run analyze
   dart pub global run melos run test
   ```
   - Core test count must equal the baseline **minus** the firebase test group.
   - Firebase package must run the full DataStore contract + firebase specifics.
   - Combined, total tests >= baseline.

---

## 6. Phase 5 — Move the example app

The example is a Firebase app (`firebase_service.dart`, `firebase_options.dart`,
Google services files). It belongs with `agenix_firebase`.

1. Move it:
   ```bash
   git mv example packages/agenix_firebase/example
   ```
2. Edit `packages/agenix_firebase/example/pubspec.yaml`:
   - It currently depends on `agenix` (likely via path `../`). Point it at both:
     ```yaml
     dependencies:
       agenix: ^4.0.0
       agenix_firebase: ^1.0.0
     ```
     (Workspace resolves these locally. If the example is **not** listed as a
     workspace member, add it to root `pubspec.yaml` `workspace:` list and add
     `resolution: workspace` + `publish_to: none` to the example pubspec.)
   - Add the example as a workspace member in root `pubspec.yaml`:
     ```yaml
     workspace:
       - packages/agenix
       - packages/agenix_firebase
       - packages/agenix_firebase/example
     ```
3. Update example Dart code: any `DataStore.firestoreDataStore(...)` call becomes
   `FirebaseDataStore(...)` with `import 'package:agenix_firebase/agenix_firebase.dart';`.
   Search and fix:
   ```bash
   grep -rn "firestoreDataStore" packages/agenix_firebase/example/lib
   ```
4. **Core needs its own example** (pub.dev scores packages higher with an example,
   and the pana gate requires it — see Phase 7). Create a minimal, Firebase-free
   example for core at `packages/agenix/example/`:
   - `pubspec.yaml`: depends only on `agenix` (workspace), `publish_to: none`,
     `resolution: workspace`, add to root `workspace:` list.
   - `lib/main.dart` (or `example/main.dart`): a tiny snippet building an `Agent`
     with `DataStore.inMemory()` and a fake/echo `LLM`, or just a `README.md` with a
     code sample if a full app is overkill. A `example/README.md` with a fenced Dart
     sample is sufficient for pana's "has example" check.
5. Verification gate:
   ```bash
   dart pub get
   dart pub global run melos run analyze
   ```

---

## 7. Phase 6 — CI/CD migration

The current `.github/workflows/ci.yml` and `publish.yml` assume a single package at
repo root. Rewrite for the monorepo.

### 7.1 CI workflow (`.github/workflows/ci.yml`)

Replace the single `flutter pub get` / `flutter test` with Melos-driven, all-package
runs. Keep the existing quality gates (format, analyze `--fatal-infos`, coverage
floor, Codecov).

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v7

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.44.3
          cache: true

      - name: Activate Melos
        run: dart pub global activate melos

      - name: Bootstrap workspace
        run: dart pub get   # pub workspaces resolves all members

      - name: Verify formatting (all packages)
        run: dart pub global run melos run format-check

      - name: Analyze (all packages)
        run: dart pub global run melos run analyze

      - name: Run tests with coverage (all packages)
        run: dart pub global run melos run test:coverage

      - name: Install lcov
        run: sudo apt-get update && sudo apt-get install -y lcov

      - name: Merge + enforce coverage floor
        run: |
          # Each package writes coverage/lcov.info under its own dir.
          FILES=$(find packages -path '*/coverage/lcov.info')
          echo "Coverage files: $FILES"
          ARGS=""
          for f in $FILES; do ARGS="$ARGS -a $f"; done
          lcov $ARGS -o merged.lcov.info
          PCT=$(lcov --summary merged.lcov.info 2>&1 \
                | grep -iE 'lines' | grep -oE '[0-9]+\.[0-9]+' | head -1)
          if [ -z "$PCT" ]; then
            echo "::warning::Could not parse coverage — skipping floor check"; exit 0; fi
          echo "Line coverage: ${PCT}% (min 50%)"
          awk -v p="$PCT" -v m="50" 'BEGIN { exit (p+0 >= m+0) ? 0 : 1 }'

      - name: Upload coverage artifact
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: coverage
          path: merged.lcov.info
          if-no-files-found: warn

      - name: Upload coverage to Codecov
        if: always()
        uses: codecov/codecov-action@v7
        with:
          files: merged.lcov.info
          fail_ci_if_error: false
        env:
          CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

> **Optional hardening:** Add a matrix job so each package is analyzed/tested in
> isolation too (catches a package accidentally relying on another's transitive
> deps). Matrix over `[agenix, agenix_firebase]`, `cd packages/${{matrix.pkg}}`,
> `flutter pub get && flutter analyze && flutter test`. Recommended once both
> packages are stable.

### 7.2 Publish workflow (`.github/workflows/publish.yml`)

Single-package tag scheme (`vX.Y.Z`) no longer disambiguates which package to
publish. Switch to **per-package tags**:

- `agenix-v4.0.0` → publishes `packages/agenix`
- `agenix_firebase-v1.0.0` → publishes `packages/agenix_firebase`

```yaml
name: Publish to pub.dev

on:
  push:
    tags:
      - 'agenix-v[0-9]+.[0-9]+.[0-9]+'
      - 'agenix_firebase-v[0-9]+.[0-9]+.[0-9]+'

jobs:
  guard:
    uses: ./.github/workflows/ci.yml

  publish:
    needs: guard
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # pub.dev OIDC publishing
    steps:
      - uses: actions/checkout@v7

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.44.3
          cache: true

      - name: Resolve package + version from tag
        id: pkg
        run: |
          TAG="${GITHUB_REF_NAME}"               # e.g. agenix_firebase-v1.0.0
          NAME="${TAG%-v*}"                        # agenix_firebase
          VER="${TAG##*-v}"                        # 1.0.0
          echo "name=$NAME" >> "$GITHUB_OUTPUT"
          echo "version=$VER" >> "$GITHUB_OUTPUT"
          echo "dir=packages/$NAME" >> "$GITHUB_OUTPUT"

      - name: Install deps
        run: dart pub get

      - name: Verify tag matches pubspec version
        working-directory: ${{ steps.pkg.outputs.dir }}
        run: |
          PUB=$(grep '^version:' pubspec.yaml | awk '{print $2}')
          echo "tag=${{ steps.pkg.outputs.version }} pubspec=$PUB"
          test "${{ steps.pkg.outputs.version }}" = "$PUB" \
            || { echo "::error::tag != pubspec version"; exit 1; }

      - name: Publish dry-run
        working-directory: ${{ steps.pkg.outputs.dir }}
        run: dart pub publish --dry-run

      - name: Enforce pana score (min 150)
        working-directory: ${{ steps.pkg.outputs.dir }}
        run: |
          dart pub global activate pana
          SCORE=$(dart pub global run pana --no-warning . 2>/dev/null \
                  | grep -oE 'Package scoring: [0-9]+' | grep -oE '[0-9]+')
          echo "Pana score: ${SCORE}/160"
          if [ -z "$SCORE" ]; then echo "::error::no pana score"; exit 1; fi
          if [ "$SCORE" -lt 150 ]; then echo "::error::pana $SCORE < 150"; exit 1; fi

      - name: Publish
        working-directory: ${{ steps.pkg.outputs.dir }}
        run: dart pub publish --force
```

> **pub.dev publishing prerequisite:** Both `agenix` and `agenix_firebase` must be
> claimed on pub.dev and have **automated publishing from GitHub Actions** enabled
> (pub.dev → package admin → "Automated publishing" → tag pattern). Configure the
> tag patterns above for each package. `agenix_firebase` is a new package — its
> first publish may need a one-time manual `dart pub publish` from a maintainer to
> create it, after which OIDC tag publishing works.

### 7.3 Dependabot (`.github/dependabot.yml`)

`directory: "/"` no longer covers the package pubspecs. Add one `pub` entry per
package directory:

```yaml
version: 2
updates:
  - package-ecosystem: "pub"
    directory: "/packages/agenix"
    schedule: { interval: "weekly" }
    open-pull-requests-limit: 5
    labels: ["dependencies"]
    groups:
      pub-minor-patch:
        update-types: ["minor", "patch"]
  - package-ecosystem: "pub"
    directory: "/packages/agenix_firebase"
    schedule: { interval: "weekly" }
    open-pull-requests-limit: 5
    labels: ["dependencies"]
    groups:
      pub-minor-patch:
        update-types: ["minor", "patch"]
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule: { interval: "weekly" }
    labels: ["ci"]
```

### 7.4 CODEOWNERS / templates
- `.github/CODEOWNERS`, issue templates, PR template: no path changes required, but
  if CODEOWNERS used `/lib/` paths, update to `/packages/**`.

### 7.5 Verification gate
- Push the branch; confirm the rewritten `ci.yml` runs green on the PR.
- Do **not** create release tags yet (Phase 9).

---

## 8. Phase 7 — Repo-root config & hygiene

1. **Root `analysis_options.yaml`:** Keep per-package analysis options (already
   copied). Optionally add a root one that members `include:` to avoid drift. Melos
   `analyze` runs each package with its own options, so per-package is sufficient.
2. **`codecov.yml`:** Stays at root (Codecov reads from repo root). Keep targets.
   Coverage is now the merged report. Optionally add `flags:` per package for
   per-package coverage visibility:
   ```yaml
   flags:
     agenix:
       paths: [packages/agenix/]
     agenix_firebase:
       paths: [packages/agenix_firebase/]
   ```
3. **`tool/check_coverage.sh`:** Moved into core in Phase 2. If it hard-codes
   `coverage/lcov.info` at repo root, generalize it or point it at the merged file.
   Update or leave per-package as appropriate.
4. **`.gitignore`:** Root one already ignores `/pubspec.lock`, `.dart_tool/`,
   `build/`, `coverage/`. Confirm these patterns are not anchored so they match
   nested `packages/*/`. Change `/pubspec.lock` → `pubspec.lock` and `coverage/` is
   already non-anchored. Add `pubspec_overrides.yaml` (Melos may generate these).
5. **`.metadata`:** Flutter app metadata — only meaningful for the example app(s);
   leave at example level, remove from repo root if it lingers.
6. Verification gate: `dart pub get && melos run analyze && melos run test` clean.

---

## 9. Phase 8 — Documentation

1. **Root `README.md`:** Convert into a monorepo landing page:
   - What agenix is (1 paragraph).
   - Table of packages with pub.dev badges:
     | Package | pub | Purpose |
     |---|---|---|
     | `agenix` | badge | Core: agents, tools, LLM, in-memory store |
     | `agenix_firebase` | badge | Firebase (Firestore/Storage/Auth) data store |
   - "Choosing a data store" section.
   - Link to `docs/architecture/package_architecture.md`.
   - Move the deep usage docs into `packages/agenix/README.md`.
2. **`packages/agenix/README.md`:** The current big README, edited:
   - Remove the Firebase setup sections (or move to firebase package README).
   - Default data store examples use `DataStore.inMemory()`.
   - Add a "Need persistence? See `agenix_firebase`" pointer.
3. **`packages/agenix_firebase/README.md`:** New. Firebase setup, `FirebaseDataStore`
   usage, the auth requirement (`NotAuthenticatedException`), Firestore schema
   (`chats/{uid}/conversations/{id}/messages`), Storage image handling.
4. **CHANGELOGs:**
   - `packages/agenix/CHANGELOG.md`: add `## 4.0.0` — **BREAKING**: removed
     `DataStore.firestoreDataStore()` and Firebase deps; moved to `agenix_firebase`.
     Include a migration snippet.
   - `packages/agenix_firebase/CHANGELOG.md`: new, `## 1.0.0` — initial release,
     extracted from `agenix` core.
5. **Migration guide for consumers** (put in core CHANGELOG + firebase README):
   ```diff
   # pubspec.yaml
     dependencies:
       agenix: ^4.0.0
   +   agenix_firebase: ^1.0.0

   # dart
   - import 'package:agenix/agenix.dart';
   + import 'package:agenix/agenix.dart';
   + import 'package:agenix_firebase/agenix_firebase.dart';

   - final store = DataStore.firestoreDataStore();
   + final store = FirebaseDataStore();
   ```
6. **CONTRIBUTING.md:** Update build/test instructions to Melos commands.

---

## 10. Phase 9 — Release

Order matters: `agenix_firebase` depends on `agenix ^4.0.0`, so core must be on
pub.dev first.

1. Final full verification:
   ```bash
   dart pub get
   melos run format-check
   melos run analyze
   melos run test:coverage
   (cd packages/agenix && dart pub publish --dry-run)
   (cd packages/agenix_firebase && dart pub publish --dry-run)
   ```
   Both dry-runs must pass with no warnings that drop pana below 150.
2. Merge the migration PR to `main` (CI green).
3. Tag + publish **core first**:
   ```bash
   git tag agenix-v4.0.0 && git push origin agenix-v4.0.0
   ```
   Wait for it to appear on pub.dev.
4. Tag + publish **firebase**:
   ```bash
   git tag agenix_firebase-v1.0.0 && git push origin agenix_firebase-v1.0.0
   ```
5. Smoke-test from a throwaway app:
   ```bash
   flutter create /tmp/smoke && cd /tmp/smoke
   flutter pub add agenix
   # confirm: NO firebase_* in pubspec.lock
   grep -i firebase pubspec.lock && echo "LEAK" || echo "CLEAN — firebase not pulled"
   flutter pub add agenix_firebase
   # now firebase_* should appear
   ```
   The **"CLEAN"** result is the entire point of this migration — verify it.

---

## 11. Final acceptance checklist

- [ ] `packages/agenix` has **zero** Firebase deps in `pubspec.yaml`.
- [ ] `grep -ri firebase packages/agenix/lib` returns only doc-comment mentions.
- [ ] A fresh app adding only `agenix` has no `firebase_*` in its `pubspec.lock`.
- [ ] `agenix_firebase` provides `FirebaseDataStore` and depends on `agenix`.
- [ ] `melos run analyze` clean across all packages (`--fatal-infos`).
- [ ] `melos run test` green; combined test count >= pre-migration baseline.
- [ ] Merged coverage >= 50% floor; Codecov upload works.
- [ ] CI workflow runs Melos and passes on PR.
- [ ] Publish workflow uses per-package tags (`agenix-vX`, `agenix_firebase-vX`).
- [ ] Both packages pass `dart pub publish --dry-run` and pana >= 150.
- [ ] READMEs + CHANGELOGs updated; consumer migration guide present.
- [ ] `docs/architecture/package_architecture.md` reflects the final structure.

---

## 12. Rollback

The migration is a single PR. If something is wrong post-merge but pre-publish:
- Revert the PR; the repo returns to the single-package layout.
Once **published**, pub.dev versions are immutable:
- You cannot un-publish `agenix 4.0.0`. Fix forward with `5.0.1`.
- Consumers on `agenix ^3.x` are unaffected until they opt into `^4.0.0`.

---

## Appendix A — Decisions log (for the executor)

| Decision | Choice | Rationale |
|---|---|---|
| Monorepo vs optional deps | Monorepo | pub has no optional deps; this is the idiomatic FlutterFire-style pattern |
| Resolution mechanism | pub workspaces + Melos 6 | Native, future-proof; Melos for scripts/versioning |
| Core version | 4.0.0 | Removing `firestoreDataStore()` is breaking |
| Firebase version | 1.0.0 | New package; independent versioning |
| Shared test contract | Duplicate the file | Tiny, dependency-free; avoids a 3rd published pkg |
| Release tags | Per-package `name-vX.Y.Z` | One tag scheme can't target two packages |
| Example app | Firebase example → firebase pkg; new tiny core example | pana wants an example per package |

## Appendix B — Future packages (apply the same recipe)

To add `agenix_supabase` / `agenix_hive` later:
1. `mkdir packages/agenix_<backend>`, add to root `workspace:`.
2. Implement `class <Backend>DataStore extends DataStore` against
   `package:agenix/agenix.dart`.
3. Barrel `agenix_<backend>.dart` exporting the public store.
4. Copy `datastore_contract.dart`, write `<backend>_store_test.dart`.
5. Add Dependabot entry + publish tag pattern.
6. Version 1.0.0, depend on `agenix: ^4.0.0`.
No core changes required — that is the payoff of the `DataStore` abstraction.
