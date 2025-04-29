import 'dart:convert';

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

  Future<void> init({required DataStore dataStore, required ToolRegistry toolRegistry}) async {
    if (_isInitialized) {
      throw Exception('Agent is already initialized');
    }

    _isInitialized = true;
    _memoryManager = _MemoryManager(dataStore: dataStore);
    this.toolRegistry = toolRegistry;

    String jsonString = await rootBundle.loadString('assets/system_data.json');
    final raw = json.decode(jsonString);
    _promptBuilder = _PromptBuilder(systemPrompt: raw);
  }
}
