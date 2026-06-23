# 01 — Generation Config & System Instruction

## Summary
`Gemini` is constructed with only `apiKey` + `modelName`. There is no temperature, token cap,
top-p/k, stop sequences, JSON/structured-output mode, or MIME control, and the system prompt
is concatenated into the **user** content by `_PromptBuilder` rather than passed to Gemini's
dedicated `systemInstruction` slot. None of the knobs that govern cost, latency, determinism,
and safety are configurable. This doc introduces a provider-neutral `LlmConfig`, threads a
real system instruction, and fixes MIME handling. It completes the partially-done
`../improvements/01-llm-settings-and-generation-config.md`.

## Severity & impact
**High.** Without this:
- Output determinism is whatever the API defaults to, which makes the JSON-only contract
  flakier than necessary (every parser retry costs a round-trip and money).
- `maxOutputTokens` is uncapped → unbounded cost/latency on a mobile data plan.
- Safety filters can't be tuned; a blocked response is indistinguishable from a real one
  (partly addressed: `_extractText` now throws on empty).
- The system prompt bloats the user turn and isn't treated as a system instruction by the
  model, degrading instruction-following.

## Affected files
- `lib/src/llm/llm.dart` (interface + `geminiLLM` factory)
- `lib/src/llm/_gemini.dart` (the adapter)
- `lib/src/llm/llm_config.dart` (**new** public config type)
- `lib/src/agent/_prompt_builder.dart` (stop embedding the system block in the user turn)
- `lib/src/agent/agent.dart` (pass system instruction through `generate`)
- `lib/agenix.dart` (export `LlmConfig`)

## Current behavior
```dart
// _gemini.dart
Gemini({required String apiKey, required String modelName}) : _modelName = modelName {
  _model = GenerativeModel(model: modelName, apiKey: apiKey); // no config, no systemInstruction
}

@override
Future<String> generate({required String prompt, Uint8List? rawData}) async {
  ...
  final DataPart dataPart = DataPart('image/jpeg', rawData); // MIME hardcoded
  ...
}
```
```dart
// _prompt_builder.dart (system prompt embedded in the prompt string)
buffer.writeln('System Instruction: ${json.encode(systemPrompt)}\n');
```

## Target design

### 1. Provider-neutral `LlmConfig` (new public type)
```dart
// lib/src/llm/llm_config.dart
/// Provider-neutral generation settings.
class LlmConfig {
  /// Sampling temperature (0.0 = deterministic). Low default suits structured JSON output.
  final double? temperature;
  /// Hard cap on output tokens (cost/latency control).
  final int? maxOutputTokens;
  final double? topP;
  final int? topK;
  final List<String>? stopSequences;
  /// Request the provider's native JSON output mode where supported (see doc 07).
  final bool jsonMode;
  /// Per-request wall-clock timeout (see doc 02).
  final Duration timeout;
  /// Retry policy (see doc 03).
  final RetryPolicy retry;

  const LlmConfig({
    this.temperature = 0.2,
    this.maxOutputTokens,
    this.topP,
    this.topK,
    this.stopSequences,
    this.jsonMode = true,
    this.timeout = const Duration(seconds: 60),
    this.retry = const RetryPolicy(),
  });

  LlmConfig copyWith({ /* all fields */ });
}
```
Keep `google_generative_ai` types **out** of this. Gemini-specific safety settings are added
as an opaque, optional field on the **Gemini** adapter (or a `GeminiConfig extends LlmConfig`),
never on the neutral type.

> `RetryPolicy` is defined in doc 03; if implementing this doc first, stub it as an empty
> `const RetryPolicy()` and flesh it out there.

### 2. System instruction as a first-class parameter
Change the interface so the agent passes the system block separately:
```dart
// llm.dart
abstract class LLM {
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType = 'image/jpeg',
  });
  String get modelId;
  LlmConfig get config;

  static LLM geminiLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    // optional, Gemini-specific safety pass-through:
    Object? safetySettings,
  }) => Gemini(apiKey: apiKey, modelName: modelName, config: config, safetySettings: safetySettings);
}
```
`_PromptBuilder` stops writing the `System Instruction:` line into the prompt string and
instead returns/exposes the system block so `Agent` can pass it as `systemInstruction`.
Two implementation options:
- **Preferred:** `_PromptBuilder.buildTextPrompt` returns the user/turn prompt only, and a
  new `_PromptBuilder.systemInstruction` getter returns `json.encode(systemPrompt)` (plus the
  rules/agents blocks that are genuinely "system"). `Agent._generateResponse` passes it to
  every `llm.generate` call.
- Alternative: keep building one string but split it at a marker. Messier — prefer the getter.

### 3. Gemini adapter honors config + system instruction + MIME
```dart
// _gemini.dart (sketch)
Gemini({required String apiKey, required String modelName,
        LlmConfig config = const LlmConfig(), Object? safetySettings})
  : _modelName = modelName, _config = config, _apiKey = apiKey,
    _safety = safetySettings as List<SafetySetting>?;

GenerationConfig _genConfig() => GenerationConfig(
  temperature: _config.temperature,
  maxOutputTokens: _config.maxOutputTokens,
  topP: _config.topP,
  topK: _config.topK,
  stopSequences: _config.stopSequences ?? const [],
  responseMimeType: _config.jsonMode ? 'application/json' : null,
);

@override
Future<String> generate({required String prompt, String? systemInstruction,
    Uint8List? rawData, String mimeType = 'image/jpeg'}) async {
  final model = GenerativeModel(
    model: _modelName, apiKey: _apiKey,
    generationConfig: _genConfig(),
    safetySettings: _safety ?? const [],
    systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null,
  );
  // ... build content with DataPart(mimeType, rawData) when rawData != null ...
  // ... wrap in .timeout(_config.timeout) per doc 02; retry per doc 03 ...
}
```
> Constructing the `GenerativeModel` per call is acceptable because `systemInstruction` is
> per-agent (loaded from `system_data.json`) and may vary per call. If profiling shows this
> matters, cache models keyed by `systemInstruction`.

### 4. JSON mode and the parser
With `responseMimeType: 'application/json'`, Gemini returns clean JSON, which makes
`PromptParser`'s fence-stripping/prose-extraction a fallback rather than the norm. Keep the
parser's defensiveness (other providers/older models still wrap output). Native schema
enforcement is doc 07.

## Step-by-step implementation
1. Create `lib/src/llm/llm_config.dart` with `LlmConfig` (+ `copyWith`). Export from
   `lib/agenix.dart`.
2. Update `llm.dart`: add `systemInstruction` + `mimeType` params to `generate`, add
   `LlmConfig get config`, update `geminiLLM(...)` to accept `config` and optional
   `safetySettings`.
3. Rewrite `Gemini` to store `config`/`apiKey`/safety, build `GenerationConfig`, pass
   `systemInstruction` + `mimeType`, and keep the existing `_extractText` empty-response
   throw. (`modelId` already returns `_modelName` — leave it.)
4. Update `_PromptBuilder`: remove the embedded `System Instruction:` line; add a
   `systemInstruction` getter exposing the system block.
5. Update `Agent._generateResponse`, `_llmGenerateWithParseRetry`, and `_reasonUsingData` to
   pass `systemInstruction:` on every `llm.generate(...)` call.
6. Update `FakeLLM` (`../tests/`) to accept/record `systemInstruction` and `mimeType` so tests
   can assert they're threaded correctly.
7. Tests (see `../tests/`):
   - `LlmConfig.copyWith` unit test.
   - Agent passes the system instruction via `systemInstruction`, not in the user prompt
     (assert the FakeLLM's recorded `systemInstruction` is set and the prompt no longer
     contains the raw system block).
   - Image messages send the supplied `mimeType`.
8. `flutter analyze` clean; `flutter test` green.

## Acceptance criteria
- `LLM.geminiLLM(apiKey: ..., modelName: 'gemini-2.0-flash', config: LlmConfig(temperature: 0,
  maxOutputTokens: 1024))` compiles and applies the settings.
- The system prompt is delivered via `systemInstruction`, not concatenated into the user turn.
- Image MIME type is configurable (no hardcoded `image/jpeg` in the call path).
- `LlmConfig` is exported and provider-neutral (no `google_generative_ai` types leak).
- Tests prove config threading and system-instruction separation against the fake.

## Related docs
- [02 — timeouts](02-timeouts.md) (uses `config.timeout`)
- [03 — retry and backoff](03-retry-and-backoff.md) (uses `config.retry`)
- [07 — native function calling](07-native-function-calling.md) (JSON schema mode)
- improvements [01 — llm settings](../improvements/01-llm-settings-and-generation-config.md) (the original, partial doc)
- improvements [09 — prompt builder](../improvements/09-prompt-builder.md) (system block location)
