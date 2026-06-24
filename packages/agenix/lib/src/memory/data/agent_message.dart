// This file defines the AgentMessage class used to represent messages exchanged
// between an agent (e.g., AI chatbot) and a user.
// It supports text content, timestamps, agent identification, and optional image data or URL.

import 'dart:convert';

import 'package:flutter/foundation.dart';

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

  /// MIME type of [imageData] (e.g. 'image/png', 'image/jpeg').
  final String mimeType;

  /// Optional URL to an image
  final String? imageUrl;

  /// Optional data associated with the message, this data is for internal use of the application and not for any extrnal use.
  final Map<String, dynamic>? data;

  /// When true, this message represents an error and should be excluded from
  /// conversation history sent to the LLM.
  final bool isError;

  /// Constructs an AgentMessage with required content and generatedAt,
  AgentMessage({
    required this.content,
    required this.generatedAt,
    required this.isFromAgent,
    this.imageData,
    this.mimeType = 'image/jpeg',
    this.imageUrl,
    this.data,
    this.isError = false,
  });

  /// Creates a copy of the current message with optional new values for each field
  AgentMessage copyWith({
    String? content,
    DateTime? generatedAt,
    bool? isFromAgent,
    Uint8List? imageData,
    String? mimeType,
    String? imageUrl,
    Map<String, dynamic>? data,
    bool? isError,
  }) {
    return AgentMessage(
      content: content ?? this.content,
      generatedAt: generatedAt ?? this.generatedAt,
      isFromAgent: isFromAgent ?? this.isFromAgent,
      imageData: imageData ?? this.imageData,
      mimeType: mimeType ?? this.mimeType,
      imageUrl: imageUrl ?? this.imageUrl,
      data: data ?? this.data,
      isError: isError ?? this.isError,
    );
  }

  /// Converts the message to a map (excluding `imageData`, which is not serializable)
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'content': content,
      'generatedAt': generatedAt.millisecondsSinceEpoch,
      'isFromAgent': isFromAgent,
      'mimeType': mimeType,
      'imageUrl': imageUrl,
      'data': data,
      'isError': isError,
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
      mimeType: map['mimeType'] as String? ?? 'image/jpeg',
      imageUrl: map['imageUrl'] != null ? map['imageUrl'] as String : null,
      data: map['data'] as Map<String, dynamic>?,
      isError: map['isError'] as bool? ?? false,
    );
  }

  /// Converts the message to a JSON string
  String toJson() => json.encode(toMap());

  /// Parses a message from a JSON string
  factory AgentMessage.fromJson(String source) =>
      AgentMessage.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'AgentMessage(content: $content, generatedAt: $generatedAt, isFromAgent: $isFromAgent, imageData: $imageData, mimeType: $mimeType, imageUrl: $imageUrl, data: $data, isError: $isError)';
  }

  /// Equality check based on all fields
  @override
  bool operator ==(covariant AgentMessage other) {
    if (identical(this, other)) return true;

    return other.content == content &&
        other.generatedAt == generatedAt &&
        other.isFromAgent == isFromAgent &&
        listEquals(other.imageData, imageData) &&
        other.mimeType == mimeType &&
        other.imageUrl == imageUrl &&
        mapEquals(other.data, data) &&
        other.isError == isError;
  }

  /// Hash code based on all fields
  @override
  int get hashCode => Object.hash(
    content,
    generatedAt,
    isFromAgent,
    imageData != null ? Object.hashAll(imageData!) : null,
    mimeType,
    imageUrl,
    data != null ? Object.hashAll(data!.entries) : null,
    isError,
  );
}
