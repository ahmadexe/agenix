# 03 — Error Handling & Exceptions

## Summary
The agent's main method wraps everything in a single `try { ... } catch (e) { return
kLLMResponseOnFailure }`. Every failure — a network blip, a malformed-JSON parse, a
missing tool, an unregistered agent, a Firestore permission error, a bug in user tool
code — collapses into the **same generic string**, with no log, no stack trace, no type,
and no way for the caller to tell "the model declined" from "your tool threw" from "the
user isn't signed in." Downstream, the LLM-not-available fallback is returned as if it
were a normal answer and then **persisted to memory**, poisoning future context.

## Severity & impact
**High.** This is the single biggest barrier to operating Agenix in production. You cannot
debug it, you cannot alert on it, you cannot retry intelligently, and failures contaminate
conversation history.

## Affected files
- `lib/src/agent/agent.dart` (the catch-all at lines 204–210; the failure returns at
  127–135, 147–153, 192–202)
- `lib/src/tools/_tool_runner.dart` (throws bare `Exception`, lines 18–23)
- `lib/src/tools/_parser.dart` (throws bare `Exception`)
- `lib/src/memory/data_sources/_firebase.dart` (force-unwraps `currentUser!`, wraps every
  error as `Exception('...$e')`)
- `lib/src/llm/_gemini.dart` (null `response.text` → fallback string)
- `lib/src/static/_pkg_constants.dart` (the fallback constant)
- New file: `lib/src/static/agenix_exceptions.dart`

## Current behavior
`lib/src/agent/agent.dart`:
```dart
} catch (e) {
  return AgentMessage(
    content: kLLMResponseOnFailure,
    isFromAgent: true,
    generatedAt: DateTime.now(),
  );
}
```
And in `generateResponse` (lines 79–97) the result of `_generateResponse` is **always
saved to memory** — including a `kLLMResponseOnFailure` message produced by the catch-all.
That failure text then re-enters the next prompt as "chat history."

`_tool_runner.dart` throws `Exception("Tool $toolName not found in registry")`, which
propagates straight into the catch-all and disappears.

`_firebase.dart` does `_auth.currentUser!.uid` — a null-check crash if the user isn't
authenticated — then re-wraps as a stringly-typed `Exception`.

## Target design

### 1. A typed exception hierarchy
Create `lib/src/static/agenix_exceptions.dart`:
```dart
sealed class AgenixException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? causeStack;
  const AgenixException(this.message, {this.cause, this.causeStack});
}

class LlmException extends AgenixException { ... }        // network, timeout, blocked, null text
class LlmTimeoutException extends LlmException { ... }
class ResponseParseException extends AgenixException { ... } // unparseable model output
class ToolNotFoundException extends AgenixException { ... }
class ToolExecutionException extends AgenixException { ... } // user tool threw
class AgentNotFoundException extends AgenixException { ... }
class DataStoreException extends AgenixException { ... }
class NotAuthenticatedException extends DataStoreException { ... }
class ConfigException extends AgenixException { ... }     // bad system_data.json, etc.
```
Export these from `lib/agenix.dart` so consumers can `catch` precisely.

### 2. Decide where failures are handled vs. surfaced
- **Adapters/leaf code** (LLM, parser, tools, datastore) throw the **specific typed
  exception**, preserving `cause` + stack.
- **The agent** chooses a policy. Two supported modes, configurable:
  - `FailureMode.throwError` — rethrow the typed exception (best for apps that want full
    control / their own UI).
  - `FailureMode.gracefulMessage` — return a fallback `AgentMessage` **flagged as an
    error** (see #3) and (optionally) report via an error hook.
- Default to `gracefulMessage` for source-compatible behavior, but make it explicit.

### 3. Mark error messages so they don't poison memory
- Add an `bool isError` (or `AgentMessageKind kind`) field to the fallback `AgentMessage`,
  or simply: **do not persist** a message produced by the failure path.
- In `generateResponse`, only save the assistant message when it represents a genuine
  model/tool answer. On failure, either skip the save or save with an `isError` flag that
  the prompt builder excludes from "Chat History".

### 4. Add an observability hook
Add an optional `void Function(AgenixException error, StackTrace stack)? onError` (or a
`Logger`) to `Agent.create`. Call it from the failure path so apps can wire Crashlytics /
Sentry. Never `print`.

## Step-by-step implementation
1. Create `lib/src/static/agenix_exceptions.dart` with the hierarchy above; export from
   the barrel.
2. **Parser** (`_parser.dart`): replace `throw Exception(...)` with
   `ResponseParseException` (and, per doc 02, prefer returning an `unparseable` outcome so
   the agent can retry before this is even thrown).
3. **Tool runner** (`_tool_runner.dart`): throw `ToolNotFoundException`; wrap user
   `tool.run` in try/catch and rethrow as `ToolExecutionException(toolName, cause, stack)`
   so a buggy tool can't masquerade as a model failure.
4. **Gemini** (`_gemini.dart`): on null `response.text`, inspect finish reason / prompt
   feedback and throw `LlmException`/blocked-specific error; convert `TimeoutException`
   (from doc 01) to `LlmTimeoutException`.
5. **Firebase** (`_firebase.dart`): replace every `currentUser!` with a guarded read that
   throws `NotAuthenticatedException`; wrap Firestore/storage errors as
   `DataStoreException(cause, stack)` (keep the original error as `cause`).
6. **Agent** (`agent.dart`):
   - Add `FailureMode failureMode` and `onError` to `Agent.create` / fields.
   - Replace the catch-all body: log via `onError`, then either rethrow (throw mode) or
     return a fallback message flagged `isError: true` (graceful mode).
   - In `generateResponse`, **do not persist** error-flagged assistant messages.
   - Narrow the `try` so expected control-flow (agent-not-found, tool-not-found) produces
     specific typed errors rather than being caught generically.
7. **Prompt builder** (`_prompt_builder.dart`): when iterating history, skip messages
   flagged `isError`.
8. Keep `kLLMResponseOnFailure` only as the *graceful-mode* default message text.

## Acceptance criteria
- A buggy tool that throws surfaces as `ToolExecutionException` (in throw mode) or a
  logged error + graceful message (in graceful mode) — never silently identical to a
  network failure.
- An unauthenticated Firestore call throws `NotAuthenticatedException`, not a null-check
  crash wrapped in a string.
- A failure message is **not** written into conversation history and therefore never
  appears in a later prompt.
- Consumers can register `onError` and receive `(typedException, stackTrace)`.
- `flutter analyze` shows no force-unwrap (`!`) on `currentUser`.

## Related docs
- [01](01-llm-settings-and-generation-config.md) & [02](02-structured-output-and-robust-parsing.md) (sources of typed errors)
- [04 — memory management](04-memory-management.md) (not persisting error messages)
- [07 — agentic loop & verification](07-agentic-loop-and-answer-verification.md) (retry policy on these errors)
- [11 — datastore robustness](11-datastore-robustness-and-testability.md) (auth handling)
