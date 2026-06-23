# 09 — Prompt Builder Rewrite

## Summary
`_PromptBuilder.buildTextPrompt` constructs the control prompt by concatenating long prose
blocks. It has multiple correctness and quality problems: the system prompt map is injected
via `"$systemPrompt"` (Dart `Map.toString`, **not** JSON), the same content is repeated in
several near-duplicate instruction paragraphs, there are typos in operative instructions
("verrify", "hadnling", "infromation"), the user message is re-appended (duplication, doc
04), and everything is jammed into the user turn instead of using a real system instruction
(doc 01). The prompt is the agent's "program," and right now it's brittle and noisy.

## Severity & impact
**Medium-High.** Prompt quality directly controls whether the JSON contract holds and
whether tool/agent routing is correct. Map-stringification and typos measurably degrade
model compliance.

## Affected files
- `lib/src/agent/_prompt_builder.dart` (entire file, lines 14–123)
- `lib/src/agent/agent.dart` (call site, lines 113–118; system instruction split, doc 01)
- `lib/src/llm/llm.dart` / `_gemini.dart` (system-instruction channel, doc 01)

## Current behavior (specific defects)
1. **Line 24** — `buffer.writeln("System Instruction: $systemPrompt\n");` interpolates a
   `Map<String, dynamic>` with `toString`, producing `{key: value, ...}` (Dart syntax),
   not valid JSON. Should be `jsonEncode(systemPrompt)` and, better, delivered via the
   model's `systemInstruction` slot (doc 01), not the user turn.
2. **Lines 46** — `tool.parameters?.map((e) => e!.toJson())` force-unwrap (see doc 06) and
   prints a lazy `Iterable` via `toString` (no `.toList()`), yielding `(... , ...)`-style
   output.
3. **Lines 101–119** — several overlapping mega-paragraphs restate the same rules with
   ALL-CAPS emphasis; contains typos: "verrify" (line 114), "hadnling" (line 97),
   "infromation"/"paramter" (lines 102/108). Typos in instructions reduce compliance.
4. **Lines 112–119** — re-appends `userMessage.content` (duplication; doc 04).
5. The whole control protocol is inlined as text; there's no single canonical schema spec
   shared with the parser (doc 02).

## Target design

### 1. Split system vs. turn content
Move static framing (role, output contract, rules) into the **system instruction**
(`systemInstruction` channel, doc 01). The user turn carries only: recent history (once),
available tools, available agents, optional hand-off input, and the current user message
(once).

### 2. Emit JSON, not `Map.toString`
- `jsonEncode(systemPrompt)` everywhere a structured object is rendered.
- Tools: build a JSON array of `{name, description, parameters}` via `jsonEncode`, not
  string interpolation of an `Iterable`.

### 3. One canonical, de-duplicated instruction block
Collapse the repeated paragraphs into a single, ordered, typo-free spec:
- The exact JSON output shapes (kept in sync with the parser/schema from doc 02 — ideally
  generated from one shared source so they can't drift).
- Tool rules (ask only for missing **required** params; never name the tool; explain why).
- Agent rules (when to chain).
- Determinism reminder ("reply with ONLY the JSON object, no prose, no fences").

### 4. Render history and the user turn exactly once
Coordinate with doc 04: either history already includes the current turn (then don't
re-append) or it doesn't (then append once). Make the invariant explicit.

### 5. Make the builder testable
`buildTextPrompt` should be a pure function of its inputs (it already mostly is, except it
reaches into the global `_AgentRegistry` at line 28 — route that through the agent's scope,
doc 05). Pure inputs → snapshot tests on the produced prompt.

## Step-by-step implementation
1. Introduce a `buildSystemInstruction()` returning the static framing + JSON-encoded
   `systemPrompt` + the canonical rules/shape spec. The agent passes this to
   `llm.generate(systemInstruction: ...)` (doc 01).
2. Reduce `buildTextPrompt` to dynamic turn content: history (once), tools (JSON), agents
   (from scope, doc 05), optional hand-off (doc 08), current user message (once).
3. Replace `"$systemPrompt"` with `jsonEncode(systemPrompt)`.
4. Replace the tools loop with a JSON array build (`jsonEncode(tools.map((t) => {...}))`),
   fixing the `e!`/missing-`.toList()` issues (doc 06).
5. Delete the duplicated instruction paragraphs; keep one corrected block. Fix all typos.
6. Remove the re-appended `userMessage.content` per the doc-04 invariant.
7. Pull the agents list from the agent's `AgentScope` instead of `_AgentRegistry.instance`.
8. Keep the JSON shape spec in a single shared constant (or generate from the schema in
   doc 02) referenced by both the prompt and the parser.
9. Add snapshot/golden tests for `buildSystemInstruction` and `buildTextPrompt`.

## Acceptance criteria
- The rendered system data is valid JSON, not Dart map syntax.
- Tools render as a JSON array of objects, no lazy `Iterable.toString`, no `!`.
- No typos remain in operative instructions.
- The user message and history each appear exactly once.
- Static framing is delivered via `systemInstruction`; the user turn is lean.
- Prompt building no longer references the global registry directly.

## Related docs
- [01 — LLM settings](01-llm-settings-and-generation-config.md) (systemInstruction channel)
- [02 — parsing](02-structured-output-and-robust-parsing.md) (shared JSON shape spec)
- [04 — memory management](04-memory-management.md) (render-once invariant)
- [05 — registry lifecycle](05-agent-registry-lifecycle.md) (scope-based agent list)
- [06 — tool validation](06-tool-validation-and-execution.md) (non-nullable params)
- [08 — agent chaining](08-agent-chaining.md) (goal vs hand-off labeling)
