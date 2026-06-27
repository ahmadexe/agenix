![Agenix Banner](https://github.com/user-attachments/assets/fbb110c9-6019-440b-b6c4-37d86dea725f)

# Agenix

<p align="center">
  <a href="https://github.com/ahmadexe/agenix/actions/workflows/ci.yml"><img src="https://github.com/ahmadexe/agenix/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="https://pub.dev/packages/agenix"><img src="https://img.shields.io/pub/v/agenix.svg" alt="Pub"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="License: MIT"></a>
  <a href="https://github.com/ahmadexe/agenix"><img src="https://img.shields.io/github/stars/ahmadexe/agenix.svg?style=flat&logo=github&colorB=deeppink&label=stars" alt="Stars"></a>
  <a href="https://pub.dev/packages/agenix"><img src="https://img.shields.io/badge/platform-Flutter%20%7C%20Dart-blue" alt="Platform"></a>
</p>

A Flutter package for building AI agents with memory, tools, and multi-agent orchestration. Define your agent's personality, give it tools, and let it handle conversations — including delegating sub-tasks across a chain of specialized agents.

<img width="960" height="600" alt="agenix_demo" src="https://raw.githubusercontent.com/ahmadexe/agenix/main/docs/visuals/agenix_demo.gif" />


> This is the **core** package. For Firebase persistence, see [`agenix_firebase`](https://pub.dev/packages/agenix_firebase).

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Agent](#agent)
  - [LLM](#llm)
  - [DataStore (Memory)](#datastore-memory)
  - [Tools](#tools)
  - [Multi-Agent Orchestration](#multi-agent-orchestration)
  - [Agent Scopes](#agent-scopes)
- [Error Handling](#error-handling)
- [API Reference](#api-reference)
- [Usage Architectures](#usage-architectures)
- [Examples](#examples)
- [Maintainers](#maintainers)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Your Flutter App                     │
│                                                             │
│   Agent.create(llm, dataStore, name, role)                  │
│       │                                                     │
│       ▼                                                     │
│   ┌─────────┐    generateResponse()    ┌───────────────┐    │
│   │  Agent   │ ◄─────────────────────► │   LLM         │    │
│   │         │                          │  (Gemini /     │    │
│   │         │                          │   Custom)      │    │
│   └────┬────┘                          └───────────────┘    │
│        │                                                     │
│   ┌────┴──────────────────────────┐                         │
│   │           │                   │                         │
│   ▼           ▼                   ▼                         │
│ ┌──────┐  ┌──────────┐  ┌────────────────┐                 │
│ │Tools │  │DataStore  │  │Agent Registry  │                 │
│ │      │  │(InMemory/ │  │(Multi-Agent    │                 │
│ │      │  │ Firebase/ │  │ Orchestration) │                 │
│ │      │  │ Custom)   │  │               │                  │
│ └──────┘  └──────────┘  └────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

The agent receives a user message, builds a structured prompt (including conversation history from the DataStore and available tools from the ToolRegistry), sends it to the LLM, and parses the response into one of three actions:

1. **Direct response** — returns text to the user
2. **Tool invocation** — runs one or more tools, optionally iterating up to 5 times before producing a final answer
3. **Agent delegation** — hands the task to a chain of other agents, each passing its output to the next

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  agenix: ^4.0.0
```

Then run:

```bash
flutter pub get
```

### Need persistence?

The core package ships with `DataStore.inMemory()` — a zero-dependency store for testing and prototyping. For production persistence with Firebase, add the companion package:

```yaml
dependencies:
  agenix: ^4.0.0
  agenix_firebase: ^1.0.0
```

See [`agenix_firebase`](https://pub.dev/packages/agenix_firebase) for setup instructions.

---

## Quick Start

### 1. Create system data

Create `assets/system_data.json` with your agent's personality and background knowledge:

```json
{
  "name": "Lens",
  "role": "A helpful assistant for the Acme platform",
  "personality": "Friendly, concise, and knowledgeable",
  "instructions": "Always greet the user by name when possible"
}
```

Add the asset to your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/system_data.json
```

### 2. Initialize the agent

```dart
import 'package:agenix/agenix.dart';

final agent = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: LLM.geminiLLM(
    apiKey: 'YOUR_API_KEY',
    modelName: 'gemini-2.0-flash',
  ),
  name: 'Assistant',
  role: 'General purpose assistant for the platform.',
);
```

### 3. Generate a response

```dart
final response = await agent.generateResponse(
  convoId: 'conversation-1',
  userMessage: AgentMessage(
    content: 'What is the weather like today?',
    isFromAgent: false,
    generatedAt: DateTime.now(),
  ),
);

print(response.content);
```

### 4. Run the app

```bash
flutter run -d chrome --dart-define=GEMINI_API_KEY=your-key-here
```

---

## Core Concepts

### Agent

The `Agent` is the central class. It wires together an LLM, a DataStore, a ToolRegistry, and an AgentScope.

```dart
final agent = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: LLM.geminiLLM(apiKey: key, modelName: 'gemini-2.0-flash'),
  name: 'Support Agent',
  role: 'Handles customer support queries for the e-commerce platform.',
  failureMode: FailureMode.throwError,  // or FailureMode.gracefulMessage (default)
  onError: (error, stack) => logger.severe('Agent error', error, stack),
  scope: AgentScope.global,             // default — or create isolated scopes
  registrationPolicy: RegistrationPolicy.throwIfExists,  // default
);
```

**Key methods:**

| Method | Description |
|---|---|
| `generateResponse(convoId, userMessage)` | Send a user message and get back an `AgentMessage` from the agent |
| `getMessages(conversationId)` | Retrieve all messages in a conversation |
| `getAllConversations()` | List all conversations for the current user |
| `deleteConversation(conversationId)` | Delete a conversation and its messages |
| `dispose()` | Unregister the agent from its scope |

**Parameters for `generateResponse`:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `convoId` | `String` | required | Conversation identifier |
| `userMessage` | `AgentMessage` | required | The user's message |
| `memoryLimit` | `int` | `10` | Max previous messages loaded as context |
| `metaData` | `Object?` | `null` | Opaque pass-through for auth tokens, tenant IDs, etc. |

---

### LLM

The `LLM` abstract class defines the contract for language model providers. Agenix ships with Gemini; implement the interface for other providers.

```dart
// Built-in Gemini
final llm = LLM.geminiLLM(
  apiKey: 'YOUR_API_KEY',
  modelName: 'gemini-2.0-flash',
  config: LlmConfig(
    temperature: 0.2,       // Low for structured JSON output
    maxOutputTokens: 2048,
    topP: 0.95,
    topK: 40,
    jsonMode: true,         // Request native JSON output mode
    timeout: Duration(seconds: 60),
  ),
);
```

**Implementing a custom LLM:**

```dart
class MyCustomLLM implements LLM {
  @override
  final String modelId = 'my-model-v1';

  @override
  final LlmConfig config;

  MyCustomLLM({this.config = const LlmConfig()});

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType = 'image/png',
  }) async {
    // Call your model API here
    // Must return a JSON string matching one of:
    //   {"response": "..."}
    //   {"tools": "tool1, tool2", "parameters": {...}}
    //   {"agents_chain": ["agent1", "agent2"]}
  }
}
```

---

### DataStore (Memory)

The `DataStore` abstract class handles conversation persistence. Messages are saved after each `generateResponse` call, and loaded as context for future prompts.

| DataStore | Package | Use Case |
|---|---|---|
| `DataStore.inMemory()` | `agenix` (this package) | Testing, prototyping, or non-persistent apps |
| `FirebaseDataStore()` | [`agenix_firebase`](https://pub.dev/packages/agenix_firebase) | Production apps with Firebase backend |

**Implementing a custom DataStore:**

```dart
class PostgresDataStore extends DataStore {
  @override
  Future<void> saveMessage(String convoId, AgentMessage msg, {Object? metaData}) async {
    // INSERT INTO messages ...
  }

  @override
  Future<List<AgentMessage>> getMessages(String conversationId, {int? limit, Object? metaData}) async {
    // SELECT * FROM messages WHERE convo_id = ? ORDER BY generated_at LIMIT ?
  }

  @override
  Future<void> deleteConversation(String conversationId, {Object? metaData}) async {
    // DELETE FROM messages WHERE convo_id = ?
  }

  @override
  Future<List<Conversation>> getConversations({Object? metaData}) async {
    // SELECT DISTINCT convo_id, last_message, last_message_time FROM ...
  }
}
```

---

### Tools

Tools let the agent perform actions beyond conversation — API calls, database queries, calculations, anything.

**Lifecycle:**

```
User Message → LLM decides tool is needed → Agent runs tool → Tool returns ToolResponse
    → Agent either returns result OR iterates (up to 5 rounds of tool calls)
```

#### Tool without parameters

```dart
class NewsTool extends Tool {
  NewsTool() : super(
    name: 'news_tool',
    description: 'Fetches the latest news headlines.',
  );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    final headlines = await NewsApi.fetchHeadlines();
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Here are today\'s headlines: ${headlines.join(", ")}',
      needsFurtherReasoning: true,  // Agent will synthesize a natural-language answer
    );
  }
}
```

#### Tool with parameters

```dart
class WeatherTool extends Tool {
  WeatherTool() : super(
    name: 'weather_tool',
    description: 'Gets current weather for a given location.',
    parameters: [
      ParameterSpecification(
        name: 'location',
        type: 'string',
        description: 'City name or coordinates.',
        required: true,
      ),
      ParameterSpecification(
        name: 'units',
        type: 'string',
        description: 'Temperature unit.',
        required: false,
        defaultValue: 'celsius',
        enumValues: ['celsius', 'fahrenheit'],
      ),
    ],
  );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    final location = params['location'] as String;
    final units = params['units'] as String? ?? 'celsius';
    final weather = await WeatherApi.get(location, units: units);
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Weather in $location: ${weather.temp}° ${weather.condition}',
      data: weather.toMap(),  // Optional structured data for chaining
    );
  }
}
```

#### Registering tools

```dart
agent.toolRegistry.registerTool(NewsTool());
agent.toolRegistry.registerTool(WeatherTool());

// Dynamically remove a tool
agent.toolRegistry.unregisterTool('weather_tool');
```

#### ToolResponse flags

| Field | Type | Description |
|---|---|---|
| `toolName` | `String` | Name of the tool that produced this response |
| `isRequestSuccessful` | `bool` | Whether the tool operation succeeded |
| `message` | `String` | Human-readable result shown to the user |
| `data` | `Map?` | Structured data for agent chaining or further reasoning |
| `needsFurtherReasoning` | `bool` | When `true`, the agent makes a second LLM call to synthesize the tool output into a natural-language answer |

---

### Multi-Agent Orchestration

When the LLM determines a task requires multiple specialists, it returns an `agents_chain`. Agenix automatically delegates sub-tasks across agents, passing each agent's output as input to the next.

```dart
// Create specialized agents
final newsAgent = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: llm,
  name: 'News Agent',
  role: 'Fetches and summarizes news articles.',
);

final favouritesAgent = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: llm,
  name: 'Favourites Agent',
  role: 'Manages user favourites: add, remove, and list.',
);

final orchestrator = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: llm,
  name: 'Orchestrator',
  role: 'Main user-facing agent. Delegates to News Agent and Favourites Agent.',
);

// Register tools on each agent as needed
newsAgent.toolRegistry.registerTool(NewsTool());
favouritesAgent.toolRegistry.registerTool(AddFavouriteTool());
favouritesAgent.toolRegistry.registerTool(ListFavouritesTool());
```

**How chaining works:**

```
User: "Save the top headline to my favourites"

┌──────────────┐     ┌────────────┐     ┌──────────────────┐
│ Orchestrator  │────►│ News Agent │────►│ Favourites Agent │
│              │     │            │     │                  │
│ Decides chain│     │ Fetches    │     │ Saves headline   │
│ [News, Favs] │     │ headlines  │     │ to favourites    │
└──────────────┘     └────────────┘     └──────────────────┘
                          │                      │
                          │  output passes as    │
                          │  input to next ──────┘
                                                 │
                                                 ▼
                                          Final response
                                          back to user
```

**Safety guardrails:**

- **Cycle detection** — if an agent appears twice in the same chain, a `ConfigException` is thrown
- **Depth limiting** — chains are capped at 5 levels deep (`kMaxChainDepth`)

---

### Agent Scopes

By default, all agents register in `AgentScope.global` and can discover each other for chaining. Use custom scopes to isolate agent groups:

```dart
// Isolated scope for testing
final testScope = AgentScope();

final agentA = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: llm,
  name: 'Agent A',
  role: 'Test agent A.',
  scope: testScope,
);

final agentB = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: llm,
  name: 'Agent B',
  role: 'Test agent B.',
  scope: testScope,
);

// Agents in testScope can chain to each other, but NOT to agents in AgentScope.global
```

**RegistrationPolicy** controls what happens when an agent name collides:

| Policy | Behavior |
|---|---|
| `throwIfExists` | Throws `ConfigException` (default — catches accidental duplicates) |
| `replace` | Silently replaces the existing agent |
| `ignore` | Keeps the existing agent, discards the new one |

---

## Error Handling

Agenix uses a sealed exception hierarchy. Every exception is an `AgenixException`, so you can exhaustively match on the type:

```dart
try {
  final response = await agent.generateResponse(
    convoId: 'convo-1',
    userMessage: message,
  );
} on LlmTimeoutException catch (e) {
  // LLM call exceeded the configured timeout
} on ResponseParseException catch (e) {
  // LLM returned malformed output after retries
  print('Raw output: ${e.rawOutput}');
} on ToolNotFoundException catch (e) {
  // LLM referenced a tool that isn't registered
  print('Missing tool: ${e.toolName}');
} on ToolExecutionException catch (e) {
  // A registered tool threw during execution
  print('Tool ${e.toolName} failed: ${e.message}');
} on AgentNotFoundException catch (e) {
  // Agent chain referenced a non-existent agent
} on DataStoreException catch (e) {
  // Persistence operation failed
} on NotAuthenticatedException {
  // DataStore operation without a signed-in user
} on ConfigException catch (e) {
  // Invalid configuration (bad system_data.json, duplicate agent name, etc.)
}
```

**FailureMode** controls the behavior at the `generateResponse` boundary:

| Mode | Behavior |
|---|---|
| `FailureMode.gracefulMessage` | Returns an `AgentMessage` with `isError: true` (default — safe for UI) |
| `FailureMode.throwError` | Rethrows the typed `AgenixException` (use when you want full control) |

The `onError` callback fires in both modes, so you can always log errors centrally:

```dart
final agent = await Agent.create(
  // ...
  failureMode: FailureMode.gracefulMessage,
  onError: (error, stack) => crashlytics.recordError(error, stack),
);
```

---

## API Reference

### Exported Classes

| Class | Description |
|---|---|
| `Agent` | Core agent with LLM, memory, tools, and multi-agent orchestration |
| `AgentScope` | Isolates groups of agents that can discover and chain to each other |
| `LLM` | Abstract interface for language model providers |
| `LlmConfig` | Provider-neutral generation settings (temperature, tokens, timeout, etc.) |
| `DataStore` | Abstract interface for conversation persistence |
| `AgentMessage` | A message in a conversation (user or agent) |
| `Conversation` | Summary of a conversation (last message, timestamp, ID) |
| `Tool` | Abstract class to extend for custom tools |
| `ParameterSpecification` | Defines a tool parameter (name, type, required, default, enum) |
| `ToolResponse` | Result returned from a tool execution |
| `ToolRegistry` | Per-agent registry for managing available tools |

### Exported Enums

| Enum | Values | Description |
|---|---|---|
| `FailureMode` | `throwError`, `gracefulMessage` | Controls error surfacing behavior |
| `RegistrationPolicy` | `throwIfExists`, `replace`, `ignore` | Controls duplicate agent name handling |

### Sealed Exception Hierarchy

```
AgenixException (sealed)
├── LlmException
│   └── LlmTimeoutException
├── ResponseParseException
├── ToolNotFoundException
├── ToolExecutionException
├── AgentNotFoundException
├── DataStoreException
│   └── NotAuthenticatedException
└── ConfigException
```

### Internal Constants

| Constant | Value | Description |
|---|---|---|
| `kMaxToolIterations` | `5` | Max tool→observe→re-prompt cycles per turn |
| `kMaxParseRetries` | `2` | Max corrective re-prompts for malformed JSON |
| `kMaxChainDepth` | `5` | Max depth for agent chain delegation |

---

## Usage Architectures

### Single-Agent Chat App

The simplest setup — one agent handling all user interactions.

```
┌──────────┐     ┌───────┐     ┌───────┐     ┌───────────┐
│  Flutter  │────►│ Agent │────►│  LLM  │     │ DataStore │
│    UI     │◄────│       │◄────│       │     │(InMemory/ │
└──────────┘     │       │     └───────┘     │ Firebase) │
                 │       │──── save/load ────►└───────────┘
                 └───────┘
```

Best for: chatbots, Q&A apps, customer support widgets.

### Agent + Tools (API Integration)

The agent can call external APIs through tools.

```
┌──────────┐     ┌───────┐     ┌───────┐
│  Flutter  │────►│ Agent │────►│  LLM  │
│    UI     │◄────│       │◄────│       │
└──────────┘     │       │     └───────┘
                 │       │
                 │  ToolRegistry
                 │  ├── WeatherTool ──► Weather API
                 │  ├── NewsTool ──► News API
                 │  └── DbTool ──► Database
                 └───────┘
```

Best for: apps where the agent needs to fetch real-time data or trigger actions.

### Multi-Agent Orchestration

Multiple specialized agents collaborating on complex tasks.

```
┌──────────┐     ┌──────────────┐
│  Flutter  │────►│ Orchestrator │
│    UI     │◄────│              │
└──────────┘     └──────┬───────┘
                        │ delegates via agents_chain
              ┌─────────┼─────────┐
              ▼         ▼         ▼
        ┌─────────┐ ┌────────┐ ┌───────────┐
        │ Search  │ │ Booking│ │ Favourites│
        │ Agent   │ │ Agent  │ │ Agent     │
        │ + tools │ │ + tools│ │ + tools   │
        └─────────┘ └────────┘ └───────────┘
```

Best for: complex platforms where different domains require specialized knowledge and tools.

### Testing / Prototyping Setup

Use `InMemoryDataStore` and scoped agents for fast, isolated development.

```dart
final scope = AgentScope();

final agent = await Agent.create(
  dataStore: DataStore.inMemory(),  // No Firebase needed
  llm: LLM.geminiLLM(apiKey: key, modelName: 'gemini-2.0-flash'),
  name: 'Test Agent',
  role: 'Agent under test.',
  scope: scope,  // Isolated from production agents
);
```

---

## Examples

| Example | Description |
|---|---|
| [Multi-Agent System](https://github.com/ahmadexe/agenix-examples/tree/main/multi_agent_system) | Three agents (Orchestrator, News, Favourites) working together |
| [Firebase Example](https://github.com/ahmadexe/agenix/tree/main/packages/agenix_firebase/example) | Single agent with tools and Firebase persistence |
| [Custom DataStore](https://github.com/ahmadexe/agenix-examples/tree/main/custom_data_source_example) | Implementing your own persistence backend |

---

## Companion Packages

| Package | Description |
|---|---|
| [`agenix_firebase`](https://pub.dev/packages/agenix_firebase) | Firebase (Firestore + Storage + Auth) data store backend |

---

## Maintainers

- [Muhammad Ahmad](https://github.com/ahmadexe)
