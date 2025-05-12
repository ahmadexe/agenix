import 'package:flutter/material.dart';

class FetchConvoScreen extends StatefulWidget {
  const FetchConvoScreen({super.key});

  @override
  State<FetchConvoScreen> createState() => _FetchConvoScreenState();
}

class _FetchConvoScreenState extends State<FetchConvoScreen> {

  @override
  void initState() {
    super.initState();

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fetch Conversation'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Fetch Conversation Screen'),
            ElevatedButton(
              onPressed: () {
                // Add your fetch conversation logic here
              },
              child: const Text('Fetch Conversation'),
            ),
          ],
        ),
      ),
    );
  }
}