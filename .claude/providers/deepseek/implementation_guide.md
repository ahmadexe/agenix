# DeepSeek — Implementation Guide

DeepSeek's API is **OpenAI Chat-Completions compatible**. You will reuse the `OpenAI` class from `lib/src/llm/_openai.dart` and only add a thin factory.

> **Prerequisite:** complete the OpenAI guide first (`.claude/providers/openai/implementation_guide.md`). Do not duplicate the `OpenAI` class.

---

## 1. API reference (frozen)

- **Base URL:** `https://api.deepseek.com/v1`
- **Endpoint:** `POST /chat/completions` (identical shape to OpenAI)
- **Auth header:** `Authorization: Bearer <API_KEY>`
- **Models:** `deepseek-chat`, `deepseek-reasoner`
- **JSON mode:** supports `response_format: { "type": "json_object" }` — works through the OpenAI class as-is.
- **Multimodal:** not supported on chat models as of writing. The OpenAI class will still send the image payload; DeepSeek may ignore it or 400. Document this in usage notes; do not branch.

---

## 2. Add the factory

Edit **`packages/agenix/lib/src/llm/llm.dart`**. The import for `_openai.dart` is already there from the OpenAI guide. Add:

```dart
  /// Creates a DeepSeek-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `deepseek-chat` or `deepseek-reasoner`.
  /// Backed by the OpenAI-compatible Chat Completions API.
  static LLM deepseekLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) =>
      OpenAI(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
        baseUrl: 'https://api.deepseek.com/v1',
      );
```

That is the only code change.

---

## 3. Tests

Create **`packages/agenix/test/llm/deepseek_test.dart`**:

```dart
import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM.deepseekLLM returns a usable LLM with correct modelId', () {
    final llm = LLM.deepseekLLM(apiKey: 'k', modelName: 'deepseek-chat');
    expect(llm.modelId, 'deepseek-chat');
    expect(llm.config.jsonMode, true);
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/deepseek_test.dart
```

---

## 4. Verify and ship

```bash
cd packages/agenix
flutter analyze
flutter test
```

Add to `CHANGELOG.md`:

```
- feat(llm): add DeepSeek provider via `LLM.deepseekLLM`.
```

Bump patch version.

---

## 5. Consumer usage

```dart
final llm = LLM.deepseekLLM(
  apiKey: const String.fromEnvironment('DEEPSEEK_API_KEY'),
  modelName: 'deepseek-chat',
);
```

For the reasoning model:

```dart
final llm = LLM.deepseekLLM(
  apiKey: const String.fromEnvironment('DEEPSEEK_API_KEY'),
  modelName: 'deepseek-reasoner',
);
```

Note: `deepseek-reasoner` ignores `temperature`, `top_p`, `presence_penalty`, `frequency_penalty`. Our generic config sends them only when non-null; DeepSeek ignores unsupported fields silently.

---

## 6. Checklist

- [ ] OpenAI guide already completed
- [ ] `LLM.deepseekLLM` factory added in `llm.dart`
- [ ] Test added and passing
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
