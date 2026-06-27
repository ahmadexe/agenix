# agenix_firebase

<p align="center">
  <a href="https://pub.dev/packages/agenix_firebase"><img src="https://img.shields.io/pub/v/agenix_firebase.svg" alt="Pub"></a>
  <a href="https://pub.dev/packages/agenix"><img src="https://img.shields.io/pub/v/agenix.svg?label=agenix" alt="agenix"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="License: MIT"></a>
</p>

Firebase (Firestore + Storage + Auth) data store backend for the [agenix](https://pub.dev/packages/agenix) AI agent framework.

This package provides `FirebaseDataStore`, an implementation of `DataStore` that persists conversations and messages to Cloud Firestore, uploads images to Firebase Storage, and scopes data per authenticated user via Firebase Auth.

<img width="960" height="600" alt="agenix_demo" src="https://raw.githubusercontent.com/ahmadexe/agenix/main/docs/visuals/agenix_demo.gif" />

---

## Installation

```yaml
dependencies:
  agenix: ^4.1.1
  agenix_firebase: ^1.0.3
```

```bash
flutter pub get
```

### Supported LLM providers

`agenix` (the core package) ships built-in adapters for **Google Gemini**, **OpenAI**, **Anthropic (Claude)**, **Groq**, **Mistral AI**, **DeepSeek**, **xAI (Grok)**, and **Cohere**. Pass any of them as the `llm` argument to `Agent.create()` — this package only handles persistence and is provider-agnostic.

---

## Firebase Setup

Before using `FirebaseDataStore`, your app must initialize Firebase and sign in a user:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Sign in — FirebaseDataStore requires an authenticated user
  await FirebaseAuth.instance.signInAnonymously();

  runApp(const MyApp());
}
```

If no user is signed in, all `FirebaseDataStore` operations throw `NotAuthenticatedException`.

---

## Usage

```dart
import 'package:agenix/agenix.dart';
import 'package:agenix_firebase/agenix_firebase.dart';

final agent = await Agent.create(
  dataStore: FirebaseDataStore(),
  llm: LLM.geminiLLM(apiKey: 'YOUR_API_KEY', modelName: 'gemini-2.0-flash'),
  name: 'Assistant',
  role: 'General purpose assistant.',
);

final response = await agent.generateResponse(
  convoId: 'conversation-1',
  userMessage: AgentMessage(
    content: 'Hello!',
    isFromAgent: false,
    generatedAt: DateTime.now(),
  ),
);
```

### Dependency injection (for testing)

`FirebaseDataStore` accepts optional Firebase instances so you can inject fakes in tests:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

final store = FirebaseDataStore(
  firestore: FakeFirebaseFirestore(),
  auth: MockFirebaseAuth(mockUser: MockUser(uid: 'test-user'), signedIn: true),
  storage: mockStorage,
);
```

---

## Firestore Schema

All data is scoped per authenticated user:

```
chats/
  {uid}/
    conversations/
      {conversationId}/
        lastMessage: String
        lastMessageTime: int (ms since epoch)
        conversationId: String
        messages/
          {autoId}/
            content: String
            isFromAgent: bool
            generatedAt: int (ms since epoch)
            imageUrl: String? (if image was uploaded)
            isError: bool
```

### Image handling

When an `AgentMessage` includes `imageData`, `FirebaseDataStore` uploads it to Firebase Storage at `messages/{uuid}.{ext}` and stores the download URL in the message document as `imageUrl`.

---

## Migrating from agenix 3.x

In agenix 3.x, Firebase was bundled in the core package. In 4.0.0, it was extracted into this separate package:

```diff
# pubspec.yaml
  dependencies:
    agenix: ^4.1.1
+   agenix_firebase: ^1.0.3

# Dart
+ import 'package:agenix_firebase/agenix_firebase.dart';

- final store = DataStore.firestoreDataStore();
+ final store = FirebaseDataStore();
```

The `FirebaseDataStore` API and Firestore schema are identical — no data migration is needed.

---

## API

| Class | Description |
|---|---|
| `FirebaseDataStore` | `DataStore` implementation backed by Firestore, Storage, and Auth |

### Constructor

```dart
FirebaseDataStore({
  FirebaseFirestore? firestore,  // defaults to FirebaseFirestore.instance
  FirebaseAuth? auth,            // defaults to FirebaseAuth.instance
  FirebaseStorage? storage,      // defaults to FirebaseStorage.instance
})
```

All parameters are optional. The defaults use the standard Firebase singleton instances. Pass custom instances for testing or multi-project setups.

---

## Example

See the [example app](https://github.com/ahmadexe/agenix/tree/main/packages/agenix_firebase/example) for a complete Flutter app using `FirebaseDataStore` with tools and image support.

---

## Related packages

| Package | Description |
|---|---|
| [`agenix`](https://pub.dev/packages/agenix) | Core — agents, tools, LLM interface, in-memory data store |

---

## Maintainers

- [Muhammad Ahmad](https://github.com/ahmadexe)
