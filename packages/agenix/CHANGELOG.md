## 4.1.0
- **Multi-provider LLM support** — built-in implementations for OpenAI, Anthropic, Cohere, Groq, DeepSeek, Mistral, and xAI (Grok) alongside the existing Gemini adapter. All OpenAI-compatible providers share a single adapter with a configurable `baseUrl`.
- **`LlmRateLimitException`** — new typed exception (extends `LlmException`) thrown on HTTP 429 responses. Carries `retryAfter: Duration?` parsed from the `Retry-After` header and `statusCode: int` (defaults to 429).
- **`LlmException.statusCode`** — all LLM HTTP errors now expose the HTTP status code via `statusCode: int?` for programmatic handling.
- **Rolling memory summarization** — `Agent.create()` accepts `summarizationBatchSize: int` (default 0 = disabled). When enabled, evicted messages accumulate in a batch; once the batch reaches the threshold the LLM summarizes them into a rolling context prepended to every future prompt, preventing context window overflow on long conversations.
- **Bounded DataStore reads** — `_MemoryManager` now tracks a per-conversation `_savedCount` counter so eviction computes are done without fetching the full message history; `getContext` never issues an unbounded `getMessages` call regardless of conversation length.

## 4.0.1
- Added demo video to README showing live multi-agent orchestration and tool-call tracing.
- Updated package description for clarity and discoverability.

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
