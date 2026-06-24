# Advanced Patterns

This guide covers advanced use cases: multimodal input, building custom LLMs, architecture patterns for production apps, and more.

## Multimodal Input (Images)

Agenix supports sending images alongside text. The LLM receives both and can reason about the image.

```dart
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

Future<void> sendImageMessage(Agent agent, String convoId) async {
  // Pick an image
  final picker = ImagePicker();
  final file = await picker.pickImage(source: ImageSource.gallery);
  if (file == null) return;

  final imageBytes = await file.readAsBytes();

  final response = await agent.generateResponse(
    convoId: convoId,
    userMessage: AgentMessage(
      content: 'What do you see in this image?',
      generatedAt: DateTime.now(),
      isFromAgent: false,
      imageData: imageBytes,
      mimeType: 'image/jpeg', // or 'image/png'
    ),
  );

  print(response.content); // "I see a golden retriever playing in a park..."
}
```

### How Images Flow Through the System

1. You attach `imageData` (raw bytes) and `mimeType` to the `AgentMessage`
2. The agent passes these to the LLM's `generate()` method via `rawData` and `mimeType`
3. The Gemini implementation sends the image as inline data alongside the text prompt
4. If using Firebase DataStore, the image is automatically uploaded to Firebase Storage and the `imageUrl` is saved

### Image-Based Tools

You can build tools that process images:

```dart
class ImageAnalysisTool extends Tool {
  ImageAnalysisTool()
      : super(
          name: 'analyze_image',
          description: 'Analyzes an uploaded image for objects, text, or specific features.',
          parameters: [
            ParameterSpecification(
              name: 'analysis_type',
              type: 'string',
              description: 'What to look for in the image.',
              required: true,
              enumValues: ['objects', 'text', 'faces', 'colors'],
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    final type = params['analysis_type'] as String;
    // Your image analysis logic here
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Analysis complete: found 3 objects...',
      needsFurtherReasoning: true,
    );
  }
}
```

## Building a Custom LLM

To use a different language model (OpenAI, Anthropic, local models, etc.), extend the `LLM` abstract class:

```dart
import 'dart:typed_data';
import 'package:agenix/agenix.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class OpenAiLLM extends LLM {
  final String apiKey;
  final String model;
  final LlmConfig _config;

  OpenAiLLM({
    required this.apiKey,
    this.model = 'gpt-4',
    LlmConfig config = const LlmConfig(),
  }) : _config = config;

  @override
  String get modelId => model;

  @override
  LlmConfig get config => _config;

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType = 'image/jpeg',
  }) async {
    final messages = <Map<String, dynamic>>[];

    if (systemInstruction != null) {
      messages.add({'role': 'system', 'content': systemInstruction});
    }

    // Build user message (text + optional image)
    if (rawData != null) {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': prompt},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:$mimeType;base64,${base64Encode(rawData)}',
            },
          },
        ],
      });
    } else {
      messages.add({'role': 'user', 'content': prompt});
    }

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': _config.temperature,
        if (_config.maxOutputTokens != null)
          'max_tokens': _config.maxOutputTokens,
        if (_config.jsonMode) 'response_format': {'type': 'json_object'},
      }),
    ).timeout(_config.timeout);

    final body = jsonDecode(response.body);
    return body['choices'][0]['message']['content'] as String;
  }
}
```

Use it like any other LLM:

```dart
final agent = await Agent.create(
  dataStore: DataStore.inMemory(),
  llm: OpenAiLLM(apiKey: 'sk-...', model: 'gpt-4'),
  name: 'assistant',
  role: 'A helpful assistant.',
);
```

> **Important:** Your custom LLM must return valid JSON when `jsonMode` is true. Agenix's prompt parser expects JSON responses in one of three shapes: `{"response": "..."}`, `{"tools": "...", "parameters": {...}}`, or `{"agents_chain": [...]}`.

## Production Architecture Patterns

### Pattern 1: Service Layer

Wrap your agents in a service class that handles initialization, configuration, and lifecycle:

```dart
class AiService {
  static AiService? _instance;
  late final Agent _agent;
  bool _initialized = false;

  AiService._();

  static AiService get instance => _instance ??= AiService._();

  Future<void> initialize({
    required String apiKey,
    required DataStore dataStore,
  }) async {
    if (_initialized) return;

    _agent = await Agent.create(
      dataStore: dataStore,
      llm: LLM.geminiLLM(
        apiKey: apiKey,
        modelName: 'gemini-2.0-flash',
      ),
      name: 'app-assistant',
      role: 'A helpful assistant for our app.',
      onError: (error, stack) {
        // Send to your error tracking
        ErrorReporting.capture(error, stack);
      },
    );

    _agent.toolRegistry.registerTool(SearchTool());
    _agent.toolRegistry.registerTool(BookmarkTool());

    _initialized = true;
  }

  Future<AgentMessage> chat(String convoId, String message) {
    assert(_initialized, 'Call initialize() first');
    return _agent.generateResponse(
      convoId: convoId,
      userMessage: AgentMessage(
        content: message,
        generatedAt: DateTime.now(),
        isFromAgent: false,
      ),
    );
  }

  Future<List<Conversation>> getConversations() {
    return _agent.getAllConversations();
  }

  void dispose() {
    _agent.dispose();
    _initialized = false;
    _instance = null;
  }
}
```

### Pattern 2: Provider/Riverpod Integration

```dart
// With Riverpod
final dataStoreProvider = Provider<DataStore>((ref) => DataStore.inMemory());

final agentProvider = FutureProvider<Agent>((ref) async {
  final dataStore = ref.watch(dataStoreProvider);

  final agent = await Agent.create(
    dataStore: dataStore,
    llm: LLM.geminiLLM(
      apiKey: const String.fromEnvironment('GEMINI_API_KEY'),
      modelName: 'gemini-2.0-flash',
    ),
    name: 'assistant',
    role: 'A helpful assistant.',
  );

  ref.onDispose(() => agent.dispose());
  return agent;
});

// In your widget
class ChatScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentAsync = ref.watch(agentProvider);

    return agentAsync.when(
      data: (agent) => ChatBody(agent: agent),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load AI: $e')),
    );
  }
}
```

### Pattern 3: Feature Flags for AI

Gradually roll out AI features by wrapping agent creation behind feature flags:

```dart
class SmartAssistant {
  Agent? _agent;

  Future<void> initialize({required bool aiEnabled}) async {
    if (!aiEnabled) return; // AI feature is off

    _agent = await Agent.create(
      dataStore: DataStore.inMemory(),
      llm: LLM.geminiLLM(
        apiKey: apiKey,
        modelName: 'gemini-2.0-flash',
      ),
      name: 'assistant',
      role: 'A helpful assistant.',
    );
  }

  Future<String?> suggest(String context) async {
    if (_agent == null) return null; // AI not available

    final response = await _agent!.generateResponse(
      convoId: 'suggestions',
      userMessage: AgentMessage(
        content: context,
        generatedAt: DateTime.now(),
        isFromAgent: false,
      ),
    );

    return response.isError ? null : response.content;
  }
}
```

## System Data Customization

The `assets/system_data.json` file is your agent's "brain configuration." Here are patterns for different use cases:

### Minimal (chatbot)

```json
{
  "instructions": "You are a friendly chatbot. Be helpful and concise."
}
```

### Detailed (domain expert)

```json
{
  "name": "MedBot",
  "domain": "healthcare",
  "personality": "professional, empathetic, careful",
  "instructions": "You are a health information assistant. Provide general health information based on established medical knowledge. Always recommend consulting a healthcare professional for specific medical advice.",
  "constraints": [
    "Never diagnose conditions",
    "Never recommend specific medications",
    "Always suggest seeing a doctor for serious symptoms"
  ],
  "knowledge_areas": [
    "General wellness",
    "Nutrition basics",
    "Exercise guidelines",
    "Common symptom information"
  ]
}
```

### Custom system data path

```dart
final agent = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'assistant',
  role: 'A helpful assistant.',
  pathToSystemData: 'assets/agents/support_bot.json', // custom path
);
```

## Conversation Design Patterns

### One Conversation Per Feature

```dart
class AppAssistant {
  final Agent _agent;

  // Each feature gets a stable conversation ID
  Future<String> getOnboardingHelp(String question) =>
      _chat('onboarding', question);

  Future<String> getSettingsHelp(String question) =>
      _chat('settings-help', question);

  Future<String> getSearchAssistance(String question) =>
      _chat('search-assist', question);

  Future<String> _chat(String convoId, String question) async {
    final response = await _agent.generateResponse(
      convoId: convoId,
      userMessage: AgentMessage(
        content: question,
        generatedAt: DateTime.now(),
        isFromAgent: false,
      ),
    );
    return response.content;
  }
}
```

### User-Scoped Conversations

```dart
// Prefix conversation IDs with user ID for multi-user apps
String convoId(String userId, String topic) => '$userId:$topic';

await agent.generateResponse(
  convoId: convoId('user-123', 'main-chat'),
  userMessage: message,
);
```

### Ephemeral Conversations (No History)

For one-shot tasks where history doesn't matter:

```dart
Future<String> summarize(Agent agent, String text) async {
  // Use a unique ID each time — no history buildup
  final response = await agent.generateResponse(
    convoId: const Uuid().v4(),
    userMessage: AgentMessage(
      content: 'Summarize this: $text',
      generatedAt: DateTime.now(),
      isFromAgent: false,
    ),
    memoryLimit: 1,
  );
  return response.content;
}
```

## API Key Management

Never hardcode API keys. Here are safe patterns:

### Compile-time environment variables

```dart
// Pass at build time: flutter run --dart-define=GEMINI_API_KEY=abc123
const apiKey = String.fromEnvironment('GEMINI_API_KEY');

final llm = LLM.geminiLLM(apiKey: apiKey, modelName: 'gemini-2.0-flash');
```

### Runtime configuration

```dart
// Load from a secure source at runtime
final apiKey = await SecureStorage.read('gemini_api_key');

// Or from your backend
final config = await MyBackend.getAiConfig();
final llm = LLM.geminiLLM(
  apiKey: config.apiKey,
  modelName: config.modelName,
);
```

### Backend proxy (most secure)

Instead of putting the API key in the app, proxy requests through your backend:

```dart
class ProxyLLM extends LLM {
  final String backendUrl;

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    Uint8List? rawData,
    String mimeType = 'image/jpeg',
  }) async {
    // Send to your backend, which holds the API key
    final response = await http.post(
      Uri.parse('$backendUrl/ai/generate'),
      body: jsonEncode({'prompt': prompt, 'system': systemInstruction}),
    );
    return jsonDecode(response.body)['result'];
  }

  // ... implement other required members
}
```

## Performance Tips

1. **Use appropriate model sizes.** `gemini-2.0-flash` is fast and cheap for most tasks. Only use larger models when you need the extra capability.

2. **Keep `memoryLimit` low for fast responses.** Every past message adds to the prompt size and latency.

3. **Use `needsFurtherReasoning: false` when possible.** Skipping the second LLM call saves a full round trip.

4. **Dispose agents you're not using.** Each agent holds references in the scope registry.

5. **Use InMemory for development.** Firebase adds network latency to every DataStore operation.

## Summary

| Pattern | When to Use |
|---------|-------------|
| Custom LLM | You need a different model provider |
| Service layer | Production apps with lifecycle management |
| Provider integration | Flutter apps with state management |
| Scoped conversations | Multi-feature or multi-user apps |
| Ephemeral conversations | One-shot tasks (summarize, translate, etc.) |
| Backend proxy | Mobile apps where you can't expose API keys |
| Multi-agent with scopes | Complex apps with isolated AI teams |
