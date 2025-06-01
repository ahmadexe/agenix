import 'tool.dart';

/// Tool Registry for managing tools in the application.
/// It allows for registering, unregistering, and retrieving tools.
/// The ToolRegistry is a singleton class that maintains a map of tool names to tool instances.
/// It provides methods to register a tool, unregister a tool, get a tool by name, and check if a tool exists.
class ToolRegistry {
  final Map<String, Tool> _tools = {};

  /// This method should be called whenever developers make a new tool.
  /// It registers the tool in the registry.
  /// If you miss this step, the tool won't be available for use.
  void registerTool(Tool tool) {
    _tools[tool.name] = tool;
  }

  /// This method should be called whenever developers want to remove a tool.
  /// It unregisters the tool from the registry.
  void unregisterTool(String toolName) {
    _tools.remove(toolName);
  }

  /// This method gets a tool by its name.
  /// It is used by the agent to find the tool it needs.
  /// If the tool is not found, it returns null.
  Tool? getTool(String toolName) {
    return _tools[toolName];
  }

  /// This method gets all the tools in the registry.
  /// It is used by prompt builders to list all available tools.
  List<Tool> getAllTools() {
    return _tools.values.toList();
  }

  /// This method checks if a tool is registered in the registry.
  bool hasTool(String toolName) {
    return _tools.containsKey(toolName);
  }
}
