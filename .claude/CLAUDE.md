# Agenix

Flutter package for building AI agents with memory, tools, and multi-agent orchestration. Currently at v4.0.0.

## Build & Test

```bash
flutter pub get          # install dependencies
flutter test             # run tests
flutter analyze          # lint
```

The package depends on Flutter SDK, so use `flutter` commands (not `dart`).

## Architecture

The package is organized under `lib/src/` into four domains:

- **agent/** — Core `Agent` class with its internal helpers as `part` files
- **llm/** — `LLM` abstract interface + concrete implementations (Gemini)
- **tools/** — `Tool` abstract class, `ToolRegistry`, `ParameterSpecification`, `ToolResponse`, and internal parser/runner
- **memory/** — `DataStore` abstract interface, data models (`AgentMessage`, `Conversation`), and concrete implementations (Firebase)
- **static/** — Package-level constants

## Conventions

### Public vs Internal API

- `lib/agenix.dart` is the barrel file — it exports only the public API surface. Any new public type must be added here.
- Internal files are prefixed with underscore: `_gemini.dart`, `_parser.dart`, `_tool_runner.dart`, `_firebase.dart`, `_memory_manager.dart`, `_prompt_builder.dart`, `_agent_registry.dart`, `_pkg_constants.dart`.
- Internal classes within the agent domain use Dart's `part`/`part of` mechanism to keep them private (`_MemoryManager`, `_PromptBuilder`, `_AgentRegistry`) while still accessing `Agent` internals.

### Extensibility via Abstract Classes

- `LLM` — abstract interface for language models. Concrete implementations go in `lib/src/llm/` with underscore prefix. Factory constructors live as static methods on the abstract class (e.g., `LLM.geminiLLM()`).
- `DataStore` — abstract interface for persistence backends. Same pattern: concrete implementations in `lib/src/memory/data_sources/` with underscore prefix, factory on the abstract class (e.g., `DataStore.firestoreDataStore()`).
- `Tool` — abstract class users extend to create custom tools. Has `name`, `description`, `parameters`, and an async `run()` method returning `ToolResponse`.

### Agent Creation

- `Agent` uses a private constructor (`Agent._internal`) and exposes an async factory `Agent.create()` that loads system data from an asset JSON file and self-registers in the singleton `_AgentRegistry`.
- System prompt data is loaded from `assets/system_data.json` by default via `rootBundle.loadString`.

### Registry Pattern

- `ToolRegistry` — instance-level, one per agent. Register/unregister tools dynamically.
- `_AgentRegistry` — singleton, package-internal. Agents auto-register on creation. Used for multi-agent orchestration (agent chaining).

### Data Models

All data models (`AgentMessage`, `Conversation`, `ToolResponse`) follow a consistent pattern:
- Named constructor with `required` fields
- `copyWith()` method
- `toMap()` / `fromMap()` for serialization
- `toJson()` / `fromJson()` (delegates to map methods via `json.encode`/`json.decode`)
- `==` operator override using `covariant` keyword
- `hashCode` override using XOR (`^`)

### LLM Communication

The agent communicates with LLMs via structured JSON prompts built by `_PromptBuilder`. The LLM is expected to respond in JSON, which `PromptParser` decodes into one of three shapes:
1. `{"response": "..."}` — direct text response
2. `{"tools": "tool1, tool2", "parameters": {...}}` — tool invocation
3. `{"agents_chain": ["agent1", "agent2"]}` — multi-agent delegation

### Tool Responses

`ToolResponse.needsFurtherReasoning` — when `true`, the agent makes a second LLM call to synthesize the tool output into a natural-language answer. This is the "reason over data" pattern for tools that fetch raw data.

### Naming

- Constants use `k` prefix: `kLLMResponseOnFailure`
- Private fields use underscore prefix: `_tools`, `_agents`, `_model`
- Method names are descriptive verbs: `registerTool`, `generateResponse`, `buildTextPrompt`

### Dependencies

- `google_generative_ai` for Gemini LLM
- Firebase suite (`firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`) for default data store
- `uuid` for unique ID generation
- SDK constraint: Dart ^3.7.2, Flutter >=1.17.0

### metaData Pattern

Many methods accept an optional `Object? metaData` parameter passed through the call chain. This is an opaque pass-through for consumer-specific context (e.g., auth tokens, tenant IDs) that concrete `DataStore` implementations can use.
