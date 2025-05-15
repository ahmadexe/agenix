// Responses from tools are used to communicate the results of a tool's operation.
// They contain information about the tool that generated the response, whether the request was successful, and any data returned by the tool.
// This class is used to encapsulate the response from a tool, making it easier to handle and process the results.
// The ToolResponse class is used to represent the response from a tool.

import 'dart:convert';

import 'package:flutter/foundation.dart';

class ToolResponse {
  // The name of the tool that generated this response.
  final String toolName;

  // Indicates whether the request to the tool was successful.
  // This is useful for error handling and debugging, is request fails add a personalized message to the user.
  final bool isRequestSuccessful;

  // This is the message the end user will see, if the tools fetches some data, add the info here or success or failure messages based on the request.
  final String message;

  // Optional data returned by the tool. This will be used for chaining responses in later versios.
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
