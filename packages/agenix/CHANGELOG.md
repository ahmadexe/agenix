## 4.0.0
- **BREAKING**: Removed `DataStore.firestoreDataStore()` and all Firebase dependencies from core. Firebase support is now in the separate `agenix_firebase` package.
  ```diff
  # pubspec.yaml
    dependencies:
      agenix: ^4.0.0
  +   agenix_firebase: ^1.0.0

  # dart
  + import 'package:agenix_firebase/agenix_firebase.dart';
  - final store = DataStore.firestoreDataStore();
  + final store = FirebaseDataStore();
  ```
- Sealed exception hierarchy (`AgenixException`) with typed subclasses: `LlmException`, `LlmTimeoutException`, `ResponseParseException`, `ToolNotFoundException`, `ToolExecutionException`, `AgentNotFoundException`, `DataStoreException`, `NotAuthenticatedException`, `ConfigException`
- `FailureMode` enum — choose between throwing typed exceptions or receiving graceful error messages
- Optional `onError` callback on `Agent` for centralized error handling
- `AgentScope` — isolate groups of agents for multi-tenant or testing scenarios
- `RegistrationPolicy` enum — control duplicate agent names (`throwIfExists`, `replace`, `ignore`)
- `LlmConfig` — provider-neutral generation settings: `temperature`, `maxOutputTokens`, `topP`, `topK`, `stopSequences`, `jsonMode`, `timeout`
- `InMemoryDataStore` — zero-dependency data store for testing and prototyping (`DataStore.inMemory()`)
- Multi-step tool iterations — agent can call tools in a loop (up to 5 iterations), accumulating observations before producing a final response
- Parse-retry mechanism — automatic corrective re-prompts (up to 2 retries) when the LLM returns malformed JSON
- Agent chain cycle detection and depth limiting (`kMaxChainDepth = 5`)
- `Agent.dispose()` — explicit cleanup to unregister agents from their scope
- `isError` field on `AgentMessage` — error messages are excluded from conversation history sent to the LLM
- `ParameterSpecification` now supports `defaultValue` and `enumValues` for richer tool parameter definitions
- CI pipeline with formatting, analysis, test coverage enforcement (50% floor), and Codecov integration
- Mimetype is not forced anymore.

### Breaking Changes
- Exception types replaced — code catching generic exceptions must switch to the sealed `AgenixException` hierarchy
- `Agent.create()` signature expanded with `failureMode`, `scope`, and `registrationPolicy` parameters (all have defaults)
- `LLM` interface now requires `modelId` getter and `config` getter returning `LlmConfig`

## 3.0.0
- Support for multiple agents
- Agents can reiterate over tool responses
- Agent orchestration to build chain of AI Agents
- Data sharing between agents


## 2.1.0
- Added support for custom path of Agent's data
- Added support to add data in the tool response directly
- Improved agent's understanding of parameters


## 2.0.0
- Added structured tool responses
- Easier interface to define messages the users should see from the tool
- Updated examples


## 1.0.2
- Updated documentation and refactored the code base


## 1.0.1
- Added keywords for better search


## 1.0.0
- Improved tool pipeline to allow the agent to understand tools without params
- Updated documentation
- Added tests with tool supports


## 0.0.1
- The release version of agenix with Firebase and Gemini
