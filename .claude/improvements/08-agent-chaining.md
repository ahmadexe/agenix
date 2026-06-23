# 08 — Agent Chaining

## Summary
Multi-agent delegation (`agents_chain`) works, but the wiring is fragile. Each chained
agent receives the **original user message** *and* a separately-passed `input` derived from
the previous agent's output via `Map.toString()` — so the next agent sees duplicated,
partly-stringified context. There is no cycle detection (A→B→A loops forever / re-enters),
the hand-off payload is untyped text, a single missing agent aborts the whole chain with a
generic failure, and `memoryLimit` is forwarded but unused (doc 04). The orchestration
needs a clean, typed contract.

## Severity & impact
**Medium-High.** Chaining is a headline feature; in its current form it's hard to reason
about, easy to break, and unsafe against cyclic chains the model might emit.

## Affected files
- `lib/src/agent/agent.dart` (`_generateResponse` agent-chain block, lines 139–170)
- `lib/src/agent/_prompt_builder.dart` (chain-related instructions; `input` handling at
  lines 105–110; `isPartOfChain` branching)
- `lib/src/agent/_agent_registry.dart` (lookup; see doc 05 for scope)

## Current behavior
`agent.dart` lines 139–170:
```dart
while (agentsChain.isNotEmpty) {
  final agentName = agentsChain.removeAt(0);
  final agent = _AgentRegistry.instance.getAgent(agentName);
  if (agent == null) {
    return AgentMessage(content: kLLMResponseOnFailure, ...); // whole chain dies
  }
  agentResponse = await agent._generateResponse(
    convoId: convoId,
    userMessage: userMessage,      // ORIGINAL message handed to every agent
    ...
    isPartOfChain: true,
    input: inputForNextStep,       // PLUS the previous output, separately
  );
  inputForNextStep = agentResponse.data != null
      ? agentResponse.data!.toString()   // Map.toString hand-off
      : agentResponse.content;
}
return agentResponse!;
```
Problems:
1. **Double context:** `userMessage` (original) and `input` (prev output) both injected;
   the prompt builder appends `userMessage.content` again (doc 04 duplication compounds).
2. **Stringly hand-off:** `agentResponse.data!.toString()` loses structure.
3. **No cycle guard:** the model can emit `["a","b","a"]` or each agent could itself emit
   another chain (nested), risking unbounded recursion.
4. **All-or-nothing failure:** one unknown agent name → generic failure for the entire
   request.
5. **`memoryLimit`** is forwarded but unused (doc 04).

## Target design

### 1. Typed hand-off payload
Define a small `AgentHandoff { String? text; Map<String, dynamic>? data; String fromAgent; }`
passed between steps. Serialize `data` as JSON when rendering into the next prompt (never
`Map.toString`). The downstream agent's prompt clearly separates "original user goal" from
"input produced by previous agent (`fromAgent`)".

### 2. One source of truth for the user goal
Pass the original goal **once** (e.g. as an immutable `goal` string), and the evolving
hand-off separately. The prompt builder should render the goal once and the hand-off once,
with distinct labels — not re-inject `userMessage.content` on top (coordinate with doc 04).

### 3. Cycle & depth protection
- Track a `Set<String> visited` (or an ordered path) across the chain and a `maxChainDepth`.
- If the model proposes an already-visited agent or exceeds depth, stop and either return
  the best result so far or a typed `AgentChainException`.
- Decide whether chained agents may themselves spawn sub-chains; if yes, propagate the
  visited-set/depth; if no, set `isPartOfChain=true` to suppress further chaining (current
  code already suppresses chain output for `isPartOfChain`, so make that explicit and
  intentional).

### 4. Graceful handling of a missing agent
A missing agent in the chain should raise `AgentNotFoundException` (doc 03) with the name,
handled by the failure policy — not a silent generic message. Optionally allow "skip and
continue" as a configurable policy.

### 5. Use the scope, not the global
Resolve agents from the agent's `AgentScope` (doc 05), not `_AgentRegistry.instance`.

## Step-by-step implementation
1. Define `AgentHandoff` (internal is fine; export only if consumers need it).
2. Refactor the chain loop in `_generateResponse`:
   - Maintain `visited` + `depth`; check before each step.
   - Resolve via scope (doc 05); throw `AgentNotFoundException` on miss (or skip per policy).
   - Call the sub-agent with `goal` + `AgentHandoff` instead of `userMessage` + stringified
     `input`.
   - Build the next `AgentHandoff` from the sub-agent's structured result (JSON-encode
     `data`).
3. Update `_PromptBuilder` to accept `goal` + optional `AgentHandoff` and render them with
   distinct, unambiguous labels; remove reliance on re-injecting `userMessage.content` in
   chain mode (doc 04).
4. Add `maxChainDepth` to config/constants; thread `memoryLimit` through properly (doc 04).
5. Fold this delegate logic into the agentic loop from doc 07 (the chain case is one branch
   of the loop).
6. Tests with fake agents/LLM: (a) A→B linear hand-off preserves structured data, (b)
   A→B→A cycle is stopped, (c) depth cap enforced, (d) missing agent → typed error/skip per
   policy.

## Acceptance criteria
- A downstream agent receives the previous agent's output as structured JSON plus the
  original goal exactly once — no duplicated user turn.
- A cyclic or over-deep chain terminates deterministically with a typed error or
  best-effort result, never infinite recursion.
- A missing agent name produces `AgentNotFoundException` (or a configured skip), not a
  blanket generic failure.
- Agent resolution goes through the scope from doc 05.

## Related docs
- [04 — memory management](04-memory-management.md) (the duplication this compounds)
- [05 — agent registry lifecycle](05-agent-registry-lifecycle.md) (scoped lookup)
- [07 — agentic loop](07-agentic-loop-and-answer-verification.md) (chaining as a loop branch)
- [09 — prompt builder](09-prompt-builder.md) (goal vs hand-off labeling)
