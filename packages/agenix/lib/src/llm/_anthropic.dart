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
  })  : _modelName = modelName,
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
      final body = e.response?.data;
      final detail = body is Map ? (body['error']?['message'] ?? body['message']) : null;
      throw LlmException(
        'Anthropic call failed: ${detail ?? e.message} (status ${e.response?.statusCode})',
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
