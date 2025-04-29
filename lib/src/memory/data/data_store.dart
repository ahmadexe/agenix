// The data layer of agent's handler should extend [MemoryManager]
// This allows for easy swapping of data stores
// (e.g., SQLite, Hive, Firestore, MongoDB or external sources) without changing the core logic of the agent's memory management.
// For vector databases, the data layer should implement the [VectorDataStore] interface.

import 'package:agenix/src/memory/data/agent_message.dart';

abstract class DataStore {
  Future<void> saveMessage(String convoId, AgentMessage msg, {Object? metaData});
  Future<List<AgentMessage>> getRecentMessages(String convoId, {int limit = 10, Object? metaData});
  Future<void> deleteConversation(String convoId, {Object? metaData});
  Future<void> updateMessage(String convoId, AgentMessage updatedMsg, {Object? metaData});
}