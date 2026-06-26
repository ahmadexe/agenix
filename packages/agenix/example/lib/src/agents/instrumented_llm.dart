import 'dart:typed_data';

import 'package:agenix/agenix.dart';

import '../event_bus.dart';

/// Wraps an [LLM] and emits "thinking" / "responded" events tagged with the
/// owning agent so the graph can light up the right node.
class InstrumentedLlm implements LLM {
  InstrumentedLlm({required this.inner, required this.agentName});

  final LLM inner;
  final String agentName;

  @override
  String get modelId => inner.modelId;

  @override
  LlmConfig get config => inner.config;

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType = 'image/jpeg',
  }) async {
    AgentEventBus.instance.emitNow(AgentEventKind.agentThinking, agentName);
    try {
      final result = await inner.generate(
        prompt: prompt,
        systemInstruction: systemInstruction,
        rawData: rawData,
        mimeType: mimeType,
      );
      AgentEventBus.instance.emitNow(
        AgentEventKind.agentResponded,
        agentName,
        detail: _peek(result),
      );
      return result;
    } catch (e) {
      AgentEventBus.instance.emitNow(
        AgentEventKind.agentResponded,
        agentName,
        detail: 'error: $e',
      );
      rethrow;
    }
  }

  String _peek(String raw) {
    final trimmed = raw.trim();
    return trimmed.length > 120 ? '${trimmed.substring(0, 120)}…' : trimmed;
  }
}
