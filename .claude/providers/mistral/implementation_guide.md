# Mistral AI — Implementation Guide

Mistral's API is **OpenAI Chat-Completions compatible** with minor differences (no `response_format: json_object` on legacy models; newer models support it). Reuse `OpenAI` from `lib/src/llm/_openai.dart`.

> **Prerequisite:** complete the OpenAI guide first.

---

## 1. API reference (frozen)

- **Base URL:** `https://api.mistral.ai/v1`
- **Endpoint:** `POST /chat/completions`
- **Auth header:** `Authorization: Bearer <API_KEY>`
- **Models:** `mistral-large-latest`, `mistral-small-latest`, `mistral-medium-latest`, `open-mistral-nemo`, `pixtral-large-latest` (vision).
- **JSON mode:** supported on recent models. The OpenAI class sends `response_format: { "type": "json_object" }` when `config.jsonMode` is true. If a Mistral model rejects this, callers should pass `LlmConfig(jsonMode: false)` and rely on the system-prompt JSON instruction (which the agent's `_PromptBuilder` provides anyway).
- **Multimodal:** supported on `pixtral-*` models with the OpenAI image content shape.

---

## 2. Add the factory

Edit **`packages/agenix/lib/src/llm/llm.dart`** and add:

```dart
  /// Creates a Mistral-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `mistral-large-latest`, `open-mistral-nemo`,
  /// or `pixtral-large-latest` (vision).
  /// Backed by the OpenAI-compatible Chat Completions API.
  static LLM mistralLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) =>
      OpenAI(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
        baseUrl: 'https://api.mistral.ai/v1',
      );
```

---

## 3. Tests

Create **`packages/agenix/test/llm/mistral_test.dart`**:

```dart
import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.mistralLLM returns a usable LLM', () {
    final llm = LLM.mistralLLM(apiKey: 'k', modelName: 'mistral-large-latest');
    expect(llm.modelId, 'mistral-large-latest');
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/mistral_test.dart
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
- feat(llm): add Mistral provider via `LLM.mistralLLM`.
```

Bump patch version.

---

## 5. Consumer usage

```dart
final llm = LLM.mistralLLM(
  apiKey: const String.fromEnvironment('MISTRAL_API_KEY'),
  modelName: 'mistral-large-latest',
);
```

---

## 6. Checklist

- [ ] OpenAI guide already completed
- [ ] `LLM.mistralLLM` factory added
- [ ] Test added and passing
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
