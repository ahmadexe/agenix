import 'package:agenix/agenix.dart';

AgentMessage userMsg(String content, {DateTime? at}) => AgentMessage(
  content: content,
  isFromAgent: false,
  generatedAt: at ?? DateTime.fromMillisecondsSinceEpoch(1700000000000),
);

AgentMessage agentMsg(String content, {DateTime? at, bool isError = false}) =>
    AgentMessage(
      content: content,
      isFromAgent: true,
      generatedAt: at ?? DateTime.fromMillisecondsSinceEpoch(1700000000000),
      isError: isError,
    );

ToolResponse okTool(
  String name, {
  String message = 'ok',
  Map<String, dynamic>? data,
  bool needsReasoning = false,
}) => ToolResponse(
  toolName: name,
  isRequestSuccessful: true,
  message: message,
  data: data,
  needsFurtherReasoning: needsReasoning,
);
