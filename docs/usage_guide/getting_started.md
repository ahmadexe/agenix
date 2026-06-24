# Getting Started

This guide walks you through installing Agenix and creating your first AI agent.

## Installation

Add Agenix to your `pubspec.yaml`:

```yaml
dependencies:
  agenix: ^4.0.0
```

If you want Firebase-backed persistence (optional), also add:

```yaml
dependencies:
  agenix_firebase: ^4.0.0
```

Then run:

```bash
flutter pub get
```

## Setting Up System Data

Agenix agents load a system data file at creation time. This file defines the agent's personality and instructions.

Create `assets/system_data.json` in your project root:

```json
{
  "name": "My Assistant",
  "personality": "friendly and helpful",
  "instructions": "You help users with their questions. Be concise and accurate."
}
```

Register the asset in your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/system_data.json
```

> **Tip:** The system data can be any JSON structure you want. It gets passed to the LLM as a system instruction, so think of it as your agent's "personality file."

## Core Concepts

Before writing code, here's what you need to know:

### Agent

The central class. An agent takes user messages, sends them to an LLM, and returns responses. It can also use tools and delegate to other agents.

### LLM

The language model that powers your agent. Agenix ships with a Gemini implementation, and you can create your own by extending the `LLM` abstract class.

### DataStore

Where conversation history is stored. Two built-in options:
- **InMemory** — no setup, data lost on restart. Great for prototyping.
- **Firebase** (via `agenix_firebase`) — persistent, cloud-backed. For production apps.

### Tool

An action your agent can perform — like calling an API, running a calculation, or controlling a device. You create tools by extending the `Tool` class.

### AgentScope

A container that groups agents together. Agents in the same scope can discover and delegate to each other.

## Your First Agent

Here's a complete example of a simple chatbot:

```dart
import 'package:flutter/material.dart';
import 'package:agenix/agenix.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ChatScreen());
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Agent? _agent;
  final List<AgentMessage> _messages = [];
  final _controller = TextEditingController();
  final String _convoId = 'main-chat';

  @override
  void initState() {
    super.initState();
    _initAgent();
  }

  Future<void> _initAgent() async {
    final agent = await Agent.create(
      dataStore: DataStore.inMemory(),
      llm: LLM.geminiLLM(
        apiKey: 'YOUR_GEMINI_API_KEY',
        modelName: 'gemini-2.0-flash',
      ),
      name: 'chatbot',
      role: 'A friendly chatbot that helps users with general questions.',
    );
    setState(() => _agent = agent);
  }

  Future<void> _sendMessage() async {
    if (_agent == null || _controller.text.isEmpty) return;

    final userMessage = AgentMessage(
      content: _controller.text,
      generatedAt: DateTime.now(),
      isFromAgent: false,
    );

    setState(() {
      _messages.add(userMessage);
      _controller.clear();
    });

    final response = await _agent!.generateResponse(
      convoId: _convoId,
      userMessage: userMessage,
    );

    setState(() => _messages.add(response));
  }

  @override
  void dispose() {
    _agent?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agenix Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return ListTile(
                  title: Text(msg.content),
                  leading: Icon(
                    msg.isFromAgent ? Icons.smart_toy : Icons.person,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

## LLM Configuration

You can fine-tune how the LLM behaves:

```dart
final llm = LLM.geminiLLM(
  apiKey: 'YOUR_API_KEY',
  modelName: 'gemini-2.0-flash',
  config: const LlmConfig(
    temperature: 0.7,       // Higher = more creative, lower = more focused
    maxOutputTokens: 1024,  // Max length of responses
    topP: 0.9,              // Nucleus sampling threshold
    topK: 40,               // Top-k sampling
    timeout: Duration(seconds: 30),
  ),
);
```

| Parameter | Default | What It Does |
|-----------|---------|-------------|
| `temperature` | `0.2` | Controls randomness. 0.0 = deterministic, 1.0 = very creative |
| `maxOutputTokens` | `null` (model default) | Maximum tokens in the response |
| `topP` | `null` | Nucleus sampling — only consider tokens with cumulative probability up to this value |
| `topK` | `null` | Only consider the top K most likely tokens |
| `jsonMode` | `true` | Force JSON output (required for Agenix's internal parsing) |
| `timeout` | `60 seconds` | How long to wait for the LLM before timing out |

> **Warning:** Don't set `jsonMode` to `false` unless you're building a custom LLM implementation. Agenix's prompt system relies on JSON responses.

## Conversation IDs

Every interaction needs a `convoId` (conversation ID). This is how Agenix groups messages into conversations:

```dart
// Each unique convoId is a separate conversation
await agent.generateResponse(convoId: 'chat-1', userMessage: msg);
await agent.generateResponse(convoId: 'chat-2', userMessage: msg); // different conversation
```

You control how conversation IDs are generated. Common patterns:
- **One conversation per session:** Use a UUID generated at app start
- **Persistent conversations:** Use a stable ID (e.g., `user-123-support`) stored in your app
- **Topic-based:** Use descriptive IDs like `onboarding`, `settings-help`

## What's Next?

- **Building a simple chatbot or assistant?** Read [Single Agent Architecture](single_agent.md)
- **Need your agent to call APIs or perform actions?** Read [Working with Tools](tools.md)
- **Building something with multiple specialized agents?** Read [Multi-Agent Architecture](multi_agent.md)
