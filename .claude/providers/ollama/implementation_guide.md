# Ollama (Local Models) — Implementation Guide

Ollama runs language models locally and exposes an HTTP API. The chat endpoint shape is custom (not OpenAI compatible by default, though there is an OpenAI-compatible adapter at `/v1/chat/completions`). This guide uses the **native** endpoint for richer error info; switch to the OpenAI factory with `baseUrl: 'http://localhost:11434/v1'` if you prefer.

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

## 2. Ollama API reference (frozen)

- **Base URL:** `http://localhost:11434` (default, override-able)
- **Endpoint:** `POST /api/chat`
- **Auth:** none by default (local). Optional `Authorization: Bearer ...` if behind a proxy.
- **Content type:** `application/json`

**Request body:**

```json
{
  "model": "llama3.2",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "...", "images": ["<base64>"] }
  ],
  "stream": false,
  "format": "json",
  "options": {
    "temperature": 0.2,
    "top_p": 0.95,
    "top_k": 40,
    "num_predict": 1024,
    "stop": ["..."]
  }
}
```

Set `"format": "json"` when `config.jsonMode == true`. Set `"stream": false` always.

**Response body (non-streaming):**

```json
{
  "model": "llama3.2",
  "message": { "role": "assistant", "content": "..." },
  "done": true
}
```

Extract `data['message']['content']`.

**Multimodal:** vision-capable models (e.g. `llava`, `llama3.2-vision`) accept `"images"` as an array of base64 strings on the user message.

---

## 3. Create the implementation

Create **`packages/agenix/lib/src/llm/_ollama.dart`**:

```dart
// Internal File, not part of the Public API

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/llm/llm_config.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';

/// Ollama LLM implementation backed by `/api/chat` (non-streaming).
class Ollama extends LLM {
  final String _modelName;
  final LlmConfig _config;
  final Dio _client;

  Ollama({
    required String modelName,
    LlmConfig config = const LlmConfig(),
    String baseUrl = 'http://localhost:11434',
    String? apiKey,
    Dio? client,
  })  : _modelName = modelName,
        _config = config,
        _client = client ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: config.timeout,
              receiveTimeout: config.timeout,
              sendTimeout: config.timeout,
              headers: {
                'Content-Type': 'application/json',
                if (apiKey != null) 'Authorization': 'Bearer $apiKey',
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
      final messages = <Map<String, dynamic>>[];
      if (systemInstruction != null) {
        messages.add({'role': 'system', 'content': systemInstruction});
      }
      messages.add({
        'role': 'user',
        'content': prompt,
        if (rawData != null) 'images': [base64Encode(rawData)],
      });

      final options = <String, dynamic>{
        if (_config.temperature != null) 'temperature': _config.temperature,
        if (_config.topP != null) 'top_p': _config.topP,
        if (_config.topK != null) 'top_k': _config.topK,
        if (_config.maxOutputTokens != null) 'num_predict': _config.maxOutputTokens,
        if (_config.stopSequences != null && _config.stopSequences!.isNotEmpty)
          'stop': _config.stopSequences,
      };

      final body = <String, dynamic>{
        'model': _modelName,
        'messages': messages,
        'stream': false,
        if (_config.jsonMode) 'format': 'json',
        if (options.isNotEmpty) 'options': options,
      };

      final response = await _client
          .post('/api/chat', data: body)
          .timeout(_config.timeout);

      return _extractText(response.data);
    } on TimeoutException catch (e, st) {
      throw LlmTimeoutException(
        'Ollama request exceeded ${_config.timeout.inSeconds}s',
        cause: e,
        causeStack: st,
      );
    } on DioException catch (e, st) {
      throw LlmException(
        'Ollama call failed: ${e.message} (status ${e.response?.statusCode})',
        cause: e,
        causeStack: st,
      );
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException('Ollama call failed: $e', cause: e, causeStack: st);
    }
  }

  String _extractText(dynamic data) {
    try {
      final content = (data['message'] as Map?)?['content'] as String?;
      if (content == null || content.isEmpty) {
        throw const LlmException('Ollama returned empty message content');
      }
      return content.trim();
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException(
        'Failed to parse Ollama response: $e',
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
import 'package:agenix/src/llm/_ollama.dart';
```

Add the factory:

```dart
  /// Creates an Ollama-backed [LLM] instance for locally hosted models.
  ///
  /// [modelName] is the Ollama model tag, e.g. `llama3.2`, `mistral`,
  /// `llava` (vision), `qwen2.5`.
  /// [baseUrl] defaults to `http://localhost:11434`; override for remote hosts.
  static LLM ollamaLLM({
    required String modelName,
    LlmConfig config = const LlmConfig(),
    String baseUrl = 'http://localhost:11434',
    String? apiKey,
  }) =>
      Ollama(
        modelName: modelName,
        config: config,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
```

Do not export `_ollama.dart` from `lib/agenix.dart`.

---

## 5. Tests

Create **`packages/agenix/test/llm/ollama_test.dart`**:

```dart
import 'package:agenix/src/llm/_ollama.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  group('Ollama', () {
    late _MockDio dio;
    late Ollama llm;

    setUp(() {
      dio = _MockDio();
      llm = Ollama(modelName: 'llama3.2', client: dio);
    });

    test('extracts message.content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/chat'),
          statusCode: 200,
          data: {
            'message': {'role': 'assistant', 'content': '  hi  '},
            'done': true,
          },
        ),
      );
      expect(await llm.generate(prompt: 'x'), 'hi');
    });

    test('throws on empty content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/chat'),
          statusCode: 200,
          data: {'message': {'content': ''}, 'done': true},
        ),
      );
      expect(() => llm.generate(prompt: 'x'), throwsA(isA<LlmException>()));
    });
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/ollama_test.dart
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
- feat(llm): add Ollama provider via `LLM.ollamaLLM` for locally hosted models.
```

Bump patch version.

---

## 7. Consumer usage

```dart
final llm = LLM.ollamaLLM(modelName: 'llama3.2');
```

Remote / vision:

```dart
final llm = LLM.ollamaLLM(
  modelName: 'llava',
  baseUrl: 'http://my-server:11434',
  apiKey: 'optional-proxy-token',
);
```

---

## 8. Checklist

- [ ] `dio` in `pubspec.yaml`
- [ ] `lib/src/llm/_ollama.dart` created exactly as in section 3
- [ ] `LLM.ollamaLLM` factory added
- [ ] Not exported from `lib/agenix.dart`
- [ ] Tests pass
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
