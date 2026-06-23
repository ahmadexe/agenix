# 01 — GitHub Actions CI Workflow (PR Gate)

## Summary
There is no CI. Nothing runs `dart format`, `flutter analyze`, or `flutter test` when code is
pushed or a PR is opened, so regressions and lint/format drift can land on `main` unnoticed.
This doc creates the core CI workflow: a fast, offline gate that every push and PR must pass.

## Severity & impact
**Critical.** This workflow is the foundation the entire engineering process rests on — it's
what makes the test suite (`../tests/`) and every future change actually *enforced* rather
than aspirational.

## Files to create
- `.github/workflows/ci.yml`
- `tool/check_coverage.sh` (if not already created in `../tests/08-coverage-and-quality-gates.md`)

## Current state
- `.github/` contains only `pull_request_template.md` and unrelated `modernize/` files.
- No `workflows/` directory.

## Target design

A single `ci.yml` with one job (optionally a matrix). It must:
1. Check out the repo.
2. Install a pinned Flutter version (which includes the matching Dart).
3. `flutter pub get`.
4. Verify formatting (`dart format --set-exit-if-changed`).
5. `flutter analyze` (treat infos/warnings as failures via `--fatal-infos`).
6. `flutter test --coverage`.
7. Enforce the coverage floor.

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Cancel superseded runs on the same ref to save minutes.
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.29.0   # pin; must bundle Dart >= 3.7.2
          cache: true               # cache the Flutter SDK + pub

      - name: Install dependencies
        run: flutter pub get

      - name: Verify formatting
        run: dart format --output=none --set-exit-if-changed .

      - name: Analyze
        run: flutter analyze --fatal-infos

      - name: Run tests with coverage
        run: flutter test --coverage

      - name: Install lcov
        run: sudo apt-get update && sudo apt-get install -y lcov

      - name: Enforce coverage floor
        run: bash tool/check_coverage.sh 85   # match the floor in ../tests/08

      - name: Upload coverage artifact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/lcov.info
          if-no-files-found: warn
```

### Notes & rationale
- **Flutter, not Dart-only:** the package depends on the Flutter SDK; `flutter_test` and the
  `flutter/services.dart` asset stubbing in tests require it.
- **`--fatal-infos`:** the project keeps `flutter analyze` perfectly clean today; make CI
  enforce that so it stays clean. If a specific info is intentional, suppress it in code with a
  justified `// ignore:` rather than weakening the gate.
- **Formatting gate:** `dart format` is the canonical Dart formatter; failing on drift keeps
  diffs clean. Run `dart format .` locally before pushing.
- **Coverage floor:** reuses `tool/check_coverage.sh` from `../tests/08`. If that script isn't
  created yet, create it per that doc. The floor (85) must match.
- **Caching:** `subosito/flutter-action`'s `cache: true` caches the SDK and pub packages,
  cutting cold-start time substantially.
- **Concurrency:** cancels stale runs on force-push/rebase to save CI minutes.

### Optional: multi-version matrix
Once green, consider a matrix to catch SDK-specific breakage:
```yaml
    strategy:
      matrix:
        flutter-version: ['3.29.0', '3.x']   # pinned floor + latest stable
```
Keep the pinned floor matching the package's minimum supported SDK.

## Step-by-step implementation
1. Ensure `tool/check_coverage.sh` exists (from `../tests/08`); if not, create it there first.
2. Create `.github/workflows/ci.yml` with the YAML above.
3. Pin `flutter-version` to a stable release bundling Dart ≥ 3.7.2; verify locally that
   `flutter --version` reports a matching Dart.
4. Run the gate locally to confirm it passes before pushing:
   ```bash
   dart format --output=none --set-exit-if-changed .
   flutter analyze --fatal-infos
   flutter test --coverage
   bash tool/check_coverage.sh 85
   ```
5. Push to a branch, open a PR, confirm the workflow runs and all steps pass.
6. Make the `analyze-and-test` job a **required status check** on `main` (see doc 04).

## Acceptance criteria
- `ci.yml` runs on every push to `main` and every PR targeting `main`.
- It installs Flutter, runs `flutter pub get`, checks formatting, runs `flutter analyze
  --fatal-infos`, runs `flutter test --coverage`, and enforces the coverage floor.
- The job fails if any step fails (format drift, analyzer issue, test failure, or coverage
  below floor).
- Coverage `lcov.info` is uploaded as an artifact.
- Runs complete in a few minutes with caching.

## Related docs
- [02 — coverage reporting](02-coverage-reporting.md) (surface coverage on the PR)
- [03 — release and publish](03-release-and-publish.md) (a separate, tag-driven workflow)
- [04 — repo hygiene](04-repo-hygiene-and-automation.md) (make this a required check)
- [../tests/08-coverage-and-quality-gates.md](../tests/08-coverage-and-quality-gates.md) (the floor + script)
