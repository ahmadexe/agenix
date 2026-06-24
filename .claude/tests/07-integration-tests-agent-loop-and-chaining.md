# 07 — Integration Tests: Agent Loop & Chaining

## Summary
This is the payoff. With the fakes (doc 02), the in-memory store (doc 06), and isolated
scopes (doc 05), we drive the **full `Agent.generateResponse` flow** end-to-end and assert
the behaviors that define Agenix: the bounded agentic tool loop, reason-over-data, parse
retries, max-iteration fallback, the two `FailureMode` branches, message persistence
semantics, and multi-agent chaining (hand-off, cycle detection, depth limit, unknown agent).

## Scope & priority
**Critical.** These tests verify the highest-value, most-likely-to-regress logic in the
package — the agent control flow assembled across improvements docs 03/04/07/08.

## Files under test
- `lib/src/agent/agent.dart` (the loop: `generateResponse`, `_generateResponse`,
  `_llmGenerateWithParseRetry`, `_handleAgentChain`, `_reasonUsingData`)
- transitively: `_PromptBuilder`, `_MemoryManager`, `_AgentRegistry`, `PromptParser`,
  `ToolRunner`.

## Files to create
- `test/agent/agent_loop_test.dart`
- `test/agent/agent_chaining_test.dart`

## Key facts the tests must respect (from source)
- `Agent.create(... scope: ...)` — **always pass a fresh `AgentScope()` per test** for
  isolation; never rely on `AgentScope.global`.
- `generateResponse({required convoId, required userMessage, memoryLimit=10, metaData})`:
  - calls `_generateResponse`, then saves **userMessage then response** to the store (saved
    *after* generation — so a thrown turn persists **neither**).
  - catches `AgenixException` → calls `onError` → if `FailureMode.throwError` rethrows, else
    returns an `AgentMessage(content: kLLMResponseOnFailure, isError: true)`.
  - catches any other error → wraps in `LlmException` → same `onError`/mode handling.
- The loop runs up to `kMaxToolIterations` (5). Each step parses the LLM output:
  - `response` → returns an `AgentMessage`; if observations were accumulated they're attached
    under `data['observations']`.
  - `tools` → runs tools, appends observations; if any response has
    `needsFurtherReasoning` → `_reasonUsingData` (one more LLM call) and returns; otherwise
    builds an observation prompt and loops again.
  - `agentsChain` → `_handleAgentChain`.
  - `unparseable` (only reached after `_llmGenerateWithParseRetry` exhausts) → throws
    `ResponseParseException`.
- `_llmGenerateWithParseRetry` retries up to `kMaxParseRetries` (2) appending
  `kParseRetryInstruction`; the **first** call passes `rawData`, retries don't.
- Default `failureMode` is `FailureMode.gracefulMessage`.

## Asset-free agent construction (prerequisite)
Use `stubSystemData(defaultSystemData())` (doc 02) in `setUp`. If your Flutter version makes
the asset mock unreliable, the fallback is a thin test seam: add (in the package, guarded and
documented) an optional `Map<String,dynamic>? systemData` parameter to `Agent.create` that,
when provided, skips `rootBundle`. This is a small, defensible production feature (it also
unblocks consumers who hold system data in code), but it's optional — prefer the asset stub.
If you add it, also write a test that `systemData` overrides `pathToSystemData`.

## Test design — `agent_loop_test.dart`

Common setup:
```dart
late AgentScope scope;
late InMemoryDataStore store; // via DataStore.inMemory()
setUpAll(() => stubSystemData(defaultSystemData()));
setUp(() { scope = AgentScope(); store = DataStore.inMemory() as InMemoryDataStore; });

Future<Agent> buildAgent(FakeLLM llm, {FailureMode mode = FailureMode.gracefulMessage,
        void Function(AgenixException, StackTrace)? onError}) =>
    Agent.create(
      dataStore: store, llm: llm, name: 'tester', role: 'test agent',
      failureMode: mode, onError: onError, scope: scope,
    );
```

Cases:
1. **Direct response:** `FakeLLM.scripted(['{"response":"hello there"}'])` → returned message
   `content == 'hello there'`, `isFromAgent == true`, `isError == false`. LLM called once.
2. **Persistence on success:** after case 1, `store.getMessages(convoId)` returns
   `[userMessage, response]` in order. (Guards the "save after generation, no duplication"
   fix.)
3. **Single tool then synthesized response:** register `SpyTool('weather', response:
   okTool('weather', message:'sunny'))`. Script two LLM turns:
   `['{"tools":"weather","parameters":{"weather":{"city":"Paris"}}}', '{"response":"It is sunny in Paris"}']`.
   Assert: tool ran once with `{'city':'Paris'}`; final content is the second turn; the
   message `data['observations']` contains the weather observation. LLM called twice.
4. **Validated params reach the tool through the loop:** give the tool a `number` param spec
   and have the LLM pass it as a string; assert the spy received a coerced number.
5. **Reason-over-data path:** tool returns `needsFurtherReasoning: true` with `data`. Script
   first turn = tool call, and make the FakeLLM's *next* `generate` (the reasoning call)
   return a natural sentence. Assert the final content is the reasoning output and
   `data['tools']` is populated. (Note: the reasoning call goes through `llm.generate`
   directly, so it consumes the next queued response.)
6. **Multi-step tool loop:** script turn1 = tool A, turn2 = tool B, turn3 = response. Two
   different `SpyTool`s. Assert both ran, in order, and final content is turn3. Assert the
   second prompt the FakeLLM saw **contains the first tool's observation** (inspect
   `fakeLLM.prompts[1]`).
7. **Max-iteration fallback:** script 5 consecutive tool calls (never a response). After
   `kMaxToolIterations`, the loop exits and synthesizes from observations (content == the
   joined observation messages, not `kLLMResponseOnFailure`, since observations exist).
   Assert LLM called exactly `kMaxToolIterations` times.
8. **Parse-retry recovery:** `FakeLLM.scripted(['garbage', '{"response":"recovered"}'])`.
   The first parse is `unparseable`; `_llmGenerateWithParseRetry` retries; second succeeds.
   Final content `== 'recovered'`. Assert the retry prompt contained `kParseRetryInstruction`
   (inspect `fakeLLM.prompts[1]`).
9. **Unparseable after all retries → ResponseParseException, graceful mode:** FakeLLM returns
   garbage for `kMaxParseRetries + 1` calls. With default `gracefulMessage`,
   `generateResponse` returns a message with `content == kLLMResponseOnFailure` and
   `isError == true`. Assert **nothing was persisted** (`store.getMessages` empty), proving
   save-after-success.
10. **Same failure, throwError mode:** build with `FailureMode.throwError` →
    `expect(() => agent.generateResponse(...), throwsA(isA<ResponseParseException>()))`.
11. **onError callback fires in both modes:** supply an `onError` spy; assert it's called once
    with an `AgenixException` for both case 9 and case 10.
12. **LLM transport error wrapped:** `FakeLLM(throwWhenExhausted:true, responses:[])` (or a
    per-call hook that throws a `StateError`). In graceful mode → `isError` message; in throw
    mode → the error surfaces (a non-Agenix throw is wrapped as `LlmException`). Assert the
    type in throw mode.
13. **`rawData` only on first call:** give the userMessage `imageData`; script a tool call
    then a response. Assert `fakeLLM.rawDataReceived.first` is non-null and
    `fakeLLM.rawDataReceived[1]` is null (retries/loop steps drop rawData).
14. **memoryLimit is forwarded:** pre-seed the store with several messages, call with
    `memoryLimit: 1`, and assert (via the prompt the FakeLLM received) that only the most
    recent history message appears. (White-box-ish but valuable; inspect `fakeLLM.prompts.first`.)
15. **Error messages excluded from history:** save an `isError` agent message into the store,
    then generate; assert the FakeLLM's prompt does **not** contain that error message's
    content (guards `_PromptBuilder` skipping `isError`).

```dart
// Illustrative shape for case 3
test('runs a tool then returns the synthesized response', () async {
  final llm = FakeLLM(responses: [
    '{"tools":"weather","parameters":{"weather":{"city":"Paris"}}}',
    '{"response":"It is sunny in Paris"}',
  ]);
  final agent = await buildAgent(llm);
  final spy = SpyTool(name: 'weather', response: okTool('weather', message: 'sunny'));
  agent.toolRegistry.registerTool(spy);

  final res = await agent.generateResponse(
    convoId: 'c1', userMessage: userMsg('weather in Paris?'),
  );

  expect(spy.calls.single['city'], 'Paris');
  expect(res.content, 'It is sunny in Paris');
  expect(res.data?['observations'], isNotEmpty);
  expect(llm.callCount, 2);
});
```

## Test design — `agent_chaining_test.dart`
`_handleAgentChain` walks `parsed.agentNames`, looking each up via the **shared scope**, and
hands off `agentResponse.data` (json-encoded) or `.content` as `input` to the next agent.
Cycle detection uses a `visited` set seeded with the originating agent's name; depth is
limited by `kMaxChainDepth` (5).

Setup: create multiple agents in the **same** `AgentScope`, each with its own `FakeLLM`.

Cases:
1. **Happy-path two-agent chain:** agent `router` (FakeLLM returns
   `{"agents_chain":["worker"]}`), agent `worker` (FakeLLM returns `{"response":"done"}`).
   `router.generateResponse(...)` returns content `'done'`. The worker's FakeLLM was called.
2. **Hand-off data passes downstream:** make `worker` return a tool/response whose `data` is
   set, chain `router → worker → finisher`; assert `finisher`'s prompt contains the
   hand-off `input` (inspect its FakeLLM prompt). (Set up `router` to emit
   `{"agents_chain":["worker","finisher"]}`.)
3. **Unknown agent → AgentNotFoundException:** `router` emits
   `{"agents_chain":["ghost"]}`; `ghost` not registered. In throw mode → that exception; in
   graceful mode → `isError` message.
4. **Cycle detection:** register `a` and `b`. `a` emits `{"agents_chain":["b"]}` and `b`
   emits `{"agents_chain":["a"]}`. Starting from `a` → `ConfigException` (cycle) once `a` is
   revisited. Assert the exception type and that the message mentions a cycle. (Use throw
   mode to assert the type directly.)
5. **Depth limit:** build a linear chain longer than `kMaxChainDepth` (e.g. agents `n0..n6`
   each delegating to the next). Starting the chain → `ConfigException` mentioning the depth
   limit. (Keep names unique so the cycle guard doesn't trip first.)
6. **Chain step is not offered the chain option again:** the `_PromptBuilder` omits the
   `agents_chain` instruction when `isPartOfChain`. Assert a chained agent's prompt does
   **not** contain `agents_chain` (inspect the downstream FakeLLM prompt).

## Step-by-step implementation
1. Create `agent_loop_test.dart`; implement cases 1–15 using `buildAgent` + `FakeLLM`
   scripts. Reuse `userMsg`/`okTool` fixtures.
2. Create `agent_chaining_test.dart`; implement cases 1–6 with multiple agents in one scope.
3. Always `scope = AgentScope()` in `setUp` (or `tearDown(() => scope.clear())`) so tests
   don't leak agents across each other.
4. For type-precise assertions, prefer `FailureMode.throwError` and `throwsA(isA<...>())`;
   for the graceful path, assert `res.isError == true` and `res.content == kLLMResponseOnFailure`.
   Note: `kLLMResponseOnFailure` is package-internal — assert on the literal string or import
   it via `package:agenix/src/static/_pkg_constants.dart` in the test.
5. Where a test inspects the prompt, read from `fakeLLM.prompts[index]` and use `contains`.
6. Run `flutter test test/agent`; `flutter analyze` clean.

## Acceptance criteria
- The loop is proven for: direct response, single tool + synthesis, multi-step loop,
  reason-over-data, max-iteration fallback, parse-retry recovery, and unparseable-after-retry.
- Both `FailureMode` branches and the `onError` callback are proven.
- Save-after-success is proven (failed turns persist nothing; successful turns persist
  user+agent in order, no duplication).
- `rawData` first-call-only and `memoryLimit` forwarding are proven.
- Chaining is proven for hand-off, unknown-agent, cycle detection, depth limit, and the
  "no chain option when chained" rule.
- All tests pass offline; `flutter analyze` clean.

## Related docs
- [02 — fakes and fixtures](02-fakes-and-fixtures.md)
- [05 — scope tests](05-unit-tests-tools-registry-scope.md)
- [06 — datastore tests](06-unit-tests-datastores.md)
- improvements [07 — agentic loop](../improvements/07-agentic-loop-and-answer-verification.md)
- improvements [08 — agent chaining](../improvements/08-agent-chaining.md)
- improvements [03 — error handling](../improvements/03-error-handling-and-exceptions.md)
