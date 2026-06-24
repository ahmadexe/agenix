# Multi-Agent Architecture

When a single agent isn't enough, Agenix lets you create multiple specialized agents that can discover each other and chain together. This is powerful for complex workflows where different steps need different expertise.

## When to Use Multiple Agents

Use multi-agent architecture when:
- You have **distinct responsibilities** that benefit from separate roles (researcher + writer, planner + executor)
- You want **separation of concerns** — each agent has a focused role
- One agent's output should **feed into another** (pipelines)
- You need **different LLM configurations** for different tasks (e.g., low temperature for analysis, high for creative writing)

**Don't use multiple agents when:**
- A single agent with tools can do the job
- The tasks don't benefit from different personalities/roles
- You're just trying to organize code (use services/classes instead)

## Core Concepts

### AgentScope

An `AgentScope` is a container that groups agents together. Agents in the same scope can see each other and delegate work.

```dart
// The default — all agents share this scope
AgentScope.global

// Create a custom scope to isolate groups of agents
final myScope = AgentScope();
```

### Agent Registration

When you create an agent, it registers itself in its scope. Other agents in the same scope can then discover and delegate to it.

```dart
// These two agents can see each other (both in global scope by default)
final researcher = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'researcher',
  role: 'Finds and summarizes information on any topic.',
);

final writer = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'writer',
  role: 'Writes polished content based on research and instructions.',
);
```

### Registration Policies

Control what happens when an agent name conflicts:

```dart
// Default: throws an error if the name already exists
final agent = await Agent.create(
  // ...
  registrationPolicy: RegistrationPolicy.throwIfExists,
);

// Replace the existing agent with this one
final agent = await Agent.create(
  // ...
  registrationPolicy: RegistrationPolicy.replace,
);

// Silently skip registration if the name exists
final agent = await Agent.create(
  // ...
  registrationPolicy: RegistrationPolicy.ignore,
);
```

## Architecture Pattern 1: Independent Agents

Multiple agents exist side by side, and your app decides which one to use.

```
┌──────────┐
│   User   │
│  (App)   │
└────┬─────┘
     │ App logic decides which agent to use
     ├──────────────────┬──────────────────┐
     ▼                  ▼                  ▼
┌──────────┐     ┌──────────┐     ┌──────────┐
│ Support  │     │  Sales   │     │ Technical│
│  Agent   │     │  Agent   │     │  Agent   │
└──────────┘     └──────────┘     └──────────┘
```

### Example: Department Router

```dart
class CustomerService {
  late final Agent _supportAgent;
  late final Agent _salesAgent;
  late final Agent _techAgent;

  Future<void> initialize(String apiKey) async {
    final dataStore = DataStore.inMemory();
    final llm = LLM.geminiLLM(apiKey: apiKey, modelName: 'gemini-2.0-flash');

    _supportAgent = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'support',
      role: 'Handles general customer support: returns, refunds, account issues.',
    );

    _salesAgent = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'sales',
      role: 'Handles product inquiries, pricing, and purchase assistance.',
    );

    _techAgent = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'tech-support',
      role: 'Handles technical troubleshooting, setup guides, and bug reports.',
    );
  }

  /// Route to the right agent based on the department
  Future<AgentMessage> ask(String department, String convoId, String question) {
    final agent = switch (department) {
      'support' => _supportAgent,
      'sales'   => _salesAgent,
      'tech'    => _techAgent,
      _         => _supportAgent, // fallback
    };

    return agent.generateResponse(
      convoId: convoId,
      userMessage: AgentMessage(
        content: question,
        generatedAt: DateTime.now(),
        isFromAgent: false,
      ),
    );
  }

  void dispose() {
    _supportAgent.dispose();
    _salesAgent.dispose();
    _techAgent.dispose();
  }
}
```

## Architecture Pattern 2: Orchestrator Agent (AI-Powered Routing)

In Pattern 1, your **app logic** decides which agent to use (e.g., the user picks a department from a dropdown). But what if you can't predict which agent is needed? What if the user says something ambiguous like "I need help" and only AI can figure out the right destination?

That's where the **orchestrator agent** comes in. It's a lightweight agent whose only job is to understand the user's intent and delegate to the right specialist via an agent chain.

```
User: "My order hasn't arrived and I want to return it"
         │
         ▼
┌──────────────────┐
│  Orchestrator    │ ──▶ LLM reads intent, decides: chain [order-specialist]
│  (no tools,      │
│   only routes)   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Order Specialist │ ──▶ Uses tools to look up order, initiate return
└──────────────────┘
         │
         ▼
User sees: "I found your order #4821. It's delayed due to..."
```

### Why Not Just Use One Big Agent?

You might wonder: "Why not make one agent that does everything?" A few reasons:

- **Focused roles produce better results.** An agent with the role "handle orders" outperforms one with the role "handle orders, products, billing, tech support, and complaints." Narrower context = better LLM output.
- **Different tasks may need different LLM configs.** Your researcher might need low temperature (factual), while your writer needs high temperature (creative).
- **Tools stay organized.** Each specialist only has the tools it needs, reducing confusion for the LLM.

### Example: AI-Powered Customer Service Router

```dart
class AiCustomerService {
  late final Agent _orchestrator;
  late final Agent _supportAgent;
  late final Agent _salesAgent;
  late final Agent _techAgent;

  Future<void> initialize(String apiKey) async {
    final dataStore = DataStore.inMemory();
    final llm = LLM.geminiLLM(apiKey: apiKey, modelName: 'gemini-2.0-flash');

    // Specialist agents — each has a focused role and its own tools
    _supportAgent = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'support',
      role: 'Handles general customer support: returns, refunds, '
          'account issues, and complaints.',
    );
    _supportAgent.toolRegistry.registerTool(RefundTool());
    _supportAgent.toolRegistry.registerTool(AccountLookupTool());

    _salesAgent = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'sales',
      role: 'Handles product inquiries, pricing, comparisons, '
          'and purchase assistance.',
    );
    _salesAgent.toolRegistry.registerTool(ProductSearchTool());
    _salesAgent.toolRegistry.registerTool(PriceCompareTool());

    _techAgent = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'tech-support',
      role: 'Handles technical troubleshooting, setup guides, '
          'connectivity issues, and bug reports.',
    );
    _techAgent.toolRegistry.registerTool(DiagnosticsTool());

    // Orchestrator — no tools, only routes to the right specialist.
    // It sees all 3 agents above because they share the same scope.
    _orchestrator = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'orchestrator',
      role: 'You are a routing agent. Your ONLY job is to understand '
          'the user\'s intent and delegate to the right specialist agent. '
          'Do NOT answer questions yourself. Always delegate to one of: '
          'support (returns, refunds, account), sales (products, pricing), '
          'or tech-support (troubleshooting, bugs).',
    );
  }

  /// User always talks to the orchestrator — it figures out the rest
  Future<AgentMessage> chat(String convoId, String message) {
    return _orchestrator.generateResponse(
      convoId: convoId,
      userMessage: AgentMessage(
        content: message,
        generatedAt: DateTime.now(),
        isFromAgent: false,
      ),
    );
  }

  void dispose() {
    _orchestrator.dispose();
    _supportAgent.dispose();
    _salesAgent.dispose();
    _techAgent.dispose();
  }
}
```

### Key Points About the Orchestrator Pattern

1. **The orchestrator has no tools.** Its only job is routing. Don't give it tools — that muddies its purpose.
2. **Write a strict role.** Tell it explicitly: "Do NOT answer questions yourself. Always delegate." Otherwise the LLM might try to answer directly.
3. **All agents must be in the same scope.** The orchestrator can only see and delegate to agents in its scope. By default, all agents share `AgentScope.global`.
4. **The orchestrator sees agent names and roles.** Agenix's prompt builder automatically tells the LLM about every agent in scope (name + role), so the orchestrator can make informed routing decisions.
5. **Delegated agents respond directly.** When the orchestrator chains to a specialist, that specialist processes the request with its own tools and returns the answer to the user. The specialist cannot re-chain (this prevents loops).

### When to Use Orchestrator vs. Independent Agents

| Scenario | Use |
|----------|-----|
| User explicitly picks a category (dropdown, tab) | Independent agents (Pattern 1) |
| Free-text input where intent is ambiguous | Orchestrator agent (Pattern 2) |
| Mixed — some routes are obvious, some need AI | Orchestrator with a simple pre-filter in app code |

## Architecture Pattern 3: Agent Chains (Pipelines)

The LLM itself decides to delegate work to other agents. When an agent realizes it needs help, it can trigger a chain — passing its task to other agents in sequence, where each agent's output feeds into the next.

```
User: "Research AI trends and write a blog post about them"
         │
         ▼
┌──────────────────┐
│  Coordinator     │ ──▶ LLM decides: chain [researcher, writer]
│  Agent           │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Researcher      │ ──▶ "Top AI trends: 1. Agents 2. RAG 3. ..."
│  Agent           │
└────────┬─────────┘
         │ output feeds into
         ▼
┌──────────────────┐
│  Writer          │ ──▶ "# AI Trends 2024\n\nThe AI landscape..."
│  Agent           │
└──────────────────┘
         │
         ▼
User sees the finished blog post
```

### How It Works

1. All agents are created in the same scope
2. The prompt builder automatically tells the LLM about other available agents
3. The LLM can respond with `{"agents_chain": ["agent1", "agent2"]}` to delegate
4. Agenix runs each agent in sequence, passing output forward
5. The final agent's response is returned to the user

### Example: Research & Write Pipeline

```dart
Future<void> setupResearchPipeline(String apiKey) async {
  final dataStore = DataStore.inMemory();

  // Researcher: factual, low temperature
  final researcher = await Agent.create(
    dataStore: dataStore,
    llm: LLM.geminiLLM(
      apiKey: apiKey,
      modelName: 'gemini-2.0-flash',
      config: const LlmConfig(temperature: 0.1),
    ),
    name: 'researcher',
    role: 'Research specialist. Finds accurate, detailed information on any '
        'topic. Always cites sources and provides structured data.',
  );

  // Writer: creative, higher temperature
  final writer = await Agent.create(
    dataStore: dataStore,
    llm: LLM.geminiLLM(
      apiKey: apiKey,
      modelName: 'gemini-2.0-flash',
      config: const LlmConfig(temperature: 0.7, maxOutputTokens: 2048),
    ),
    name: 'writer',
    role: 'Content writer. Takes research or raw information and transforms '
        'it into engaging, well-structured content. Adapts tone to the '
        'requested format (blog post, email, social media, etc).',
  );

  // Coordinator: orchestrates the others
  final coordinator = await Agent.create(
    dataStore: dataStore,
    llm: LLM.geminiLLM(
      apiKey: apiKey,
      modelName: 'gemini-2.0-flash',
    ),
    name: 'coordinator',
    role: 'Project coordinator. Analyzes user requests and delegates to '
        'specialized agents. For research + writing tasks, delegate to '
        'researcher first, then writer.',
  );

  // User talks to the coordinator
  final response = await coordinator.generateResponse(
    convoId: 'project-1',
    userMessage: AgentMessage(
      content: 'Research the latest trends in mobile AI and write a '
          'short blog post about the top 3 trends.',
      generatedAt: DateTime.now(),
      isFromAgent: false,
    ),
  );

  // The coordinator chains: researcher → writer
  // The user gets the writer's polished blog post
  print(response.content);
}
```

### Chain Safety

Agenix has built-in safety mechanisms for agent chains:

- **Cycle detection:** If agent A delegates to agent B which tries to delegate back to A, the chain stops.
- **Depth limit:** Chains are limited to **5 levels** deep to prevent runaway delegation.
- **Chained agents can't re-chain:** When an agent is called as part of a chain, it can only use tools or respond directly — it cannot start a new chain. This prevents infinite loops.

## Architecture Pattern 4: Scoped Agent Groups

Use `AgentScope` to create isolated groups of agents that can only see each other:

```
┌─────────────────────────┐     ┌─────────────────────────┐
│   Content Scope          │     │   Analytics Scope        │
│                          │     │                          │
│  ┌──────┐  ┌──────┐    │     │  ┌──────┐  ┌──────┐    │
│  │Writer│  │Editor│    │     │  │Analyst│  │Report│    │
│  │      │◀▶│      │    │     │  │       │◀▶│Writer│    │
│  └──────┘  └──────┘    │     │  └──────┘  └──────┘    │
│                          │     │                          │
│  These agents can ONLY   │     │  These agents can ONLY   │
│  see each other          │     │  see each other          │
└─────────────────────────┘     └─────────────────────────┘
```

### Example: Isolated Scopes

```dart
// Content team — writer and editor work together
final contentScope = AgentScope();

final contentWriter = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'writer',
  role: 'Writes first drafts of content.',
  scope: contentScope,
);

final contentEditor = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'editor',
  role: 'Reviews and improves written content for clarity and grammar.',
  scope: contentScope,
);

// Analytics team — analyst and report writer work together
final analyticsScope = AgentScope();

final analyst = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'analyst',
  role: 'Analyzes data and identifies trends.',
  scope: analyticsScope,
);

final reportWriter = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'report-writer',
  role: 'Creates formatted reports from analysis results.',
  scope: analyticsScope,
);

// The writer can delegate to the editor (same scope), but NOT to the analyst
// The analyst can delegate to the report-writer (same scope), but NOT to the writer
```

## Choosing the Right Pattern

| Pattern | Use When | Example |
|---------|----------|---------|
| **Independent Agents** | Your app controls routing; agents don't need to talk to each other | Department-based support, tabbed AI features |
| **Orchestrator Agent** | Free-text input where AI must decide which specialist to use | AI-powered customer service, open-ended chat with multiple capabilities |
| **Agent Chains** | Tasks naturally flow as pipelines; one agent's output feeds another | Research → Write, Analyze → Summarize |
| **Scoped Groups** | You have multiple teams of agents that should be isolated | Content team, Analytics team, separate customer tenants |

## Complete Example: E-Commerce Assistant

An e-commerce app with a coordinator, product expert, and order specialist:

```dart
class ECommerceAI {
  late final Agent coordinator;
  late final Agent productExpert;
  late final Agent orderSpecialist;

  Future<void> initialize(String apiKey) async {
    final dataStore = DataStore.inMemory();
    final llm = LLM.geminiLLM(apiKey: apiKey, modelName: 'gemini-2.0-flash');

    // Product expert with search tools
    productExpert = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'product-expert',
      role: 'Product specialist. Helps customers find products, compare '
          'options, and make purchase decisions. Has access to the product '
          'catalog via tools.',
    );
    productExpert.toolRegistry.registerTool(ProductSearchTool());
    productExpert.toolRegistry.registerTool(PriceCompareTool());

    // Order specialist with order management tools
    orderSpecialist = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'order-specialist',
      role: 'Order management specialist. Helps customers track orders, '
          'process returns, and handle shipping issues.',
    );
    orderSpecialist.toolRegistry.registerTool(OrderLookupTool());
    orderSpecialist.toolRegistry.registerTool(ReturnRequestTool());

    // Coordinator — talks to the user, delegates to specialists
    coordinator = await Agent.create(
      dataStore: dataStore,
      llm: llm,
      name: 'coordinator',
      role: 'Customer service coordinator for an e-commerce store. '
          'Greet customers warmly, understand their needs, and delegate to '
          'the right specialist: product-expert for product questions, '
          'order-specialist for order-related issues.',
    );
  }

  Future<AgentMessage> chat(String convoId, String message) {
    return coordinator.generateResponse(
      convoId: convoId,
      userMessage: AgentMessage(
        content: message,
        generatedAt: DateTime.now(),
        isFromAgent: false,
      ),
    );
  }

  void dispose() {
    coordinator.dispose();
    productExpert.dispose();
    orderSpecialist.dispose();
  }
}
```

**User flow:**
1. User says: "I want to find a laptop under $1000 and also check on my last order"
2. Coordinator chains: `product-expert` → `order-specialist`
3. Product expert uses `ProductSearchTool` to find laptops
4. Order specialist uses `OrderLookupTool` to check the order
5. User gets a combined response covering both topics

## Best Practices

1. **Give agents distinct, non-overlapping roles.** If two agents do similar things, the LLM won't know which to pick.

2. **Name agents descriptively.** The LLM sees agent names and roles when deciding to delegate. `researcher` is better than `agent-1`.

3. **Use a coordinator pattern for complex workflows.** Have one "router" agent that the user talks to, which delegates to specialists.

4. **Keep chains short.** 2-3 agents in a chain is ideal. Longer chains increase latency and token cost.

5. **Use scopes to prevent unwanted delegation.** If agents shouldn't talk to each other, put them in different scopes.

6. **Remember: each agent has its own tools.** Register tools on the agents that need them, not on the coordinator.

7. **Dispose all agents.** When you're done, dispose each agent to clean up the scope registry.

## Next Steps

- Add persistent memory with [Memory & Persistence](memory_and_persistence.md)
- Handle failures gracefully with [Error Handling](error_handling.md)
