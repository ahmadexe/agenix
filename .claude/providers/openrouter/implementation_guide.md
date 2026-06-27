# OpenRouter — Implementation Guide

OpenRouter aggregates many providers behind a single **OpenAI Chat-Completions compatible** endpoint. Reuse `OpenAI` from `lib/src/llm/_openai.dart`.

> **Prerequisite:** complete the OpenAI guide first.

---

## 1. API reference (frozen)

- **Base URL:** `https://openrouter.ai/api/v1`
- **Endpoint:** `POST /chat/completions`
- **Auth header:** `Authorization: Bearer <API_KEY>`
- **Recommended optional headers (for OpenRouter analytics):**
  - `HTTP-Referer: <your app URL>`
  - `X-Title: <your app name>`
- **Model id format:** `<provider>/<model>` — e.g. `anthropic/claude-sonnet-4-5`, `openai/gpt-4o`, `meta-llama/llama-3.1-70b-instruct`, `google/gemini-pro-1.5`.
- **JSON mode:** supported via `response_format: { "type": "json_object" }` (passthrough to upstream provider — works for OpenAI/Mistral/etc., may be ignored by others).
- **Multimodal:** supported when the upstream model supports it, using the standard OpenAI content shape.

---

## 2. Add the factory

Edit **`packages/agenix/lib/src/llm/llm.dart`** and add:

```dart
  /// Creates an OpenRouter-backed [LLM] instance.
  ///
  /// [modelName] is the OpenRouter model slug, e.g. `anthropic/claude-sonnet-4-5`,
  /// `openai/gpt-4o`, `meta-llama/llama-3.1-70b-instruct`.
  ///
  /// [appUrl] and [appName] populate OpenRouter's analytics headers
  /// (`HTTP-Referer` and `X-Title`). Both are optional.
  static LLM openRouterLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    String? appUrl,
    String? appName,
  }) =>
      OpenAI(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
        baseUrl: 'https://openrouter.ai/api/v1',
        extraHeaders: {
          if (appUrl != null) 'HTTP-Referer': appUrl,
          if (appName != null) 'X-Title': appName,
        },
      );
```

This relies on the `extraHeaders` parameter that the OpenAI guide added to the `OpenAI` constructor. If you have not added that parameter yet, do so now (see the OpenAI guide, section 3).

---

## 3. Tests

Create **`packages/agenix/test/llm/openrouter_test.dart`**:

```dart
import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.openRouterLLM returns a usable LLM', () {
    final llm = LLM.openRouterLLM(
      apiKey: 'k',
      modelName: 'anthropic/claude-sonnet-4-5',
      appName: 'agenix-test',
    );
    expect(llm.modelId, 'anthropic/claude-sonnet-4-5');
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/openrouter_test.dart
```

---

## 4. Verify and ship

```bash
cd packages/agenix
flutter analyze
flutter test
```

`CHANGELOG.md`:

```
- feat(llm): add OpenRouter provider via `LLM.openRouterLLM`. Use any upstream model behind a single key.
```

Bump patch version.

---

## 5. Consumer usage

```dart
final llm = LLM.openRouterLLM(
  apiKey: const String.fromEnvironment('OPENROUTER_API_KEY'),
  modelName: 'anthropic/claude-sonnet-4-5',
  appName: 'My App',
  appUrl: 'https://my-app.example',
);
```

---

## 6. Checklist

- [ ] OpenAI guide already completed (including `extraHeaders` constructor param)
- [ ] `LLM.openRouterLLM` factory added
- [ ] Test added and passing
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
