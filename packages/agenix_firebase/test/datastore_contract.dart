import 'package:agenix/agenix.dart';
import 'package:flutter_test/flutter_test.dart';

void runDataStoreContract(String label, Future<DataStore> Function() build) {
  group('DataStore contract: $label', () {
    late DataStore store;
    setUp(() async => store = await build());

    AgentMessage msg(String c, {required bool fromAgent, required int ms}) =>
        AgentMessage(
          content: c,
          isFromAgent: fromAgent,
          generatedAt: DateTime.fromMillisecondsSinceEpoch(ms),
        );

    test('saveMessage then getMessages returns it', () async {
      await store.saveMessage('c1', msg('hi', fromAgent: false, ms: 1000));
      final out = await store.getMessages('c1');
      expect(out.map((m) => m.content), ['hi']);
    });

    test('getMessages returns oldest-first', () async {
      await store.saveMessage('c1', msg('a', fromAgent: false, ms: 1000));
      await store.saveMessage('c1', msg('b', fromAgent: true, ms: 2000));
      final out = await store.getMessages('c1');
      expect(out.map((m) => m.content), ['a', 'b']);
    });

    test('getMessages honors limit (most recent N, oldest-first)', () async {
      for (var i = 0; i < 5; i++) {
        await store.saveMessage(
          'c1',
          msg('m$i', fromAgent: false, ms: 1000 + i),
        );
      }
      final out = await store.getMessages('c1', limit: 2);
      expect(out.map((m) => m.content), ['m3', 'm4']);
    });

    test('getMessages on unknown conversation returns empty', () async {
      expect(await store.getMessages('nope'), isEmpty);
    });

    test('getConversations reflects the last saved message', () async {
      await store.saveMessage('c1', msg('first', fromAgent: false, ms: 1000));
      await store.saveMessage('c1', msg('last', fromAgent: true, ms: 2000));
      final convos = await store.getConversations();
      final c1 = convos.firstWhere((c) => c.conversationId == 'c1');
      expect(c1.lastMessage, 'last');
    });

    test('deleteConversation removes messages and summary', () async {
      await store.saveMessage('c1', msg('x', fromAgent: false, ms: 1000));
      await store.deleteConversation('c1');
      expect(await store.getMessages('c1'), isEmpty);
      expect(
        (await store.getConversations()).where((c) => c.conversationId == 'c1'),
        isEmpty,
      );
    });
  });
}
