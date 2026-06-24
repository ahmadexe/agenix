# Agenix Usage Guide

Welcome to the Agenix usage guide. This documentation will help you understand how to build AI-powered agents in your Flutter apps using Agenix.

## Table of Contents

| Guide | Description |
|-------|-------------|
| [Getting Started](getting_started.md) | Installation, setup, and your first agent |
| [Single Agent Architecture](single_agent.md) | Building apps with one agent — chatbots, assistants, Q&A |
| [Working with Tools](tools.md) | Give your agent superpowers — API calls, calculations, device actions |
| [Multi-Agent Architecture](multi_agent.md) | Orchestrating multiple specialized agents that work together |
| [Memory & Persistence](memory_and_persistence.md) | Conversation history, storage backends, and the DataStore system |
| [Error Handling](error_handling.md) | Graceful failures, exception types, and recovery strategies |
| [Advanced Patterns](advanced_patterns.md) | Multimodal input, custom LLMs, custom data stores, and more |

## Which Architecture Is Right for You?

```
Do you need one AI capability or many?
│
├── One capability (e.g., a chatbot, a summarizer)
│   └── Use a Single Agent → see single_agent.md
│
└── Multiple capabilities that need to collaborate
    │
    ├── Each capability is independent (user picks which to talk to)
    │   └── Use Multiple Independent Agents → see multi_agent.md#independent-agents
    │
    └── Capabilities need to chain together (output of one feeds another)
        └── Use Agent Chains → see multi_agent.md#agent-chains
```

## Quick Example

```dart
import 'package:agenix/agenix.dart';

// 1. Create a data store (in-memory for prototyping)
final dataStore = DataStore.inMemory();

// 2. Create an LLM
final llm = LLM.geminiLLM(
  apiKey: 'YOUR_API_KEY',
  modelName: 'gemini-2.0-flash',
);

// 3. Create an agent
final agent = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'assistant',
  role: 'A helpful assistant that answers questions clearly and concisely.',
);

// 4. Send a message
final response = await agent.generateResponse(
  convoId: 'conversation-1',
  userMessage: AgentMessage(
    content: 'What is Flutter?',
    generatedAt: DateTime.now(),
    isFromAgent: false,
  ),
);

print(response.content);
```
