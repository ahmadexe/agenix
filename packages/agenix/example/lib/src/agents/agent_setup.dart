import 'package:agenix/agenix.dart';

import '../event_bus.dart';
import 'instrumented_llm.dart';
import 'instrumented_tool.dart';
import 'tools.dart';

/// A live, in-memory description of the agent topology — used by both the
/// runtime (to wire agents together) and the UI (to draw the graph).
class AgentTopology {
  AgentTopology({required this.scope, required this.agents});

  final AgentScope scope;
  final List<AgentNodeSpec> agents;

  Agent get coordinator =>
      agents.firstWhere((a) => a.role == AgentRole.coordinator).agent;

  void disposeAll() {
    for (final spec in agents) {
      spec.agent.dispose();
    }
  }
}

enum AgentRole { coordinator, specialist }

class AgentNodeSpec {
  AgentNodeSpec({
    required this.agent,
    required this.role,
    required this.label,
    required this.tools,
  });

  final Agent agent;
  final AgentRole role;
  final String label;
  final List<String> tools;

  String get name => agent.name;
}

/// Builds the demo's coordinator + 3 specialists, each with their own tools.
/// All agents live in a dedicated [AgentScope] so we don't collide with any
/// other agent the host app might create.
Future<AgentTopology> buildDemoTopology({required String apiKey}) async {
  final scope = AgentScope();
  final dataStore = DataStore.inMemory();

  LLM baseLlm({double temperature = 0.4}) => LLM.geminiLLM(
    apiKey: apiKey,
    modelName: 'gemini-2.5-flash',
    config: LlmConfig(temperature: temperature, jsonMode: true),
  );

  // --- Researcher ------------------------------------------------------------
  final researcher = await Agent.create(
    dataStore: dataStore,
    llm: InstrumentedLlm(
      inner: baseLlm(temperature: 0.2),
      agentName: 'researcher',
    ),
    name: 'researcher',
    role:
        'Research specialist. Gathers factual, well-sourced information about '
        'a topic using the web_search tool. Returns 3-5 bullet findings.',
    scope: scope,
  );
  researcher.toolRegistry.registerTool(
    InstrumentedTool(inner: WebSearchTool(), ownerAgent: 'researcher'),
  );

  // --- Analyst ---------------------------------------------------------------
  final analyst = await Agent.create(
    dataStore: dataStore,
    llm: InstrumentedLlm(
      inner: baseLlm(temperature: 0.1),
      agentName: 'analyst',
    ),
    name: 'analyst',
    role:
        'Quantitative analyst. Uses market_data to pull a time series and '
        'statistics to compute mean/min/max/growth. Returns a short numeric '
        'summary with the headline number callers should know.',
    scope: scope,
  );
  analyst.toolRegistry.registerTool(
    InstrumentedTool(inner: MarketDataTool(), ownerAgent: 'analyst'),
  );
  analyst.toolRegistry.registerTool(
    InstrumentedTool(inner: StatisticsTool(), ownerAgent: 'analyst'),
  );

  // --- Writer ----------------------------------------------------------------
  final writer = await Agent.create(
    dataStore: dataStore,
    llm: InstrumentedLlm(inner: baseLlm(temperature: 0.7), agentName: 'writer'),
    name: 'writer',
    role:
        'Editorial writer. Synthesizes prior research and analysis into a '
        'crisp 3-paragraph briefing. Uses sentiment_scan to add one line of '
        'qualitative color at the end.',
    scope: scope,
  );
  writer.toolRegistry.registerTool(
    InstrumentedTool(inner: SentimentTool(), ownerAgent: 'writer'),
  );

  // --- Coordinator -----------------------------------------------------------
  // Last, so its prompt sees the three specialists already in scope.
  final coordinator = await Agent.create(
    dataStore: dataStore,
    llm: InstrumentedLlm(
      inner: baseLlm(temperature: 0.3),
      agentName: 'coordinator',
    ),
    name: 'coordinator',
    role:
        'Coordinator. Your ONLY job is to route work to specialists by '
        'returning an agents_chain. Do NOT answer questions yourself. For any '
        'topic the user asks about, delegate in this order: '
        '[researcher, analyst, writer]. researcher gathers facts, analyst '
        'computes numbers, writer produces the final briefing.',
    scope: scope,
  );

  AgentEventBus.instance.emitNow(
    AgentEventKind.agentResponded,
    'system',
    detail: 'Topology online: coordinator + 3 specialists, 4 tools.',
  );

  return AgentTopology(
    scope: scope,
    agents: [
      AgentNodeSpec(
        agent: coordinator,
        role: AgentRole.coordinator,
        label: 'Coordinator',
        tools: const [],
      ),
      AgentNodeSpec(
        agent: researcher,
        role: AgentRole.specialist,
        label: 'Researcher',
        tools: const ['web_search'],
      ),
      AgentNodeSpec(
        agent: analyst,
        role: AgentRole.specialist,
        label: 'Analyst',
        tools: const ['market_data', 'statistics'],
      ),
      AgentNodeSpec(
        agent: writer,
        role: AgentRole.specialist,
        label: 'Writer',
        tools: const ['sentiment_scan'],
      ),
    ],
  );
}
