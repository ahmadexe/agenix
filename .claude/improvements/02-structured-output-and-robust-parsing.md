# 02 — Structured Output & Robust Parsing

## Summary
The agent's entire control flow depends on the LLM returning a precise JSON shape, but it
**asks for JSON in prose** and then **parses it with brittle string surgery**. The parser
strips ```` ```json ```` fences with a regex, assumes `tools` is always a comma-delimited
*string*, assumes `agents_chain` is always a `List<String>`, and `throw`s `Exception` on
anything unexpected — which the agent's catch-all then converts into a generic failure
message. One malformed token from the model and the turn silently dies.

## Severity & impact
**High.** This is the most common real-world failure mode for LLM agents. Models wrap
JSON in prose, emit trailing commas, return `"tools": ["a","b"]` instead of
`"tools": "a, b"`, or add a markdown fence. Each of those currently crashes the turn.

## Affected files
- `lib/src/tools/_parser.dart` (entire file)
- `lib/src/llm/_gemini.dart` (enable native JSON output — see doc 01)
- `lib/src/agent/_prompt_builder.dart` (the output-format spec, lines 53–83)
- `lib/src/agent/agent.dart` (consumes `PromptParserResult`, lines 125–203)

## Current behavior
`lib/src/tools/_parser.dart`:
```dart
Map<String, dynamic> _tryJsonDecode(String data) {
  try {
    data = data.replaceFirst(RegExp(r'```json'), '');
    data = data.replaceFirst(RegExp(r'```'), '');
    return json.decode(data);
  } catch (e) {
    throw Exception("Invalid JSON output from LLM: $e");
  }
}
```
```dart
if (parsed.containsKey("agents_chain")) {
  agentNames: (parsed["agents_chain"] as List<dynamic>).cast<String>(), // crashes if not a list
}
...
} else if (parsed.containsKey("tools")) {
  final tools = (parsed["tools"] as String).split(',')... // crashes if model returns a JSON array
}
...
} else {
  throw Exception("Unrecognized format"); // becomes generic failure upstream
}
```
Also `Agent._loadSystemData` does `return json.decode(raw);` typed as
`Map<String, dynamic>` — if the asset's root is not an object, this is a runtime cast
failure at startup.

## Target design

### 1. Make the model emit JSON natively
In the Gemini adapter (doc 01), set
`GenerationConfig(responseMimeType: 'application/json')` when `config.jsonMode` is true.
Better still, supply a **response schema** (`responseSchema:` via `Schema.object({...})`)
that encodes the three valid shapes' superset, so the model is constrained at decode time.
This eliminates ~90% of fence/prose problems before parsing.

### 2. Make the parser defensive and total
Rewrite `PromptParser` so it **never throws on shape variance** and instead returns a
typed result, including an explicit "could not parse" outcome the agent can act on
(retry, see doc 07).

Key robustness rules:
- **Strip fences safely:** match ```` ```json ... ``` ```` or ```` ``` ... ``` ```` and
  extract the inner block; if no fence, use the whole string. Use a global, multiline
  regex, not `replaceFirst`.
- **Extract the first balanced JSON object** if there's leading/trailing prose: scan from
  the first `{` to its matching `}`.
- **Accept `tools` as either** a `String` (`"a, b"`) **or** a `List` (`["a","b"]`).
  Normalize to `List<String>`.
- **Accept `agents_chain` as either** a `List` or a single `String`. Normalize.
- **Tolerate missing `parameters`** (default `{}` per tool — already done) and
  non-map parameter values (coerce/skip with a recorded warning).
- On total failure, return `PromptParserResult.unparseable(rawText)` instead of throwing.

### 3. Add a parse-status to the result
Extend `PromptParserResult` with an enum, e.g.:
```dart
enum ParseOutcome { response, tools, agentsChain, unparseable }
```
so `Agent` can branch on intent explicitly instead of inferring from empty lists
(`if (parsed.agentNames.isEmpty && parsed.toolNames.isEmpty)` is implicit and fragile).

## Step-by-step implementation
1. **Schema/JSON mode (adapter):** In `Gemini`, build `GenerationConfig` with
   `responseMimeType: 'application/json'`. Optionally define a `responseSchema`. Verify
   against the installed `google_generative_ai` version's API (`Schema.object`,
   `Schema.string`, `Schema.array`).
2. **Rewrite `_tryJsonDecode`** as `Map<String, dynamic>? _extractJson(String raw)`:
   - Trim; remove fences via `RegExp(r'```(?:json)?', multiLine: true)`.
   - If `json.decode` fails, fall back to substring between first `{` and last `}` and
     retry.
   - Return `null` on total failure (do not throw).
3. **Add `ParseOutcome`** to `_parser.dart` and set it in every branch.
4. **Normalize `tools`:** accept `String` or `List`; if `String`, split on `,`. If
   `List`, `cast`/map `toString`. Trim and drop empties (existing behavior).
5. **Normalize `agents_chain`:** accept `List` or single `String`.
6. **Normalize parameters:** for each tool, `rawParamsMap[tool]` may be absent or not a
   map — coerce to `{}` and continue.
7. **Return `unparseable`** with the raw text instead of throwing `"Unrecognized format"`.
8. **Update `Agent._generateResponse`** to switch on `parsed.outcome`:
   - `response` → return text.
   - `tools` → run tools.
   - `agentsChain` → delegate.
   - `unparseable` → trigger the retry path (doc 07); if retries exhausted, surface a
     typed error (doc 03).
9. **Harden `_loadSystemData`:** validate that `json.decode(raw)` is a `Map` and throw a
   clear, typed config error (doc 03) if not, instead of an implicit cast crash.

## Acceptance criteria
- Feeding the parser each of these does **not** throw and yields the right outcome:
  - `` ```json\n{"response":"hi"}\n``` ``
  - `{"tools":["a","b"],"parameters":{"a":{}}}`
  - `{"tools":"a, b"}`
  - `{"agents_chain":"solo"}` and `{"agents_chain":["a","b"]}`
  - `Sure! {"response":"hi"} hope that helps` (prose-wrapped)
  - `not json at all` → `unparseable`
- The agent retries on `unparseable` rather than emitting a generic failure on the first
  bad token.
- Gemini requests run with `responseMimeType: 'application/json'`.

## Related docs
- [01 — LLM settings](01-llm-settings-and-generation-config.md) (`responseMimeType`/schema)
- [03 — error handling](03-error-handling-and-exceptions.md) (typed parse/config errors)
- [07 — agentic loop & verification](07-agentic-loop-and-answer-verification.md) (retry on unparseable)
- [09 — prompt builder](09-prompt-builder.md) (output-format spec wording)
