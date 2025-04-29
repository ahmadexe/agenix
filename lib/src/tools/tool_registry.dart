import 'tool.dart';

class ToolRegistry {
  static final ToolRegistry _instance = ToolRegistry._internal();

  factory ToolRegistry() => _instance;

  final Map<String, Tool> _tools = {};

  ToolRegistry._internal();

  void registerTool(Tool tool) {
    _tools[tool.name] = tool;
  }

  void unregisterTool(String toolName) {
    _tools.remove(toolName);
  }

  Tool? getTool(String toolName) {
    return _tools[toolName];
  }

  List<Tool> getAllTools() {
    return _tools.values.toList();
  }

  bool hasTool(String toolName) {
    return _tools.containsKey(toolName);
  }
}
