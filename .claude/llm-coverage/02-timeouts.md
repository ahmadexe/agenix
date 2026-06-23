# 02 — Request Timeouts

## Summary
The codebase defines `LlmTimeoutException` but **nothing ever throws it** — it is dead code.
`Gemini.generate` has no `.timeout(...)`, so a stalled request (common on mobile networks)
hangs the agent forever: no response, no error, no recovery. This doc wires a real per-request
timeout driven by `LlmConfig.timeout` and makes the dead exception type live.

## Severity & impact
**High.** A hung LLM call is the worst production failure mode — the UI spins indefinitely
with no way to recover except killing the app. On flaky mobile connections this is not an
edge case.

## Affected files
- `lib/src/llm/_gemini.dart` (wrap the network call)
- `lib/src/llm/llm_config.dart` (`timeout` field — added in doc 01)
- `lib/src/static/agenix_exceptions.dart` (`LlmTimeoutException` already exists)
- any future provider adapter (doc 06) must apply the same pattern

## Current behavior
```dart
// _gemini.dart — no timeout anywhere
final response = await _model.generateContent([Content.text(prompt)]);
```
```dart
// agenix_exceptions.dart — defined but never thrown
class LlmTimeoutException extends LlmException {
  const LlmTimeoutException(super.message, {super.cause, super.causeStack});
}
```

## Target design

### 1. Wrap every model call in `.timeout(config.timeout)`
`Future.timeout` throws `TimeoutException` (from `dart:async`) when the deadline passes.
Catch it and convert to the typed `LlmTimeoutException`.

```dart
import 'dart:async'; // TimeoutException

Future<GenerateContentResponse> _call(List<Content> content) {
  return _model.generateContent(content).timeout(_config.timeout);
}

@override
Future<String> generate({required String prompt, String? systemInstruction,
    Uint8List? rawData, String mimeType = 'image/jpeg'}) async {
  try {
    final content = rawData == null
        ? [Content.text(prompt)]
        : [Content.multi([TextPart(prompt), DataPart(mimeType, rawData)])];
    final response = await _call(content);   // already model built w/ systemInstruction
    return _extractText(response);
  } on TimeoutException catch (e, st) {
    throw LlmTimeoutException(
      'LLM request exceeded ${_config.timeout.inSeconds}s',
      cause: e, causeStack: st,
    );
  } on AgenixException {
    rethrow;
  } catch (e, st) {
    throw LlmException('LLM call failed: $e', cause: e, causeStack: st);
  }
}
```

### 2. Order of catches matters
- `on TimeoutException` **before** the generic `catch` so timeouts get the precise type.
- `on AgenixException { rethrow; }` so `_extractText`'s `LlmException` (empty response) isn't
  re-wrapped.
- Generic `catch` last for everything else.

### 3. Interaction with retries (doc 03)
A timeout is a **retryable** condition. When doc 03 lands, the retry wrapper should treat
`LlmTimeoutException` as retryable (up to the policy's max attempts) and only surface it after
the final attempt. Keep the timeout *inside* the per-attempt call so each retry gets a fresh
deadline.

### 4. Agent-level behavior
No change needed in `Agent` — `LlmTimeoutException` is an `AgenixException` (via `LlmException`),
so `generateResponse` already handles it: `onError` fires, and `FailureMode` decides between
rethrow and the graceful `isError` message. Add a test asserting that path.

## Step-by-step implementation
1. Ensure `LlmConfig.timeout` exists (doc 01). Default 60s.
2. In `_gemini.dart`, `import 'dart:async';`, wrap the `generateContent` call in
   `.timeout(_config.timeout)`, and add the `on TimeoutException` → `LlmTimeoutException`
   conversion **before** the generic catch.
3. Verify catch ordering (`TimeoutException` → `AgenixException` rethrow → generic).
4. Extend `FakeLLM` (`../tests/`) with a way to simulate a slow/timed-out call — e.g. an
   `onGenerate` hook that `throw TimeoutException('simulated')` or returns a delayed future
   you wrap with a tiny timeout in the test. Simplest: have the fake throw
   `LlmTimeoutException` directly to test the agent path; test the **conversion** logic by a
   focused `_gemini` test that injects a delaying model double if feasible, otherwise unit-test
   the catch mapping by extracting it into a small testable helper.
5. Tests (see `../tests/`):
   - Agent in `throwError` mode surfaces `LlmTimeoutException` when the LLM times out.
   - Agent in `gracefulMessage` mode returns an `isError` message and fires `onError` with an
     `LlmTimeoutException`.
   - A configured short `timeout` actually triggers within roughly that bound (use a fake
     that delays; keep the bound generous to avoid flaky CI — e.g. assert it throws, not exact
     timing).
6. `flutter analyze` clean; `flutter test` green.

## Acceptance criteria
- A request that exceeds `config.timeout` throws `LlmTimeoutException` (not a hang, not a
  generic `LlmException`).
- Catch ordering preserves `_extractText`'s empty-response `LlmException`.
- The agent surfaces the timeout per `FailureMode` and fires `onError`.
- `LlmTimeoutException` is no longer dead code (covered by a test).
- Each retry attempt (doc 03) gets its own fresh timeout.

## Related docs
- [01 — generation config](01-generation-config-and-system-instruction.md) (`config.timeout`)
- [03 — retry and backoff](03-retry-and-backoff.md) (timeouts are retryable)
- improvements [03 — error handling](../improvements/03-error-handling-and-exceptions.md) (the exception model)
- [../tests/07-integration-tests-agent-loop-and-chaining.md](../tests/07-integration-tests-agent-loop-and-chaining.md) (agent-path tests)
