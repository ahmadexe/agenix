// The data layer of agent's handler should extend [MemoryManager]
// This allows for easy swapping of data stores
// (e.g., SQLite, Hive, Firestore, MongoDB or external sources) without changing the core logic of the agent's memory management.
// For vector databases, the data layer should implement the [VectorDataStore] interface. Not yet implemented.

import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/conversation.dart';

abstract class DataStore {
  Future<void> saveMessage(
    String convoId,
    AgentMessage msg, {
    Object? metaData,
  });
  Future<List<AgentMessage>> getMessages(
    String conversationId, {
    Object? metaData,
  });
  Future<void> deleteConversation(String conversationId, {Object? metaData});
  Future<List<Conversation>> getConversations(
    String convoId, {
    Object? metaData,
  });
}
