# 05 — Agent Registry Lifecycle

## Summary
`_AgentRegistry` is a **process-global mutable singleton** that every `Agent.create()`
auto-registers into, and `registerAgent` **throws** if an agent with the same name already
exists. There is **no `unregisterAgent`**, no `clear`, and no way to scope a set of agents.
The practical consequences: calling `Agent.create()` twice with the same name crashes
(Flutter hot-restart, re-navigation, re-login, tests run in sequence — all hit this), two
independent agent "worlds" can't coexist in one app, and tests become order-dependent and
leaky. This is the "singleton that shouldn't be a hidden global" problem.

## Severity & impact
**High.** A framework whose "create an agent" call can throw on the second invocation is
not safe for real app lifecycles. The hidden global also makes the prompt builder's
"Agents in the System" list non-deterministic across the app.

## Affected files
- `lib/src/agent/_agent_registry.dart` (entire file; note `getAllAgents` and `hasAgent`
  exist but no `unregister`/`clear`)
- `lib/src/agent/agent.dart` (`Agent.create` auto-registers at line 65; chaining looks up
  via `_AgentRegistry.instance` at line 145)
- `lib/src/agent/_prompt_builder.dart` (reads `_AgentRegistry.instance.getAllAgents()` at
  line 28)

## Current behavior
`_agent_registry.dart`:
```dart
void registerAgent(Agent agent) {
  if (hasAgent(agent.name)) {
    throw Exception('Agent with name ${agent.name} already exists...');
  }
  _agents[agent.name] = agent;
}
// no unregisterAgent, no clear
```
`agent.dart`:
```dart
_AgentRegistry.instance.registerAgent(agent); // unconditional, throws on dup
```
There is no public way to remove an agent, so the only recovery from a duplicate is a full
process restart.

## Target design
Two complementary fixes; do at least #1 and #2.

### 1. Lifecycle methods + idempotent/explicit registration
- Add `unregisterAgent(String name)` and `clear()` to the registry.
- Add `Agent.dispose()` that unregisters the agent (and releases any resources).
- Decide duplicate policy explicitly via a parameter on `Agent.create`:
  `RegistrationPolicy { throwIfExists, replace, ignore }` (default `throwIfExists` to keep
  current contract, but make `replace` available for hot-restart/re-login flows).

### 2. Make the registry injectable / scoped (kill the hidden global)
- Introduce a public `AgentScope` (or `AgentRegistry`) object that owns a `Map<String,
  Agent>`. `Agent.create({AgentScope? scope})` registers into the given scope, defaulting
  to a shared `AgentScope.global` for backward compatibility.
- The prompt builder and chaining should consult the **agent's own scope**, not a hardcoded
  global singleton. Store a reference to the scope on the `Agent` so
  `_PromptBuilder`/chaining can reach it via the part-of relationship.
- This lets an app (or a test) build an isolated set of agents that can chain among
  themselves without colliding with anything else in the process.

### 3. Fix the doc/wording bugs while here
- `_agent_registry.dart` copy is wrong ("should be called whenever developers make a new
  **tool**", "list all available **tools**", parameter named `toolName` in `hasAgent`).
  Correct to agent terminology.

## Step-by-step implementation
1. **Registry**: add `unregisterAgent(String name)`, `clear()`, and rename the misleading
   `toolName` parameter in `hasAgent` to `agentName`. Fix the doc comments.
2. **Scope (recommended)**: create a public `AgentScope` class wrapping the map and the
   register/unregister/get/getAll APIs. Provide `AgentScope.global`. Move the
   singleton's storage into it. Export `AgentScope` from the barrel if you want consumers
   to create isolated scopes.
3. **Agent.create**: add `{AgentScope? scope, RegistrationPolicy policy =
   RegistrationPolicy.throwIfExists}`. Resolve `scope ??= AgentScope.global`. Apply the
   policy:
   - `throwIfExists` → current behavior.
   - `replace` → overwrite existing.
   - `ignore` → keep existing, return the new instance unregistered or the existing one
     (pick one and document it).
   Store the resolved `scope` on the agent.
4. **Chaining** (`_generateResponse`): look up via the agent's `scope.getAgent(name)`
   instead of `_AgentRegistry.instance.getAgent(name)`.
5. **Prompt builder**: list agents from the agent's `scope`, not the global singleton. Pass
   the scope into `_PromptBuilder` (it's a `part of agent.dart`, so it can read it from the
   enclosing `Agent`, or accept it in its constructor).
6. **Agent.dispose**: unregister from its scope. Document that apps should dispose agents
   they recreate (e.g. on logout/hot-restart) — or use `RegistrationPolicy.replace`.
7. **Tests**: add a `tearDown` that calls `scope.clear()` (or use a fresh scope per test)
   to guarantee isolation.

## Acceptance criteria
- Creating two agents with the same name no longer crashes when using
  `RegistrationPolicy.replace` (or after `dispose`/`unregister`).
- Two `AgentScope`s can each hold an agent named `"router"` without colliding.
- Chaining and the "Agents in the System" prompt list reflect the agent's own scope.
- Tests can fully reset registry state between cases.
- No remaining references to `_AgentRegistry.instance` outside the scope abstraction.

## Related docs
- [08 — agent chaining](08-agent-chaining.md) (lookup + cycle detection use the scope)
- [09 — prompt builder](09-prompt-builder.md) ("Agents in the System" listing)
- [11 — datastore robustness & testability](11-datastore-robustness-and-testability.md) (test isolation patterns)
