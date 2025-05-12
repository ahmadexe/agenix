import 'package:agenix/agenix.dart';
import 'package:basic_app/firebase_options.dart';
import 'package:basic_app/screens/chatbot_screen.dart';
import 'package:basic_app/screens/fetch_convo_screen.dart';
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
    dataStore: DataStore.firestoreDataStore(),
    llm: LLM.geminiLLM(apiKey: apiKey, modelName: 'gemini-1.5-flash'),
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
      home: const BaseScreen(),
    );
  }
}

class BaseScreen extends StatelessWidget {
  const BaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voucher Vertical Tests')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Test Agent'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ChatbotScreen()),
              );
            },
          ),
          ListTile(
            title: const Text('Test Fetch Conversation'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const FetchMessagesScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
