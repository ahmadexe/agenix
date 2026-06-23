// Internal file, not part of the Public API
// Thin shim that delegates to AgentScope for backward compatibility.

part of 'agent.dart';

class _AgentRegistry {
  _AgentRegistry._internal();

  static final _AgentRegistry _instance = _AgentRegistry._internal();
  static _AgentRegistry get instance => _instance;

  /// Registers an agent into its scope.
  void registerAgent(
    Agent agent, {
    RegistrationPolicy policy = RegistrationPolicy.throwIfExists,
  }) {
    agent._scope.registerAgent(agent.name, agent, policy: policy);
  }

  /// Returns the agent registered under [agentName] in the given [scope],
  /// or in the global scope if none is specified.
  Agent? getAgent(String agentName, {AgentScope? scope}) {
    return (scope ?? AgentScope.global).getAgent(agentName) as Agent?;
  }

  /// Returns all agents in the given [scope], or in the global scope.
  List<Agent> getAllAgents({AgentScope? scope}) {
    return (scope ?? AgentScope.global).getAllAgents().cast<Agent>();
  }

  /// Unregisters an agent from its scope.
  void unregisterAgent(Agent agent) {
    agent._scope.unregisterAgent(agent.name);
  }
}
