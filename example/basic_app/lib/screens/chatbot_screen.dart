import 'package:agenix/agenix.dart';
import 'package:flutter/material.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  bool _isLoading = false;
  String _response = 'Awaiting for response...';

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: const Text('Agenix Basic Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: controller),
            const SizedBox(height: 16),
            !_isLoading
                ? ElevatedButton(
                  onPressed: () async {
                    final userMessageRaw = controller.text;
                    final userMessage = AgentMessage(
                      content: userMessageRaw,
                      generatedAt: DateTime.now(),
                      isFromAgent: false,
                      imageUrl: null,
                      imageData: null,
                    );
                    setState(() {
                      _isLoading = true;
                    });
                    // Call the agent to get a response
                    final res = await Agent().generateResponse(
                      convoId: '1',
                      userMessage: userMessage,
                    );

                    setState(() {
                      _isLoading = false;
                      _response = res;
                    });
                  },
                  child: const Text('Send'),
                )
                : const CircularProgressIndicator(),

            const SizedBox(height: 16),
            Text(_response, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
