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
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    final apiResponse = {
      'headline': 'Flutter is Awesome!',
      'details': 'Flutter 3.0 has been released with amazing features.',
    };
    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message:
          'Breaking News: ${apiResponse['headline']}. \n${apiResponse['details']}',
      data:
          apiResponse, // The data field is optional you can return data if it is required.
    );
  }
}

class WeatherTool extends Tool {
  WeatherTool({
    required super.name,
    required super.description,
    required super.parameters,
  });

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    final apiResponse = {'temperature': 25, 'condition': 'Sunny'};
    final location = params['location'] as String;

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message:
          'The weather in $location is ${apiResponse['condition']} with a temperature of ${apiResponse['temperature']}°C.',
    );
  }
}
