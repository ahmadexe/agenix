# Groq — Implementation Guide

Groq's API is **OpenAI Chat-Completions compatible**. Reuse `OpenAI` from `lib/src/llm/_openai.dart`.

> **Prerequisite:** complete the OpenAI guide first.

---

## 1. API reference (frozen)

- **Base URL:** `https://api.groq.com/openai/v1`
- **Endpoint:** `POST /chat/completions`
- **Auth header:** `Authorization: Bearer <API_KEY>`
- **Models:** `llama-3.3-70b-versatile`, `llama-3.1-8b-instant`, `mixtral-8x7b-32768`, `gemma2-9b-it`, `llama-3.2-90b-vision-preview` (vision).
- **JSON mode:** supported via `response_format: { "type": "json_object" }`.
- **Multimodal:** only on `*-vision-*` models; uses the standard OpenAI image content shape.

---

## 2. Add the factory

Edit **`packages/agenix/lib/src/llm/llm.dart`** and add:

```dart
  /// Creates a Groq-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `llama-3.3-70b-versatile`, `mixtral-8x7b-32768`,
  /// or `llama-3.2-90b-vision-preview`.
  /// Backed by the OpenAI-compatible Chat Completions API.
  static LLM groqLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) =>
      OpenAI(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
        baseUrl: 'https://api.groq.com/openai/v1',
      );
```

---

## 3. Tests

Create **`packages/agenix/test/llm/groq_test.dart`**:

```dart
import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.groqLLM returns a usable LLM', () {
    final llm = LLM.groqLLM(apiKey: 'k', modelName: 'llama-3.3-70b-versatile');
    expect(llm.modelId, 'llama-3.3-70b-versatile');
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/groq_test.dart
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
- feat(llm): add Groq provider via `LLM.groqLLM`.
```

Bump patch version.

---

## 5. Consumer usage

```dart
final llm = LLM.groqLLM(
  apiKey: const String.fromEnvironment('GROQ_API_KEY'),
  modelName: 'llama-3.3-70b-versatile',
);
```

---

## 6. Checklist

- [ ] OpenAI guide already completed
- [ ] `LLM.groqLLM` factory added
- [ ] Test added and passing
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
