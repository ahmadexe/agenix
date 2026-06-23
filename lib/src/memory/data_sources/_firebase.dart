// Internal File, not part of the Public API
// Firebase is used as a data store for the agent.
// By default Agenix provides the support for Firebase.

import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/conversation.dart';
import 'package:agenix/src/memory/data/data_store.dart';
import 'package:agenix/src/static/agenix_exceptions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// FirebaseDataStore is an implementation of DataStore that uses Firebase Firestore and Firebase Storage to store and retrieve data.
/// This allows for easy swapping of data stores without changing the core logic of the agent's memory management.
/// To use this data store, you need to initialize Firebase in your app and provide the necessary configuration.
class FirebaseDataStore extends DataStore {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String _resolveUserId() {
    final user = _auth.currentUser;
    if (user == null) throw const NotAuthenticatedException();
    return user.uid;
  }

  @override
  Future<void> deleteConversation(
    String conversationId, {
    Object? metaData,
  }) async {
    try {
      final userId = _resolveUserId();
      final ref = _firestore
          .collection('chats')
          .doc(userId)
          .collection('conversations')
          .doc(conversationId);

      final messagesRef = ref.collection('messages');
      final messages = await messagesRef.get();

      final batch = _firestore.batch();
      for (final message in messages.docs) {
        batch.delete(message.reference);
      }

      batch.delete(ref);

      await batch.commit();
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw DataStoreException('Error deleting conversation', cause: e, causeStack: st);
    }
  }

  @override
  Future<List<Conversation>> getConversations(
    String conversationId, {
    Object? metaData,
  }) async {
    try {
      final userId = _resolveUserId();
      final ref = _firestore
          .collection('chats')
          .doc(userId)
          .collection('conversations');

      final snapshots = await ref.get();
      if (snapshots.docs.isEmpty) return [];

      return snapshots.docs
          .map((doc) => Conversation.fromMap(doc.data()))
          .toList();
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw DataStoreException('Error fetching conversations', cause: e, causeStack: st);
    }
  }

  @override
  Future<List<AgentMessage>> getMessages(
    String conversationId, {
    Object? metaData,
  }) async {
    try {
      final userId = _resolveUserId();
      final ref = _firestore
          .collection('chats')
          .doc(userId)
          .collection('conversations')
          .doc(conversationId)
          .collection('messages');

      final snapshots = await ref.orderBy('generatedAt').get();
      if (snapshots.docs.isEmpty) return [];

      return snapshots.docs
          .map((doc) => AgentMessage.fromMap(doc.data()))
          .toList();
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw DataStoreException('Error fetching recent messages', cause: e, causeStack: st);
    }
  }

  @override
  Future<void> saveMessage(
    String conversationId,
    AgentMessage msg, {
    Object? metaData,
  }) async {
    try {
      final userId = _resolveUserId();
      final ref =
          _firestore
              .collection('chats')
              .doc(userId)
              .collection('conversations')
              .doc(conversationId)
              .collection('messages')
              .doc();

      Map<String, dynamic> payload = msg.toMap();

      if (msg.imageData != null) {
        final storageRef = _storage.ref();
        final id = const Uuid().v4();
        final imageRef = storageRef.child('messages/$id.jpg');
        await imageRef.putData(msg.imageData!);
        final url = await imageRef.getDownloadURL();
        payload['imageUrl'] = url.toString();
      }

      await ref.set(payload);
      await _firestore
          .collection('chats')
          .doc(userId)
          .collection('conversations')
          .doc(conversationId)
          .set({
            'lastMessage': payload['content'],
            'lastMessageTime': payload['generatedAt'],
            'conversationId': conversationId,
          }, SetOptions(merge: true));
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw DataStoreException('Error saving message', cause: e, causeStack: st);
    }
  }
}
