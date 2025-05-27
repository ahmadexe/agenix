// The data layer of agent's handler should extend [MemoryManager]
// This allows for easy swapping of data stores
// (e.g., SQLite, Hive, Firestore, MongoDB or external sources) without changing the core logic of the agent's memory management.
// For vector databases, the data layer should implement the [VectorDataStore] interface. Not yet implemented.

import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/conversation.dart';
import 'package:agenix/src/memory/data_sources/_firebase.dart';

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

  /// This is the abstract method to get the messages, it should be implemented by the concrete class
  Future<List<AgentMessage>> getMessages(
    String conversationId, {
    Object? metaData,
  });

  /// This is the abstract method to delete the conversation, it should be implemented by the concrete class
  Future<void> deleteConversation(String conversationId, {Object? metaData});

  /// This is the abstract method to get the conversations, it should be implemented by the concrete class
  Future<List<Conversation>> getConversations(
    String convoId, {
    Object? metaData,
  });

  /// Add more methods as needed, such as for Supabase etc.
  static DataStore firestoreDataStore() => FirebaseDataStore();
}
