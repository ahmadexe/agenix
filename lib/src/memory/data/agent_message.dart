// This file defines the AgentMessage class used to represent messages exchanged
// between an agent (e.g., AI chatbot) and a user.
// It supports text content, timestamps, agent identification, and optional image data or URL.

import 'dart:convert';
import 'dart:typed_data';

/// Represents a message in a conversation, either from the agent or the user.
/// It can optionally contain an image (as binary data or a URL).
class AgentMessage {
  /// The main text content of the message
  final String content;

  /// Timestamp when the message was generated
  final DateTime generatedAt;

  /// Indicates whether the message is from the agent (true) or user (false)
  final bool isFromAgent;

  /// Optional binary image data (e.g., for displaying inline)
  final Uint8List? imageData;

  /// Optional URL to an image
  final String? imageUrl;

  /// Optional data associated with the message, this data is for internal use of the application and not for any extrnal use.
  final Map<String, dynamic>? data;

  /// Constructs an AgentMessage with required content and generatedAt,
  AgentMessage({
    required this.content,
    required this.generatedAt,
    required this.isFromAgent,
    this.imageData,
    this.imageUrl,
    this.data,
  });

  /// Creates a copy of the current message with optional new values for each field
  AgentMessage copyWith({
    String? content,
    DateTime? generatedAt,
    bool? isFromAgent,
    Uint8List? imageData,
    String? imageUrl,
    Map<String, dynamic>? data,
  }) {
    return AgentMessage(
      content: content ?? this.content,
      generatedAt: generatedAt ?? this.generatedAt,
      isFromAgent: isFromAgent ?? this.isFromAgent,
      imageData: imageData ?? this.imageData,
      imageUrl: imageUrl ?? this.imageUrl,
      data: data ?? this.data,
    );
  }

  /// Converts the message to a map (excluding `imageData`, which is not serializable)
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'content': content,
      'generatedAt': generatedAt.millisecondsSinceEpoch,
      'isFromAgent': isFromAgent,
      'imageUrl': imageUrl,
      'data': data,
    };
  }

  /// Constructs a message from a map (used for decoding from storage or network)
  factory AgentMessage.fromMap(Map<String, dynamic> map) {
    return AgentMessage(
      content: map['content'] as String,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['generatedAt'] as int,
      ),
      isFromAgent: map['isFromAgent'] as bool,
      imageUrl: map['imageUrl'] != null ? map['imageUrl'] as String : null,
      data: map['data'] as Map<String, dynamic>?,
    );
  }

  /// Converts the message to a JSON string
  String toJson() => json.encode(toMap());

  /// Parses a message from a JSON string
  factory AgentMessage.fromJson(String source) =>
      AgentMessage.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'AgentMessage(content: $content, generatedAt: $generatedAt, isFromAgent: $isFromAgent, imageData: $imageData, imageUrl: $imageUrl, data: $data)';
  }

  /// Equality check based on all fields
  @override
  bool operator ==(covariant AgentMessage other) {
    if (identical(this, other)) return true;

    return other.content == content &&
        other.generatedAt == generatedAt &&
        other.isFromAgent == isFromAgent &&
        other.imageData == imageData &&
        other.imageUrl == imageUrl &&
        other.data == data;
  }

  /// Hash code based on all fields
  @override
  int get hashCode {
    return content.hashCode ^
        generatedAt.hashCode ^
        isFromAgent.hashCode ^
        imageData.hashCode ^
        imageUrl.hashCode ^
        data.hashCode;
  }
}
