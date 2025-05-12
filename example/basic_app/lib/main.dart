import 'package:agenix/agenix.dart';
import 'package:basic_app/firebase_options.dart';
import 'package:basic_app/screens/chatbot_screen.dart';
import 'package:basic_app/services/firebase_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseService.init();
  final agent = Agent();
  const apiKey = String.fromEnvironment('GEMINI_API_KEY');
  agent.init(
    dataStore: FirebaseDataStore(),
    llm: Gemini(apiKey: apiKey, modelName: 'gemini-1.5-flash'),
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
