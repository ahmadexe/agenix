import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/conversation.dart';
import 'package:agenix/src/memory/data_sources/_in_memory.dart';

/// Abstract contract for data storage and retrieval in the agent's memory system.
///
/// Extend this class to provide a custom backend (e.g., SQLite, Hive, Supabase).
/// For Firebase support, see the `agenix_firebase` package.
abstract class DataStore {
  /// Saves a message to the given conversation.
  Future<void> saveMessage(
    String convoId,
    AgentMessage msg, {
    Object? metaData,
  });

  /// Returns messages for [conversationId].
  /// When [limit] is provided, only the most recent [limit] messages are returned
  /// (ordered oldest-first for prompt construction).
  Future<List<AgentMessage>> getMessages(
    String conversationId, {
    int? limit,
    Object? metaData,
  });

  /// Deletes the conversation and its messages.
  Future<void> deleteConversation(String conversationId, {Object? metaData});

  /// Returns all conversations for the current user.
  Future<List<Conversation>> getConversations({Object? metaData});

  /// Creates an [InMemoryDataStore] — data lives only for the lifetime of the
  /// instance. Ideal for tests and prototyping.
  static DataStore inMemory() => InMemoryDataStore();
}
