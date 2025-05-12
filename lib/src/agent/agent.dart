import 'dart:convert';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/data_store.dart';
import 'package:agenix/src/static/_pkg_constants.dart';
import 'package:agenix/src/tools/parser.dart';
import 'package:agenix/src/tools/tool_registry.dart';
import 'package:agenix/src/tools/tool_runner.dart';
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

    _isInitialized = true;

    _memoryManager = _MemoryManager(dataStore: dataStore);
    this.llm = llm;

    String jsonString = await rootBundle.loadString('assets/system_data.json');
    final raw = json.decode(jsonString);
    _promptBuilder = _PromptBuilder(systemPrompt: raw);

    _promptParser = PromptParser();
    _toolRunner = ToolRunner();
  }

  Future<String> generateResponse({
    required String convoId,
    required AgentMessage userMessage,
    int memoryLimit = 10,
    Object? metaData,
  }) async {
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
      return parsed.fallbackResponse ?? kLLMResponseOnFailure;
    }

    final toolResponses = await _toolRunner.runTools(parsed);

    String response = toolResponses
        .map((r) => r.values.first.toString())
        .join("\n");
    if (response.isEmpty) {
      return parsed.fallbackResponse ?? kLLMResponseOnFailure;
    }
    return "This is the infromation I can find for your query\n$response";
  }
}
