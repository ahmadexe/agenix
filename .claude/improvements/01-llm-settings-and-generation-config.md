# 01 — LLM Settings & Generation Config

## Summary
The `Gemini` implementation creates a `GenerativeModel` with **only** a model name and
API key. There is no temperature, no token cap, no top-p/top-k, no safety-setting
control, no request timeout, and — critically — the system prompt is stuffed into the
**user content** instead of Gemini's dedicated `systemInstruction` slot. None of the
knobs that determine cost, latency, determinism, and safety in a real app are
configurable. This is the difference between a demo and a production agent.

## Severity & impact
**High.** Without these settings:
- You cannot make outputs deterministic (temperature is whatever the API defaults to),
  which makes the JSON-only contract flakier than it needs to be.
- You cannot cap `maxOutputTokens`, so cost/latency are unbounded.
- You cannot relax/tighten safety filters; a blocked response silently becomes the
  generic failure string.
- A hung network call has no timeout and will wedge the agent.

## Affected files
- `lib/src/llm/_gemini.dart` (entire file)
- `lib/src/llm/llm.dart` (the abstract interface + `geminiLLM` factory, lines 12–22)
- `lib/src/agent/_prompt_builder.dart` (system prompt is currently embedded in the
  user-facing prompt at line 24 — moving it to `systemInstruction` interacts with this)
- `lib/agenix.dart` (export any new public config type)

## Current behavior
`lib/src/llm/_gemini.dart`:
```dart
Gemini({required String apiKey, required String modelName}) {
  final model = GenerativeModel(model: modelName, apiKey: apiKey);
  _model = model;
}

@override
String get modelId => 'gemini'; // hardcoded, ignores modelName

@override
Future<String> generate({required String prompt, Uint8List? rawData}) async {
  if (rawData == null) {
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? kLLMResponseOnFailure;
  } else {
    final DataPart dataPart = DataPart('image/jpeg', rawData); // mime hardcoded
    ...
  }
}
```

Problems visible here:
1. No `GenerationConfig`, no `safetySettings`, no `systemInstruction`.
2. `modelId` returns the literal `'gemini'`, ignoring `modelName` (see also doc 12).
3. Image MIME type is hardcoded to `image/jpeg` regardless of the real format.
4. `response.text` being null (a safety block or empty candidate) is indistinguishable
   from a real answer — it just becomes `kLLMResponseOnFailure` (see doc 03).

## Target design

### 1. A public, LLM-agnostic config object
Create `lib/src/llm/llm_config.dart` exporting `LlmConfig`:
```dart
class LlmConfig {
  final double? temperature;      // 0.0–2.0; default low (e.g. 0.2) for structured tasks
  final int? maxOutputTokens;
  final double? topP;
  final int? topK;
  final List<String>? stopSequences;
  /// Whether to request native JSON output (see doc 02).
  final bool jsonMode;
  /// Per-request wall-clock timeout.
  final Duration timeout;

  const LlmConfig({
    this.temperature = 0.2,
    this.maxOutputTokens,
    this.topP,
    this.topK,
    this.stopSequences,
    this.jsonMode = true,
    this.timeout = const Duration(seconds: 60),
  });
}
```
Keep it provider-neutral. Provider-specific concepts (Gemini `SafetySetting`) can be
accepted as an opaque, optional field or via a Gemini-specific subclass to avoid leaking
`google_generative_ai` types into the public surface.

### 2. Pass a real system instruction
`generate()` should accept the system prompt separately from the user turn so the Gemini
adapter can map it to `GenerativeModel(systemInstruction: Content.system(...))`. Two
options:
- **Preferred:** add an optional `String? systemInstruction` parameter to
  `LLM.generate(...)`. The agent passes the system block here instead of concatenating it
  into the user prompt (coordinate with doc 09).
- Alternative: set `systemInstruction` once at model-construction time if it's static.
  It is *not* static here (it comes from `system_data.json` per agent), so prefer the
  per-call parameter, or construct the `GenerativeModel` lazily once the system data is
  known.

### 3. Honor MIME type for images
Add an optional `String mimeType = 'image/jpeg'` to `generate(...)` (or detect from the
bytes' magic number). Plumb it through from `AgentMessage` if/when the message carries a
content type.

## Step-by-step implementation
1. Create `lib/src/llm/llm_config.dart` with `LlmConfig` as above. Add it to
   `lib/agenix.dart` exports.
2. Update the abstract interface in `lib/src/llm/llm.dart`:
   - `Future<String> generate({required String prompt, String? systemInstruction, Uint8List? rawData, String mimeType});`
   - Add `LlmConfig get config;` (or accept config in the factory).
   - Update `geminiLLM(...)` factory to accept `LlmConfig config = const LlmConfig()`.
3. Rewrite `Gemini`:
   - Store `modelName`, `apiKey`, `config`, and optional safety settings.
   - Build `GenerationConfig(temperature: config.temperature, maxOutputTokens: ..., topP: ..., topK: ..., stopSequences: ..., responseMimeType: config.jsonMode ? 'application/json' : null)` (the `responseMimeType` part is detailed in doc 02).
   - Construct `GenerativeModel(model: modelName, apiKey: apiKey, generationConfig: ..., safetySettings: ..., systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null)`. If `systemInstruction` varies per call, construct the model per call or use the per-call API that accepts it.
   - Fix `modelId` to return `modelName`.
   - Use the passed `mimeType` in `DataPart`.
   - Wrap the `generateContent` call in `.timeout(config.timeout)` and convert a
     `TimeoutException` into the typed LLM error from doc 03.
   - Inspect the response: if `response.text == null`, check `promptFeedback`/finish
     reason and throw a typed `LlmException` (doc 03) rather than returning the fallback
     string. Returning the fallback is the agent layer's decision, not the adapter's.
4. Update `Agent._generateResponse` and `_reasonUsingData` to pass the system instruction
   separately (coordinate with doc 09's prompt split).

## Acceptance criteria
- A consumer can do `LLM.geminiLLM(apiKey: ..., modelName: 'gemini-2.0-flash', config: LlmConfig(temperature: 0, maxOutputTokens: 1024, timeout: Duration(seconds: 30)))`.
- The system prompt is delivered via `systemInstruction`, not concatenated into the user
  turn.
- `modelId` reflects the actual model name.
- A request that exceeds `timeout` throws a typed timeout error (doc 03), not a hang.
- Image messages send the correct MIME type.

## Related docs
- [02 — structured output](02-structured-output-and-robust-parsing.md) (`responseMimeType`/schema)
- [03 — error handling](03-error-handling-and-exceptions.md) (timeout & null-text errors)
- [09 — prompt builder](09-prompt-builder.md) (moving the system block out of the user turn)
