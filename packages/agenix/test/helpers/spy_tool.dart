import 'package:agenix/agenix.dart';

class SpyTool extends Tool {
  SpyTool({
    required super.name,
    super.description = 'spy tool',
    super.parameters = const [],
    ToolResponse? response,
    this.throwOnRun = false,
  }) : _response = response;

  final ToolResponse? _response;
  final bool throwOnRun;

  final List<Map<String, dynamic>> calls = [];

  int get callCount => calls.length;

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    calls.add(params);
    if (throwOnRun) throw StateError('SpyTool $name boom');
    return _response ??
        ToolResponse(
          toolName: name,
          isRequestSuccessful: true,
          message: 'ok from $name',
        );
  }
}
