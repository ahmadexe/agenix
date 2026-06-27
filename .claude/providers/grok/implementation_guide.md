# xAI Grok — Implementation Guide

xAI's API is **OpenAI Chat-Completions compatible**. Reuse `OpenAI` from `lib/src/llm/_openai.dart`.

> **Prerequisite:** complete the OpenAI guide first.

---

## 1. API reference (frozen)

- **Base URL:** `https://api.x.ai/v1`
- **Endpoint:** `POST /chat/completions`
- **Auth header:** `Authorization: Bearer <API_KEY>`
- **Models:** `grok-4`, `grok-4-mini`, `grok-3`, `grok-3-mini`, `grok-vision-beta` (vision-capable).
- **JSON mode:** supported via `response_format: { "type": "json_object" }`.
- **Multimodal:** supported on `grok-vision-*` models using the OpenAI image content shape — works through our OpenAI class as-is.

---

## 2. Add the factory

Edit **`packages/agenix/lib/src/llm/llm.dart`** and add:

```dart
  /// Creates an xAI Grok-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `grok-4`, `grok-4-mini`, or `grok-vision-beta`.
  /// Backed by the OpenAI-compatible Chat Completions API.
  static LLM grokLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) =>
      OpenAI(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
        baseUrl: 'https://api.x.ai/v1',
      );
```

---

## 3. Tests

Create **`packages/agenix/test/llm/grok_test.dart`**:

```dart
import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.grokLLM returns a usable LLM', () {
    final llm = LLM.grokLLM(apiKey: 'k', modelName: 'grok-4');
    expect(llm.modelId, 'grok-4');
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/grok_test.dart
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
- feat(llm): add xAI Grok provider via `LLM.grokLLM`.
```

Bump patch version.

---

## 5. Consumer usage

```dart
final llm = LLM.grokLLM(
  apiKey: const String.fromEnvironment('XAI_API_KEY'),
  modelName: 'grok-4',
);
```

---

## 6. Checklist

- [ ] OpenAI guide already completed
- [ ] `LLM.grokLLM` factory added
- [ ] Test added and passing
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
