# Cohere — Implementation Guide

Cohere uses a **custom REST API** (the `/v2/chat` endpoint). It is **not** OpenAI compatible. You must write a dedicated implementation.

---

## 0. Context

**Package:** `packages/agenix/`
**Existing abstraction:** `lib/src/llm/llm.dart`, `lib/src/llm/llm_config.dart`.
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

Throw `LlmException` / `LlmTimeoutException` on failure.

---

## 1. Add the HTTP dependency (skip if already added)

`packages/agenix/pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.7.0
```

---

## 2. Cohere API reference (frozen)

- **Base URL:** `https://api.cohere.com/v2`
- **Endpoint:** `POST /chat`
- **Auth header:** `Authorization: Bearer <API_KEY>`
- **Content type:** `application/json`

**Request body:**

```json
{
  "model": "command-r-plus-08-2024",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ],
  "temperature": 0.2,
  "p": 0.95,
  "max_tokens": 1024,
  "stop_sequences": ["..."],
  "response_format": { "type": "json_object" }
}
```

Note: Cohere uses `p` (not `top_p`) and does not accept `top_k` on v2.

**Response body (only what matters):**

```json
{
  "id": "...",
  "message": {
    "role": "assistant",
    "content": [{ "type": "text", "text": "..." }]
  },
  "finish_reason": "COMPLETE"
}
```

You extract `data['message']['content'][0]['text']`.

**Multimodal:** Cohere chat does not support image input as of writing. Reject `rawData != null` with `LlmException`.

**JSON mode:** native via `response_format: { "type": "json_object" }`.

---

## 3. Create the implementation

Create **`packages/agenix/lib/src/llm/_cohere.dart`**:

```dart
// Internal File, not part of the Public API

import 'dart:async';
import 'dart:typed_data';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/llm/llm_config.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';

/// Cohere LLM implementation backed by the v2 Chat API.
class Cohere extends LLM {
  final String _apiKey;
  final String _modelName;
  final LlmConfig _config;
  final Dio _client;

  Cohere({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    Dio? client,
  })  : _apiKey = apiKey,
        _modelName = modelName,
        _config = config,
        _client = client ??
            Dio(BaseOptions(
              baseUrl: 'https://api.cohere.com/v2',
              connectTimeout: config.timeout,
              receiveTimeout: config.timeout,
              sendTimeout: config.timeout,
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
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
    if (rawData != null) {
      throw const LlmException(
        'Cohere multimodal input is not supported by this provider.',
      );
    }

    try {
      final messages = <Map<String, String>>[];
      if (systemInstruction != null) {
        messages.add({'role': 'system', 'content': systemInstruction});
      }
      messages.add({'role': 'user', 'content': prompt});

      final body = <String, dynamic>{
        'model': _modelName,
        'messages': messages,
        if (_config.temperature != null) 'temperature': _config.temperature,
        if (_config.topP != null) 'p': _config.topP,
        if (_config.maxOutputTokens != null) 'max_tokens': _config.maxOutputTokens,
        if (_config.stopSequences != null && _config.stopSequences!.isNotEmpty)
          'stop_sequences': _config.stopSequences,
        if (_config.jsonMode) 'response_format': {'type': 'json_object'},
      };

      final response = await _client
          .post('/chat', data: body)
          .timeout(_config.timeout);

      return _extractText(response.data);
    } on TimeoutException catch (e, st) {
      throw LlmTimeoutException(
        'Cohere request exceeded ${_config.timeout.inSeconds}s',
        cause: e,
        causeStack: st,
      );
    } on DioException catch (e, st) {
      throw LlmException(
        'Cohere call failed: ${e.message} (status ${e.response?.statusCode})',
        cause: e,
        causeStack: st,
      );
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException('Cohere call failed: $e', cause: e, causeStack: st);
    }
  }

  String _extractText(dynamic data) {
    try {
      final content = (data['message'] as Map?)?['content'] as List?;
      if (content == null || content.isEmpty) {
        throw const LlmException('Cohere returned empty content array');
      }
      final text = (content.first as Map)['text'] as String?;
      if (text == null || text.isEmpty) {
        throw const LlmException('Cohere returned empty text');
      }
      return text.trim();
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException(
        'Failed to parse Cohere response: $e',
        cause: e,
        causeStack: st,
      );
    }
  }
}
```

---

## 4. Add the factory

Edit **`packages/agenix/lib/src/llm/llm.dart`**. Import:

```dart
import 'package:agenix/src/llm/_cohere.dart';
```

Add the factory:

```dart
  /// Creates a Cohere-backed [LLM] instance.
  ///
  /// [modelName] is e.g. `command-r-plus-08-2024`, `command-r-08-2024`,
  /// or `command-light`.
  /// Multimodal input is not supported.
  static LLM cohereLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) =>
      Cohere(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
      );
```

Do not export `_cohere.dart` from `lib/agenix.dart`.

---

## 5. Tests

Create **`packages/agenix/test/llm/cohere_test.dart`**:

```dart
import 'dart:typed_data';

import 'package:agenix/src/llm/_cohere.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  group('Cohere', () {
    late _MockDio dio;
    late Cohere llm;

    setUp(() {
      dio = _MockDio();
      llm = Cohere(apiKey: 'k', modelName: 'command-r-plus-08-2024', client: dio);
    });

    test('extracts message.content[0].text', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/chat'),
          statusCode: 200,
          data: {
            'message': {
              'role': 'assistant',
              'content': [{'type': 'text', 'text': '  hi  '}],
            },
            'finish_reason': 'COMPLETE',
          },
        ),
      );
      expect(await llm.generate(prompt: 'x'), 'hi');
    });

    test('rejects multimodal input', () async {
      expect(
        () => llm.generate(prompt: 'x', rawData: Uint8List(0)),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/cohere_test.dart
```

---

## 6. Verify and ship

```bash
cd packages/agenix
flutter analyze
flutter test
```

`CHANGELOG.md`:

```
- feat(llm): add Cohere provider via `LLM.cohereLLM`. Multimodal input not supported.
```

Bump patch version.

---

## 7. Consumer usage

```dart
final llm = LLM.cohereLLM(
  apiKey: const String.fromEnvironment('COHERE_API_KEY'),
  modelName: 'command-r-plus-08-2024',
);
```

---

## 8. Checklist

- [ ] `dio` in `pubspec.yaml`
- [ ] `lib/src/llm/_cohere.dart` created exactly as in section 3
- [ ] `LLM.cohereLLM` factory added
- [ ] Not exported from `lib/agenix.dart`
- [ ] Tests pass
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
