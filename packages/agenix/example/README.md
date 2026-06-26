# Agenix · Live Topology Example

A self-contained Flutter app that demonstrates **multi-agent orchestration**
with [`agenix`](https://pub.dev/packages/agenix) and visualises every agent
and tool call in real time on a sci-fi style graph.

## What it shows

- A **Coordinator** agent (no tools) that routes work to specialists.
- Three specialist agents, each with their own tools:
  - **Researcher** → `web_search`
  - **Analyst** → `market_data`, `statistics`
  - **Writer** → `sentiment_scan`
- An agent chain that runs `researcher → analyst → writer` for any topic
  the user asks about.
- A live **agent topology graph** on the left half of the UI: nodes pulse
  while their agent is thinking, edges glow when delegation or a tool call
  fires, and a scrolling event log tracks every step.
- A **chat terminal** on the right where you talk to the coordinator.

## Run it

```bash
cd packages/agenix/example
flutter pub get
flutter run --dart-define=GEMINI_API_KEY=your_key_here
```

If you don't pass `GEMINI_API_KEY` at build time, the app prompts for one on
launch and keeps it in memory for the session only.

## How the wiring works

The example wraps the package's public APIs (`LLM`, `Tool`) with two tiny
adapters that emit events on an in-process bus:

- `InstrumentedLlm` tags every `generate()` call with the owning agent name,
  so the graph knows which node to light up while the LLM is thinking.
- `InstrumentedTool` wraps each tool and emits `toolInvoked` /
  `toolCompleted` / `toolFailed` events with the owning agent name, so the
  edge between an agent and its tool can animate.

The graph itself is a single `CustomPainter` that reads the event stream and
maintains per-node and per-edge animation state. No third-party graph library
is involved — everything you see is plain Flutter.

## File layout

```
example/
├── assets/system_data.json     # Required by Agent.create
├── lib/
│   ├── main.dart
│   └── src/
│       ├── app.dart            # App shell, API-key gate, layout
│       ├── event_bus.dart      # In-process pub/sub
│       ├── agents/
│       │   ├── agent_setup.dart       # Builds coordinator + 3 specialists
│       │   ├── instrumented_llm.dart  # LLM wrapper that emits events
│       │   ├── instrumented_tool.dart # Tool wrapper that emits events
│       │   └── tools.dart             # The four demo tools
│       └── ui/
│           ├── chat_panel.dart        # Right-hand chat terminal
│           ├── event_log_panel.dart   # Scrolling activity feed
│           ├── graph_panel.dart       # CustomPainter graph
│           └── theme.dart
└── pubspec.yaml
```
