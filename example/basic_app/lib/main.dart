import 'package:agenix/agenix.dart';
import 'package:basic_app/screens/chatbot_screen.dart';
import 'package:flutter/material.dart';

void main() {
  final agent = Agent();
  final apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
  );
  agent.init(
    dataStore: FirebaseDataStore(),
    llm: Gemini(
      apiKey: apiKey,
      modelName: 'gemini-1.5-flash',
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenix Basic Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ChatbotScreen(),
    );
  }
}
