import 'dart:async';

import 'package:flutter/foundation.dart';

/// All events that flow through the visualizer.
enum AgentEventKind {
  userMessage,
  agentThinking,
  agentResponded,
  agentDelegated,
  toolInvoked,
  toolCompleted,
  toolFailed,
}

@immutable
class AgentEvent {
  final AgentEventKind kind;
  final String source;
  final String? target;
  final String? detail;
  final DateTime at;

  const AgentEvent({
    required this.kind,
    required this.source,
    required this.at,
    this.target,
    this.detail,
  });
}

/// In-process pub/sub the example uses to surface live activity into the UI.
class AgentEventBus {
  AgentEventBus._();
  static final AgentEventBus instance = AgentEventBus._();

  final _controller = StreamController<AgentEvent>.broadcast();

  Stream<AgentEvent> get stream => _controller.stream;

  void emit(AgentEvent event) => _controller.add(event);

  void emitNow(
    AgentEventKind kind,
    String source, {
    String? target,
    String? detail,
  }) {
    _controller.add(
      AgentEvent(
        kind: kind,
        source: source,
        target: target,
        detail: detail,
        at: DateTime.now(),
      ),
    );
  }
}
