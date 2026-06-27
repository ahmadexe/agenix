# OpenAI (GPT) — Implementation Guide

Deterministic, step-by-step plan to add OpenAI support to the `agenix` Flutter package.

---

## 0. Context you must know

**Package:** `packages/agenix/`
**Existing abstraction:** `lib/src/llm/llm.dart` (the `LLM` abstract class) and `lib/src/llm/llm_config.dart` (`LlmConfig`).
**Reference implementation:** `lib/src/llm/_gemini.dart`.

The `LLM` contract:

```dart
abstract class LLM {
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType,
  });
  String get modelId;
  LlmConfig get config;
}
```

Your implementation must throw `LlmException`/`LlmTimeoutException` on failure (see `lib/src/static/agenix_exceptions.dart`). Do not return `kLLMResponseOnFailure` from inside the provider; that is the caller's concern via `FailureMode`.

Important: OpenAI's wire format is the de-facto standard reused by DeepSeek, Grok (xAI), Groq, OpenRouter, Mistral, etc. Implementing this one cleanly makes those nearly free.

---

## 1. Add the HTTP dependency (skip if already added)

Edit `packages/agenix/pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.7.0
```

Run:

```bash
cd packages/agenix && flutter pub get
```

---

## 2. OpenAI API reference (frozen)

- **Base URL:** `https://api.openai.com/v1`
- **Endpoint:** `POST /chat/completions`
- **Auth header:** `Authorization: Bearer <API_KEY>`
- **Content type:** `application/json`

**Request body:**

```json
{
  "model": "gpt-4o",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ],
  "temperature": 0.2,
  "top_p": 0.95,
  "max_tokens": 1024,
  "stop": ["..."],
  "response_format": { "type": "json_object" }
}
```

**Response body (only what matters):**

```json
{
  "id": "chatcmpl-...",
  "choices": [
    {
      "index": 0,
      "message": { "role": "assistant", "content": "..." },
      "finish_reason": "stop"
    }
  ]
}
```

You will extract `data['choices'][0]['message']['content']`.

**Multimodal:** `content` becomes an array with text + image entries:

```json
{
  "role": "user",
  "content": [
    { "type": "text", "text": "<prompt>" },
    { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,<base64>" } }
  ]
}
```

**JSON mode:** native, via `response_format: { "type": "json_object" }`. When using it, OpenAI **requires** the word `json` to appear somewhere in the messages — the system instruction below already provides this.

---

## 3. Create the implementation

Create **`packages/agenix/lib/src/llm/_openai.dart`**:

```dart
// Internal File, not part of the Public API

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/llm/llm_config.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';

/// OpenAI Chat Completions LLM implementation.
class OpenAI extends LLM {
  final String _apiKey;
  final String _modelName;
  final LlmConfig _config;
  final Dio _client;

  /// Creates an OpenAI instance. [modelName] is e.g. `gpt-4o`, `gpt-4o-mini`,
  /// `gpt-4.1`, or any chat-completions compatible model.
  ///
  /// Pass [baseUrl] to point at an OpenAI-compatible endpoint (DeepSeek, Grok,
  /// Groq, OpenRouter, etc.); defaults to `https://api.openai.com/v1`.
  OpenAI({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    String baseUrl = 'https://api.openai.com/v1',
    Map<String, String> extraHeaders = const {},
    Dio? client,
  })  : _apiKey = apiKey,
        _modelName = modelName,
        _config = config,
        _client = client ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: config.timeout,
              receiveTimeout: config.timeout,
              sendTimeout: config.timeout,
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
                ...extraHeaders,
              },
            ));

  @override
  String get modelId => _modelName;

  @override
  LlmConfig get config => _config;

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final messages = _buildMessages(prompt, systemInstruction, rawData, mimeType);

      final body = <String, dynamic>{
        'model': _modelName,
        'messages': messages,
        if (_config.temperature != null) 'temperature': _config.temperature,
        if (_config.topP != null) 'top_p': _config.topP,
        if (_config.maxOutputTokens != null) 'max_tokens': _config.maxOutputTokens,
        if (_config.stopSequences != null && _config.stopSequences!.isNotEmpty)
          'stop': _config.stopSequences,
        if (_config.jsonMode) 'response_format': {'type': 'json_object'},
      };

      final response = await _client
          .post('/chat/completions', data: body)
          .timeout(_config.timeout);

      return _extractText(response.data);
    } on TimeoutException catch (e, st) {
      throw LlmTimeoutException(
        'OpenAI request exceeded ${_config.timeout.inSeconds}s',
        cause: e,
        causeStack: st,
      );
    } on DioException catch (e, st) {
      throw LlmException(
        'OpenAI call failed: ${e.message} (status ${e.response?.statusCode})',
        cause: e,
        causeStack: st,
      );
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException('OpenAI call failed: $e', cause: e, causeStack: st);
    }
  }

  List<Map<String, dynamic>> _buildMessages(
    String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType,
  ) {
    final messages = <Map<String, dynamic>>[];

    // OpenAI requires the literal word "json" in messages when response_format is json_object.
    final sys = <String>[
      if (systemInstruction != null) systemInstruction,
      if (_config.jsonMode)
        'Respond with ONLY a valid json object. No prose, no markdown fences.',
    ].join('\n\n');

    if (sys.isNotEmpty) {
      messages.add({'role': 'system', 'content': sys});
    }

    if (rawData == null) {
      messages.add({'role': 'user', 'content': prompt});
    } else {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': prompt},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:$mimeType;base64,${base64Encode(rawData)}',
            },
          },
        ],
      });
    }

    return messages;
  }

  String _extractText(dynamic data) {
    try {
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const LlmException('OpenAI returned empty choices array');
      }
      final content = (choices.first as Map)['message']?['content'] as String?;
      if (content == null || content.isEmpty) {
        throw const LlmException('OpenAI returned empty message content');
      }
      return content.trim();
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException(
        'Failed to parse OpenAI response: $e',
        cause: e,
        causeStack: st,
      );
    }
  }
}
```

---

## 4. Add the factory

Edit **`packages/agenix/lib/src/llm/llm.dart`**. Add the import:

```dart
import 'package:agenix/src/llm/_openai.dart';
```

Add the factory inside `abstract class LLM`:

```dart
  /// Creates an OpenAI Chat-Completions backed [LLM] instance.
  ///
  /// [modelName] is e.g. `gpt-4o`. Pass [baseUrl] to use an OpenAI-compatible
  /// endpoint such as DeepSeek, Grok, Groq, or OpenRouter.
  static LLM openAiLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    String baseUrl = 'https://api.openai.com/v1',
    Map<String, String> extraHeaders = const {},
  }) =>
      OpenAI(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
        baseUrl: baseUrl,
        extraHeaders: extraHeaders,
      );
```

Do not export `_openai.dart` from `lib/agenix.dart`.

---

## 5. Tests

Create **`packages/agenix/test/llm/openai_test.dart`**:

```dart
import 'package:agenix/src/llm/_openai.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  group('OpenAI', () {
    late _MockDio dio;
    late OpenAI llm;

    setUp(() {
      dio = _MockDio();
      llm = OpenAI(apiKey: 'k', modelName: 'gpt-4o', client: dio);
    });

    test('extracts choices[0].message.content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/chat/completions'),
          statusCode: 200,
          data: {
            'choices': [
              {'message': {'content': '  hi  '}, 'finish_reason': 'stop'}
            ],
          },
        ),
      );
      expect(await llm.generate(prompt: 'x'), 'hi');
    });

    test('throws on empty content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/chat/completions'),
          statusCode: 200,
          data: {'choices': [{'message': {'content': ''}}]},
        ),
      );
      expect(() => llm.generate(prompt: 'x'), throwsA(isA<LlmException>()));
    });
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/openai_test.dart
```

---

## 6. Verify and ship

```bash
cd packages/agenix
flutter pub get
flutter analyze
flutter test
```

Add to `CHANGELOG.md`:

```
- feat(llm): add OpenAI (Chat Completions) provider via `LLM.openAiLLM`. Reusable for any OpenAI-compatible endpoint via the `baseUrl` parameter.
```

Bump patch version.

---

## 7. Consumer usage

```dart
final llm = LLM.openAiLLM(
  apiKey: const String.fromEnvironment('OPENAI_API_KEY'),
  modelName: 'gpt-4o',
);
```

---

## 8. Reuse note (important)

This `OpenAI` class is reused verbatim by the **DeepSeek**, **Grok**, **Groq**, **OpenRouter**, and **Mistral** guides via the `baseUrl` parameter. Do not duplicate the class for those providers — only add a thin factory.

---

## 9. Checklist

- [ ] `dio` in `pubspec.yaml`
- [ ] `lib/src/llm/_openai.dart` created
- [ ] `LLM.openAiLLM` factory added in `llm.dart`
- [ ] Not exported from `lib/agenix.dart`
- [ ] Tests pass
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
