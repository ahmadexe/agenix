// This file defines the Conversation class, which represents a summary of a chat conversation.
// It contains the last message, the time it was sent, and a unique conversation ID.

import 'dart:convert';

/// Represents a chat conversation summary, typically shown in a conversation list.
/// Stores the last message exchanged, the time it occurred, and a unique ID for identification.
class Conversation {
  final String lastMessage; // The text of the most recent message in the conversation
  final DateTime lastMessageTime; // Timestamp of the last message
  final String conversationId; // Unique ID identifying the conversation

  Conversation({
    required this.lastMessage,
    required this.lastMessageTime,
    required this.conversationId,
  });

  /// Returns a copy of the current Conversation object with optional new values.
  Conversation copyWith({
    String? lastMessage,
    DateTime? lastMessageTime,
    String? conversationId,
  }) {
    return Conversation(
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      conversationId: conversationId ?? this.conversationId,
    );
  }

  /// Converts the Conversation object to a map for serialization or database storage.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.microsecondsSinceEpoch,
      'conversationId': conversationId,
    };
  }

  /// Constructs a Conversation object from a map (usually from Firestore or other storage).
  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      lastMessage: map['lastMessage'] as String,
      lastMessageTime: DateTime.fromMicrosecondsSinceEpoch(
        map['lastMessageTime'] as int,
      ),
      conversationId: map['conversationId'] as String,
    );
  }

  /// Converts the Conversation object to a JSON string.
  String toJson() => json.encode(toMap());

  /// Constructs a Conversation object from a JSON string.
  factory Conversation.fromJson(String source) =>
      Conversation.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'Conversation(lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, conversationId: $conversationId)';

  /// Checks for equality by comparing each field.
  @override
  bool operator ==(covariant Conversation other) {
    if (identical(this, other)) return true;

    return other.lastMessage == lastMessage &&
        other.lastMessageTime == lastMessageTime &&
        other.conversationId == conversationId;
  }

  /// Generates a hash code based on the object's fields.
  @override
  int get hashCode =>
      lastMessage.hashCode ^ lastMessageTime.hashCode ^ conversationId.hashCode;
}
