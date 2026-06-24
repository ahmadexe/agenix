# Agenix — Test Suite Implementation Plan

This folder is a **work backlog** for building Agenix's automated test suite from scratch.
Today the entire suite is a single empty `test/agenix_test.dart` with `void main() {}`.
For a published package that markets itself as "production-grade and pluggable," zero test
coverage is the single largest blocker to industry adoption. Everything that was hardened
across `.claude/improvements/` (parser robustness, parameter validation, cycle detection,
parse-retry, the in-memory store, the typed exception model) is currently **unverified** —
any refactor can silently break the contract.

The good news: the hardening work already made the package testable. `DataStore.inMemory()`
exists, Firebase services are injectable, the `LLM` interface is a clean seam, and the
agent registry is scoped (`AgentScope`) so tests can be isolated. This backlog turns that
testability into actual tests.

Every document is written so that **an LLM (or a human) can implement the tests
end-to-end without re-deriving the analysis**. Each file follows the same structure:

1. **Summary** — what this layer of tests covers and why.
2. **Scope & priority** — how critical, and what it gates.
3. **Files under test / files to create** — exact paths.
4. **Current state** — what exists today.
5. **Test design** — the cases to write, with the seams to exploit.
6. **Step-by-step implementation** — ordered, concrete edits with example code.
7. **Acceptance criteria** — how to know it's done.
8. **Related docs** — cross-links.

> Code snippets reference the codebase as of this writing. Always re-read the source file
> before writing a test; treat signatures here as hints, not contracts.

---

## Guiding principles

- **No live LLM, no live Firebase.** Every test must run offline and deterministically via
  `flutter test`. Use the in-memory store and a scriptable fake LLM. The only place real
  Firebase types appear is in `_firebase.dart` tests, and there they are faked with
  `fake_cloud_firestore` / `firebase_auth_mocks`.
- **Test the public contract, not the private internals.** Prefer driving behavior through
  the public API (`Agent.create`, `agent.generateResponse`, `DataStore`, `LLM`,
  `PromptParser`, `validateParams`). Internal `part` classes (`_PromptBuilder`,
  `_MemoryManager`, `_AgentRegistry`) are exercised transitively through the public flow.
- **Isolation between tests.** The agent registry is global by default
  (`AgentScope.global`). Every agent-level test must use its **own** `AgentScope` instance
  (or call `scope.clear()` in `tearDown`) so test order never matters.
- **One behavior per `test()`.** Name tests as `does X when Y`. Group with `group()` per
  unit.
- **Determinism.** Never assert on wall-clock values; inject or tolerate time. Never assert
  on map/iteration order unless the code guarantees it.
- **Coverage is a gate, not a vanity metric.** See doc 08 for thresholds.

---

## How to work through this backlog

Do them roughly in order — infrastructure and fakes first, then pure-unit tests (fast, no
async surprises), then the integration tests that wire everything together.

| #  | Doc | Priority | Theme |
|----|-----|----------|-------|
| 01 | [test-infrastructure-and-dependencies.md](01-test-infrastructure-and-dependencies.md) | Critical | dev_dependencies, folder layout, how to run, coverage tooling |
| 02 | [fakes-and-fixtures.md](02-fakes-and-fixtures.md) | Critical | `FakeLLM`, spy tools, message fixtures, fake Firebase |
| 03 | [unit-tests-data-and-serialization.md](03-unit-tests-data-and-serialization.md) | High | `AgentMessage`, `Conversation`, `ToolResponse` round-trips, equality |
| 04 | [unit-tests-parser-and-validation.md](04-unit-tests-parser-and-validation.md) | High | `PromptParser`, `validateParams` |
| 05 | [unit-tests-tools-registry-scope.md](05-unit-tests-tools-registry-scope.md) | High | `ToolRegistry`, `ToolRunner`, `AgentScope`, `RegistrationPolicy` |
| 06 | [unit-tests-datastores.md](06-unit-tests-datastores.md) | High | `InMemoryDataStore`, `FirebaseDataStore` (faked) |
| 07 | [integration-tests-agent-loop-and-chaining.md](07-integration-tests-agent-loop-and-chaining.md) | Critical | `generateResponse` end-to-end, tool loop, chaining, failure modes |
| 08 | [coverage-and-quality-gates.md](08-coverage-and-quality-gates.md) | High | Coverage measurement, thresholds, what the CI gate enforces |

**Suggested sequencing:** 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08.

---

## Definition of done for the whole backlog

- `flutter test` runs green offline with **no Firebase init and no network**.
- Every public type in `lib/agenix.dart` has at least one test exercising its core contract.
- The full `Agent.generateResponse` flow is covered for: direct response, single tool,
  multi-step tool loop, reason-over-data, max-iteration fallback, parse-retry recovery,
  unparseable-after-retry error, and both `FailureMode` branches.
- Agent chaining is covered for: happy-path hand-off, cycle detection, depth-limit, and
  unknown-agent.
- Both `DataStore` implementations pass the **same** behavioral contract test.
- Line coverage meets the threshold in doc 08, and the CI gate (see `../ci-cd/`) enforces it.
