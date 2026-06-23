# 07 — Native Function Calling (Advanced)

## Summary
Agenix decides tool use by asking the model to emit a JSON object in its text
(`{"tools": "...", "parameters": {...}}`) and then recovering it with `PromptParser`
(fence-stripping, first-`{`-to-last-`}` extraction). Every modern LLM API instead offers
**native function/tool calling**: you declare tools as a schema, the model returns a
*structured* tool-call object the SDK parses for you, with constrained decoding that all but
eliminates malformed output. Moving to native function calling is the biggest reliability
upgrade available to the LLM layer — but it's also the deepest change, so it's last and marked
**advanced/optional**.

## Severity & impact
**Medium (high reliability upside, high effort).** The current prose-JSON approach works, but
its fragility is exactly why `PromptParser` needs heroics and why `_llmGenerateWithParseRetry`
exists. Native calling makes tool selection robust and reduces wasted round-trips. It is a
generation-defining difference between Agenix and current-gen frameworks.

## Affected files
- `lib/src/llm/llm.dart` (new capability surface for tool declarations + tool-call results)
- `lib/src/llm/_gemini.dart`, `_openai.dart`/`_claude.dart` (map to each API's tool spec)
- `lib/src/tools/tool.dart`, `param_spec.dart` (already close to a JSON schema — formalize it)
- `lib/src/agent/agent.dart` (the loop branches on structured tool calls, not parsed prose)
- `lib/src/tools/_parser.dart` (becomes a fallback for providers/models without native tools)

## Why this is a good fit for Agenix
`ParameterSpecification` already carries `name`, `type`, `description`, `required`,
`enumValues`, `defaultValue` — that is essentially a JSON-Schema property. `Tool` already has
`name`, `description`, `parameters`. So Agenix can emit a standard function/tool schema with
very little new modeling. `validateParams` remains useful as a defense-in-depth check on the
arguments the model returns.

## Target design

### 1. A neutral tool-schema + tool-call contract
Add neutral types the adapters translate per provider:
```dart
/// What the model is told it can call (built from registered Tools).
class LlmToolSpec {
  final String name;
  final String description;
  final Map<String, dynamic> jsonSchema; // {type:object, properties:{...}, required:[...]}
  const LlmToolSpec({required this.name, required this.description, required this.jsonSchema});
}

/// What the model asks to call.
class LlmToolCall {
  final String id;          // provider call id (for submitting results back)
  final String name;
  final Map<String, dynamic> arguments;
  const LlmToolCall({required this.id, required this.name, required this.arguments});
}

/// The model's turn: either text, or one/more tool calls.
class LlmTurn {
  final String? text;
  final List<LlmToolCall> toolCalls;
  final LlmUsage? usage;
  const LlmTurn({this.text, this.toolCalls = const [], this.usage});
}
```

### 2. A capability-aware `generate`
Add an overload that accepts tool specs and prior tool results, returning an `LlmTurn`:
```dart
Future<LlmTurn> generateWithTools({
  required String prompt,
  String? systemInstruction,
  List<LlmToolSpec> tools = const [],
  List<LlmToolResult> priorResults = const [], // for multi-step submit-results loops
  Uint8List? rawData,
  String mimeType = 'image/jpeg',
});
```
Keep the existing `generate`/`generateStream` for plain text. Adapters that can't do native
tools fall back to: call `generate`, run `PromptParser`, and synthesize an `LlmTurn` (so the
agent code path is uniform).

### 3. Provider mapping
- **Gemini:** `Tool(functionDeclarations: [...])` + `FunctionDeclaration(name, description,
  parameters: Schema.object(...))`. The response contains `FunctionCall` parts; map to
  `LlmToolCall`. Submit results as `FunctionResponse` parts.
- **OpenAI-compatible:** `tools: [{type:'function', function:{name, description, parameters}}]`;
  response `choices[0].message.tool_calls[]`; submit results as
  `{role:'tool', tool_call_id, content}` messages.
- **Claude:** `tools: [{name, description, input_schema}]`; response `content` blocks of
  `type:'tool_use'`; submit results as `tool_result` content blocks.

### 4. Build schemas from `Tool`
Add `LlmToolSpec Tool.toLlmToolSpec()` (or a builder) that turns `parameters` into JSON
Schema:
```dart
Map<String, dynamic> _schema(List<ParameterSpecification> ps) => {
  'type': 'object',
  'properties': {
    for (final p in ps) p.name: {
      'type': p.type,
      'description': p.description,
      if (p.enumValues != null) 'enum': p.enumValues,
    }
  },
  'required': [for (final p in ps) if (p.required) p.name],
};
```

### 5. Agent loop on structured calls
Refactor `_generateResponse` so that, when the LLM supports native tools, the loop:
1. Calls `generateWithTools(tools: registry→specs, priorResults: ...)`.
2. If `turn.toolCalls` is non-empty → run them via `ToolRunner` (still validate args with
   `validateParams` as defense-in-depth), then submit results and loop (bounded by
   `kMaxToolIterations`).
3. If `turn.text` is set → that's the final answer.
The prose-JSON path (`PromptParser`) remains as the fallback branch for providers without
native tools, so nothing regresses.

### 6. Agent chaining
`agents_chain` has no native-API analogue (it's an Agenix concept). Keep it as a prose-JSON
instruction, OR model "delegate to agent X" as a special built-in tool the model can call.
The built-in-tool approach is cleaner with native calling — consider it, but it's optional.

## Step-by-step implementation
1. Add the neutral types (`LlmToolSpec`, `LlmToolCall`, `LlmToolResult`, `LlmTurn`); export.
2. Add `Tool.toLlmToolSpec()` building JSON Schema from `ParameterSpecification`.
3. Add `generateWithTools` to `LLM` with a **default fallback** implementation that uses
   `generate` + `PromptParser` so existing/custom providers keep working.
4. Implement `generateWithTools` natively in Gemini (and OpenAI/Claude if present).
5. Refactor the agent loop to prefer the structured path; keep the prose path as fallback.
6. Keep `validateParams` as an arguments check on returned tool calls.
7. Tests (see `../tests/`):
   - `Tool.toLlmToolSpec()` produces correct JSON Schema (types, required, enum).
   - Default fallback `generateWithTools` maps a `PromptParser` tool result into an `LlmTurn`.
   - Gemini/OpenAI adapter (mock client/model) returns a tool-call → mapped to `LlmToolCall`;
     submitting results continues the loop; final text ends it.
   - Agent end-to-end with a fake that returns structured tool calls behaves like the
     prose-JSON path (same observable result), proving parity.
8. `flutter analyze` clean; `flutter test` green.

## Acceptance criteria
- Tools can be declared to the model as native function/tool schemas built from `Tool`.
- The agent loop acts on structured tool calls when the provider supports them, falling back
  to the prose-JSON contract otherwise — no regression for existing providers.
- `validateParams` still guards tool arguments.
- Native function calling is covered by tests for at least Gemini (and any second provider).

## Related docs
- [01 — generation config](01-generation-config-and-system-instruction.md) (JSON mode is the lighter cousin of this)
- [06 — second provider](06-provider-abstraction-and-second-provider.md) (per-provider tool mapping)
- improvements [02 — structured output & parsing](../improvements/02-structured-output-and-robust-parsing.md) (the prose-JSON fallback this supersedes)
- improvements [06 — tool validation](../improvements/06-tool-validation-and-execution.md) (`validateParams` as defense-in-depth)
