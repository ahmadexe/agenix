import 'package:agenix/src/memory/data/agent_message.dart';
import 'package:agenix/src/memory/data/data_store.dart';

part '_memory_manager.dart';

class Agent {
  static final Agent _instance = Agent._internal();
  factory Agent() => _instance;
  Agent._internal();

  bool _isInitialized = false;
  late final _MemoryManager _memoryManager;

  void init({required DataStore dataStore}) {
    if (_isInitialized) {
      throw Exception('Agent is already initialized');
    }
    _isInitialized = true;
    _memoryManager = _MemoryManager(dataStore: dataStore);
  }
}
