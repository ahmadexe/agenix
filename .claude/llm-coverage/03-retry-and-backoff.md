# 03 — Retry & Backoff

## Summary
A single transient failure — a dropped packet, a `503`, a `429` rate-limit, a timeout — fails
the entire agent turn. There is no retry anywhere in the LLM call path. (Note: the agent's
existing `_llmGenerateWithParseRetry` retries **malformed output**, which is a different
concern — that's re-prompting a *successful* call whose content was unparseable. This doc adds
**transport-level** retry for *failed* calls.) On mobile networks, transient failures are
routine; a production framework must absorb them with bounded, jittered backoff.

## Severity & impact
**High.** Without retry, perceived reliability on real networks is poor: users see "I am
unable to process your request" for blips that a single retry would have hidden.

## Affected files
- `lib/src/llm/llm_config.dart` (`RetryPolicy` type + `retry` field — introduced here)
- `lib/src/llm/_gemini.dart` (apply the policy around the model call)
- `lib/src/llm/_retry.dart` (**new** internal helper — reusable across providers)
- `lib/agenix.dart` (export `RetryPolicy`)
- any future provider (doc 06) reuses `_retry.dart`

## Current behavior
No transport retry exists. `Gemini.generate` makes exactly one network call and any failure
propagates immediately.

## Target design

### 1. A public, provider-neutral `RetryPolicy`
```dart
// in llm_config.dart (or a sibling) — exported
class RetryPolicy {
  /// Total attempts including the first (1 = no retry).
  final int maxAttempts;
  /// Base delay for exponential backoff.
  final Duration baseDelay;
  /// Upper bound on any single delay.
  final Duration maxDelay;
  /// Multiplier per attempt (2.0 = double each time).
  final double factor;
  /// Add random jitter in [0, computedDelay) to avoid thundering herds.
  final bool jitter;

  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
    this.maxDelay = const Duration(seconds: 8),
    this.factor = 2.0,
    this.jitter = true,
  });

  /// No retries.
  static const RetryPolicy none = RetryPolicy(maxAttempts: 1);
}
```
`LlmConfig` carries a `RetryPolicy retry` (default `const RetryPolicy()`).

### 2. What is retryable
Retry **only** transient failures; never retry a deterministic error (bad request, auth
failure, content blocked, or a *successful* call whose body was unparseable — that's the
agent's parse-retry job, not this).

Define a predicate:
```dart
bool _isRetryable(Object error) {
  if (error is LlmTimeoutException) return true;          // doc 02
  if (error is LlmException) {
    // Inspect cause for transient HTTP/network signals.
    final s = error.cause?.toString().toLowerCase() ?? error.message.toLowerCase();
    return s.contains('429') || s.contains('rate') ||
           s.contains('503') || s.contains('502') || s.contains('500') ||
           s.contains('unavailable') || s.contains('timeout') ||
           s.contains('socket') || s.contains('connection');
  }
  return false;
}
```
> This is heuristic because `google_generative_ai` surfaces errors as typed exceptions whose
> details vary. Prefer matching on the SDK's specific exception types where they exist; fall
> back to string sniffing. Document exactly what you match so it's maintainable. When doc 06
> adds another provider, give each adapter its own `_isRetryable` (or a per-provider classifier)
> rather than one giant string match.

### 3. The retry runner (`_retry.dart`)
```dart
// lib/src/llm/_retry.dart  (internal)
import 'dart:async';
import 'dart:math';

Future<T> runWithRetry<T>(
  Future<T> Function() action, {
  required RetryPolicy policy,
  required bool Function(Object error) isRetryable,
  void Function(int attempt, Object error, Duration nextDelay)? onRetry,
}) async {
  final rng = Random();
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await action();
    } catch (e) {
      final isLast = attempt >= policy.maxAttempts;
      if (isLast || !isRetryable(e)) rethrow;
      var delayMs = (policy.baseDelay.inMilliseconds *
              pow(policy.factor, attempt - 1))
          .clamp(0, policy.maxDelay.inMilliseconds)
          .toDouble();
      if (policy.jitter) delayMs = rng.nextDouble() * delayMs;
      final delay = Duration(milliseconds: delayMs.round());
      onRetry?.call(attempt, e, delay);
      await Future.delayed(delay);
    }
  }
}
```

### 4. Apply it in the Gemini adapter
Wrap the *per-attempt* call (which includes the doc-02 timeout) so each attempt gets a fresh
deadline:
```dart
@override
Future<String> generate({...}) {
  return runWithRetry<String>(
    () => _generateOnce(prompt: prompt, systemInstruction: systemInstruction,
                        rawData: rawData, mimeType: mimeType),
    policy: _config.retry,
    isRetryable: _isRetryable,
    onRetry: (attempt, error, delay) {
      // Hook into telemetry (doc 05) here.
    },
  );
}
```
`_generateOnce` is the doc-02 body (build model, call with `.timeout`, `_extractText`,
exception mapping).

### 5. Interaction with the agent's parse-retry
Keep them separate and layered:
- **Inner:** transport retry (this doc) — retries *failed* network calls.
- **Outer:** `_llmGenerateWithParseRetry` (agent) — re-prompts *successful* calls whose body
  was unparseable.
A single `generate()` may thus do up to `retry.maxAttempts` network attempts, and the agent
may call `generate()` up to `kMaxParseRetries + 1` times. Make sure the math is intentional
and documented (worst case is the product — keep both bounds modest).

## Step-by-step implementation
1. Add `RetryPolicy` (export it) and `LlmConfig.retry` (doc 01 stubbed it).
2. Create `lib/src/llm/_retry.dart` with `runWithRetry`.
3. In `_gemini.dart`, extract the single-attempt logic into `_generateOnce`, add
   `_isRetryable`, and wrap with `runWithRetry`.
4. Wire `onRetry` to the telemetry hook from doc 05 (or leave a TODO if doc 05 isn't done).
5. Tests (see `../tests/`):
   - **Unit-test `runWithRetry`** in isolation: succeeds on attempt 1 (no delay); succeeds on
     attempt 2 after one retryable error; gives up after `maxAttempts` and rethrows the last
     error; does **not** retry a non-retryable error; respects `RetryPolicy.none`.
     Use `fakeAsync` (from `package:fake_async`) or a zero/short `baseDelay` to keep tests fast
     and deterministic — **do not** sleep real seconds in CI.
   - `_isRetryable` classification: timeout → true; a "429"/"503"/"unavailable" cause → true;
     an auth/bad-request cause → false; an unparseable-body case is **not** funneled here.
   - Agent-level: a FakeLLM that throws a retryable error once then succeeds yields a normal
     response (when the retry is applied at the adapter; for the fake, simulate by composing
     `runWithRetry` around the fake or by testing the adapter directly).
6. `flutter analyze` clean; `flutter test` green and fast.

## Acceptance criteria
- `runWithRetry` retries only retryable errors, with exponential backoff + jitter, bounded by
  `maxAttempts` and `maxDelay`; `RetryPolicy.none` disables it.
- The Gemini adapter retries transient failures and timeouts; deterministic errors fail fast.
- Transport retry and agent parse-retry remain distinct and are both bounded.
- Retry tests run deterministically without real delays.
- `RetryPolicy` is exported and provider-neutral.

## Related docs
- [01 — generation config](01-generation-config-and-system-instruction.md) (`config.retry`)
- [02 — timeouts](02-timeouts.md) (timeouts are retryable; per-attempt deadline)
- [05 — usage and observability](05-usage-and-observability.md) (`onRetry` telemetry)
- [06 — second provider](06-provider-abstraction-and-second-provider.md) (reuse `_retry.dart`)
