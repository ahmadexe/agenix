// Internal file, not part of the Public API

part of 'agent.dart';

class _AgentRegistry {
  // Private constructor
  _AgentRegistry._internal();

  // Singleton instance
  static final _AgentRegistry _instance = _AgentRegistry._internal();

  // Accessor for the singleton instance
  static _AgentRegistry get instance => _instance;

  final Map<String, Agent> _agents = {};

  /// This method should be called whenever developers make a new tool.
  /// It registers the tool in the registry.
  /// If you miss this step, the tool won't be available for use.
  void registerTool(Agent agent) {
    _agents[agent.name] = agent;
  }

  /// This method gets an agent by its name.
  /// It is used by the agent to find other agents if required
  Agent? getTool(String agentName) {
    return _agents[agentName];
  }

  /// This method gets all the agents in the registry.
  /// It is used by prompt builders to list all available tools.
  List<Agent> getAllTools() {
    return _agents.values.toList();
  }

  /// This method checks if an agent is registered in the registry.
  bool hasTool(String toolName) {
    return _agents.containsKey(toolName);
  }
}
