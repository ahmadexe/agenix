# 04 — Streaming Responses

## Summary
`LLM.generate` returns a single `Future<String>` — the agent waits for the *entire* response
before anything reaches the UI. Every modern chat product streams tokens as they arrive; a
blocking call makes Agenix-powered chat feel slow even when it isn't. This doc adds an
**optional** streaming path to the LLM layer and a streaming entrypoint on the agent, without
breaking the existing blocking API.

## Severity & impact
**High (UX).** For any conversational client-side app, perceived latency is dominated by
time-to-first-token. Streaming is the difference between "feels instant" and "feels stuck."

## Affected files
- `lib/src/llm/llm.dart` (add an optional streaming method)
- `lib/src/llm/_gemini.dart` (implement via `generateContentStream`)
- `lib/src/agent/agent.dart` (a streaming entrypoint)
- `lib/agenix.dart` (export any new public types, e.g. `AgentChunk`)
- `../tests/02-fakes-and-fixtures.md` (extend `FakeLLM` to stream)

## The core tension: streaming vs. the JSON tool contract
Agenix's control flow depends on parsing a **complete** JSON object (`{"response": ...}`,
`{"tools": ...}`, `{"agents_chain": ...}`). You cannot meaningfully act on a half-streamed
tool call. So streaming applies cleanly only to the **final natural-language answer**, not to
the decision step. Design accordingly:

- The **decision/tool/loop steps** stay blocking (they need the whole JSON).
- Streaming kicks in for the **terminal `response`** (and for `_reasonUsingData`'s synthesis,
  which is pure natural language).

Concretely: the agent runs the loop as today; when it reaches a terminal `response` outcome
(or the reason-over-data synthesis), it issues that final generation as a **stream** and
forwards chunks to the caller.

## Target design

### 1. Add a default-implemented stream method to `LLM`
Keep it optional so existing custom `LLM`s don't break:
```dart
abstract class LLM {
  Future<String> generate({required String prompt, String? systemInstruction,
      Uint8List? rawData, String mimeType = 'image/jpeg'});

  /// Streams the response in chunks. Default implementation falls back to a
  /// single-chunk emission of [generate] so existing providers keep working.
  Stream<String> generateStream({required String prompt, String? systemInstruction,
      Uint8List? rawData, String mimeType = 'image/jpeg'}) async* {
    yield await generate(prompt: prompt, systemInstruction: systemInstruction,
        rawData: rawData, mimeType: mimeType);
  }

  String get modelId;
  LlmConfig get config;
}
```

### 2. Gemini implements real streaming
```dart
@override
Stream<String> generateStream({...}) async* {
  final model = _buildModel(systemInstruction); // same as generate()
  final content = rawData == null
      ? [Content.text(prompt)]
      : [Content.multi([TextPart(prompt), DataPart(mimeType, rawData)])];
  try {
    await for (final chunk in model.generateContentStream(content)) {
      final t = chunk.text;
      if (t != null && t.isNotEmpty) yield t;
    }
  } on TimeoutException catch (e, st) {
    throw LlmTimeoutException('LLM stream exceeded ${_config.timeout.inSeconds}s',
        cause: e, causeStack: st);
  } catch (e, st) {
    if (e is AgenixException) rethrow;
    throw LlmException('LLM stream failed: $e', cause: e, causeStack: st);
  }
}
```
> Timeout semantics for streams differ from `Future.timeout`: apply a timeout to the
> **first** chunk (time-to-first-token) and optionally an overall budget. Use
> `Stream.timeout(config.timeout)` for an inter-event deadline, or wrap with a manual timer.
> Document which you chose. Retry (doc 03) for streams is harder (you may have already emitted
> partial output) — only retry if **nothing** has been yielded yet; otherwise surface the
> error. State this rule explicitly in code.

### 3. Agent streaming entrypoint
Add a public method that mirrors `generateResponse` but yields chunks for the terminal answer:
```dart
/// Streams the agent's final answer. Tool selection, the agentic loop, and
/// chaining run to completion first (they require complete JSON); only the
/// terminal natural-language answer is streamed.
Stream<AgentChunk> generateResponseStream({
  required String convoId,
  required AgentMessage userMessage,
  int memoryLimit = 10,
  Object? metaData,
}) async* { ... }
```
Where `AgentChunk` is a small public value type:
```dart
class AgentChunk {
  final String delta;        // the incremental text
  final bool isDone;         // true on the final chunk
  final AgentMessage? message; // populated on the final chunk (the saved message)
  const AgentChunk({required this.delta, this.isDone = false, this.message});
}
```
Flow:
1. Run the existing loop logic up to the point a terminal `response` is determined. (Refactor
   `_generateResponse` so the "decide" phase is reusable and returns either "needs streaming
   final answer with prompt X" or a non-streamable terminal like a tool-less direct response.)
2. Stream the final generation, accumulating the full text.
3. On completion, build the final `AgentMessage`, **persist** user + agent messages (same
   save-after-success rule as `generateResponse`), and emit a final `AgentChunk(isDone: true,
   message: saved)`.
4. Errors: convert to `AgentChunk`-free behavior — either emit an error `AgentChunk` or throw
   per `FailureMode` (decide and document; recommended: respect `FailureMode` exactly like
   `generateResponse`, emitting a terminal error message in graceful mode).

### 4. Persistence + history
Only the **final** assembled answer is saved (never partial deltas). Same exclusion of
`isError` messages from history applies.

## Step-by-step implementation
1. Add `generateStream` (with default fallback) to `LLM`; add `AgentChunk` (export it).
2. Implement `Gemini.generateStream` via `generateContentStream`; apply first-chunk timeout;
   apply the "retry only if nothing yielded" rule.
3. Refactor `Agent._generateResponse` so the decision phase can hand back a "stream this final
   prompt" instruction; implement `generateResponseStream` on top.
4. Extend `FakeLLM` (`../tests/`): add a `streamResponses`/`chunksFor` mechanism so a test can
   script `['Hello', ' ', 'world']` and assert the agent forwards three deltas then a done
   chunk with the assembled message `'Hello world'`.
5. Tests (see `../tests/`):
   - LLM default `generateStream` emits exactly one chunk equal to `generate`'s result.
   - `Gemini.generateStream` (via a model double if feasible, else skip with a note) yields
     multiple chunks and maps timeout/errors to typed exceptions.
   - Agent streaming happy path: deltas in order, final `isDone` chunk carries the saved
     message, and the store contains user + assembled-agent message.
   - Streaming respects `FailureMode` on error.
   - Tool/chain turns still resolve correctly before streaming begins (a tool call then a
     streamed final answer).
6. `flutter analyze` clean; `flutter test` green.

## Acceptance criteria
- A consumer can stream the agent's final answer chunk-by-chunk via `generateResponseStream`.
- The blocking `generateResponse` is unchanged and still passes all existing tests.
- Custom `LLM`s that don't override `generateStream` still work (single-chunk fallback).
- Only complete answers are persisted; partial deltas are never saved.
- Streaming errors/timeouts surface as typed exceptions and respect `FailureMode`.

## Related docs
- [01 — generation config](01-generation-config-and-system-instruction.md)
- [02 — timeouts](02-timeouts.md) (first-chunk timeout)
- [03 — retry and backoff](03-retry-and-backoff.md) (retry-before-first-chunk rule)
- [06 — second provider](06-provider-abstraction-and-second-provider.md) (design streaming against 2 backends)
