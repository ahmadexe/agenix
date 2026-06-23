# 02 — Fakes & Fixtures

## Summary
Every meaningful Agenix test needs three things the real world supplies: an LLM, tools, and
sample messages. This doc specifies the reusable test doubles and builders that live in
`test/helpers/`: a **scriptable `FakeLLM`** (the core seam — it lets us drive the agent's
JSON contract deterministically), a **`SpyTool`** that records its invocations, **fixture
builders** for the data models, and the **system-data/asset stub** that makes `Agent.create`
work in a test process.

## Scope & priority
**Critical.** Docs 05–07 cannot be written without these. Build them first and well.

## Files to create
- `test/helpers/fake_llm.dart`
- `test/helpers/spy_tool.dart`
- `test/helpers/fixtures.dart`
- `test/helpers/system_data.dart`

## Background: the seams
- `LLM` is `Future<String> generate({required String prompt, Uint8List? rawData})` plus
  `String get modelId`. The agent feeds the model a prompt and parses the **string** it
  returns. So a fake LLM is just a function from call-count/prompt → canned JSON string.
- `Tool` is `name`, `description`, `parameters`, and `Future<ToolResponse> run(params)`.
- `Agent.create({required dataStore, required llm, required name, required role,
  pathToSystemData, failureMode, onError, scope, registrationPolicy})` loads system data via
  `rootBundle.loadString(pathToSystemData)`.

## Test design

### 1. `FakeLLM` — scriptable, inspectable
Requirements:
- Return a **queue** of canned responses, one per `generate` call (so we can script a
  multi-step tool loop: first call → `{"tools": ...}`, second call → `{"response": ...}`).
- Record every `prompt` and `rawData` it received, for assertions (e.g. "the observation
  prompt contained the tool result").
- Support an "always return this" mode for simple tests.
- Support throwing (to test error handling), including throwing a specific exception type or
  after N successful calls.
- Report a configurable `modelId`.

```dart
// test/helpers/fake_llm.dart
import 'dart:typed_data';
import 'package:agenix/agenix.dart';

/// A scriptable [LLM] double.
///
/// Provide [responses] to return one canned string per `generate` call, in order.
/// When the queue is exhausted it returns [fallback] (default: a direct JSON response)
/// or throws if [throwWhenExhausted] is set.
class FakeLLM extends LLM {
  FakeLLM({
    List<String>? responses,
    this.fallback = '{"response":"fake default"}',
    this.throwWhenExhausted = false,
    this.modelIdValue = 'fake-llm',
    this.onGenerate,
  }) : _responses = List<String>.from(responses ?? const []);

  final List<String> _responses;
  final String fallback;
  final bool throwWhenExhausted;
  final String modelIdValue;

  /// Optional hook to throw or mutate behavior based on the call. Receives the
  /// 0-based call index and the prompt. Return a String to override the queued
  /// response, or throw to simulate an LLM failure.
  final String? Function(int callIndex, String prompt)? onGenerate;

  /// All prompts received, in order.
  final List<String> prompts = [];

  /// All rawData payloads received, in order (null when none).
  final List<Uint8List?> rawDataReceived = [];

  int get callCount => prompts.length;

  @override
  String get modelId => modelIdValue;

  @override
  Future<String> generate({required String prompt, Uint8List? rawData}) async {
    final index = prompts.length;
    prompts.add(prompt);
    rawDataReceived.add(rawData);

    if (onGenerate != null) {
      final override = onGenerate!(index, prompt);
      if (override != null) return override;
    }

    if (_responses.isNotEmpty) return _responses.removeAt(0);
    if (throwWhenExhausted) {
      throw const LlmException('FakeLLM: response queue exhausted');
    }
    return fallback;
  }
}
```

Helper constructors worth adding as named factories or top-level helpers:
- `FakeLLM.alwaysResponds(String text)` → queue is empty, fallback is
  `{"response": "<text>"}`.
- `FakeLLM.scripted(List<String> jsonStrings)` → the queue form (most common).

> **Important parser detail:** the responses you script must match what `PromptParser`
> understands. Valid shapes (see `lib/src/tools/_parser.dart`):
> - `{"response":"hi"}`
> - `{"tools":"weather","parameters":{"weather":{"city":"London"}}}`
> - `{"agents_chain":["billing","support"]}`
> - Anything else → `ParseOutcome.unparseable` (use this to test parse-retry).

### 2. `SpyTool` — records calls, returns a canned `ToolResponse`
```dart
// test/helpers/spy_tool.dart
import 'package:agenix/agenix.dart';

/// A [Tool] double that records the params it was run with and returns a
/// pre-set [ToolResponse]. Can also be told to throw.
class SpyTool extends Tool {
  SpyTool({
    required super.name,
    super.description = 'spy tool',
    super.parameters = const [],
    ToolResponse? response,
    this.throwError = false,
  }) : _response = response;

  final ToolResponse? _response;
  final bool throwError;

  /// Each element is the params map for one `run` invocation, in order.
  final List<Map<String, dynamic>> calls = [];

  int get callCount => calls.length;

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    calls.add(params);
    if (throwError) throw StateError('SpyTool $name boom');
    return _response ??
        ToolResponse(
          toolName: name,
          isRequestSuccessful: true,
          message: 'ok from $name',
        );
  }
}
```

Add a variant or constructor flag for `needsFurtherReasoning: true` to drive the
reason-over-data path in doc 07.

### 3. Fixture builders
Keep model construction terse and consistent across tests.
```dart
// test/helpers/fixtures.dart
import 'package:agenix/agenix.dart';

AgentMessage userMsg(String content, {DateTime? at}) => AgentMessage(
      content: content,
      isFromAgent: false,
      generatedAt: at ?? DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

AgentMessage agentMsg(String content, {DateTime? at, bool isError = false}) =>
    AgentMessage(
      content: content,
      isFromAgent: true,
      generatedAt: at ?? DateTime.fromMillisecondsSinceEpoch(1700000000000),
      isError: isError,
    );

ToolResponse okTool(String name, {String message = 'ok', Map<String, dynamic>? data,
        bool needsReasoning = false}) =>
    ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: message,
      data: data,
      needsFurtherReasoning: needsReasoning,
    );
```
> Note: `generatedAt` uses a **fixed** epoch so equality/serialization tests are
> deterministic. Never default to `DateTime.now()` in a fixture.

### 4. Making `Agent.create` work in tests (the asset bundle)
`Agent.create` reads `pathToSystemData` via `rootBundle.loadString`. In a `flutter test`
process you must (a) initialize the test binding and (b) stub the asset load.

Provide a helper that registers an in-memory asset:
```dart
// test/helpers/system_data.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Call once in `setUpAll` (or `setUp`) before `Agent.create`.
/// Registers [json] as the asset at [path] so `rootBundle.loadString(path)` works.
void stubSystemData(
  Map<String, dynamic> json, {
  String path = 'assets/system_data.json',
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final key = utf8.decode(message!.buffer.asUint8List());
    if (key == path) {
      return ByteData.view(bytes.buffer);
    }
    return null;
  });
}

/// A minimal valid system-data map.
Map<String, dynamic> defaultSystemData() => {
      'persona': 'You are a helpful test assistant.',
      'rules': ['Be concise.'],
    };
```
> The exact mock channel name/handler API can drift between Flutter versions. If
> `setMockMessageHandler('flutter/assets', ...)` is deprecated in your Flutter, the modern
> equivalent is `rootBundle` + `ServicesBinding.instance.defaultBinaryMessenger`. If stubbing
> proves brittle, the **fallback** is documented in doc 07: add a thin test-only path that
> bypasses `rootBundle` (see "Asset-free agent construction" there). Prefer the stub; keep the
> fallback in your back pocket.

## Step-by-step implementation
1. Create `test/helpers/fake_llm.dart` with `FakeLLM` as above; add the two named helpers.
2. Create `test/helpers/spy_tool.dart` with `SpyTool` (+ a `needsFurtherReasoning` path).
3. Create `test/helpers/fixtures.dart` with the builders; use fixed timestamps.
4. Create `test/helpers/system_data.dart` with `stubSystemData` + `defaultSystemData`.
5. Write one smoke test that proves the stack: build a `FakeLLM.alwaysResponds('hi')`,
   `DataStore.inMemory()`, `stubSystemData(defaultSystemData())`, `Agent.create(... scope:
   AgentScope())`, call `generateResponse`, assert the returned message content is `hi`.
   This validates the fakes before docs 03–07 rely on them.
6. `flutter analyze` and `flutter test` must be clean.

## Acceptance criteria
- All four helper files compile and are importable from test files.
- The smoke test passes: an agent built entirely from fakes returns the scripted response.
- No helper uses `DateTime.now()`, real network, or real Firebase.
- `FakeLLM` records prompts and supports scripted queues, exhaustion-throw, and a per-call
  hook.

## Related docs
- [01 — test infrastructure](01-test-infrastructure-and-dependencies.md) (where helpers live)
- [04 — parser tests](04-unit-tests-parser-and-validation.md) (valid LLM JSON shapes)
- [07 — agent integration tests](07-integration-tests-agent-loop-and-chaining.md) (heaviest consumer of these fakes)
