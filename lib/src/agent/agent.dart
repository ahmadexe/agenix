import 'dart:convert';
import 'package:agenix/agenix.dart';
import 'package:agenix/src/static/_pkg_constants.dart';
import 'package:agenix/src/tools/_parser.dart';
import 'package:agenix/src/tools/_tool_runner.dart';
import 'package:agenix/src/tools/tool_registry.dart';
import 'package:flutter/services.dart';

part '_memory_manager.dart';
part '_prompt_builder.dart';
part '_agent_registry.dart';

/// Agent is the main class that represents the AI agent.
/// Define the agent with all background knowledge and tools.
class Agent {
  final _MemoryManager _memoryManager;
  final _PromptBuilder _promptBuilder;
  final PromptParser _promptParser = PromptParser();

  /// This is where you define the tools that the agent can use, registry allows you to register and unregister tools.
  final ToolRegistry toolRegistry;
  final ToolRunner _toolRunner = ToolRunner();

  /// The LLM that powers the agent, you can use a pre-built model like Gemini or if you have a custom implementation running on the server, you can use that.
  final LLM llm;

  /// This is the name of your agent, it is used to identify the agent in the conversation.
  final String name;

  /// This is the role of your agent, make it very descriptive because based on the description provided in role agents will be able to communicate with each other.
  final String role;

  /// Controls whether the agent throws typed exceptions or returns a graceful error message.
  final FailureMode failureMode;

  /// Optional callback invoked when an error occurs, regardless of failure mode.
  final void Function(AgenixException error, StackTrace stack)? onError;

  Agent._internal({
    required this.llm,
    required _MemoryManager memoryManager,
    required _PromptBuilder promptBuilder,
    required this.toolRegistry,
    required this.name,
    required this.role,
    required this.failureMode,
    this.onError,
  }) : _memoryManager = memoryManager,
       _promptBuilder = promptBuilder;

  /// Async factory constructor to create an instance with loaded system data.
  static Future<Agent> create({
    required DataStore dataStore,
    required LLM llm,
    required String name,
    required String role,
    String pathToSystemData = 'assets/system_data.json',
    FailureMode failureMode = FailureMode.gracefulMessage,
    void Function(AgenixException error, StackTrace stack)? onError,
  }) async {
    final systemData = await _loadSystemData(pathToSystemData);
    final registry = ToolRegistry();
    final agent = Agent._internal(
      llm: llm,
      memoryManager: _MemoryManager(dataStore: dataStore),
      promptBuilder: _PromptBuilder(
        systemPrompt: systemData,
        registry: registry,
      ),
      toolRegistry: registry,
      name: name,
      role: role,
      failureMode: failureMode,
      onError: onError,
    );

    _AgentRegistry.instance.registerAgent(agent);
    return agent;
  }

  static Future<Map<String, dynamic>> _loadSystemData(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw ConfigException(
          'System data at $path must be a JSON object, got ${decoded.runtimeType}',
        );
      }
      return decoded;
    } on AgenixException {
      rethrow;
    } catch (e, st) {
      throw ConfigException(
        'Failed to load system data from $path',
        cause: e,
        causeStack: st,
      );
    }
  }

  /// Generate a response to the user message. This is the public facing method.
  Future<AgentMessage> generateResponse({
    required String convoId,
    required AgentMessage userMessage,
    int memoryLimit = 10,
    Object? metaData,
  }) async {
    try {
      final response = await _generateResponse(
        convoId: convoId,
        userMessage: userMessage,
        memoryLimit: memoryLimit,
        metaData: metaData,
        isPartOfChain: false,
      );

      // Save both messages after generation so the user message isn't
      // duplicated in the context that was just sent to the LLM.
      await _memoryManager.saveMessage(convoId, userMessage, metaData: metaData);
      await _memoryManager.saveMessage(convoId, response, metaData: metaData);
      return response;
    } on AgenixException catch (e, st) {
      onError?.call(e, st);
      if (failureMode == FailureMode.throwError) rethrow;
      return AgentMessage(
        content: kLLMResponseOnFailure,
        isFromAgent: true,
        generatedAt: DateTime.now(),
        isError: true,
      );
    } catch (e, st) {
      final wrapped = LlmException('Unexpected error: $e', cause: e, causeStack: st);
      onError?.call(wrapped, st);
      if (failureMode == FailureMode.throwError) throw wrapped;
      return AgentMessage(
        content: kLLMResponseOnFailure,
        isFromAgent: true,
        generatedAt: DateTime.now(),
        isError: true,
      );
    }
  }

  Future<AgentMessage> _generateResponse({
    required String convoId,
    required AgentMessage userMessage,
    int memoryLimit = 10,
    Object? metaData,
    bool isPartOfChain = false,
    String? input,
  }) async {
    final memoryMessages = await _memoryManager.getContext(
      convoId,
      limit: memoryLimit,
      metaData: metaData,
    );

    final prompt = _promptBuilder.buildTextPrompt(
      memoryMessages: memoryMessages,
      userMessage: userMessage,
      isPartOfChain: isPartOfChain,
      input: input,
    );

    final String rawLLMResponse = await llm.generate(
      prompt: prompt,
      rawData: userMessage.imageData,
    );

    final parsed = _promptParser.parse(rawLLMResponse);

    if (parsed.agentNames.isEmpty && parsed.toolNames.isEmpty) {
      final response = parsed.fallbackResponse ?? kLLMResponseOnFailure;
      return AgentMessage(
        content: response,
        isFromAgent: true,
        generatedAt: DateTime.now(),
      );
    }

    if (parsed.agentNames.isNotEmpty) {
      List<String> agentsChain = parsed.agentNames;
      String? inputForNextStep;
      AgentMessage? agentResponse;
      while (agentsChain.isNotEmpty) {
        final agentName = agentsChain.removeAt(0);
        final agent = _AgentRegistry.instance.getAgent(agentName);

        if (agent == null) {
          throw AgentNotFoundException(agentName);
        }

        agentResponse = await agent._generateResponse(
          convoId: convoId,
          userMessage: userMessage,
          memoryLimit: memoryLimit,
          metaData: metaData,
          isPartOfChain: true,
          input: inputForNextStep,
        );

        inputForNextStep =
            agentResponse.data != null
                ? agentResponse.data!.toString()
                : agentResponse.content;
      }

      return agentResponse!;
    } else {
      final toolResponses = await _toolRunner.runTools(parsed, toolRegistry);
      final response = toolResponses.map((r) => r.message).join('\n');

      final needsFurtherReasoning = toolResponses.any(
        (r) => r.needsFurtherReasoning,
      );

      if (needsFurtherReasoning) {
        final originalPrompt = userMessage.content;
        final rawData = toolResponses.map((r) => r.data).join('\n');

        final processedResponse = await _reasonUsingData(
          originalPrompt,
          response,
          rawData,
        );

        return processedResponse;
      }

      final botMessage = AgentMessage(
        content: response.isEmpty ? kLLMResponseOnFailure : response,
        isFromAgent: true,
        generatedAt: DateTime.now(),
        data:
            toolResponses.isNotEmpty
                ? {'tools': toolResponses.map((r) => r.data).toList()}
                : null,
      );

      return botMessage;
    }
  }

  /// Get messages for a specific conversation from the datastore.
  Future<List<AgentMessage>> getMessages({
    required String conversationId,
    Object? metaData,
  }) {
    return _memoryManager.dataStore.getMessages(
      conversationId,
      metaData: metaData,
    );
  }

  /// Get all conversations from the datastore.
  Future<List<Conversation>> getAllConversations({
    required String conversationId,
    Object? metaData,
  }) {
    return _memoryManager.dataStore.getConversations(
      conversationId,
      metaData: metaData,
    );
  }

  /// Delete a conversation from the datastore.
  Future<void> deleteConversation({
    required String conversationId,
    Object? metaData,
  }) {
    return _memoryManager.dataStore.deleteConversation(
      conversationId,
      metaData: metaData,
    );
  }

  // The method is executed if further reasoning is required over the responses by the tools
  Future<AgentMessage> _reasonUsingData(
    String originalPrompt,
    String response,
    String rawData,
  ) async {
    final result = await llm.generate(
      prompt:
          "Keep the answer to the point but natural, only answer what is asked in the original prompt using this information: $response, and data: $rawData. Original prompt: $originalPrompt",
    );

    return AgentMessage(
      content: result,
      isFromAgent: true,
      generatedAt: DateTime.now(),
    );
  }

  @override
  String toString() => 'Agent(name: $name, role: $role)';
}
