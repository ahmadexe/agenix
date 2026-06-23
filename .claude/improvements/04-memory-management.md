# 04 — Memory Management

## Summary
`generateResponse` advertises a `memoryLimit` parameter (default 10), passes it down to
`_generateResponse`, and then **never uses it**. `_MemoryManager.getContext` loads the
**entire** message history for the conversation on every turn. As the conversation grows,
every request re-sends all prior messages, so token usage, latency, and cost grow without
bound until the model's context window overflows and the turn fails. On top of that, the
user message is effectively **duplicated** in the prompt, and failure messages get written
into history (see doc 03), polluting future context.

## Severity & impact
**High.** Unbounded context is a guaranteed production incident: cost creep, latency
creep, then a hard failure once history exceeds the window. The dead `memoryLimit` makes
it look configurable when it isn't.

## Affected files
- `lib/src/agent/agent.dart` (`memoryLimit` declared but unused: lines 82, 102, 156–158;
  context load at 108–111; user-message duplication via save+reload, see below)
- `lib/src/agent/_memory_manager.dart` (`getContext` ignores any limit; TODO at line 22)
- `lib/src/memory/data/data_store.dart` (`getMessages` has no limit/pagination)
- `lib/src/memory/data_sources/_firebase.dart` (`getMessages` fetches all docs)
- `lib/src/agent/_prompt_builder.dart` (renders full history into the prompt)

## Current behavior
- `Agent.generateResponse(... int memoryLimit = 10 ...)` → forwards `memoryLimit` to
  `_generateResponse`, which **never references it**.
- `_MemoryManager.getContext`:
  ```dart
  Future<List<AgentMessage>> getContext(String convoId, {Object? metaData}) async {
    // TODO: Generate efficient graph based context
    return await dataStore.getMessages(convoId, metaData: metaData); // ALL messages
  }
  ```
- `FirebaseDataStore.getMessages` does `ref.orderBy('generatedAt').get()` with no
  `.limit()` — full-collection read every turn (also a Firestore cost issue).
- **Duplication:** `generateResponse` saves the user message *first* (line 85), then
  `_generateResponse` reloads context (now containing that just-saved user message) **and**
  the prompt builder separately appends `userMessage.content` again at the end
  (`_prompt_builder.dart` lines 114/118). The model sees the user's turn twice.

## Target design

### 1. Make `memoryLimit` real
Thread the limit into `getContext` → `getMessages`. Fetch only the **most recent N**
messages (ordered ascending for the prompt, but selected as the latest N).

### 2. Add a token-aware budget (beyond a raw count)
A raw message count is a blunt instrument. Add an optional token/character budget:
- `MemoryPolicy { int maxMessages; int? maxChars; SummarizationStrategy summarize; }`
- When history exceeds the budget, either **truncate** (drop oldest) or **summarize**
  oldest-into-a-running-summary (see #4).

### 3. Fix the duplication
Pick one source of truth for the current user turn:
- **Recommended:** save the user message, then build context as "history *excluding* the
  current turn" + explicitly render the current user message once. Easiest concrete fix:
  in `generateResponse`, capture context **before** saving the user message, or have the
  prompt builder not re-append `userMessage.content` when it's already the last item in
  `memoryMessages`.
- Document the chosen invariant in code so it doesn't regress.

### 4. (Optional, higher-value) Rolling summarization
Replace the dropped-oldest messages with an LLM-generated running summary stored on the
conversation. This preserves long-range context without unbounded tokens. This is the
"graph/efficient context" TODO realized in a pragmatic form.

### 5. Pagination for retrieval APIs
`getMessages` and `getConversations` should support `limit` + a cursor/`startAfter` for UI
that lists history, independent of what the agent feeds the model.

## Step-by-step implementation
1. **DataStore interface** (`data_store.dart`): change
   `getMessages(String conversationId, {int? limit, Object? metaData})`. Add an optional
   cursor param if you want pagination now (e.g. `DateTime? before`).
2. **Firebase impl** (`_firebase.dart`): when `limit != null`, query
   `.orderBy('generatedAt', descending: true).limit(limit)` then reverse the list to
   ascending before returning (so the prompt reads oldest→newest). Keep ascending+no-limit
   behavior when `limit == null`.
3. **`_MemoryManager.getContext`**: accept `int? limit` (and optionally a `MemoryPolicy`)
   and pass it to `getMessages`. Apply char/token trimming after fetch if a budget is set.
4. **Agent**: pass `memoryLimit` into `getContext`. Remove the parameter from places where
   it's genuinely unused, or actually use it everywhere it's declared (it's currently dead
   in `_generateResponse` and forwarded uselessly through the agent chain).
5. **Fix duplication**: implement the chosen invariant from Target #3. Add a code comment
   stating "the current user turn is rendered exactly once."
6. **Coordinate with doc 03**: ensure error-flagged messages are excluded from
   `getContext` (filter them out, or never persist them).
7. **(Optional)** Implement rolling summarization: add `summary` to `Conversation`
   (serialization in doc 10), and a `_MemoryManager.summarizeIfNeeded` that compresses
   the oldest messages via `llm.generate` when over budget.
8. **(Optional)** Add a cursor to `getConversations`/`getMessages` for paginated UI.

## Acceptance criteria
- With `memoryLimit: 5`, only the last 5 messages are sent to the model (verify via a fake
  LLM that records the prompt).
- Firestore reads are bounded by the limit, not the full collection.
- The current user message appears exactly once in the constructed prompt.
- A long conversation (e.g. 1000 messages) produces a bounded prompt and does not error.
- Error/fallback messages never appear in the context window.

## Related docs
- [03 — error handling](03-error-handling-and-exceptions.md) (don't persist error messages)
- [09 — prompt builder](09-prompt-builder.md) (rendering history once)
- [10 — serialization](10-serialization-correctness.md) (adding `summary` to Conversation)
- [12 — dead arguments](12-dead-arguments-and-api-cleanup.md) (`memoryLimit` is the headline dead arg)
