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

  final AgentScope _scope;

  Agent._internal({
    required this.llm,
    required _MemoryManager memoryManager,
    required _PromptBuilder promptBuilder,
    required this.toolRegistry,
    required this.name,
    required this.role,
    required this.failureMode,
    required AgentScope scope,
    this.onError,
  }) : _memoryManager = memoryManager,
       _promptBuilder = promptBuilder,
       _scope = scope;

  /// Async factory constructor to create an instance with loaded system data.
  ///
  /// [scope] controls which group of agents this agent can discover and chain
  /// to. Defaults to [AgentScope.global].
  ///
  /// [registrationPolicy] controls what happens when an agent with the same
  /// [name] already exists in the scope. Defaults to
  /// [RegistrationPolicy.throwIfExists].
  static Future<Agent> create({
    required DataStore dataStore,
    required LLM llm,
    required String name,
    required String role,
    String pathToSystemData = 'assets/system_data.json',
    FailureMode failureMode = FailureMode.gracefulMessage,
    void Function(AgenixException error, StackTrace stack)? onError,
    AgentScope? scope,
    RegistrationPolicy registrationPolicy = RegistrationPolicy.throwIfExists,
  }) async {
    final resolvedScope = scope ?? AgentScope.global;
    final systemData = await _loadSystemData(pathToSystemData);
    final registry = ToolRegistry();
    final agent = Agent._internal(
      llm: llm,
      memoryManager: _MemoryManager(dataStore: dataStore),
      promptBuilder: _PromptBuilder(
        systemPrompt: systemData,
        registry: registry,
        scope: resolvedScope,
      ),
      toolRegistry: registry,
      name: name,
      role: role,
      failureMode: failureMode,
      onError: onError,
      scope: resolvedScope,
    );

    _AgentRegistry.instance.registerAgent(agent, policy: registrationPolicy);
    return agent;
  }

  /// Unregisters this agent from its scope, releasing it for re-creation.
  void dispose() {
    _AgentRegistry.instance.unregisterAgent(this);
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
    Set<String>? chainVisited,
    int chainDepth = 0,
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

    // Accumulated tool observations for multi-step tool use.
    final observations = <Map<String, dynamic>>[];
    var currentPrompt = prompt;
    var isFirstCall = true;

    for (var step = 0; step < kMaxToolIterations; step++) {
      final rawLLMResponse = await _llmGenerateWithParseRetry(
        prompt: currentPrompt,
        rawData: isFirstCall ? userMessage.imageData : null,
      );
      isFirstCall = false;

      final parsed = rawLLMResponse;

      switch (parsed.outcome) {
        case ParseOutcome.response:
          final response = parsed.fallbackResponse ?? kLLMResponseOnFailure;
          return AgentMessage(
            content: response,
            isFromAgent: true,
            generatedAt: DateTime.now(),
            data: observations.isNotEmpty ? {'observations': observations} : null,
          );

        case ParseOutcome.agentsChain:
          return _handleAgentChain(
            parsed: parsed,
            convoId: convoId,
            userMessage: userMessage,
            memoryLimit: memoryLimit,
            metaData: metaData,
            visited: chainVisited,
            depth: chainDepth,
          );

        case ParseOutcome.tools:
          final toolResponses = await _toolRunner.runTools(parsed, toolRegistry);

          for (final r in toolResponses) {
            observations.add({
              'tool': r.toolName,
              'success': r.isRequestSuccessful,
              'message': r.message,
              if (r.data != null) 'data': r.data,
            });
          }

          final needsFurtherReasoning = toolResponses.any(
            (r) => r.needsFurtherReasoning,
          );

          if (needsFurtherReasoning) {
            return _reasonUsingData(
              userMessage.content,
              toolResponses,
            );
          }

          // Build a follow-up prompt with observations so the LLM can
          // decide whether to call more tools or produce a final response.
          currentPrompt = _buildObservationPrompt(
            originalPrompt: prompt,
            observations: observations,
          );

        case ParseOutcome.unparseable:
          // All parse retries exhausted in _llmGenerateWithParseRetry
          throw ResponseParseException(
            'LLM output remained unparseable after retries',
            rawOutput: parsed.rawOutput ?? '',
          );
      }
    }

    // Max iterations reached — synthesize from what we have
    if (observations.isNotEmpty) {
      final summary = observations.map((o) => o['message'] ?? '').join('\n');
      return AgentMessage(
        content: summary.isEmpty ? kLLMResponseOnFailure : summary,
        isFromAgent: true,
        generatedAt: DateTime.now(),
        data: {'observations': observations},
      );
    }

    return AgentMessage(
      content: kLLMResponseOnFailure,
      isFromAgent: true,
      generatedAt: DateTime.now(),
    );
  }

  /// Calls the LLM and retries with a corrective instruction on parse failure.
  Future<PromptParserResult> _llmGenerateWithParseRetry({
    required String prompt,
    Uint8List? rawData,
  }) async {
    var currentPrompt = prompt;
    for (var attempt = 0; attempt <= kMaxParseRetries; attempt++) {
      final raw = await llm.generate(
        prompt: currentPrompt,
        rawData: attempt == 0 ? rawData : null,
      );
      final parsed = _promptParser.parse(raw);
      if (parsed.outcome != ParseOutcome.unparseable) return parsed;

      // Append corrective instruction for retry
      currentPrompt = '$prompt\n\n$kParseRetryInstruction';
    }

    // Return unparseable after all retries exhausted
    return PromptParserResult(
      outcome: ParseOutcome.unparseable,
      agentNames: [],
      toolNames: [],
      params: {},
      rawOutput: currentPrompt,
    );
  }

  String _buildObservationPrompt({
    required String originalPrompt,
    required List<Map<String, dynamic>> observations,
  }) {
    final observationJson = json.encode(observations);
    return '$originalPrompt\n\n'
        'Tool observations so far:\n$observationJson\n\n'
        'Based on these observations, either call more tools if needed or '
        'provide a final response in JSON format.';
  }

  Future<AgentMessage> _handleAgentChain({
    required PromptParserResult parsed,
    required String convoId,
    required AgentMessage userMessage,
    required int memoryLimit,
    Object? metaData,
    Set<String>? visited,
    int depth = 0,
  }) async {
    List<String> agentsChain = parsed.agentNames;
    String? inputForNextStep;
    AgentMessage? agentResponse;
    final visitedSet = visited ?? <String>{name};

    while (agentsChain.isNotEmpty) {
      final agentName = agentsChain.removeAt(0);

      if (visitedSet.contains(agentName)) {
        throw ConfigException(
          'Cycle detected in agent chain: $agentName has already been visited '
          '(path: ${visitedSet.join(" → ")} → $agentName)',
        );
      }

      if (depth >= kMaxChainDepth) {
        throw ConfigException(
          'Agent chain depth limit ($kMaxChainDepth) exceeded at agent $agentName',
        );
      }

      final agent = _AgentRegistry.instance.getAgent(agentName, scope: _scope);

      if (agent == null) {
        throw AgentNotFoundException(agentName);
      }

      visitedSet.add(agentName);

      agentResponse = await agent._generateResponse(
        convoId: convoId,
        userMessage: userMessage,
        memoryLimit: memoryLimit,
        metaData: metaData,
        isPartOfChain: true,
        input: inputForNextStep,
        chainVisited: visitedSet,
        chainDepth: depth + 1,
      );

      inputForNextStep =
          agentResponse.data != null
              ? json.encode(agentResponse.data)
              : agentResponse.content;
    }

    return agentResponse!;
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
    Object? metaData,
  }) {
    return _memoryManager.dataStore.getConversations(
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

  Future<AgentMessage> _reasonUsingData(
    String originalPrompt,
    List<ToolResponse> toolResponses,
  ) async {
    final toolData = toolResponses.map((r) => {
      'tool': r.toolName,
      'message': r.message,
      if (r.data != null) 'data': r.data,
    }).toList();

    final result = await llm.generate(
      prompt:
          'Keep the answer to the point but natural, only answer what is asked '
          'in the original prompt using this data.\n\n'
          'Tool results: ${json.encode(toolData)}\n\n'
          'Original prompt: $originalPrompt',
    );

    return AgentMessage(
      content: result,
      isFromAgent: true,
      generatedAt: DateTime.now(),
      data: {'tools': toolData},
    );
  }

  @override
  String toString() => 'Agent(name: $name, role: $role)';
}
