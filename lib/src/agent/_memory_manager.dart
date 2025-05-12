// Internal file, not part of the Public API

part of 'agent.dart';

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
    Object? metaData,
  }) async {
    return await dataStore.getMessages(convoId, metaData: metaData);
  }

  Future<void> deleteConversation(String convoId, {Object? metaData}) async {
    await dataStore.deleteConversation(convoId, metaData: metaData);
  }
}
