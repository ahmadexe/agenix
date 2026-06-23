# 06 — Tool Validation & Execution

## Summary
The tool subsystem advertises rich parameter specifications (`required`, `defaultValue`,
`enumValues`, `type`) but **none of it is enforced**. Parameters are passed to `tool.run`
exactly as the LLM emitted them — no type coercion, no required-field check, no enum
validation, no default injection. Meanwhile the prompt builder force-unwraps each parameter
spec (`e!`) even though the list element type is **nullable** (`List<ParameterSpecification?>?`),
so a single `null` entry crashes prompt construction. Tool failures throw bare exceptions
that get swallowed upstream (doc 03).

## Severity & impact
**Medium-High.** "Validation" that doesn't validate is worse than none — it gives a false
sense of safety. Tools receive unvalidated, possibly mistyped params from a stochastic
model, and a malformed spec list crashes the whole turn before the LLM is even called.

## Affected files
- `lib/src/tools/param_spec.dart` (`defaultValue`, `enumValues`, `type`, `required` —
  declared, never enforced)
- `lib/src/tools/tool.dart` (`parameters` is `List<ParameterSpecification?>?` — doubly
  nullable for no reason; `run` takes a raw untyped map)
- `lib/src/tools/_tool_runner.dart` (no validation; bare `throw Exception`; dead null-check)
- `lib/src/agent/_prompt_builder.dart` (line 46: `tool.parameters?.map((e) => e!.toJson())`
  — force-unwraps a nullable element)
- `lib/src/tools/tool_registry.dart` (fine, but see naming note below)

## Current behavior
`_prompt_builder.dart` line 46:
```dart
"Parameters: ${tool.parameters?.map((e) => e!.toJson())}" // e! crashes if any element is null
```
`_tool_runner.dart`:
```dart
final tool = registry.getTool(toolName);
if (tool == null) throw Exception("Tool $toolName not found in registry");
if (result.params[toolName] == null) throw Exception("No parameters provided..."); // dead: parser always supplies {}
final toolParams = result.params[toolName] ?? {};
final output = await tool.run(toolParams); // params never validated/coerced
```
`param_spec.dart` defines `required`, `defaultValue`, `enumValues` and a `type` string, but
nothing anywhere reads them for validation; `toJson` only serializes them into the prompt.

## Target design

### 1. Make the parameter list non-nullable elements
Change `Tool.parameters` from `List<ParameterSpecification?>?` to
`List<ParameterSpecification> parameters` (default `const []`). There is no legitimate
reason to allow a `null` spec inside the list. This removes the `e!` hazard entirely.

### 2. Build a real validator
Create `lib/src/tools/_param_validator.dart` with a function that, given a
`List<ParameterSpecification>` and the raw `Map<String, dynamic>` from the LLM, returns a
validated/normalized map **or** a structured validation error:
- **Required check:** every `required` param must be present (and non-null/non-empty).
- **Enum check:** if `enumValues != null`, the value must be one of them.
- **Type coercion:** coerce to the declared `type` (`'number'` → `num.tryParse`,
  `'boolean'` → parse `"true"/"false"`, `'string'` → `toString`, `'object'`/`'array'`
  → ensure shape). Reject (or coerce) mismatches deterministically.
- **Default injection:** if a param is absent and `defaultValue != null`, inject it.
- Ignore/strip unknown params not in the spec (or surface a warning), to prevent
  prompt-injected extra fields from reaching tools.

### 3. Decide what a validation failure does
Prefer **feeding the error back to the model** (one corrective turn — see doc 07) so it can
re-ask the user or fix the params, rather than throwing. If retries are exhausted, throw
`ToolExecutionException`/a validation-specific subtype (doc 03).

### 4. Harden tool execution
- Wrap `await tool.run(...)` in try/catch and rethrow as `ToolExecutionException` with the
  tool name + cause + stack (doc 03), so a buggy user tool is attributable.
- Remove the dead `result.params[toolName] == null` branch (the parser always provides a
  map per tool — see doc 02).

## Step-by-step implementation
1. **Type fix**: in `tool.dart`, change `parameters` to
   `final List<ParameterSpecification> parameters;` with a default of `const []` in the
   constructor. Update `_prompt_builder.dart` line 46 to drop the `?`/`!`:
   `tool.parameters.map((e) => e.toJson()).toList()`.
2. **Validator**: implement `_param_validator.dart` per Target #2. Return a small result
   type, e.g. `({Map<String, dynamic> values, List<String> errors})`.
3. **Tool runner**: before calling `tool.run`, run the validator using `tool.parameters`.
   - If `errors` is non-empty → return the validation feedback to the agent loop (doc 07)
     or throw a typed validation exception if no loop is in place yet.
   - Else call `tool.run(validatedValues)` inside try/catch → `ToolExecutionException`.
   - Delete the dead null-params branch.
4. **Registry naming** (minor): `tool_registry.dart`'s class doc claims it's a singleton
   ("The ToolRegistry is a singleton class") but it's intentionally **instance-level, one
   per agent**. Fix the misleading doc comment.
5. **Tests**: add unit tests for the validator (missing required, bad enum, type coercion,
   default injection, unknown-field stripping) and for a tool that throws.

## Acceptance criteria
- A `Tool` with a `null` element can no longer be constructed (compile-time), and prompt
  building never force-unwraps.
- Calling a tool without a required parameter produces a validation error path, not a
  silent pass-through of missing data.
- An `enumValues`-constrained param rejects out-of-set values.
- A `defaultValue` is injected when the model omits an optional param.
- A user tool that throws surfaces as `ToolExecutionException` attributing the tool.
- The dead `"No parameters provided"` branch is gone.

## Related docs
- [02 — parsing](02-structured-output-and-robust-parsing.md) (params come from the parser)
- [03 — error handling](03-error-handling-and-exceptions.md) (`ToolExecutionException`)
- [07 — agentic loop & verification](07-agentic-loop-and-answer-verification.md) (feed validation errors back to the model)
