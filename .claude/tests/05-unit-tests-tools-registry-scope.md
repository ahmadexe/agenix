# 05 — Unit Tests: Tool Registry, Tool Runner & Agent Scope

## Summary
Three small stateful classes coordinate tool/agent lookup: `ToolRegistry` (per-agent tool
map), `ToolRunner` (validates params then executes tools, raising typed exceptions), and
`AgentScope` (the injectable replacement for the old global singleton, with a
`RegistrationPolicy`). Their behavior — especially the typed-exception and policy paths — is
contract the rest of the system depends on.

## Scope & priority
**High.** `ToolRunner` is where validation meets execution and where `ToolNotFoundException`
/ `ToolExecutionException` originate. `AgentScope` is the isolation primitive that makes
every other agent test deterministic.

## Files under test
- `lib/src/tools/tool_registry.dart`
- `lib/src/tools/_tool_runner.dart`
- `lib/src/agent/agent_scope.dart`

## Files to create
- `test/tools/tool_registry_test.dart`
- `test/tools/tool_runner_test.dart`
- `test/agent/agent_scope_test.dart`

## Test design — `ToolRegistry` (`tool_registry_test.dart`)
Contract: `registerTool` throws `ConfigException` on duplicate name; `getTool` returns null
when absent; `hasTool`/`getAllTools`/`unregisterTool` behave as named.

Cases:
1. Register then `getTool(name)` returns the same instance; `hasTool` true.
2. `getTool` for an unknown name returns `null`.
3. Duplicate registration throws `ConfigException` (assert the type, not a bare `Exception`).
4. `unregisterTool` removes it; subsequent `getTool` → null; re-registering then succeeds.
5. `getAllTools` returns all registered tools (length + membership).
6. `unregisterTool` of an absent name is a no-op (no throw).

```dart
import 'package:agenix/agenix.dart';
import 'package:agenix/src/tools/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/spy_tool.dart';

void main() {
  group('ToolRegistry', () {
    late ToolRegistry reg;
    setUp(() => reg = ToolRegistry());

    test('registers and retrieves a tool', () {
      final t = SpyTool(name: 'weather');
      reg.registerTool(t);
      expect(reg.getTool('weather'), same(t));
      expect(reg.hasTool('weather'), isTrue);
    });

    test('throws ConfigException on duplicate name', () {
      reg.registerTool(SpyTool(name: 'dup'));
      expect(() => reg.registerTool(SpyTool(name: 'dup')),
          throwsA(isA<ConfigException>()));
    });

    test('unregister removes the tool', () {
      reg.registerTool(SpyTool(name: 'x'));
      reg.unregisterTool('x');
      expect(reg.getTool('x'), isNull);
    });
  });
}
```
> `ToolRegistry` is in a non-`part` file, so import it directly:
> `import 'package:agenix/src/tools/tool_registry.dart';`. `Tool`, `ToolResponse`,
> `ConfigException` come from the barrel.

## Test design — `ToolRunner` (`tool_runner_test.dart`)
Contract (from source): for each tool name in the `PromptParserResult`:
- unknown tool → `ToolNotFoundException`,
- params fail validation → `ToolExecutionException` (message mentions validation),
- tool's `run` throws a non-Agenix error → wrapped in `ToolExecutionException` (cause set),
- tool's `run` throws an `AgenixException` → rethrown as-is,
- success → its `ToolResponse` collected; multiple tools run in order.

You'll construct a `PromptParserResult` directly (it's a plain class). Import the parser file
for the type.

Cases:
1. **Happy path single tool:** registry has `SpyTool('a')`; result names `['a']` with params
   → returns one `ToolResponse`; the spy recorded one call with the **validated** params.
2. **Validated params reach the tool:** spec has a `number` param sent as a string `'5'`;
   assert the spy received `5` (int/num), proving `validateParams` runs before `run`.
3. **Unknown tool:** result names `['ghost']`, registry empty → `throwsA(isA<ToolNotFoundException>())`.
4. **Validation failure:** tool requires param `q`; result omits it →
   `throwsA(isA<ToolExecutionException>())` and the message contains "validation".
5. **Tool throws generic error:** `SpyTool(throwError: true)` →
   `throwsA(isA<ToolExecutionException>())`; assert `.cause` is non-null.
6. **Tool throws AgenixException:** a tool whose `run` throws e.g. `DataStoreException` →
   that exact type propagates (not wrapped). Use a small inline `Tool` subclass.
7. **Multiple tools run in order:** names `['a','b']` → two responses in order; both spies
   called once.

```dart
import 'package:agenix/agenix.dart';
import 'package:agenix/src/tools/tool_registry.dart';
import 'package:agenix/src/tools/_tool_runner.dart';
import 'package:agenix/src/tools/_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/spy_tool.dart';

PromptParserResult toolCall(List<String> tools,
        [Map<String, Map<String, dynamic>> params = const {}]) =>
    PromptParserResult(
      outcome: ParseOutcome.tools,
      toolNames: tools,
      params: params,
      agentNames: const [],
    );

void main() {
  group('ToolRunner', () {
    late ToolRegistry reg;
    final runner = ToolRunner();
    setUp(() => reg = ToolRegistry());

    test('runs a registered tool and returns its response', () async {
      reg.registerTool(SpyTool(name: 'a'));
      final out = await runner.runTools(toolCall(['a']), reg);
      expect(out, hasLength(1));
      expect(out.first.toolName, 'a');
    });

    test('throws ToolNotFoundException for an unknown tool', () {
      expect(() => runner.runTools(toolCall(['ghost']), reg),
          throwsA(isA<ToolNotFoundException>()));
    });

    test('wraps a thrown error in ToolExecutionException with a cause', () async {
      reg.registerTool(SpyTool(name: 'boom', throwError: true));
      await expectLater(
        runner.runTools(toolCall(['boom']), reg),
        throwsA(isA<ToolExecutionException>()),
      );
    });
  });
}
```

## Test design — `AgentScope` (`agent_scope_test.dart`)
Contract: register/lookup/unregister/clear; `RegistrationPolicy.throwIfExists` (default)
throws `ConfigException`, `.replace` overwrites, `.ignore` keeps the original.

> `AgentScope.registerAgent(String name, Object agent, {policy})` types the agent as
> `Object` (because `Agent` is in a `part` file). For scope-only tests you can register any
> sentinel object (e.g. a `String` or a small marker class) — you do **not** need a real
> `Agent`. Real-agent registration is covered transitively in doc 07.

Cases:
1. Register + `getAgent` returns the same object; `hasAgent` true; `getAllAgents` includes it.
2. `getAgent` for unknown name → null.
3. Duplicate with default policy → `ConfigException`.
4. Duplicate with `RegistrationPolicy.replace` → second object wins.
5. Duplicate with `RegistrationPolicy.ignore` → first object retained, no throw.
6. `unregisterAgent` removes; re-register then succeeds.
7. `clear` empties the scope.
8. **Isolation:** two distinct `AgentScope` instances don't see each other's agents; and
   `AgentScope.global` is independent of a fresh `AgentScope()`.

## Step-by-step implementation
1. Create the three test files.
2. Use `SpyTool` for registry/runner tests; build `PromptParserResult` via a small helper.
3. For runner case 2, define a `ParameterSpecification(type:'number', ...)` and assert
   coercion happened by inspecting `SpyTool.calls.first`.
4. For runner case 6, write a tiny inline `Tool` whose `run` throws a `DataStoreException`.
5. For scope tests, register plain sentinel objects; assert identity with `same(...)`.
6. Run `flutter test test/tools test/agent/agent_scope_test.dart`; `flutter analyze` clean.

## Acceptance criteria
- `ToolRegistry`: dup→`ConfigException`, lookup/unregister/getAll proven.
- `ToolRunner`: not-found, validation-fail, generic-throw-wrapped (cause set),
  Agenix-throw-propagated, ordered multi-tool, and validated-params-reach-tool all proven.
- `AgentScope`: all three `RegistrationPolicy` branches, unregister, clear, and cross-scope
  isolation proven.
- Tests pass; `flutter analyze` clean.

## Related docs
- [02 — fixtures](02-fakes-and-fixtures.md) (`SpyTool`)
- [04 — validation tests](04-unit-tests-parser-and-validation.md) (validateParams unit, complementary)
- improvements [05 — agent registry lifecycle](../improvements/05-agent-registry-lifecycle.md)
- improvements [06 — tool validation & execution](../improvements/06-tool-validation-and-execution.md)
