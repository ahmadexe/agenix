import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void stubSystemData(
  Map<String, dynamic> json, {
  String path = 'assets/system_data.json',
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key == path) {
          return ByteData.view(bytes.buffer);
        }
        return null;
      });
}

Map<String, dynamic> defaultSystemData() => {
  'persona': 'You are a helpful test assistant.',
  'rules': ['Be concise.'],
};
