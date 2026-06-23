# 04 — Unit Tests: Parser & Parameter Validation

## Summary
Two pure functions carry most of the agent's robustness load: `PromptParser.parse` (turns a
raw LLM string into a typed `PromptParserResult`, and **never throws**) and `validateParams`
(coerces/validates tool params before execution). Both were rewritten during hardening and
both have rich edge-case behavior that is trivial to break and currently untested.

## Scope & priority
**High.** These are deterministic, dependency-free functions — the highest value-per-line
tests in the suite. They directly protect the LLM↔agent contract.

## Files under test
- `lib/src/tools/_parser.dart` (`PromptParser`, `PromptParserResult`, `ParseOutcome`)
- `lib/src/tools/_param_validator.dart` (`validateParams`, `ValidationResult`)

## Files to create
- `test/tools/parser_test.dart`
- `test/tools/param_validator_test.dart`

> **Import note:** these are internal (underscore) files but **not** `part` files, so test
> code can import them directly:
> ```dart
> import 'package:agenix/src/tools/_parser.dart';
> import 'package:agenix/src/tools/_param_validator.dart';
> import 'package:agenix/src/tools/param_spec.dart';
> ```
> This is allowed and intentional for white-box unit testing of internals.

## Test design — `PromptParser`

Behavior recap (from source):
- Trims input, strips markdown fences (` ```json ` / ` ``` `), `json.decode`s.
- On decode failure, extracts the first `{` … last `}` substring and retries.
- Recognizes keys in priority order: `agents_chain` → `response` → `tools`.
- `tools` accepts a comma-string **or** a list; splits/trims, drops empties.
- `parameters` is a map of tool→param-map; missing/non-map params become `{}`.
- `agents_chain` accepts a list **or** a single string.
- Anything unrecognized → `ParseOutcome.unparseable`, and `rawOutput` preserves the input.
- It **never throws**.

Cases (group `PromptParser`):
1. **Direct response:** `{"response":"hi"}` → `outcome == response`, `fallbackResponse == 'hi'`.
2. **Response with non-string value:** `{"response": 42}` → `fallbackResponse == '42'`
   (it calls `.toString()`).
3. **Tools as comma string:** `{"tools":"a, b ,c"}` → `toolNames == ['a','b','c']`
   (trimmed, no empties).
4. **Tools as list:** `{"tools":["a"," b "]}` → `toolNames == ['a','b']`.
5. **Tools with params:** `{"tools":"w","parameters":{"w":{"city":"London"}}}` →
   `params['w'] == {'city':'London'}`.
6. **Tools missing params:** `{"tools":"w"}` → `params['w'] == {}`.
7. **Tools with non-map params entry:** `{"tools":"w","parameters":{"w":"oops"}}` →
   `params['w'] == {}`.
8. **Empty tools collapses to unparseable-or-empty:** `{"tools":" , "}` → `toolNames == []`.
   (Assert the actual outcome the code produces — it returns `ParseOutcome.tools` with an
   empty list; pin whatever the implementation does so the behavior is documented.)
9. **Agents chain as list:** `{"agents_chain":["x","y"]}` → `outcome == agentsChain`,
   `agentNames == ['x','y']`.
10. **Agents chain as single string:** `{"agents_chain":"solo"}` → `agentNames == ['solo']`.
11. **Priority:** a map containing both `agents_chain` and `tools` → resolves as
    `agentsChain` (chain is checked first). Pin this ordering.
12. **Markdown fences:** ` ```json\n{"response":"hi"}\n``` ` → parses to `response`.
13. **Prose around JSON:** `Sure! {"response":"hi"} hope that helps` → extracts and parses.
14. **Garbage:** `not json at all` → `outcome == unparseable`, `rawOutput` == the input.
15. **Empty string / whitespace:** `''` and `'   '` → `unparseable`.
16. **Valid JSON but not an object:** `[1,2,3]` → `unparseable` (decoder returns a List).
17. **Valid JSON object with none of the known keys:** `{"foo":"bar"}` → `unparseable`.
18. **Never throws:** wrap a malformed/huge/binary-ish input in `expect(() => parser.parse(x),
    returnsNormally)`.

```dart
import 'package:agenix/src/tools/_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = PromptParser();

  group('PromptParser', () {
    test('parses a direct response', () {
      final r = parser.parse('{"response":"hi"}');
      expect(r.outcome, ParseOutcome.response);
      expect(r.fallbackResponse, 'hi');
    });

    test('parses tools as a comma string with trimming', () {
      final r = parser.parse('{"tools":"a, b ,c"}');
      expect(r.outcome, ParseOutcome.tools);
      expect(r.toolNames, ['a', 'b', 'c']);
    });

    test('agents_chain wins over tools when both present', () {
      final r = parser.parse('{"agents_chain":["x"],"tools":"a"}');
      expect(r.outcome, ParseOutcome.agentsChain);
    });

    test('strips markdown fences', () {
      final r = parser.parse('```json\n{"response":"hi"}\n```');
      expect(r.outcome, ParseOutcome.response);
    });

    test('extracts JSON embedded in prose', () {
      final r = parser.parse('Sure! {"response":"hi"} done');
      expect(r.fallbackResponse, 'hi');
    });

    test('returns unparseable for garbage and never throws', () {
      expect(() => parser.parse('not json'), returnsNormally);
      expect(parser.parse('not json').outcome, ParseOutcome.unparseable);
      expect(parser.parse('not json').rawOutput, 'not json');
    });
  });
}
```

## Test design — `validateParams`

Behavior recap (from source):
- Iterates the tool's `ParameterSpecification` list.
- Missing + has `defaultValue` → inject default. Missing + `required` → error. Missing +
  optional → skip.
- `enumValues` (non-empty) → value's `.toString()` must be in the set, else error.
- Type coercion via `_coerce`: `string` (toString), `number` (num or parseable, else error),
  `boolean` (`true`/`false`/string variants, else error), `object` (Map→`Map<String,dynamic>`,
  else error), `array` (List, else error), default/unknown type → pass through unchanged.
- Unknown params not in the spec are **passed through** to `values`.
- `ValidationResult.isValid` is `errors.isEmpty`.

Cases (group `validateParams`):
1. **Required present:** spec `[name required string]`, raw `{name:'Sam'}` → valid,
   `values['name'] == 'Sam'`.
2. **Required missing:** raw `{}` → invalid, error mentions `name`.
3. **Optional missing, no default:** → valid, key absent from `values`.
4. **Default injection:** optional spec with `defaultValue: 5`, raw `{}` → valid,
   `values == {param: 5}`.
5. **Default NOT overriding provided value:** provided value wins over default.
6. **Enum pass:** `enumValues:['red','green']`, raw `{c:'red'}` → valid.
7. **Enum fail:** raw `{c:'blue'}` → invalid, error lists allowed values.
8. **Number coercion from string:** type `number`, raw `{n:'42'}` → `values['n'] == 42`.
9. **Number coercion failure:** raw `{n:'abc'}` → invalid.
10. **Boolean coercion:** `'true'`→`true`, `'FALSE'`→`false`, `true`→`true`; `'maybe'`→error.
11. **Object coercion:** raw `{o:{'k':'v'}}` → `values['o']` is a `Map<String,dynamic>`;
    a non-map (`o:'x'`) → error.
12. **Array coercion:** list passes; non-list errors.
13. **Unknown type passes through:** type `'weird'` returns the value unchanged.
14. **Unknown param passthrough:** spec has only `a`; raw has `a` and `extra` → `values`
    contains both.
15. **Null value treated as missing:** raw `{name: null}` for a required `name` → invalid
    (the code treats `containsKey && value != null`).
16. **Multiple errors accumulate:** two bad params → `errors.length == 2`, `isValid` false.

## Step-by-step implementation
1. Create `test/tools/parser_test.dart` covering cases 1–18. Always include the
   "never throws" guard.
2. Create `test/tools/param_validator_test.dart` covering cases 1–16. Build
   `ParameterSpecification`s inline.
3. For ambiguous edges (case 8 of the parser — empty tool list), assert the **actual**
   current behavior and add a comment noting it's a pinned behavior, not necessarily ideal.
4. Run `flutter test test/tools/parser_test.dart test/tools/param_validator_test.dart`.
5. `flutter analyze` clean.

## Acceptance criteria
- All parser outcomes (`response`, `tools`, `agentsChain`, `unparseable`) are covered,
  including fence-stripping, prose-extraction, both `tools` shapes, both `agents_chain`
  shapes, key priority, and the never-throws guarantee.
- All `validateParams` paths are covered: required, defaults, enums, every coercion type
  (success + failure), unknown-type passthrough, unknown-param passthrough, null-as-missing,
  and error accumulation.
- `flutter test test/tools` (parser + validator) passes; `flutter analyze` clean.

## Related docs
- [02 — fixtures](02-fakes-and-fixtures.md)
- improvements [02 — structured output & parsing](../improvements/02-structured-output-and-robust-parsing.md)
- improvements [06 — tool validation](../improvements/06-tool-validation-and-execution.md)
