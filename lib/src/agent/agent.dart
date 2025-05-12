import 'dart:convert';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/data_store.dart';
import 'package:agenix/src/static/_pkg_constants.dart';
import 'package:agenix/src/tools/_parser.dart';
import 'package:agenix/src/tools/tool_registry.dart';
import 'package:agenix/src/tools/_tool_runner.dart';
import 'package:flutter/services.dart';

part '_memory_manager.dart';
part '_prompt_builder.dart';

class Agent {
  static final Agent _instance = Agent._internal();
  factory Agent() => _instance;
  Agent._internal();

  bool _isInitialized = false;

  late final _MemoryManager _memoryManager;
  late final _PromptBuilder _promptBuilder;
  late final LLM llm;
  late final PromptParser _promptParser;
  late final ToolRunner _toolRunner;

  Future<void> init({required DataStore dataStore, required LLM llm}) async {
    if (_isInitialized) {
      throw Exception('Agent is already initialized');
    }
    try {
      _isInitialized = true;

      _memoryManager = _MemoryManager(dataStore: dataStore);
      this.llm = llm;

      String jsonString = await rootBundle.loadString(
        'assets/system_data.json',
      );
      final raw = json.decode(jsonString);
      _promptBuilder = _PromptBuilder(systemPrompt: raw);

      _promptParser = PromptParser();
      _toolRunner = ToolRunner();
    } catch (e) {
      _isInitialized = false;
      throw Exception('Failed to initialize Agent: $e');
    }
  }

  Future<AgentMessage> generateResponse({
    required String convoId,
    required AgentMessage userMessage,
    int memoryLimit = 10,
    Object? metaData,
  }) async {
    try {
      _memoryManager.saveMessage(convoId, userMessage);

      final memoryMessages = await _memoryManager.getContext(
        convoId,
        metaData: metaData,
      );

      final prompt = _promptBuilder.buildTextPrompt(
        memoryMessages: memoryMessages,
        userMessage: userMessage,
      );

      final rawLLMResponse = await llm.generate(prompt: prompt);
      final parsed = _promptParser.parse(rawLLMResponse);

      if (parsed.toolNames.isEmpty) {
        final response = parsed.fallbackResponse ?? kLLMResponseOnFailure;
        final botResponse = AgentMessage(
          content: response,
          isFromAgent: true,
          generatedAt: DateTime.now(),
        );
        _memoryManager.saveMessage(convoId, botResponse);
        return botResponse;
      }

      final toolResponses = await _toolRunner.runTools(parsed);

      String response = toolResponses
          .map((r) => r.values.first.toString())
          .join("\n");
      if (response.isEmpty) {
        response = parsed.fallbackResponse ?? kLLMResponseOnFailure;
        final botMessage = AgentMessage(
          content: response,
          isFromAgent: true,
          generatedAt: DateTime.now(),
        );
        _memoryManager.saveMessage(convoId, botMessage);
        return botMessage;
      }
      final queryResponse =
          "This is the infromation I can find for your query\n$response";
      final botMessage = AgentMessage(
        content: queryResponse,
        isFromAgent: true,
        generatedAt: DateTime.now(),
      );
      _memoryManager.saveMessage(convoId, botMessage);
      return botMessage;
    } catch (e) {
      if (!_isInitialized) {
        throw Exception('Agent is not initialized, please call init() first.');
      }
      return AgentMessage(
        content: kLLMResponseOnFailure,
        isFromAgent: true,
        generatedAt: DateTime.now(),
      );
    }
  }
}
