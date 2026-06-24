# 08 — Coverage & Quality Gates

## Summary
Tests only protect the package if they're measured and enforced. This doc defines how to
measure coverage, what threshold to hold, which files to exclude, and how the local
quality gate (analyze + format + test + coverage) is composed — the same gate CI runs (see
`../ci-cd/`).

## Scope & priority
**High.** Without a gate, coverage silently rots. This is what turns "we have tests" into
"we keep having tests."

## Files to create / change
- `coverage/` — generated, git-ignored (add to `.gitignore`).
- `test/coverage_helper_test.dart` — optional, forces all `lib/` files to be counted.
- A small script or documented commands (used verbatim by CI in `../ci-cd/`).

## Measuring coverage
```bash
flutter test --coverage          # writes coverage/lcov.info
```
`lcov.info` only counts files that were **imported** by some test. Files never imported show
0% — or worse, are omitted entirely, inflating the percentage. Two ways to handle this:

### Option A (recommended): a coverage helper
Create a test that imports every library so they're all instrumented:
```dart
// test/coverage_helper_test.dart
// Forces coverage instrumentation of every source file, even those not yet
// directly tested. Keep imports in sync with lib/ (or generate it — see below).
// ignore_for_file: unused_import
import 'package:agenix/agenix.dart';
import 'package:agenix/src/agent/agent.dart';
import 'package:agenix/src/llm/_gemini.dart';
import 'package:agenix/src/tools/_parser.dart';
import 'package:agenix/src/tools/_tool_runner.dart';
import 'package:agenix/src/tools/_param_validator.dart';
import 'package:agenix/src/tools/tool_registry.dart';
import 'package:agenix/src/memory/data_sources/_in_memory.dart';
import 'package:agenix/src/memory/data_sources/_firebase.dart';
import 'package:agenix/src/static/_pkg_constants.dart';

void main() {}
```
This guarantees the denominator is the whole package, so the percentage is honest.

### Option B: generate the helper
There are tooling options (e.g. `full_coverage`) that generate the helper above
automatically. Either is fine; Option A is zero-dependency.

## Thresholds
Hold a **line-coverage floor** and ratchet it up over time. Recommended phased targets:

| Phase | Target | Rationale |
|-------|--------|-----------|
| Initial (docs 03–05 done) | ≥ 60% | Pure units land first; cheap, high value. |
| After doc 06 | ≥ 75% | Stores covered by the shared contract. |
| After doc 07 | ≥ 85% | The agent loop + chaining dominate the line count. |
| Steady state | ≥ 85% line, no untested public type | The enforced CI floor. |

Exclude from the denominator (legitimately hard/low-value to unit test):
- `_firebase.dart` **only if** the Firebase mocks couldn't resolve (doc 06 fallback);
  otherwise include it.
- `_gemini.dart` network branches that require a live API (the LLM-coverage backlog adds
  real fakes/contract tests — see `../llm-coverage/`); cover what's coverable (the
  `_extractText` empty-response throw, `modelId`) and exclude the raw network call lines.

### Filtering lcov
Use `lcov`'s `--remove` to drop excluded files before computing the percentage:
```bash
lcov --remove coverage/lcov.info \
  '*/_gemini.dart' \
  -o coverage/lcov.cleaned.info       # only if you justified the exclusion
```
> Prefer **including** files and writing the tests over excluding. Every exclusion needs a
> one-line justification in this doc when you add it.

## Enforcing the floor locally
A tiny check the CI reuses (bash + lcov summary parsing):
```bash
#!/usr/bin/env bash
# tool/check_coverage.sh
set -euo pipefail
MIN=${1:-85}
flutter test --coverage
PCT=$(lcov --summary coverage/lcov.info 2>/dev/null \
      | grep -oE 'lines.*: [0-9.]+%' | grep -oE '[0-9.]+' | head -1)
echo "Line coverage: ${PCT}% (min ${MIN}%)"
awk -v p="$PCT" -v m="$MIN" 'BEGIN { exit (p+0 >= m+0) ? 0 : 1 }'
```
> `lcov` is preinstalled on the GitHub `ubuntu-latest` runner; locally install via
> `brew install lcov`. If you'd rather not depend on `lcov`, a pure-Dart alternative is the
> `test_cov_console` / `coverde` package to print and threshold the percentage — pick one and
> document it.

## The full local gate
The command sequence every contributor (and CI) runs before merge:
```bash
dart format --output=none --set-exit-if-changed .   # formatting
flutter analyze                                      # zero issues
flutter test --coverage                             # all green
bash tool/check_coverage.sh 85                       # coverage floor
```

## Step-by-step implementation
1. Add `coverage/` to `.gitignore`.
2. Add `test/coverage_helper_test.dart` (Option A) importing every `lib/` file.
3. Add `tool/check_coverage.sh` (chmod +x) with the floor check.
4. Run the full gate locally; fix any gaps until the phase-appropriate floor passes.
5. Record the current enforced floor here and wire the exact same commands into
   `../ci-cd/01-github-actions-ci-workflow.md`.
6. Each time you exclude a file from coverage, add a justification line to this doc.

## Acceptance criteria
- `flutter test --coverage` produces an honest `lcov.info` (all `lib/` files counted via the
  helper).
- `tool/check_coverage.sh` exits non-zero below the floor, zero at/above it.
- The full local gate (format + analyze + test + coverage) passes.
- The enforced floor is documented here and matched by the CI job.

## Related docs
- [01 — test infrastructure](01-test-infrastructure-and-dependencies.md)
- [07 — agent integration tests](07-integration-tests-agent-loop-and-chaining.md) (where most coverage comes from)
- [../ci-cd/01-github-actions-ci-workflow.md](../ci-cd/01-github-actions-ci-workflow.md) (runs this gate)
- [../ci-cd/02-coverage-reporting.md](../ci-cd/02-coverage-reporting.md) (uploading/visualizing coverage)
