# Single Agent Architecture

A single agent is the simplest and most common architecture. One agent handles all user interactions, optionally using tools to extend its capabilities.

## When to Use a Single Agent

Use a single agent when:
- You're building a **chatbot** or **conversational assistant**
- Your app has **one AI-powered feature** (summarization, Q&A, content generation)
- All interactions share the **same context and personality**
- You want the **simplest possible setup**

## Architecture Overview

```
┌──────────┐     ┌───────────┐     ┌─────────┐
│   User   │────▶│   Agent   │────▶│   LLM   │
│  (App)   │◀────│           │◀────│(Gemini) │
└──────────┘     │  ┌──────┐ │     └─────────┘
                 │  │Tools │ │
                 │  └──────┘ │
                 │  ┌──────┐ │
                 │  │Memory│ │
                 │  └──────┘ │
                 └───────────┘
```

The agent sits between your app and the LLM. It manages conversation memory, routes tool calls, and returns responses.

## Example: Customer Support Bot

A support bot that answers questions about your product:

### Step 1: Define System Data

Create `assets/system_data.json`:

```json
{
  "name": "SupportBot",
  "company": "Acme Inc",
  "personality": "professional, empathetic, and solution-oriented",
  "instructions": "You are a customer support agent for Acme Inc. Help users with their product questions, troubleshooting, and account issues. If you cannot solve a problem, suggest they contact human support at support@acme.com."
}
```

### Step 2: Create the Agent

```dart
class SupportService {
  late final Agent _agent;

  Future<void> initialize(String apiKey) async {
    _agent = await Agent.create(
      dataStore: DataStore.inMemory(),
      llm: LLM.geminiLLM(
        apiKey: apiKey,
        modelName: 'gemini-2.0-flash',
      ),
      name: 'support-bot',
      role: 'Customer support agent for Acme Inc products.',
    );
  }

  Future<String> ask(String conversationId, String question) async {
    final response = await _agent.generateResponse(
      convoId: conversationId,
      userMessage: AgentMessage(
        content: question,
        generatedAt: DateTime.now(),
        isFromAgent: false,
      ),
    );
    return response.content;
  }

  Future<List<AgentMessage>> getHistory(String conversationId) {
    return _agent.getMessages(conversationId: conversationId);
  }

  void dispose() => _agent.dispose();
}
```

### Step 3: Use It in Your UI

```dart
class _SupportChatState extends State<SupportChat> {
  final _service = SupportService();
  final _messages = <AgentMessage>[];
  final _convoId = const Uuid().v4(); // unique per session

  @override
  void initState() {
    super.initState();
    _service.initialize('YOUR_API_KEY');
  }

  Future<void> _send(String text) async {
    final userMsg = AgentMessage(
      content: text,
      generatedAt: DateTime.now(),
      isFromAgent: false,
    );
    setState(() => _messages.add(userMsg));

    final reply = await _service.ask(_convoId, text);
    setState(() => _messages.add(AgentMessage(
      content: reply,
      generatedAt: DateTime.now(),
      isFromAgent: true,
    )));
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  // ... build method with chat UI
}
```

## Example: Content Generator

An agent that generates marketing copy, blog posts, or social media content:

```dart
Future<void> setupContentGenerator() async {
  final agent = await Agent.create(
    dataStore: DataStore.inMemory(),
    llm: LLM.geminiLLM(
      apiKey: apiKey,
      modelName: 'gemini-2.0-flash',
      config: const LlmConfig(
        temperature: 0.8, // higher creativity for content generation
        maxOutputTokens: 2048,
      ),
    ),
    name: 'content-writer',
    role: 'Creative content writer specializing in marketing copy, '
        'blog posts, and social media content. Write in a conversational, '
        'engaging tone.',
  );

  // Each content piece gets its own conversation for clean context
  final blogConvoId = const Uuid().v4();
  
  final outline = await agent.generateResponse(
    convoId: blogConvoId,
    userMessage: AgentMessage(
      content: 'Write an outline for a blog post about AI in mobile apps.',
      generatedAt: DateTime.now(),
      isFromAgent: false,
    ),
  );

  // Follow up in the same conversation — the agent remembers the outline
  final draft = await agent.generateResponse(
    convoId: blogConvoId,
    userMessage: AgentMessage(
      content: 'Now write the full blog post based on that outline.',
      generatedAt: DateTime.now(),
      isFromAgent: false,
    ),
  );
}
```

## Memory Limit

By default, the agent sends the last **10 messages** as context to the LLM. You can adjust this:

```dart
final response = await agent.generateResponse(
  convoId: convoId,
  userMessage: message,
  memoryLimit: 20, // send last 20 messages for more context
);
```

**Trade-offs:**
- **Higher limit** = more context, better continuity, but more tokens (slower + more expensive)
- **Lower limit** = faster responses, less context, agent may "forget" earlier messages
- **For most chatbots:** 10-15 is a good balance
- **For long-form content generation:** 20-30 helps maintain consistency

## Managing Conversations

```dart
// List all conversations
final conversations = await agent.getAllConversations();
for (final convo in conversations) {
  print('${convo.conversationId}: ${convo.lastMessage}');
}

// Get messages for a specific conversation
final messages = await agent.getMessages(conversationId: 'chat-1');

// Delete a conversation
await agent.deleteConversation(conversationId: 'chat-1');
```

## Best Practices for Single Agents

1. **Write a clear role.** The `role` parameter is your most important lever. Be specific about what the agent should and shouldn't do.

2. **Use conversation IDs strategically.** One conversation per user session is simplest. For apps where users return to past topics, persist the conversation ID.

3. **Start with InMemory, switch to Firebase later.** Get your agent logic right first, then swap `DataStore.inMemory()` for `DataStore.firestoreDataStore()` when you're ready to persist.

4. **Tune temperature for your use case:**
   - Factual Q&A: `0.1 - 0.3`
   - General chat: `0.4 - 0.6`
   - Creative writing: `0.7 - 0.9`

5. **Dispose when done.** Always call `agent.dispose()` when the agent is no longer needed to clean up the scope registry.

## When to Move Beyond a Single Agent

Consider [multi-agent architecture](multi_agent.md) when:
- You have **distinct AI responsibilities** that need different roles/personalities
- One agent's output should **feed into another agent's input**
- You want **separation of concerns** (e.g., a "researcher" agent and a "writer" agent)
- Your single agent's role description is getting too complex

## Next Steps

- Add capabilities to your agent with [Tools](tools.md)
- Scale up to [Multi-Agent Architecture](multi_agent.md)
- Add persistent storage with [Memory & Persistence](memory_and_persistence.md)
