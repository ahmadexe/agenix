# 12 — Dead Arguments & Public API Cleanup

## Summary
A collection of smaller, low-risk-but-important defects: parameters that are declared and
threaded through the call chain but never used, a method argument that is semantically
wrong, a hardcoded identifier, and spec fields that the docs claim are enforced but aren't.
Individually minor; together they make the public API misleading — callers configure things
that do nothing. Fixing them is mostly mechanical and improves trust in the surface.

## Severity & impact
**Low-Medium.** No crashes, but a misleading API ("I set `memoryLimit` / passed a
`conversationId` / defined a `defaultValue`… and nothing happened") is a real production
footgun and a documentation lie.

## Inventory of issues

### A. `memoryLimit` is dead (headline)
- `lib/src/agent/agent.dart` — `generateResponse(... int memoryLimit = 10 ...)` (line 82)
  forwards to `_generateResponse(... memoryLimit ...)` (line 102), which forwards it again
  in the chain (lines 156–158) but **never uses it**. → Either wire it (doc 04, preferred)
  or remove it. Do **not** leave it dead.

### B. `getAllConversations`/`getConversations` take a misleading `conversationId`
- `lib/src/agent/agent.dart` lines 225–233: `getAllConversations({required String
  conversationId, ...})` — listing *all* conversations should not require a single
  conversation's id.
- `lib/src/memory/data/data_store.dart` lines 32–35 and `_firebase.dart` lines 51–71: the
  `conversationId`/`convoId` param is accepted and **ignored** (the impl lists all docs).
  → Remove the parameter (breaking change — bundle into v5.0.0), or repurpose it as a
  cursor/filter if that was the intent.

### C. `modelId` is hardcoded
- `lib/src/llm/_gemini.dart` line 23: `String get modelId => 'gemini';` ignores the actual
  `modelName`. → Return the real model name (also doc 01). It's currently unused anywhere,
  so also decide whether the getter earns its place; if kept, make it accurate.

### D. `metaData` accepted but never used in the default store
- `_firebase.dart`: every method takes `Object? metaData` and ignores it. → Use it for
  user/tenant resolution (doc 11) or document clearly that the default store ignores it.

### E. `ParameterSpecification.defaultValue` / `enumValues` / `type` are decorative
- `lib/src/tools/param_spec.dart`: documented as used "to validate the parameters passed to
  the tool," but nothing validates. → Enforce them (doc 06) or correct the documentation to
  say they are only surfaced to the LLM in the prompt.

### F. `ToolResponse.data` "later versions" + mutable flag
- `lib/src/tools/tool_response.dart` line 22: comment says `data` "will be used for chaining
  responses in later versions" — it **is** used now (agent chaining + `_reasonUsingData`).
  Update the comment. `needsFurtherReasoning` is a non-`final` field on an otherwise
  value-style class → make it `final` (doc 10).

### G. `ToolRunner` dead branch
- `lib/src/tools/_tool_runner.dart` lines 21–23: `if (result.params[toolName] == null)
  throw...` is unreachable because the parser always inserts a `{}` per tool (doc 02). →
  Remove (doc 06).

### H. Misleading class doc comments
- `tool_registry.dart` lines 3–6 call `ToolRegistry` a "singleton" — it's intentionally
  instance-per-agent. `_agent_registry.dart` comments reference "tools" instead of
  "agents" and name a param `toolName` in `hasAgent`. → Correct the docs/naming (doc 05).

## Step-by-step implementation
1. **memoryLimit** — implement via doc 04, or delete from `generateResponse`,
   `_generateResponse`, and the chain call. (Prefer implement.)
2. **conversationId arg** — remove from `Agent.getAllConversations`,
   `DataStore.getConversations`, and `FirebaseDataStore.getConversations` (and the
   in-memory store from doc 11). Note the breaking change in the CHANGELOG.
3. **modelId** — return the stored `modelName` (doc 01).
4. **metaData** — wire into `_resolveUserId` (doc 11) or document the no-op.
5. **param spec fields** — enforce via the validator (doc 06) or fix the doc comment.
6. **ToolResponse** — fix the `data` comment; make `needsFurtherReasoning` `final` (doc 10).
7. **ToolRunner** — delete the dead null-params branch (doc 06).
8. **Doc comments** — fix `ToolRegistry` "singleton" wording and `_AgentRegistry`
   tool/agent mix-ups + `hasAgent(toolName)` param name (doc 05).
9. Run `flutter analyze` and resolve any "unused parameter"/lint findings surfaced by the
   cleanup.

## Acceptance criteria
- No parameter in the public API is accepted-but-ignored without an explicit, documented
  reason.
- `modelId` reflects the configured model.
- Doc comments accurately describe the classes (no "singleton" lie, no tool/agent mix-up).
- `flutter analyze` is clean.
- Breaking removals are captured in the CHANGELOG with migration notes for v5.0.0.

## Related docs
- [01](01-llm-settings-and-generation-config.md) (modelId) ·
  [04](04-memory-management.md) (memoryLimit) ·
  [06](06-tool-validation-and-execution.md) (param enforcement, dead branch) ·
  [10](10-serialization-correctness.md) (final field) ·
  [11](11-datastore-robustness-and-testability.md) (metaData, conversationId arg)
