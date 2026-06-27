# ModelsLab — Implementation Guide

ModelsLab (modelslab.com) exposes a **custom REST API** for text generation. It is **not** OpenAI compatible. You must write a dedicated implementation.

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

Throw `LlmException` / `LlmTimeoutException` on failure. Never return `kLLMResponseOnFailure` from inside the provider.

---

## 1. Add the HTTP dependency (skip if already added)

`packages/agenix/pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.7.0
```

---

## 2. ModelsLab API reference (frozen)

- **Base URL:** `https://modelslab.com/api/v6`
- **Text endpoint:** `POST /llm/chat`
- **Auth:** API key is passed in the JSON body as `key`, not in headers.
- **Content type:** `application/json`

**Request body:**

```json
{
  "key": "<API_KEY>",
  "model_id": "Qwen2-7B",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ],
  "max_tokens": 1024,
  "temperature": 0.2,
  "top_p": 0.95
}
```

**Response body:**

```json
{
  "status": "success",
  "message": "...",
  "output": "<assistant text>",
  "meta": { ... }
}
```

You extract `data['output']`. If `data['status'] != 'success'`, treat as failure.

**Multimodal:** ModelsLab has a separate `image-to-text` endpoint. For v1 of this integration, **reject** `rawData != null` with a clear `LlmException("ModelsLab multimodal is not supported in this provider; use a vision-specific endpoint")`. Document this limitation.

**JSON mode:** no native flag. Append an instruction to the system prompt when `config.jsonMode == true`.

---

## 3. Create the implementation

Create **`packages/agenix/lib/src/llm/_models_lab.dart`**:

```dart
// Internal File, not part of the Public API

import 'dart:async';
import 'dart:typed_data';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/llm/llm_config.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';

/// ModelsLab LLM implementation backed by the `/llm/chat` endpoint.
class ModelsLab extends LLM {
  final String _apiKey;
  final String _modelName;
  final LlmConfig _config;
  final Dio _client;

  ModelsLab({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    Dio? client,
  })  : _apiKey = apiKey,
        _modelName = modelName,
        _config = config,
        _client = client ??
            Dio(BaseOptions(
              baseUrl: 'https://modelslab.com/api/v6',
              connectTimeout: config.timeout,
              receiveTimeout: config.timeout,
              sendTimeout: config.timeout,
              headers: {'Content-Type': 'application/json'},
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
        'ModelsLab multimodal input is not supported by this provider.',
      );
    }

    try {
      final messages = <Map<String, String>>[];
      final sys = <String>[
        if (systemInstruction != null) systemInstruction,
        if (_config.jsonMode)
          'Respond with ONLY a valid JSON object. No prose, no markdown fences.',
      ].join('\n\n');
      if (sys.isNotEmpty) messages.add({'role': 'system', 'content': sys});
      messages.add({'role': 'user', 'content': prompt});

      final body = <String, dynamic>{
        'key': _apiKey,
        'model_id': _modelName,
        'messages': messages,
        if (_config.maxOutputTokens != null) 'max_tokens': _config.maxOutputTokens,
        if (_config.temperature != null) 'temperature': _config.temperature,
        if (_config.topP != null) 'top_p': _config.topP,
      };

      final response = await _client
          .post('/llm/chat', data: body)
          .timeout(_config.timeout);

      return _extractText(response.data);
    } on TimeoutException catch (e, st) {
      throw LlmTimeoutException(
        'ModelsLab request exceeded ${_config.timeout.inSeconds}s',
        cause: e,
        causeStack: st,
      );
    } on DioException catch (e, st) {
      throw LlmException(
        'ModelsLab call failed: ${e.message} (status ${e.response?.statusCode})',
        cause: e,
        causeStack: st,
      );
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException('ModelsLab call failed: $e', cause: e, causeStack: st);
    }
  }

  String _extractText(dynamic data) {
    try {
      final status = data['status']?.toString();
      if (status != null && status != 'success') {
        throw LlmException(
          'ModelsLab returned non-success status: $status (${data['message']})',
        );
      }
      final output = data['output'];
      if (output == null) {
        throw const LlmException('ModelsLab returned no output field');
      }
      if (output is String) return output.trim();
      // Some models return a list of message objects; handle that too.
      if (output is List && output.isNotEmpty) {
        final first = output.first;
        if (first is Map && first['content'] is String) {
          return (first['content'] as String).trim();
        }
      }
      throw LlmException('ModelsLab output had unexpected shape: $output');
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException(
        'Failed to parse ModelsLab response: $e',
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
import 'package:agenix/src/llm/_models_lab.dart';
```

Add the factory:

```dart
  /// Creates a ModelsLab-backed [LLM] instance.
  ///
  /// [modelName] is the ModelsLab `model_id`, e.g. `Qwen2-7B`, `Llama-3-8B`.
  /// Multimodal input is not supported.
  static LLM modelsLabLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) =>
      ModelsLab(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
      );
```

Do not export `_models_lab.dart` from `lib/agenix.dart`.

---

## 5. Tests

Create **`packages/agenix/test/llm/models_lab_test.dart`**:

```dart
import 'package:agenix/src/llm/_models_lab.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'dart:typed_data';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  group('ModelsLab', () {
    late _MockDio dio;
    late ModelsLab llm;

    setUp(() {
      dio = _MockDio();
      llm = ModelsLab(apiKey: 'k', modelName: 'Qwen2-7B', client: dio);
    });

    test('extracts output string', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/llm/chat'),
          statusCode: 200,
          data: {'status': 'success', 'output': '  hi  '},
        ),
      );
      expect(await llm.generate(prompt: 'x'), 'hi');
    });

    test('throws on non-success status', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/llm/chat'),
          statusCode: 200,
          data: {'status': 'error', 'message': 'bad key'},
        ),
      );
      expect(() => llm.generate(prompt: 'x'), throwsA(isA<LlmException>()));
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
cd packages/agenix && flutter test test/llm/models_lab_test.dart
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
- feat(llm): add ModelsLab provider via `LLM.modelsLabLLM`. Multimodal input not supported.
```

Bump patch version.

---

## 7. Consumer usage

```dart
final llm = LLM.modelsLabLLM(
  apiKey: const String.fromEnvironment('MODELS_LAB_API_KEY'),
  modelName: 'Qwen2-7B',
);
```

---

## 8. Checklist

- [ ] `dio` in `pubspec.yaml`
- [ ] `lib/src/llm/_models_lab.dart` created exactly as in section 3
- [ ] `LLM.modelsLabLLM` factory added
- [ ] Not exported from `lib/agenix.dart`
- [ ] Tests pass
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` updated, version bumped
