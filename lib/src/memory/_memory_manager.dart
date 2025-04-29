// Internal file, not part of the Public API

import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/data_store.dart';

class _MemoryManager {
  final DataStore dataStore;

  _MemoryManager({required this.dataStore});

  Future<void> saveMessage(
    String convoId,
    AgentMessage msg, {
    Object? metaData,
  }) async {
    await dataStore.saveMessage(convoId, msg, metaData: metaData);
  }

  Future<List<AgentMessage>> getContext(
    String convoId, {
    int limit = 10,
    Object? metaData,
  }) async {
    return await dataStore.getRecentMessages(
      convoId,
      limit: limit,
      metaData: metaData,
    );
  }

  Future<void> deleteConversation(String convoId, {Object? metaData}) async {
    await dataStore.deleteConversation(convoId, metaData: metaData);
  }

  Future<void> updateMessage(
    String convoId,
    AgentMessage updatedMsg, {
    Object? metaData,
  }) async {
    await dataStore.updateMessage(convoId, updatedMsg, metaData: metaData);
  }
}
