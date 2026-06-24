// The data layer of agent's handler should extend [MemoryManager]
// This allows for easy swapping of data stores
// (e.g., SQLite, Hive, Firestore, MongoDB or external sources) without changing the core logic of the agent's memory management.
// For vector databases, the data layer should implement the [VectorDataStore] interface. Not yet implemented.

import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/conversation.dart';
import 'package:agenix/src/memory/data_sources/_firebase.dart';
import 'package:agenix/src/memory/data_sources/_in_memory.dart';

/// DataStore is an abstract class that defines the contract for data storage and retrieval in the agent's memory management system.
/// It provides methods to save messages, retrieve messages, delete conversations, and get conversations.
/// This allows for easy swapping of data stores (e.g., Firestore, SQLite, Hive) without changing the core logic of the agent's memory management.
/// To implement a new data store, simply extend this class and provide the necessary methods.
abstract class DataStore {
  /// This is the abstract method to save the data, it should be implemented by the concrete class
  Future<void> saveMessage(
    String convoId,
    AgentMessage msg, {
    Object? metaData,
  });

  /// This is the abstract method to get the messages, it should be implemented by the concrete class.
  /// When [limit] is provided, only the most recent [limit] messages are returned
  /// (ordered oldest-first for prompt construction).
  Future<List<AgentMessage>> getMessages(
    String conversationId, {
    int? limit,
    Object? metaData,
  });

  /// This is the abstract method to delete the conversation, it should be implemented by the concrete class
  Future<void> deleteConversation(String conversationId, {Object? metaData});

  /// Returns all conversations for the current user.
  Future<List<Conversation>> getConversations({Object? metaData});

  /// Creates a [FirebaseDataStore]. Accepts optional Firebase instances for
  /// dependency injection in tests.
  static DataStore firestoreDataStore({
    dynamic firestore,
    dynamic auth,
    dynamic storage,
  }) => FirebaseDataStore(firestore: firestore, auth: auth, storage: storage);

  /// Creates an [InMemoryDataStore] — no Firebase dependency, data lives only
  /// for the lifetime of the instance. Ideal for tests and prototyping.
  static DataStore inMemory() => InMemoryDataStore();
}
