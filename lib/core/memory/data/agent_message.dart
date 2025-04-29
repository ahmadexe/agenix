import 'dart:convert';
import 'dart:typed_data';

class AgentMessage {
  final String content;
  final DateTime generatedAt;
  final bool isFromAgent;
  final Uint8List? imageData;
  final String? imageUrl;
  
  AgentMessage({
    required this.content,
    required this.generatedAt,
    required this.isFromAgent,
    this.imageData,
    this.imageUrl,
  });

  AgentMessage copyWith({
    String? content,
    DateTime? generatedAt,
    bool? isFromAgent,
    Uint8List? imageData,
    String? imageUrl,
  }) {
    return AgentMessage(
      content: content ?? this.content,
      generatedAt: generatedAt ?? this.generatedAt,
      isFromAgent: isFromAgent ?? this.isFromAgent,
      imageData: imageData ?? this.imageData,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'content': content,
      'generatedAt': generatedAt.millisecondsSinceEpoch,
      'isFromAgent': isFromAgent,
      'imageUrl': imageUrl,
    };
  }

  factory AgentMessage.fromMap(Map<String, dynamic> map) {
    return AgentMessage(
      content: map['content'] as String,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(map['generatedAt'] as int),
      isFromAgent: map['isFromAgent'] as bool,
      imageUrl: map['imageUrl'] != null ? map['imageUrl'] as String : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory AgentMessage.fromJson(String source) => AgentMessage.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'AgentMessage(content: $content, generatedAt: $generatedAt, isFromAgent: $isFromAgent, imageData: $imageData, imageUrl: $imageUrl)';
  }

  @override
  bool operator ==(covariant AgentMessage other) {
    if (identical(this, other)) return true;
  
    return 
      other.content == content &&
      other.generatedAt == generatedAt &&
      other.isFromAgent == isFromAgent &&
      other.imageData == imageData &&
      other.imageUrl == imageUrl;
  }

  @override
  int get hashCode {
    return content.hashCode ^
      generatedAt.hashCode ^
      isFromAgent.hashCode ^
      imageData.hashCode ^
      imageUrl.hashCode;
  }
}
