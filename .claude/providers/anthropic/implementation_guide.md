# Anthropic (Claude) — Implementation Guide

This guide is a deterministic, step-by-step plan to add Anthropic Claude support to the `agenix` Flutter package. It is written so that any AI agent or human engineer can complete it without making creative decisions.

---

## 0. Context you must know before starting

**Package:** `packages/agenix/`
**Existing abstraction:** `lib/src/llm/llm.dart` (the `LLM` abstract class), `lib/src/llm/llm_config.dart` (the `LlmConfig` value class), `lib/src/llm/_gemini.dart` (the reference implementation).

The `LLM` contract you must satisfy:

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

Your new class must:
1. Extend `LLM`.
2. Return a plain `String` from `generate` (the LLM's textual answer).
3. On any failure, throw `LlmException` (or `LlmTimeoutException` on timeout). Do **not** swallow errors and do **not** return `kLLMResponseOnFailure` from inside the provider — that constant is used by higher layers when `FailureMode.gracefulMessage` is set.
4. Live in `lib/src/llm/` with a leading underscore (`_anthropic.dart`) because it is internal; the factory on `LLM` is the public surface.

---

## 1. Add the HTTP dependency

Edit `packages/agenix/pubspec.yaml` and add `dio` under `dependencies` (only once for the whole package — every new provider will reuse it):

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_generative_ai: ^0.4.7
  uuid: ^4.5.1
  dio: ^5.7.0
```

Then run:

```bash
cd packages/agenix && flutter pub get
```

---

## 2. Anthropic API reference (frozen)

- **Base URL:** `https://api.anthropic.com/v1`
- **Endpoint:** `POST /messages`
- **Auth header:** `x-api-key: <API_KEY>`
- **Required header:** `anthropic-version: 2023-06-01`
- **Content type:** `application/json`

**Request body shape:**

```json
{
  "model": "claude-sonnet-4-5",
  "max_tokens": 1024,
  "system": "optional system prompt",
  "messages": [
    { "role": "user", "content": "string OR content blocks" }
  ],
  "temperature": 0.2,
  "top_p": 0.95,
  "top_k": 40,
  "stop_sequences": ["..."]
}
```

**Response body shape (only the parts you need):**

```json
{
  "id": "msg_...",
  "type": "message",
  "role": "assistant",
  "content": [
    { "type": "text", "text": "..." }
  ],
  "stop_reason": "end_turn",
  "usage": { "input_tokens": 12, "output_tokens": 34 }
}
```

You will extract `data['content'][0]['text']`.

**Multimodal (image) input:** if `rawData != null`, the user message becomes a content array:

```json
{
  "role": "user",
  "content": [
    { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": "<base64>" } },
    { "type": "text", "text": "<prompt>" }
  ]
}
```

**JSON mode:** Anthropic has no native `response_format: json` flag. When `config.jsonMode == true`, you must append an instruction to the system prompt: `"Respond with ONLY a valid JSON object. No prose, no markdown fences."` (See section 5.)

---

## 3. Create the implementation file

Create **`packages/agenix/lib/src/llm/_anthropic.dart`** with the exact content below.

```dart
// Internal File, not part of the Public API

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/llm/llm_config.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';

/// Anthropic (Claude) LLM implementation backed by the Messages API.
class Anthropic extends LLM {
  final String _apiKey;
  final String _modelName;
  final LlmConfig _config;
  final Dio _client;

  /// Creates an Anthropic instance. [modelName] must be a valid Claude model id
  /// such as `claude-sonnet-4-5`, `claude-opus-4-7`, or `claude-haiku-4-5-20251001`.
  Anthropic({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    Dio? client,
  })  : _apiKey = apiKey,
        _modelName = modelName,
        _config = config,
        _client = client ??
            Dio(BaseOptions(
              baseUrl: 'https://api.anthropic.com/v1',
              connectTimeout: config.timeout,
              receiveTimeout: config.timeout,
              sendTimeout: config.timeout,
              headers: {
                'x-api-key': apiKey,
                'anthropic-version': '2023-06-01',
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
    try {
      final messages = _buildMessages(prompt, rawData, mimeType);
      final system = _buildSystem(systemInstruction);

      final body = <String, dynamic>{
        'model': _modelName,
        'max_tokens': _config.maxOutputTokens ?? 4096,
        'messages': messages,
        if (system != null) 'system': system,
        if (_config.temperature != null) 'temperature': _config.temperature,
        if (_config.topP != null) 'top_p': _config.topP,
        if (_config.topK != null) 'top_k': _config.topK,
        if (_config.stopSequences != null && _config.stopSequences!.isNotEmpty)
          'stop_sequences': _config.stopSequences,
      };

      final response = await _client
          .post('/messages', data: body)
          .timeout(_config.timeout);

      return _extractText(response.data);
    } on TimeoutException catch (e, st) {
      throw LlmTimeoutException(
        'Anthropic request exceeded ${_config.timeout.inSeconds}s',
        cause: e,
        causeStack: st,
      );
    } on DioException catch (e, st) {
      throw LlmException(
        'Anthropic call failed: ${e.message} (status ${e.response?.statusCode})',
        cause: e,
        causeStack: st,
      );
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException('Anthropic call failed: $e', cause: e, causeStack: st);
    }
  }

  List<Map<String, dynamic>> _buildMessages(
    String prompt,
    Uint8List? rawData,
    String mimeType,
  ) {
    if (rawData == null) {
      return [
        {'role': 'user', 'content': prompt},
      ];
    }
    return [
      {
        'role': 'user',
        'content': [
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': mimeType,
              'data': base64Encode(rawData),
            },
          },
          {'type': 'text', 'text': prompt},
        ],
      },
    ];
  }

  String? _buildSystem(String? systemInstruction) {
    if (systemInstruction == null && !_config.jsonMode) return null;
    final parts = <String>[
      if (systemInstruction != null) systemInstruction,
      if (_config.jsonMode)
        'Respond with ONLY a valid JSON object. No prose, no markdown fences.',
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  String _extractText(dynamic data) {
    try {
      final content = data['content'] as List?;
      if (content == null || content.isEmpty) {
        throw const LlmException('Anthropic returned empty content array');
      }
      final block = content.first as Map;
      final text = block['text'] as String?;
      if (text == null || text.isEmpty) {
        throw const LlmException('Anthropic returned empty text');
      }
      return text.trim();
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw LlmException(
        'Failed to parse Anthropic response: $e',
        cause: e,
        causeStack: st,
      );
    }
  }
}
```

---

## 4. Add the factory on the `LLM` abstract class

Edit **`packages/agenix/lib/src/llm/llm.dart`**.

Add the import at the top alongside the existing Gemini import:

```dart
import 'package:agenix/src/llm/_anthropic.dart';
```

Add this static factory inside the `abstract class LLM { ... }` block, immediately after `geminiLLM`:

```dart
  /// Creates an Anthropic (Claude) backed [LLM] instance.
  ///
  /// [modelName] is the Claude model id, e.g. `claude-sonnet-4-5`.
  static LLM anthropicLLM({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
  }) =>
      Anthropic(
        apiKey: apiKey,
        modelName: modelName,
        config: config,
      );
```

Do **not** export `_anthropic.dart` from `lib/agenix.dart`. The factory is the only public surface.

---

## 5. JSON mode behaviour (critical)

Agenix relies heavily on structured JSON output from the LLM (see `_PromptBuilder` and `PromptParser`). The default `LlmConfig.jsonMode` is `true`.

Because Anthropic does not have a native JSON-mode flag, the `_buildSystem` helper above appends an explicit instruction to the system prompt when `jsonMode == true`. This is sufficient in practice with Claude 3.5+ models. Do **not** remove that block.

If parsing still fails downstream, the agent already retries via `kMaxParseRetries` with `kParseRetryInstruction`. You do not need to add provider-side retry.

---

## 6. Tests

Create **`packages/agenix/test/llm/anthropic_test.dart`**:

```dart
import 'package:agenix/src/llm/_anthropic.dart';
import 'package:agenix/src/llm/llm_config.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  group('Anthropic', () {
    late _MockDio dio;
    late Anthropic llm;

    setUp(() {
      dio = _MockDio();
      llm = Anthropic(
        apiKey: 'test-key',
        modelName: 'claude-sonnet-4-5',
        client: dio,
      );
    });

    test('returns text from content[0].text', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/messages'),
          statusCode: 200,
          data: {
            'content': [
              {'type': 'text', 'text': '  hello  '}
            ],
          },
        ),
      );

      final result = await llm.generate(prompt: 'hi');
      expect(result, 'hello');
    });

    test('throws LlmException on Dio error', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/messages'),
          response: Response(
            requestOptions: RequestOptions(path: '/messages'),
            statusCode: 401,
          ),
        ),
      );

      expect(
        () => llm.generate(prompt: 'hi'),
        throwsA(isA<LlmException>()),
      );
    });

    test('throws LlmException on empty content', () async {
      when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/messages'),
          statusCode: 200,
          data: {'content': []},
        ),
      );

      expect(
        () => llm.generate(prompt: 'hi'),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
```

Run:

```bash
cd packages/agenix && flutter test test/llm/anthropic_test.dart
```

All three tests must pass.

---

## 7. Verify and ship

```bash
cd packages/agenix
flutter pub get
flutter analyze    # must have 0 issues
flutter test       # entire suite must pass
```

Then update `CHANGELOG.md` under the next version with:

```
- feat(llm): add Anthropic (Claude) provider via `LLM.anthropicLLM`.
```

Bump the patch version in `pubspec.yaml`.

---

## 8. Consumer usage (for the README later)

```dart
final llm = LLM.anthropicLLM(
  apiKey: const String.fromEnvironment('ANTHROPIC_API_KEY'),
  modelName: 'claude-sonnet-4-5',
);
final agent = await Agent.create(name: 'assistant', llm: llm);
```

---

## 9. Checklist (do not skip)

- [ ] `dio` added to `pubspec.yaml`
- [ ] `lib/src/llm/_anthropic.dart` created exactly as in section 3
- [ ] `LLM.anthropicLLM` factory added in `lib/src/llm/llm.dart`
- [ ] `_anthropic.dart` **not** exported from `lib/agenix.dart`
- [ ] Tests in `test/llm/anthropic_test.dart` pass
- [ ] `flutter analyze` clean
- [ ] `CHANGELOG.md` entry added
- [ ] Version bumped
