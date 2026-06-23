# 06 — Provider Abstraction & A Second Provider

## Summary
`Gemini` is the only `LLM` implementation. An abstraction proven against exactly one
implementation isn't proven — it's Gemini with extra steps. To claim "pluggable LLMs," ship a
**second** provider (recommended: OpenAI-compatible chat completions, which also covers many
self-hosted/local gateways; or Anthropic Claude). Doing so will surface every hidden
Gemini-ism in the interface and force the config/timeout/retry/streaming/telemetry work to be
genuinely provider-neutral.

## Severity & impact
**High (for the "flexible/industry-grade" claim).** This is the doc that validates the entire
LLM-coverage effort. It also immediately broadens the package's addressable use cases.

## Affected files
- `lib/src/llm/llm.dart` (the interface must be provider-neutral; add a new factory)
- `lib/src/llm/_openai.dart` (**new** — or `_claude.dart`)
- `lib/src/llm/_retry.dart`, `llm_config.dart`, `llm_telemetry.dart` (reused, not duplicated)
- `lib/agenix.dart` (export the new factory)
- `pubspec.yaml` (add the provider's SDK or use `package:http` directly)

## Choosing the provider
- **OpenAI-compatible (recommended):** one adapter unlocks OpenAI, Azure OpenAI, Groq,
  OpenRouter, Ollama, LM Studio, and most local gateways (they expose `/v1/chat/completions`).
  Maximum leverage; implement with `package:http` so there's no heavy SDK dependency.
- **Anthropic Claude:** also excellent; use `package:http` against the Messages API.
Pick one; the steps below use the OpenAI-compatible path. (For Claude, the shape is the same;
only the request/response JSON and the `system` field placement differ.)

## What this will expose in the current interface
Auditing `LLM` against a second backend reveals Gemini-isms to neutralize:
- `Uint8List? rawData` + `mimeType` assumes a single inline image. OpenAI/Claude take image
  **URLs or base64 parts** in a structured `content` array. Generalize the image-passing
  contract (see step 2).
- `systemInstruction` maps to Gemini's `Content.system`, OpenAI's `{"role":"system"}` message,
  and Claude's top-level `system` field. The neutral param is fine; each adapter places it.
- JSON mode: Gemini uses `responseMimeType`; OpenAI uses `response_format: {"type":"json_object"}`
  (or `json_schema`); Claude uses tool-forcing / prefill. Each adapter maps `config.jsonMode`.
- Usage: each provider names token fields differently — map all into `LlmUsage` (doc 05).

## Target design

### 1. Keep the public interface neutral; add a factory
```dart
// llm.dart
abstract class LLM {
  // ... existing neutral methods (generate, generateStream, modelId, config) ...

  static LLM openAI({
    required String apiKey,
    required String model,                 // e.g. 'gpt-4o-mini'
    Uri? baseUrl,                          // default https://api.openai.com/v1; override for Azure/Ollama/etc.
    LlmConfig config = const LlmConfig(),
    TelemetrySink? telemetry,
  }) => OpenAILLM(apiKey: apiKey, model: model, baseUrl: baseUrl, config: config, telemetry: telemetry);
}
```

### 2. Generalize image/multimodal input (interface-level decision)
Two acceptable approaches — choose and apply across **all** adapters:
- **Minimal:** keep `Uint8List? rawData` + `mimeType`; each adapter base64-encodes as needed
  (OpenAI: a `data:` URL image part). Lowest churn; works now.
- **Cleaner (preferred long-term):** introduce a neutral `LlmAttachment { bytes?, url?,
  mimeType }` and accept `List<LlmAttachment> attachments` in `generate`/`generateStream`.
  Gemini maps to `DataPart`, OpenAI to image-url/base64 parts. More work, future-proof.
If you take the minimal path now, note the cleaner path as a follow-up so it isn't forgotten.

### 3. The OpenAI adapter (`_openai.dart`)
```dart
class OpenAILLM extends LLM {
  OpenAILLM({required String apiKey, required this.model, Uri? baseUrl,
      LlmConfig config = const LlmConfig(), this.telemetry, http.Client? client})
    : _apiKey = apiKey, _config = config,
      _base = baseUrl ?? Uri.parse('https://api.openai.com/v1'),
      _client = client ?? http.Client();

  @override String get modelId => model;
  @override LlmConfig get config => _config;

  @override
  Future<String> generate({required String prompt, String? systemInstruction,
      Uint8List? rawData, String mimeType = 'image/jpeg'}) {
    return runWithRetry(() => _once(prompt, systemInstruction, rawData, mimeType),
        policy: _config.retry, isRetryable: _isRetryable, onRetry: _emitRetry);
  }

  Future<String> _once(String prompt, String? sys, Uint8List? img, String mime) async {
    final messages = [
      if (sys != null) {'role': 'system', 'content': sys},
      {'role': 'user', 'content': _userContent(prompt, img, mime)},
    ];
    final body = {
      'model': model, 'messages': messages,
      if (_config.temperature != null) 'temperature': _config.temperature,
      if (_config.maxOutputTokens != null) 'max_tokens': _config.maxOutputTokens,
      if (_config.topP != null) 'top_p': _config.topP,
      if (_config.stopSequences != null) 'stop': _config.stopSequences,
      if (_config.jsonMode) 'response_format': {'type': 'json_object'},
    };
    final resp = await _client
        .post(_base.resolve('chat/completions'),
            headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(_config.timeout);              // doc 02
    if (resp.statusCode >= 400) {
      throw LlmException('OpenAI ${resp.statusCode}: ${resp.body}'); // _isRetryable reads code
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final text = json['choices']?[0]?['message']?['content'] as String?;
    if (text == null || text.isEmpty) throw const LlmException('OpenAI returned empty content');
    _emitUsage(json['usage']);                  // doc 05
    return text;
  }
  // _userContent, _isRetryable (429/5xx → true), streaming via SSE, telemetry...
}
```
Notes:
- Inject `http.Client` for tests (no real network — see below).
- `jsonMode` → `response_format: {"type":"json_object"}`. The prose-JSON parser stays as a
  safety net.
- Streaming (doc 04): OpenAI streams **Server-Sent Events** (`stream: true`, `data: {...}`
  lines, terminated by `data: [DONE]`). Implement `generateStream` by reading the response
  byte stream, splitting on `\n\n`, parsing each `data:` chunk's
  `choices[0].delta.content`. Apply the doc-04 first-chunk timeout and retry-before-first-token
  rules.
- Reuse `_retry.dart` and the telemetry types — do not fork them.

### 4. Timeout & retry parity
The adapter must honor `config.timeout` and `config.retry` exactly like Gemini, mapping HTTP
`429`/`5xx`/socket errors to retryable, `4xx` (except 429) to non-retryable.

## Step-by-step implementation
1. Decide image strategy (minimal vs. `LlmAttachment`); apply to the interface.
2. Add `http` to `dependencies` (if not pulling a provider SDK).
3. Create `_openai.dart` implementing `generate`, `generateStream`, `modelId`, `config`,
   reusing `_retry.dart` + telemetry. Inject `http.Client`.
4. Add `LLM.openAI(...)` factory in `llm.dart`; export nothing internal (factory only).
5. Audit `llm.dart`/`llm_config.dart` for any leaked Gemini types; remove/neutralize them.
6. Tests (see `../tests/`):
   - Unit-test `OpenAILLM` with a **mock `http.Client`** (`mocktail`): returns a canned
     completion JSON → `generate` yields the content; maps `usage` into `LlmUsage`; a `429`
     response is retried (with `RetryPolicy` and a stubbed clock/short delay) then succeeds;
     a `401` fails fast; empty content throws.
   - Streaming: feed a canned SSE byte stream → assert ordered deltas and clean termination on
     `[DONE]`.
   - Contract parity: run the **same** behavioral expectations you wrote for the agent against
     an agent built with `LLM.openAI(... client: mockClient)` to prove the agent is
     provider-agnostic. (Reuse `FakeLLM` for most agent tests; this parity test specifically
     validates the real adapter through the agent.)
7. Update `README.md` (root) to mention the second provider once it lands.
8. `flutter analyze` clean; `flutter test` green (no real network).

## Acceptance criteria
- A second provider (`LLM.openAI(...)` or Claude) implements the full neutral interface:
  `generate`, `generateStream`, config, timeout, retry, telemetry, JSON mode, system
  instruction, and image input.
- No `google_generative_ai` types leak into the public surface or the new adapter.
- The adapter is fully tested with a mock HTTP client — no live API in CI.
- An `Agent` works unchanged when constructed with the new provider (proven by a parity test).
- Shared infra (`_retry.dart`, telemetry, `LlmConfig`) is reused, not duplicated.

## Related docs
- [01](01-generation-config-and-system-instruction.md) · [02](02-timeouts.md) · [03](03-retry-and-backoff.md) · [04](04-streaming-responses.md) · [05](05-usage-and-observability.md) — all reused here
- [07 — native function calling](07-native-function-calling.md) (provider-native tools differ per backend)
