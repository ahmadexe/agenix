// Internal File, not part of the Public API

import 'dart:async';
import 'dart:typed_data';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/llm/llm_config.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:dio/dio.dart';

/// Cohere LLM implementation backed by the v2 Chat API.
class Cohere extends LLM {
  final String _modelName;
  final LlmConfig _config;
  final Dio _client;

  /// Creates a Cohere instance. [modelName] is e.g. `command-r-plus-08-2024`.
  Cohere({
    required String apiKey,
    required String modelName,
    LlmConfig config = const LlmConfig(),
    Dio? client,
  })  : _modelName = modelName,
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
