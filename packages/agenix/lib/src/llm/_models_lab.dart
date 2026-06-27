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

  /// Creates a ModelsLab instance. [modelName] is the `model_id`, e.g. `Qwen2-7B`.
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
      // Handle explicit error envelope: {"type":"error","message":"..."}
      if (data['type']?.toString() == 'error') {
        throw LlmException(
          'ModelsLab error: ${data['message']}',
        );
      }
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
