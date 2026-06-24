import 'package:agenix/src/static/agenix_exceptions.dart';

/// An [AgentScope] owns a set of agents that can discover and chain to each other.
///
/// Use [AgentScope.global] for the default shared scope, or create isolated
/// scopes for testing or multi-tenant setups.
class AgentScope {
  /// The default, process-wide scope. Agents register here when no explicit
  /// scope is provided to [Agent.create].
  static final AgentScope global = AgentScope();

  final Map<String, Object> _agents = {};

  /// Creates a new, empty [AgentScope].
  AgentScope();

  /// Registers [agent] under [name] according to [policy].
  ///
  /// The [agent] parameter is typed as [Object] here because [Agent] is
  /// defined in a `part` file and cannot be referenced directly. The caller
  /// is responsible for passing a valid [Agent] instance.
  void registerAgent(
    String name,
    Object agent, {
    RegistrationPolicy policy = RegistrationPolicy.throwIfExists,
  }) {
    if (_agents.containsKey(name)) {
      switch (policy) {
        case RegistrationPolicy.throwIfExists:
          throw ConfigException(
            'Agent with name $name already exists. Use RegistrationPolicy.replace '
            'to overwrite, or call dispose() on the existing agent first.',
          );
        case RegistrationPolicy.replace:
          _agents[name] = agent;
        case RegistrationPolicy.ignore:
          return;
      }
    } else {
      _agents[name] = agent;
    }
  }

  /// Removes the agent registered under [name], if any.
  void unregisterAgent(String name) {
    _agents.remove(name);
  }

  /// Returns the agent registered under [name], or `null`.
  Object? getAgent(String name) => _agents[name];

  /// Returns all registered agents.
  List<Object> getAllAgents() => _agents.values.toList();

  /// Returns `true` if an agent named [agentName] is registered.
  bool hasAgent(String agentName) => _agents.containsKey(agentName);

  /// Removes all agents from this scope.
  void clear() => _agents.clear();
}

/// Controls how [Agent.create] handles a duplicate agent name in its scope.
enum RegistrationPolicy {
  /// Throw an exception if an agent with the same name already exists.
  throwIfExists,

  /// Silently replace the existing agent with the new one.
  replace,

  /// Keep the existing agent; the new instance is not registered.
  ignore,
}
