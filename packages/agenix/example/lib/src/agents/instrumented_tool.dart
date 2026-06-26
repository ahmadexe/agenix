import 'package:agenix/agenix.dart';

import '../event_bus.dart';

/// Wraps a [Tool] to broadcast invocation/completion events tagged with the
/// owning agent so the graph can animate the edge between agent and tool.
class InstrumentedTool extends Tool {
  InstrumentedTool({required this.inner, required this.ownerAgent})
    : super(
        name: inner.name,
        description: inner.description,
        parameters: inner.parameters,
      );

  final Tool inner;
  final String ownerAgent;

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    AgentEventBus.instance.emitNow(
      AgentEventKind.toolInvoked,
      ownerAgent,
      target: name,
      detail: params.toString(),
    );
    try {
      final response = await inner.run(params);
      AgentEventBus.instance.emitNow(
        response.isRequestSuccessful
            ? AgentEventKind.toolCompleted
            : AgentEventKind.toolFailed,
        ownerAgent,
        target: name,
        detail: response.message,
      );
      return response;
    } catch (e) {
      AgentEventBus.instance.emitNow(
        AgentEventKind.toolFailed,
        ownerAgent,
        target: name,
        detail: e.toString(),
      );
      rethrow;
    }
  }
}
