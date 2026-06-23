# Agenix — Production-Hardening Improvement Plan

This folder is a **work backlog**. Each `.md` file describes one cohesive area of the
codebase that must be fixed, improved, or redesigned to take Agenix from a working
prototype (v4.0.0) to a production-grade, flexible-but-not-fragile agent framework.

Every document is written so that **an LLM (or a human) can implement the change
end-to-end without re-deriving the analysis**. Each file follows the same structure:

1. **Summary** — one paragraph: what's wrong and why it matters.
2. **Severity & impact** — how badly this hurts a real app.
3. **Affected files** — exact paths and line references (as of this writing).
4. **Current behavior** — the offending code, quoted.
5. **Target design** — what it should look like.
6. **Step-by-step implementation** — ordered, concrete edits.
7. **Acceptance criteria** — how to know it's done.
8. **Related docs** — cross-links.

> Line numbers refer to the code at the time of analysis. Always re-read the file
> before editing; treat line numbers as hints, not contracts.

---

## How to work through this backlog

Do them in roughly this order. Earlier items unblock later ones (e.g. you want real
exceptions and structured output before you build a verification loop on top).

| #  | Doc | Severity | Theme |
|----|-----|----------|-------|
| 01 | [llm-settings-and-generation-config.md](01-llm-settings-and-generation-config.md) | High | Settings: temperature, system instruction, safety, timeouts |
| 02 | [structured-output-and-robust-parsing.md](02-structured-output-and-robust-parsing.md) | High | LLM JSON mode + a parser that doesn't crash |
| 03 | [error-handling-and-exceptions.md](03-error-handling-and-exceptions.md) | High | Stop swallowing errors; typed exceptions; observability |
| 04 | [memory-management.md](04-memory-management.md) | High | `memoryLimit` is dead; unbounded context; duplication |
| 05 | [agent-registry-lifecycle.md](05-agent-registry-lifecycle.md) | High | Global mutable singleton; no unregister; crashes on re-create |
| 06 | [tool-validation-and-execution.md](06-tool-validation-and-execution.md) | Med | Param validation, `e!` crash, defaults/enums never enforced |
| 07 | [agentic-loop-and-answer-verification.md](07-agentic-loop-and-answer-verification.md) | High | Multi-step tool loop, retries, self-verification |
| 08 | [agent-chaining.md](08-agent-chaining.md) | Med | Double-context, untyped hand-off, no cycle guard |
| 09 | [prompt-builder.md](09-prompt-builder.md) | Med | Typos, map-stringification, contradictory rules |
| 10 | [serialization-correctness.md](10-serialization-correctness.md) | High | Timestamp 1000× bug, asymmetric round-trips |
| 11 | [datastore-robustness-and-testability.md](11-datastore-robustness-and-testability.md) | Med | Auth force-unwrap, no DI, no in-memory store |
| 12 | [dead-arguments-and-api-cleanup.md](12-dead-arguments-and-api-cleanup.md) | Low | Misleading/unused parameters across the public API |

**Suggested sequencing:** 03 → 01 → 02 → 10 → 04 → 05 → 06 → 07 → 08 → 09 → 11 → 12.
(Error model and settings first, then correctness, then the higher-order AI behaviors,
then cleanup.)

---

## Cross-cutting principles for every change

- **Backward compatibility:** This is a published package (v4.0.0). Breaking public API
  changes must be deliberate and noted in the doc, and should land together as a single
  major version bump (v5.0.0) with a CHANGELOG and migration notes.
- **Fail loud in dev, degrade gracefully in prod:** Never silently return
  `kLLMResponseOnFailure` in a way that hides a bug. Surface a typed error or a result
  object that carries the failure reason; let the consumer decide.
- **No new hard dependency on Firebase:** Core agent logic must not assume Firestore.
  Keep `DataStore` swappable and provide an in-memory implementation for tests.
- **Determinism in tests:** Anything that touches the global registry, the LLM, or the
  clock must be injectable so tests are isolated and repeatable.
- **Every new public type goes in `lib/agenix.dart`** (the barrel file), per the project
  conventions in `.claude/CLAUDE.md`.

## Definition of done for the whole backlog

- `flutter analyze` is clean (no force-unwrap warnings, no dead parameters).
- A unit test suite exists that runs without Firebase or a live LLM (using fakes).
- A consumer can configure temperature/limits/timeouts and choose how failures surface.
- Context size is bounded and predictable.
- Malformed LLM output never crashes the agent; it is retried or surfaced as a typed error.
