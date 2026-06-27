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
  }) : _modelName = modelName,
       _config = config,
       _client =
           client ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: config.timeout,
               receiveTimeout: config.timeout,
               sendTimeout: config.timeout,
               headers: {
                 'Authorization': 'Bearer $apiKey',
                 'Content-Type': 'application/json',
                 ...extraHeaders,
               },
             ),
           );

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
      final messages = _buildMessages(
        prompt,
        systemInstruction,
        rawData,
        mimeType,
      );

      final body = <String, dynamic>{
        'model': _modelName,
        'messages': messages,
        if (_config.temperature != null) 'temperature': _config.temperature,
        if (_config.topP != null) 'top_p': _config.topP,
        if (_config.maxOutputTokens != null)
          'max_tokens': _config.maxOutputTokens,
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
      final status = e.response?.statusCode;
      final msg = 'OpenAI call failed: ${e.message} (status $status)';
      if (status == 429) {
        throw LlmRateLimitException(
          msg,
          cause: e,
          causeStack: st,
          retryAfter: _parseRetryAfter(e.response?.headers),
        );
      }
      throw LlmException(msg, cause: e, causeStack: st, statusCode: status);
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

  Duration? _parseRetryAfter(Headers? headers) {
    final value = headers?.value('retry-after');
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    return seconds != null ? Duration(seconds: seconds) : null;
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
