# Memory & Persistence

Every conversation your agent has is stored through a `DataStore`. This guide covers how conversation memory works, the built-in storage options, and how to build your own.

## How Memory Works

When your agent generates a response, it:

1. **Loads recent messages** from the DataStore (controlled by `memoryLimit`)
2. **Includes them in the prompt** so the LLM has conversation context
3. **Saves the new messages** (user message + agent response) after generating

```
User sends message
       │
       ▼
┌──────────────────────────┐
│ 1. Load last N messages   │◀── DataStore.getMessages()
│ 2. Build prompt with      │
│    history + system data   │
│ 3. Send to LLM            │
│ 4. Get response            │
│ 5. Save user msg + reply   │──▶ DataStore.saveMessage()
└──────────────────────────┘
```

## Built-in Data Stores

### InMemoryDataStore

Zero dependencies. Data lives in a `Map` and is lost when the app restarts.

```dart
final dataStore = DataStore.inMemory();
```

**Use for:**
- Prototyping and development
- Conversations that don't need to persist
- Unit testing
- Quick demos

### FirebaseDataStore (via `agenix_firebase`)

Persists conversations in Cloud Firestore. Supports image uploads via Firebase Storage.

```yaml
# pubspec.yaml
dependencies:
  agenix: ^4.0.0
  agenix_firebase: ^4.0.0
  firebase_core: ^3.0.0
```

```dart
import 'package:agenix_firebase/agenix_firebase.dart';

// Make sure Firebase is initialized first
await Firebase.initializeApp();

final dataStore = DataStore.firestoreDataStore();
```

**Data structure in Firestore:**

```
chats/
  {userId}/
    conversations/
      {conversationId}/
        messages/
          {messageId}/
            content: "Hello!"
            isFromAgent: false
            generatedAt: Timestamp
            imageUrl: null
            ...
```

**Requirements:**
- Firebase project with Firestore enabled
- User must be authenticated via Firebase Auth
- Firebase Storage enabled (if using image messages)

**Use for:**
- Production apps with persistent conversations
- Multi-device sync (conversations available across devices)
- Apps with user authentication

## Working with Conversations

### Listing Conversations

```dart
final conversations = await agent.getAllConversations();

for (final convo in conversations) {
  print('ID: ${convo.conversationId}');
  print('Last message: ${convo.lastMessage}');
  print('Time: ${convo.lastMessageTime}');
}
```

### Loading Message History

```dart
// Get all messages in a conversation
final messages = await agent.getMessages(conversationId: 'chat-1');

for (final msg in messages) {
  final sender = msg.isFromAgent ? 'Agent' : 'User';
  print('$sender: ${msg.content}');
}
```

### Deleting Conversations

```dart
await agent.deleteConversation(conversationId: 'chat-1');
```

### Memory Limit

Control how many past messages are sent to the LLM:

```dart
// Default: last 10 messages
final response = await agent.generateResponse(
  convoId: convoId,
  userMessage: message,
);

// Send more context
final response = await agent.generateResponse(
  convoId: convoId,
  userMessage: message,
  memoryLimit: 25,
);

// Minimal context (fast, cheap)
final response = await agent.generateResponse(
  convoId: convoId,
  userMessage: message,
  memoryLimit: 3,
);
```

**How to choose:**

| Use Case | Suggested Limit | Why |
|----------|----------------|-----|
| Quick Q&A | 3-5 | Each question is independent |
| Casual chatbot | 10 (default) | Enough for conversational context |
| Long-form collaboration | 20-30 | Maintains consistency over many turns |
| Single-turn (no history) | 1 | Treats every message as standalone |

## Building a Custom DataStore

If you need a different backend (SQLite, Hive, Supabase, your own API), implement the `DataStore` interface:

```dart
import 'package:agenix/agenix.dart';

class SqliteDataStore extends DataStore {
  final Database _db;

  SqliteDataStore(this._db);

  @override
  Future<void> saveMessage(
    String convoId,
    AgentMessage message, {
    Object? metaData,
  }) async {
    await _db.insert('messages', {
      'conversation_id': convoId,
      'content': message.content,
      'is_from_agent': message.isFromAgent ? 1 : 0,
      'generated_at': message.generatedAt.toIso8601String(),
      'image_url': message.imageUrl,
      'is_error': message.isError ? 1 : 0,
    });
  }

  @override
  Future<List<AgentMessage>> getMessages(
    String conversationId, {
    int? limit,
    Object? metaData,
  }) async {
    final rows = await _db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'generated_at ASC',
      limit: limit,
    );

    return rows.map((row) => AgentMessage(
      content: row['content'] as String,
      isFromAgent: row['is_from_agent'] == 1,
      generatedAt: DateTime.parse(row['generated_at'] as String),
      imageUrl: row['image_url'] as String?,
      isError: row['is_error'] == 1,
    )).toList();
  }

  @override
  Future<void> deleteConversation(
    String conversationId, {
    Object? metaData,
  }) async {
    await _db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  @override
  Future<List<Conversation>> getConversations({Object? metaData}) async {
    final rows = await _db.rawQuery('''
      SELECT conversation_id, content, generated_at
      FROM messages
      WHERE rowid IN (
        SELECT MAX(rowid) FROM messages GROUP BY conversation_id
      )
      ORDER BY generated_at DESC
    ''');

    return rows.map((row) => Conversation(
      conversationId: row['conversation_id'] as String,
      lastMessage: row['content'] as String,
      lastMessageTime: DateTime.parse(row['generated_at'] as String),
    )).toList();
  }
}
```

Use it like any other DataStore:

```dart
final db = await openDatabase('chat.db');
final dataStore = SqliteDataStore(db);

final agent = await Agent.create(
  dataStore: dataStore,
  llm: llm,
  name: 'assistant',
  role: 'A helpful assistant.',
);
```

## The `metaData` Pattern

Every DataStore method accepts an optional `Object? metaData` parameter. This is an opaque pass-through for context your DataStore needs but Agenix doesn't know about.

```dart
// Example: multi-tenant app where each tenant has separate data
class TenantDataStore extends DataStore {
  @override
  Future<void> saveMessage(
    String convoId,
    AgentMessage message, {
    Object? metaData,
  }) async {
    final tenantId = metaData as String; // your app passes the tenant ID
    await _db.collection('tenants/$tenantId/messages').add(message.toMap());
  }

  // ... other methods use metaData similarly
}

// When generating responses, pass your metadata
final response = await agent.generateResponse(
  convoId: convoId,
  userMessage: message,
  metaData: 'tenant-abc-123', // flows through to all DataStore calls
);
```

Common uses for `metaData`:
- Tenant IDs in multi-tenant apps
- Auth tokens for custom API backends
- User context for row-level security
- Request tracing IDs

## Data Models

### AgentMessage

```dart
final message = AgentMessage(
  content: 'Hello, how can I help?',
  generatedAt: DateTime.now(),
  isFromAgent: true,
  imageData: null,          // raw image bytes (Uint8List)
  mimeType: 'image/jpeg',  // image MIME type
  imageUrl: null,           // URL to stored image
  data: {'key': 'value'},  // optional structured data
  isError: false,           // whether this is an error message
);

// Serialization
final map = message.toMap();
final json = message.toJson();

// Deserialization
final fromMap = AgentMessage.fromMap(map);
final fromJson = AgentMessage.fromJson(json);

// Copy with modifications
final updated = message.copyWith(content: 'Updated content');
```

### Conversation

```dart
final conversation = Conversation(
  conversationId: 'chat-1',
  lastMessage: 'See you later!',
  lastMessageTime: DateTime.now(),
);

// Same serialization pattern
final map = conversation.toMap();
final fromMap = Conversation.fromMap(map);
```

## Best Practices

1. **Start with InMemory, migrate later.** Get your agent logic right before worrying about persistence. The `DataStore` interface makes swapping trivial.

2. **Choose `memoryLimit` deliberately.** Too low and the agent forgets context. Too high and you burn tokens. Profile your use case.

3. **Use conversation IDs that make sense.** For chat apps, use UUIDs. For support tickets, use the ticket ID. For per-feature assistants, use the feature name.

4. **Clean up old conversations.** If you're using persistent storage, give users a way to delete conversations they no longer need.

5. **Handle the `NotAuthenticatedException`.** Firebase DataStore requires an authenticated user. Check auth state before creating the agent.

## Next Steps

- Handle storage and LLM failures with [Error Handling](error_handling.md)
- Explore advanced storage patterns in [Advanced Patterns](advanced_patterns.md)
