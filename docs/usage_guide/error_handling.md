# Error Handling

Agenix provides a structured exception hierarchy and configurable failure modes so your app can handle errors gracefully.

## Failure Modes

When creating an agent, you choose how it handles errors:

```dart
// Default: returns a friendly error message instead of crashing
final agent = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'assistant',
  role: 'A helpful assistant.',
  failureMode: FailureMode.gracefulMessage,
);

// Alternative: throws exceptions that you catch yourself
final agent = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'assistant',
  role: 'A helpful assistant.',
  failureMode: FailureMode.throwException,
);
```

### `FailureMode.gracefulMessage` (Default)

When something goes wrong, the agent returns an `AgentMessage` with `isError: true` instead of throwing. The user sees a generic error message, and your app doesn't crash.

```dart
final response = await agent.generateResponse(
  convoId: convoId,
  userMessage: message,
);

if (response.isError) {
  // Show error UI
  showErrorBanner('Something went wrong. Please try again.');
} else {
  // Show normal response
  displayMessage(response.content);
}
```

### `FailureMode.throwException`

Exceptions propagate to your code. Use this when you want full control over error handling:

```dart
try {
  final response = await agent.generateResponse(
    convoId: convoId,
    userMessage: message,
  );
  displayMessage(response.content);
} on LlmTimeoutException {
  showError('The AI is taking too long. Please try again.');
} on ToolExecutionException catch (e) {
  showError('The ${e.toolName} tool failed. Please try again.');
} on DataStoreException {
  showError('Could not save your message. Check your connection.');
} on AgenixException catch (e) {
  showError('Something went wrong: ${e.message}');
}
```

## Exception Hierarchy

All Agenix exceptions extend `AgenixException` (a sealed class), so you can catch them granularly or catch-all:

```
AgenixException (sealed)
│
├── LlmException
│   └── LlmTimeoutException
│
├── ResponseParseException
│
├── ToolNotFoundException
│
├── ToolExecutionException
│
├── AgentNotFoundException
│
├── DataStoreException
│   └── NotAuthenticatedException
│
└── ConfigException
```

### When Each Exception Occurs

| Exception | When It Happens | Common Cause |
|-----------|----------------|--------------|
| `LlmException` | LLM call fails | Invalid API key, rate limit, network error |
| `LlmTimeoutException` | LLM doesn't respond in time | Slow network, overloaded model |
| `ResponseParseException` | LLM response isn't valid JSON | Model returned malformed output (rare — Agenix retries up to 2 times) |
| `ToolNotFoundException` | LLM requested a tool that isn't registered | Typo in tool name, tool was unregistered |
| `ToolExecutionException` | A tool's `run()` method threw | Bug in tool code, external API failure |
| `AgentNotFoundException` | Agent chain references a non-existent agent | Typo in agent name, agent not in scope |
| `DataStoreException` | DataStore operation failed | Network error, permissions issue |
| `NotAuthenticatedException` | Firebase DataStore used without auth | User not signed in |
| `ConfigException` | Agent configuration is invalid | Missing system data file, bad setup |

## The `onError` Callback

For logging and monitoring, pass an `onError` callback when creating the agent:

```dart
final agent = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'assistant',
  role: 'A helpful assistant.',
  failureMode: FailureMode.gracefulMessage,
  onError: (error, stackTrace) {
    // Log to your error tracking service
    Sentry.captureException(error, stackTrace: stackTrace);

    // Or just print for debugging
    debugPrint('Agent error: ${error.message}');
    debugPrint('Stack: $stackTrace');
  },
);
```

This fires regardless of the failure mode. Even with `gracefulMessage`, you can still log every error for debugging.

## Practical Patterns

### Retry with Exponential Backoff

```dart
Future<AgentMessage> askWithRetry(
  Agent agent,
  String convoId,
  AgentMessage message, {
  int maxRetries = 3,
}) async {
  for (var attempt = 0; attempt < maxRetries; attempt++) {
    final response = await agent.generateResponse(
      convoId: convoId,
      userMessage: message,
    );

    if (!response.isError) return response;

    // Wait before retrying (exponential backoff)
    if (attempt < maxRetries - 1) {
      await Future.delayed(Duration(seconds: 1 << attempt)); // 1s, 2s, 4s
    }
  }

  return AgentMessage(
    content: 'Sorry, I am unable to respond right now. Please try again later.',
    generatedAt: DateTime.now(),
    isFromAgent: true,
    isError: true,
  );
}
```

### Fallback Agent

If the primary LLM is down, fall back to a simpler model:

```dart
class ResilientService {
  late final Agent _primaryAgent;
  late final Agent _fallbackAgent;

  Future<void> initialize() async {
    final dataStore = DataStore.inMemory();
    final scope = AgentScope(); // isolated scope — they don't see each other

    _primaryAgent = await Agent.create(
      dataStore: dataStore,
      llm: LLM.geminiLLM(
        apiKey: apiKey,
        modelName: 'gemini-2.0-flash',
      ),
      name: 'primary',
      role: 'A helpful assistant.',
      failureMode: FailureMode.throwException,
      scope: scope,
    );

    _fallbackAgent = await Agent.create(
      dataStore: dataStore,
      llm: LLM.geminiLLM(
        apiKey: apiKey,
        modelName: 'gemini-2.0-flash', // or a different model
        config: const LlmConfig(timeout: Duration(seconds: 15)),
      ),
      name: 'fallback',
      role: 'A helpful assistant. Keep responses brief.',
      failureMode: FailureMode.gracefulMessage,
      scope: scope,
    );
  }

  Future<AgentMessage> chat(String convoId, AgentMessage message) async {
    try {
      return await _primaryAgent.generateResponse(
        convoId: convoId,
        userMessage: message,
      );
    } on LlmException {
      // Primary failed — try fallback
      return await _fallbackAgent.generateResponse(
        convoId: convoId,
        userMessage: message,
      );
    }
  }
}
```

### Safe Firebase Initialization

```dart
Future<DataStore> createDataStore() async {
  try {
    await Firebase.initializeApp();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Not authenticated — use in-memory as fallback
      return DataStore.inMemory();
    }
    return DataStore.firestoreDataStore();
  } catch (e) {
    // Firebase not configured — use in-memory
    return DataStore.inMemory();
  }
}
```

## Best Practices

1. **Use `gracefulMessage` for user-facing agents.** Users don't want to see stack traces. Log errors with `onError` and show friendly messages.

2. **Use `throwException` for backend/service agents.** When you need programmatic control over error recovery.

3. **Always set `onError`.** Even with graceful mode, you want to know when things go wrong. Connect it to your error tracking (Sentry, Crashlytics, etc.).

4. **Check `isError` on responses.** When using graceful mode, always check this flag before displaying the response to distinguish real answers from error fallbacks.

5. **Don't swallow exceptions in tools.** If your tool catches an error, return a failed `ToolResponse` — don't return a success with empty data. The LLM needs to know the tool failed.

## Next Steps

- Explore more patterns in [Advanced Patterns](advanced_patterns.md)
