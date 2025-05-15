import 'dart:convert';

import 'package:flutter/foundation.dart';

class ToolResponse {
  final String toolName;
  final bool isRequestSuccessful;
  final String message;
  final Map<String, dynamic>? data;
  ToolResponse({
    required this.toolName,
    required this.isRequestSuccessful,
    required this.message,
    this.data,
  });

  ToolResponse copyWith({
    String? toolName,
    bool? isRequestSuccessful,
    String? message,
    Map<String, dynamic>? data,
  }) {
    return ToolResponse(
      toolName: toolName ?? this.toolName,
      isRequestSuccessful: isRequestSuccessful ?? this.isRequestSuccessful,
      message: message ?? this.message,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'toolName': toolName,
      'isRequestSuccessful': isRequestSuccessful,
      'message': message,
      'data': data,
    };
  }

  factory ToolResponse.fromMap(Map<String, dynamic> map) {
    return ToolResponse(
      toolName: map['toolName'] as String,
      isRequestSuccessful: map['isRequestSuccessful'] as bool,
      message: map['message'] as String,
      data: map['data'] is Map ? Map<String, dynamic>.from(map['data']) : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory ToolResponse.fromJson(String source) =>
      ToolResponse.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'ToolResponse(toolName: $toolName, isRequestSuccessful: $isRequestSuccessful, message: $message, data: $data)';

  @override
  bool operator ==(covariant ToolResponse other) {
    if (identical(this, other)) return true;

    return other.toolName == toolName &&
        other.isRequestSuccessful == isRequestSuccessful &&
        other.message == message &&
        mapEquals(other.data, data);
  }

  @override
  int get hashCode =>
      toolName.hashCode ^
      isRequestSuccessful.hashCode ^
      message.hashCode ^
      data.hashCode;
}
