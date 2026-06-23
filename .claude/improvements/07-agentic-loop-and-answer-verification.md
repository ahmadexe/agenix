# 07 — Agentic Loop, Retries & Answer Verification

## Summary
Agenix runs a **single forward pass**: prompt → parse → (run tools once **or** delegate to
agents once) → return. There is no loop that lets the model observe tool results and decide
to call more tools, no retry when the model emits malformed JSON, no backoff on transient
LLM errors, and no verification that the produced answer is actually grounded in the tool
data or even answers the question. The only "second pass" is `_reasonUsingData`, a one-shot
free-text summarization triggered by `needsFurtherReasoning`. For anything beyond a single
tool call this is too rigid, and for anything stochastic it is too fragile.

## Severity & impact
**High** for real agentic use cases. Production agents need: bounded multi-step tool use,
resilience to malformed output, and at least a lightweight self-check before returning.

## Affected files
- `lib/src/agent/agent.dart` (`_generateResponse` lines 99–211; `_reasonUsingData`
  247–262)
- `lib/src/tools/_parser.dart` (retry hooks on `unparseable`, doc 02)
- `lib/src/llm/_gemini.dart` (retry/backoff lives at the call boundary, doc 01/03)
- `lib/src/static/_pkg_constants.dart` (new tunables: max iterations, max retries)

## Current behavior
- After tools run, results are joined into a string and returned (or one-shot
  `_reasonUsingData`). The model never gets to say "now call tool B with this output."
- `_reasonUsingData` builds its prompt by concatenating `r.data` maps with `.join('\n')`
  (Dart `Map.toString`), which is unstructured and lossy:
  ```dart
  final rawData = toolResponses.map((r) => r.data).join('\n');
  ```
- A single malformed JSON response → parser throws → caught → generic failure. No retry.
- No timeout/backoff/retry around `llm.generate`.
- No check that the final answer is consistent with tool outputs.

## Target design

### 1. Bounded agentic tool loop
Replace the single tool pass with a loop:
```
for step in 1..maxToolIterations:
    response = llm.generate(prompt + accumulated tool observations)
    parsed = parse(response)
    if parsed is response  -> break with answer
    if parsed is tools     -> validate (doc 06) + run + append observations; continue
    if parsed is agents    -> delegate (doc 08); break
    if parsed is unparseable -> retry (see #2)
```
- Maintain an **observation transcript** (structured, not `Map.toString`): each tool's
  name, success, message, and `data` as JSON, appended to the next prompt.
- Cap with `maxToolIterations` (e.g. 5) to prevent infinite tool loops. On cap, return the
  best answer so far or a typed error.

### 2. Malformed-output retry
On `unparseable` (doc 02), re-prompt up to `maxParseRetries` (e.g. 2) with a short
corrective instruction ("Your last reply was not valid JSON. Reply with ONLY the JSON
object."). Only after retries are exhausted do you surface a `ResponseParseException`
(doc 03).

### 3. Transient-error retry with backoff
Wrap `llm.generate` with retry-on-transient (timeouts, 5xx/network) using exponential
backoff + jitter, `maxLlmRetries` (e.g. 2). Do **not** retry on deterministic errors
(safety block, auth). Put this at the adapter boundary or in a small `_retry` helper.

### 4. Lightweight answer verification (opt-in)
Add an optional verification step before returning, controlled by config:
- **Grounding check:** when tools produced data, ask the model (cheap, low-temp) to confirm
  the drafted answer is supported by the tool data and contains no invented facts; if it
  fails, re-draft once. This is the "answer verification loop."
- **Schema/format check:** if the consumer expects a particular output shape, validate it
  and re-ask once on mismatch.
- Keep it **optional and bounded** (one re-draft max) so it doesn't double cost by default.

### 5. Replace `_reasonUsingData` internals
Feed structured JSON observations (not `Map.toString`) and the original user question into
a clearly-scoped synthesis prompt. Keep the public behavior (natural-language synthesis
when `needsFurtherReasoning`) but make the inputs structured and the prompt templated.

## Step-by-step implementation
1. Add tunables to constants/config: `maxToolIterations`, `maxParseRetries`,
   `maxLlmRetries`, `verifyAnswers` (bool), and backoff base. Expose the important ones on
   `Agent.create` or an `AgentConfig`.
2. Add a `_retry<T>(Future<T> Function() op, {int max, bool Function(Object) retryable})`
   helper; use it around `llm.generate`.
3. Refactor `_generateResponse` into a loop that accumulates structured observations and
   branches on `parsed.outcome` (doc 02). Move the agents-chain branch into the loop's
   delegate case (doc 08).
4. Implement the parse-retry path using the loop + corrective re-prompt.
5. Rewrite `_reasonUsingData` to consume a `List<ToolResponse>` and serialize each `data`
   as JSON (`jsonEncode`), not `toString`.
6. (Optional) Implement the verification re-draft behind `verifyAnswers`. Add a private
   `_verifyAnswer(question, draft, observations)` returning `(ok, maybeRedraft)`.
7. Ensure every terminal path returns through the doc-03 failure policy (graceful vs throw)
   and respects doc-04 (don't persist error/intermediate scratch messages).
8. Tests with a scripted fake LLM: (a) two-step tool loop, (b) malformed-then-valid retry,
   (c) transient error retried then succeeds, (d) iteration cap reached, (e) verification
   catches an ungrounded draft.

## Acceptance criteria
- The agent can call tool A, observe its output, then call tool B in the same turn, within
  `maxToolIterations`.
- A first malformed JSON reply is retried and recovered without a user-visible failure.
- A transient LLM timeout is retried with backoff; a safety block is **not** retried.
- Tool observations passed to synthesis are structured JSON, not `Map.toString`.
- With `verifyAnswers: true`, an ungrounded draft triggers exactly one re-draft.
- Loops are provably bounded (cap tests pass).

## Related docs
- [02 — parsing](02-structured-output-and-robust-parsing.md) (`unparseable` outcome to retry on)
- [03 — error handling](03-error-handling-and-exceptions.md) (which errors are retryable; terminal policy)
- [06 — tool validation](06-tool-validation-and-execution.md) (feed validation errors back into the loop)
- [08 — agent chaining](08-agent-chaining.md) (delegate case inside the loop)
