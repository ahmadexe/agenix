import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

import 'datastore_contract.dart';

void main() {
  runDataStoreContract('InMemoryDataStore', () async => DataStore.inMemory());

  group('InMemoryDataStore specifics', () {
    test('different convoIds are isolated', () async {
      final store = DataStore.inMemory();
      await store.saveMessage(
        'c1',
        AgentMessage(
          content: 'a',
          isFromAgent: false,
          generatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );
      expect(await store.getMessages('c2'), isEmpty);
    });

    test('new instance starts empty', () async {
      final store1 = DataStore.inMemory();
      await store1.saveMessage(
        'c1',
        AgentMessage(
          content: 'a',
          isFromAgent: false,
          generatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );
      final store2 = DataStore.inMemory();
      expect(await store2.getMessages('c1'), isEmpty);
    });
  });
}
