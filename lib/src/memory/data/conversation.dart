import 'dart:convert';

class Conversation {
  final String lastMessage;
  final DateTime lastMessageTime;
  final String conversationId;
  Conversation({
    required this.lastMessage,
    required this.lastMessageTime,
    required this.conversationId,
  });

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

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.microsecondsSinceEpoch,
      'conversationId': conversationId,
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      lastMessage: map['lastMessage'] as String,
      lastMessageTime: DateTime.fromMicrosecondsSinceEpoch(
        map['lastMessageTime'] as int,
      ),
      conversationId: map['conversationId'] as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory Conversation.fromJson(String source) =>
      Conversation.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'Conversation(lastMessage: $lastMessage, lastMessageTime: $lastMessageTime, conversationId: $conversationId)';

  @override
  bool operator ==(covariant Conversation other) {
    if (identical(this, other)) return true;

    return other.lastMessage == lastMessage &&
        other.lastMessageTime == lastMessageTime &&
        other.conversationId == conversationId;
  }

  @override
  int get hashCode =>
      lastMessage.hashCode ^ lastMessageTime.hashCode ^ conversationId.hashCode;
}
