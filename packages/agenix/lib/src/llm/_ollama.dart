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

  /// Creates an Ollama instance. [modelName] is the model tag, e.g. `llama3.2`.
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
