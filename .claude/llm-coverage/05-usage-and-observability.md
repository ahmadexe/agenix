# 05 — Token Usage & Observability

## Summary
There is no way to see what the LLM layer is doing: no token/usage reporting, no per-call
latency, no record of retries, no count of loop iterations or tool calls per turn. The only
hook is the agent's `onError` callback (errors only). For a production framework — especially
client-side, where cost is the user's API bill and latency is the user's experience — you need
to *observe* successful calls, not just failed ones.

## Severity & impact
**Medium.** Not a correctness bug, but without observability you can't measure cost, debug
"why was that turn slow / why did it call that tool," or build a usage meter. It's what
separates "it works on my phone" from "we run this in a shipped app."

## Affected files
- `lib/src/llm/llm.dart` (return richer result / expose usage)
- `lib/src/llm/_gemini.dart` (read `usageMetadata` from the response)
- `lib/src/llm/llm_telemetry.dart` (**new** public telemetry types + hook)
- `lib/src/agent/agent.dart` (emit turn-level events; thread a telemetry sink)
- `lib/agenix.dart` (export telemetry types)

## Target design

### 1. A usage value type
```dart
// llm_telemetry.dart
class LlmUsage {
  final int? promptTokens;
  final int? responseTokens;
  final int? totalTokens;
  const LlmUsage({this.promptTokens, this.responseTokens, this.totalTokens});
}
```
Gemini exposes `response.usageMetadata` (`promptTokenCount`, `candidatesTokenCount`,
`totalTokenCount`). Map those in the adapter.

### 2. How to surface usage without breaking `generate`
Two options — pick one and apply consistently:
- **Option A (recommended): a telemetry sink.** `generate` still returns `String`, but the
  adapter reports an `LlmCallEvent` to an optional sink. Non-breaking, and it captures latency
  + retries + usage in one place.
- **Option B: a richer return type.** Add `Future<LlmResult> generateDetailed(...)` returning
  `{text, usage, modelId, latency}`, keeping `generate` as a thin wrapper. More explicit but
  adds public surface and a parallel call path.

### 3. Telemetry events + sink (Option A)
```dart
sealed class AgenixTelemetryEvent { const AgenixTelemetryEvent(); }

class LlmCallEvent extends AgenixTelemetryEvent {
  final String modelId;
  final Duration latency;
  final int attempts;          // 1 if no retry
  final LlmUsage? usage;
  final bool streamed;
  final Object? error;         // null on success
  const LlmCallEvent({required this.modelId, required this.latency,
      required this.attempts, this.usage, this.streamed = false, this.error});
}

class ToolCallEvent extends AgenixTelemetryEvent {
  final String toolName; final bool success; final Duration latency;
  const ToolCallEvent({required this.toolName, required this.success, required this.latency});
}

class AgentTurnEvent extends AgenixTelemetryEvent {
  final String agentName; final int loopIterations; final int toolCalls;
  final int chainDepth; final Duration latency; final bool isError;
  const AgentTurnEvent({required this.agentName, required this.loopIterations,
      required this.toolCalls, required this.chainDepth, required this.latency,
      required this.isError});
}

typedef TelemetrySink = void Function(AgenixTelemetryEvent event);
```

### 4. Wiring
- `LLM.geminiLLM(... , TelemetrySink? telemetry)` (or set it on `LlmConfig`). The adapter
  times each call, counts attempts (from doc 03's `onRetry`), reads `usageMetadata`, and emits
  an `LlmCallEvent` on both success and failure.
- `Agent.create(... , TelemetrySink? telemetry)`: the agent emits `ToolCallEvent` per tool
  (wrap `_toolRunner.runTools` timing) and an `AgentTurnEvent` at the end of `generateResponse`
  (and the streaming variant), recording loop iterations, tool count, chain depth, latency, and
  whether it ended in error.
- A single sink can receive all event types (it's a sealed hierarchy — consumers `switch`).

### 5. Keep it zero-overhead when unused
If no sink is provided, do no extra work beyond cheap timing. Never `print`; never log by
default. The consumer decides where events go (analytics, console, a usage meter widget).

## Step-by-step implementation
1. Create `lib/src/llm/llm_telemetry.dart` with `LlmUsage`, the event hierarchy, and
   `TelemetrySink`. Export from `lib/agenix.dart`.
2. Adapter: in `_gemini.dart`, measure latency (`Stopwatch`), capture attempt count from the
   retry runner, read `response.usageMetadata`, and emit `LlmCallEvent` (success + error).
3. Agent: thread an optional `TelemetrySink` through `Agent.create`; emit `ToolCallEvent` and
   `AgentTurnEvent`. Increment counters inside `_generateResponse`'s loop and chaining.
4. Extend `FakeLLM` to optionally report a scripted `LlmUsage`/latency so agent telemetry tests
   are deterministic.
5. Tests (see `../tests/`):
   - Adapter emits an `LlmCallEvent` with usage + latency on success and with `error` set on
     failure (use a fake/double; assert fields, not exact latency — assert `latency >= 0`).
   - Agent emits one `AgentTurnEvent` per `generateResponse` with correct `loopIterations` and
     `toolCalls` for a multi-step scenario, and `isError` true on a failed turn.
   - No sink → no crash, no output.
6. `flutter analyze` clean; `flutter test` green.

## Acceptance criteria
- Token usage is readable for Gemini calls (mapped from `usageMetadata`).
- A consumer can attach one `TelemetrySink` and observe LLM calls, tool calls, and turns,
  including latency, attempts, usage, loop iterations, and chain depth.
- Telemetry is opt-in and zero-overhead when no sink is set; the library never logs by default.
- Telemetry events are a sealed, exported, provider-neutral hierarchy.

## Related docs
- [03 — retry and backoff](03-retry-and-backoff.md) (`attempts`, `onRetry`)
- [04 — streaming](04-streaming-responses.md) (`streamed` flag on events)
- [06 — second provider](06-provider-abstraction-and-second-provider.md) (each adapter emits the same events)
- improvements [03 — error handling](../improvements/03-error-handling-and-exceptions.md) (`onError` is the error half of this)
