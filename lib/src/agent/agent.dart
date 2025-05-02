import 'dart:convert';

import 'package:agenix/src/llm/llm.dart';
import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/data_store.dart';
import 'package:agenix/src/tools/tool_registry.dart';
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
  late final ToolRegistry toolRegistry;
  late final LLM llm;

  Future<void> init({required DataStore dataStore, required ToolRegistry toolRegistry, required LLM llm}) async {
    if (_isInitialized) {
      throw Exception('Agent is already initialized');
    }

    _isInitialized = true;

    _memoryManager = _MemoryManager(dataStore: dataStore);
    this.toolRegistry = toolRegistry;
    this.llm = llm;

    String jsonString = await rootBundle.loadString('assets/system_data.json');
    final raw = json.decode(jsonString);
    _promptBuilder = _PromptBuilder(systemPrompt: raw);
  }

  Future<String> generateResponse({
    required String convoId,
    required AgentMessage userMessage,
    int memoryLimit = 10,
    Object? metaData,
  }) async {
    // TODO: Add memory manager implementation
    final memoryMessages = await _memoryManager.getContext(
      convoId,
      metaData: metaData,
    );

    final prompt = _promptBuilder.buildTextPrompt(
      memoryMessages: memoryMessages,
      userMessage: userMessage,
    );

    final response = await llm.generate(prompt: prompt);
    return response;
  }
}
