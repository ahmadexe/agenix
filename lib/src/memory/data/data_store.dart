// The data layer of agent's handler should extend [MemoryManager]
// This allows for easy swapping of data stores
// (e.g., SQLite, Hive, Firestore, MongoDB or external sources) without changing the core logic of the agent's memory management.
// For vector databases, the data layer should implement the [VectorDataStore] interface. Not yet implemented.

import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/conversation.dart';
import 'package:agenix/src/memory/data_sources/_firebase.dart';

abstract class DataStore {
  // This is the abstract method to save the data, it should be implemented by the concrete class
  Future<void> saveMessage(
    String convoId,
    AgentMessage msg, {
    Object? metaData,
  });

  // This is the abstract method to get the messages, it should be implemented by the concrete class
  Future<List<AgentMessage>> getMessages(
    String conversationId, {
    Object? metaData,
  });

  // This is the abstract method to delete the conversation, it should be implemented by the concrete class
  Future<void> deleteConversation(String conversationId, {Object? metaData});
  Future<List<Conversation>> getConversations(
    String convoId, {
    Object? metaData,
  });

  // Add more methods as needed, such as for Supabase etc.
  static DataStore firestoreDataStore() => FirebaseDataStore();
}
