# Agenix — LLM Layer Coverage & Robustness Plan

This folder is a **work backlog** for hardening and broadening Agenix's LLM layer — the
single seam (`LLM`) through which every agent talks to a model. Today that layer is minimal:
one provider (Gemini), a single blocking `Future<String> generate({prompt, rawData})`, no
generation config, no timeout (the `LlmTimeoutException` type exists but is **never thrown**),
no retry/backoff, no streaming, no token/usage reporting, and a hardcoded `image/jpeg` MIME.
For a framework meant to power real client-side products, the LLM layer is the highest-risk,
least-covered surface.

"Coverage" here means two things at once:
1. **Behavioral coverage** — the LLM layer handles the messy realities of talking to a model
   in production: timeouts, transient failures, retries, streaming, cost/limits, usage.
2. **Provider coverage** — the abstraction is proven against more than one backend so it's
   genuinely pluggable, not Gemini-shaped.

Every document is written so that **an LLM (or a human) can implement the change end-to-end
without re-deriving the analysis**. Each file follows the same structure:

1. **Summary** — what's missing and why it matters.
2. **Severity & impact** — how badly this hurts a real client-side app.
3. **Affected files** — exact paths.
4. **Current behavior** — the code today, quoted.
5. **Target design** — what it should look like.
6. **Step-by-step implementation** — ordered, concrete edits.
7. **Acceptance criteria** — how to know it's done.
8. **Related docs** — cross-links.

> Code snippets reference the codebase as of this writing. Re-read the source before editing.

---

## Design constraints (important — this is a client-side framework)

- **Client-side by design.** Agenix runs in the Flutter app, not on a server. That means:
  - API keys live on the device. Design configs so a consumer *can* route through their own
    proxy/edge function if they want to hide keys, but don't assume a server.
  - Latency and flaky mobile networks are the norm — timeouts, retries, and streaming are
    not luxuries, they're table stakes for a good mobile UX.
- **Keep the public surface provider-neutral.** Don't leak `google_generative_ai` types
  (e.g. `SafetySetting`, `GenerationConfig`) into `lib/agenix.dart`. Provider-specific knobs
  go behind provider-specific subclasses/adapters or opaque pass-through fields.
- **Backward compatibility.** `LLM.generate` and `LLM.geminiLLM(...)` are public. Additive,
  defaulted parameters are fine; breaking signature changes must be deliberate and bundled
  into the v5.0.0 major bump with CHANGELOG + migration notes.
- **Every new public type goes in `lib/agenix.dart`.**
- **Everything must stay testable** with a fake — see `../tests/02-fakes-and-fixtures.md`.
  New LLM features must be expressible/observable through the `FakeLLM` double (extend it as
  needed).

---

## How to work through this backlog

| #  | Doc | Severity | Theme |
|----|-----|----------|-------|
| 01 | [generation-config-and-system-instruction.md](01-generation-config-and-system-instruction.md) | High | temperature/tokens/topP, JSON mode, real `systemInstruction`, MIME |
| 02 | [timeouts.md](02-timeouts.md) | High | wire `LlmTimeoutException`; no more hangs |
| 03 | [retry-and-backoff.md](03-retry-and-backoff.md) | High | transient-failure resilience on flaky networks |
| 04 | [streaming-responses.md](04-streaming-responses.md) | High | token streaming for chat UX |
| 05 | [usage-and-observability.md](05-usage-and-observability.md) | Med | token/usage reporting + per-call telemetry hooks |
| 06 | [provider-abstraction-and-second-provider.md](06-provider-abstraction-and-second-provider.md) | High | prove the seam with a second provider (OpenAI/Claude) |
| 07 | [native-function-calling.md](07-native-function-calling.md) | Med (Advanced) | move off prose-JSON parsing to native tool calling |

**Suggested sequencing:** 01 → 02 → 03 → 05 → 06 → 04 → 07.
(Config first because timeout/retry/usage all attach to it; second provider before streaming
so streaming is designed against two backends; native function calling last because it's the
deepest change and partially supersedes the prose-JSON contract.)

> This backlog supersedes and expands `../improvements/01-llm-settings-and-generation-config.md`,
> which was only partially implemented (the `modelId` fix and system-prompt separation landed;
> the config object, timeout, and MIME handling did not). Doc 01 here finishes that work.

## Definition of done for the whole backlog

- A consumer can configure temperature, max tokens, top-p/k, stop sequences, JSON mode, and a
  per-request timeout — provider-neutrally.
- A hung request throws `LlmTimeoutException`, never wedges the agent.
- Transient failures are retried with backoff and jitter, bounded and configurable.
- Streaming responses are available for chat UIs without breaking the existing blocking API.
- Token/usage is reportable, and a telemetry hook observes every LLM call (latency, tokens,
  retries, outcome).
- At least one **second** provider implements `LLM`, proving the abstraction.
- Every feature is covered by tests using fakes (no live API in CI).
