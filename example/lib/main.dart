import 'package:agenix/agenix.dart';
import 'package:basic_app/firebase_options.dart';
import 'package:basic_app/services/firebase_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseService.init();

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

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  bool _isLoading = false;
  String _response = 'Awaiting for response...';

  // Image Data
  XFile? media;
  Uint8List? imageData;

  bool isAgentReady = false;
  late final Agent agent;
  Future<void> initAgent() async {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    agent = await Agent.create(
      dataStore: DataStore.firestoreDataStore(),
      llm: LLM.geminiLLM(apiKey: apiKey, modelName: 'gemini-1.5-flash'),
      name: 'All Purpose Agent',
      role: 'Everything is handled by this agent',
    );

    agent.toolRegistry.registerTool(
      NewsTool(
        name: 'news_tool',
        description:
            'This tool should be used if the user asks for news of any sort.',
      ),
    );
    agent.toolRegistry.registerTool(
      WeatherTool(
        name: 'weather_tool',
        description:
            'This tool should be used if the user asks for the weather.',
        parameters: [
          ParameterSpecification(
            name: 'location',
            type: 'String',
            description: 'The location for which to get the weather.',
            required: true,
          ),
        ],
      ),
    );

    agent.toolRegistry.registerTool(
      HelloTool(
        name: 'hello_tool',
        description:
            'This tool should be used if the user asks for hello, or any sort of greeting.',
        parameters: [
          ParameterSpecification(
            name: 'userName',
            type: 'String',
            description:
                'The user name that the agent should use to greet the user.',
            required: false,
          ),
        ],
      ),
    );

    agent.toolRegistry.registerTool(
      JobsTool(
        name: 'jobs_tool',
        description: 'This tool should be used if the user asks to post a job',
        parameters: [
          ParameterSpecification(
            name: 'jobTitle',
            type: 'String',
            description: 'The job title for which to get job postings.',
            required: true,
          ),
          ParameterSpecification(
            name: 'location',
            type: 'String',
            description: 'The location for which to get job postings.',
            required: true,
          ),
          ParameterSpecification(
            name: 'company',
            type: 'String',
            description: 'The company for which to get job postings.',
            required: true,
          ),
          ParameterSpecification(
            name: 'salary',
            type: 'String',
            description: 'The salary for which to get job postings.',
            required: true,
          ),
          ParameterSpecification(
            name: 'experience',
            type: 'String',
            description: 'The experience for which to get job postings.',
            required: true,
          ),
          ParameterSpecification(
            name: 'skills',
            type: 'String',
            description: 'The skills for which to get job postings.',
            required: true,
          ),
          ParameterSpecification(
            name: 'description',
            type: 'String',
            description: 'The description for which to get job postings.',
            required: true,
          ),
          ParameterSpecification(
            name: 'type',
            type: 'String',
            description: 'The type for which to get job postings.',
            required: true,
          ),
        ],
      ),
    );

    agent.toolRegistry.registerTool(
      CreatePostsTool(
        name: 'create_posts_tool',
        description:
            'This tool should be used if the user asks to create a post',
        parameters: [
          ParameterSpecification(
            name: 'title',
            type: 'String',
            description: 'The title of the post.',
            required: true,
          ),
          ParameterSpecification(
            name: 'description',
            type: 'String',
            description: 'The description of the post.',
            required: true,
          ),
          ParameterSpecification(
            name: 'userId',
            type: 'String',
            description: 'The user ID of the post creator.',
            required: true,
          ),
          ParameterSpecification(
            name: 'category',
            type: 'String',
            description: 'The category of the post.',
            required: true,
          ),
          ParameterSpecification(
            name: 'userName',
            type: 'String',
            description: 'The user name of the post creator.',
            required: true,
          ),
          ParameterSpecification(
            name: 'userProfilePic',
            type: 'String',
            description: 'The profile picture URL of the post creator.',
            required: false,
          ),
        ],
      ),
    );

    setState(() {
      isAgentReady = true;
    });
  }

  @override
  void initState() {
    super.initState();

    initAgent();
  }

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: const Text('Agenix Basic Example')),
      body:
          !isAgentReady
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(controller: controller),
                    ElevatedButton(
                      onPressed: () async {
                        final image = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          setState(() {
                            media = image;
                          });
                        }

                        final Uint8List data = await image!.readAsBytes();
                        setState(() {
                          imageData = data;
                        });
                      },
                      child: Text('Add Image'),
                    ),
                    const SizedBox(height: 16),
                    !_isLoading
                        ? ElevatedButton(
                          onPressed: () async {
                            final userMessageRaw = controller.text;
                            final userMessage = AgentMessage(
                              content: userMessageRaw,
                              generatedAt: DateTime.now(),
                              isFromAgent: false,
                              imageData: imageData,
                            );
                            setState(() {
                              _isLoading = true;
                            });
                            // Call the agent to get a response
                            final res = await agent.generateResponse(
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
    final location = params['location'] as String?;

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message:
          'The weather in $location is ${apiResponse['condition']} with a temperature of ${apiResponse['temperature']}°C.',
    );
  }
}

class HelloTool extends Tool {
  HelloTool({
    required super.name,
    required super.description,
    required super.parameters,
  });

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    final userName = params['userName'] as String?;

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Hello ${userName ?? 'User'} from the HelloTool!',
    );
  }
}

class JobsTool extends Tool {
  JobsTool({
    required super.name,
    required super.description,
    required super.parameters,
  });

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));
    final payload = {
      'jobTitle': params['jobTitle'] as String,
      'location': params['location'] as String,
      'company': params['company'] as String,
      'salary': params['salary'] as String,
      'experience': params['experience'] as String,
      'skills': params['skills'] as String,
      'description': params['description'] as String,
      'type': params['type'] as String,
    };

    debugPrint(payload.toString());

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Job posted successfully!',
      data:
          payload, // The data field is optional you can return data if it is required.
    );
  }
}

class CreatePostsTool extends Tool {
  CreatePostsTool({
    required super.name,
    required super.description,
    required super.parameters,
  });

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    final payload = {
      'title': params['title'] as String,
      'description': params['description'] as String,
      'userId': params['userId'] as String,
      'category': params['category'] as String,
      'userName': params['userName'] as String,
      'userProfilePic': params['userProfilePic'] as String,
      'createdAt': DateTime.now().toString(),
    };

    return ToolResponse(
      toolName: name,
      isRequestSuccessful: true,
      message: 'Post created successfully',
      data:
          payload, // The data field is optional you can return data if it is required.
    );
  }
}
