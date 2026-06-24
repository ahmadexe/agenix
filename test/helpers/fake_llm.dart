import 'dart:typed_data';
import 'package:agenix/agenix.dart';

class FakeLLM extends LLM {
  FakeLLM({
    List<String>? responses,
    this.fallback = '{"response":"fake default"}',
    this.throwWhenExhausted = false,
    this.modelIdValue = 'fake-llm',
    this.onGenerate,
    LlmConfig? config,
  })  : _responses = List<String>.from(responses ?? const []),
        _config = config ?? const LlmConfig();

  FakeLLM.alwaysResponds(String text)
      : _responses = [],
        fallback = '{"response":"$text"}',
        throwWhenExhausted = false,
        modelIdValue = 'fake-llm',
        onGenerate = null,
        _config = const LlmConfig();

  FakeLLM.scripted(List<String> jsonStrings)
      : _responses = List<String>.from(jsonStrings),
        fallback = '{"response":"fake default"}',
        throwWhenExhausted = true,
        modelIdValue = 'fake-llm',
        onGenerate = null,
        _config = const LlmConfig();

  final List<String> _responses;
  final String fallback;
  final bool throwWhenExhausted;
  final String modelIdValue;
  final String? Function(int callIndex, String prompt)? onGenerate;
  final LlmConfig _config;

  final List<String> prompts = [];
  final List<Uint8List?> rawDataReceived = [];
  final List<String?> systemInstructionsReceived = [];
  final List<String> mimeTypesReceived = [];

  int get callCount => prompts.length;

  @override
  String get modelId => modelIdValue;

  @override
  LlmConfig get config => _config;

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType = 'image/jpeg',
  }) async {
    final index = prompts.length;
    prompts.add(prompt);
    rawDataReceived.add(rawData);
    systemInstructionsReceived.add(systemInstruction);
    mimeTypesReceived.add(mimeType);

    if (onGenerate != null) {
      final override = onGenerate!(index, prompt);
      if (override != null) return override;
    }

    if (_responses.isNotEmpty) return _responses.removeAt(0);
    if (throwWhenExhausted) {
      throw const LlmException('FakeLLM: response queue exhausted');
    }
    return fallback;
  }
}
