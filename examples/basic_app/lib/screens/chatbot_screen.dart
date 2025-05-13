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
  void initState() {
    super.initState();
    ToolRegistry().registerTool(
      NewsTool(
        name: 'news_tool',
        description:
            'This tool should be used if the user asks for news of any sort.',
      ),
    );
    ToolRegistry().registerTool(
      WeatherTool(
        name: 'weather_tool',
        description:
            'This tool should be used if the user asks for the weather.',
        parameters: [
          ParamSpec(
            name: 'location',
            type: 'String',
            description: 'The location for which to get the weather.',
            required: true,
          ),
        ],
      ),
    );
  }

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
                      _response = res.content;
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

class NewsTool extends Tool {
  NewsTool({required super.name, required super.description});

  @override
  Future<Map<String, dynamic>?> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    return {
      'title': 'Breaking News',
      'description': 'This is a sample news description.',
    };
  }
}

class WeatherTool extends Tool {
  WeatherTool({
    required super.name,
    required super.description,
    required super.parameters,
  });

  @override
  Future<Map<String, dynamic>?> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    return {
      'temperature': '25°C',
      'condition': 'Sunny',
      'location': params['location'],
    };
  }
}
