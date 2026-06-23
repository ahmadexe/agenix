// Internal File, not part of the Public API
// In-memory DataStore for testing and prototyping without Firebase.

import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/conversation.dart';
import 'package:agenix/src/memory/data/data_store.dart';

/// A simple in-memory [DataStore] backed by maps.
///
/// Useful for unit tests (no Firebase dependency) and lightweight prototyping.
/// Data lives only for the lifetime of the instance.
class InMemoryDataStore extends DataStore {
  final Map<String, List<AgentMessage>> _messages = {};
  final Map<String, Conversation> _conversations = {};

  @override
  Future<void> saveMessage(
    String convoId,
    AgentMessage msg, {
    Object? metaData,
  }) async {
    _messages.putIfAbsent(convoId, () => []);
    _messages[convoId]!.add(msg);

    _conversations[convoId] = Conversation(
      lastMessage: msg.content,
      lastMessageTime: msg.generatedAt,
      conversationId: convoId,
    );
  }

  @override
  Future<List<AgentMessage>> getMessages(
    String conversationId, {
    int? limit,
    Object? metaData,
  }) async {
    final all = _messages[conversationId] ?? [];
    if (limit == null || limit >= all.length) return List.of(all);
    return all.sublist(all.length - limit);
  }

  @override
  Future<void> deleteConversation(
    String conversationId, {
    Object? metaData,
  }) async {
    _messages.remove(conversationId);
    _conversations.remove(conversationId);
  }

  @override
  Future<List<Conversation>> getConversations({
    Object? metaData,
  }) async {
    return _conversations.values.toList();
  }
}
