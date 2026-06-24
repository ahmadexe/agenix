// firebase_storage_mocks is incompatible with firebase_storage ^13.0.0.
// We use mocktail to create a minimal FirebaseStorage mock.
import 'package:agenix/agenix.dart';
import 'package:agenix/src/memory/data_sources/_firebase.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'datastore_contract.dart';

class _MockFirebaseStorage extends Mock implements FirebaseStorage {}

void main() {
  runDataStoreContract('FirebaseDataStore', () async {
    final user = MockUser(uid: 'test-user');
    return FirebaseDataStore(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(mockUser: user, signedIn: true),
      storage: _MockFirebaseStorage(),
    );
  });

  group('FirebaseDataStore specifics', () {
    test('throws NotAuthenticatedException when no user signed in', () async {
      final store = FirebaseDataStore(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: false),
        storage: _MockFirebaseStorage(),
      );
      expect(
        () => store.getConversations(),
        throwsA(isA<NotAuthenticatedException>()),
      );
    });

    test(
      'throws NotAuthenticatedException on saveMessage when signed out',
      () async {
        final store = FirebaseDataStore(
          firestore: FakeFirebaseFirestore(),
          auth: MockFirebaseAuth(signedIn: false),
          storage: _MockFirebaseStorage(),
        );
        expect(
          () => store.saveMessage(
            'c1',
            AgentMessage(
              content: 'hi',
              isFromAgent: false,
              generatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
          ),
          throwsA(isA<NotAuthenticatedException>()),
        );
      },
    );
  });
}
