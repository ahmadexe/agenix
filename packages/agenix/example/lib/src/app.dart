import 'package:flutter/material.dart';

import 'agents/agent_setup.dart';
import 'event_bus.dart';
import 'ui/chat_panel.dart';
import 'ui/event_log_panel.dart';
import 'ui/graph_panel.dart';
import 'ui/theme.dart';

class AgenixDemoApp extends StatelessWidget {
  const AgenixDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenix · Live Topology',
      debugShowCheckedModeBanner: false,
      theme: SciTheme.build(),
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  String? _apiKey;
  AgentTopology? _topology;
  String? _error;

  static const _envKey = String.fromEnvironment('GEMINI_API_KEY');

  @override
  void initState() {
    super.initState();
    if (_envKey.isNotEmpty) {
      _apiKey = _envKey;
      _boot();
    }
  }

  Future<void> _boot() async {
    try {
      final t = await buildDemoTopology(apiKey: _apiKey!);
      if (!mounted) return;
      setState(() => _topology = t);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _topology?.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_topology != null) return _Shell(topology: _topology!);
    if (_apiKey == null) {
      return _ApiKeyGate(
        onSubmit: (k) {
          setState(() => _apiKey = k);
          _boot();
        },
      );
    }
    return Scaffold(
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator(color: SciTheme.cyan)
            : Text(
                'Failed to boot: $_error',
                style: const TextStyle(color: SciTheme.danger),
              ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.topology});
  final AgentTopology topology;

  @override
  Widget build(BuildContext context) {
    final log = ValueNotifier<List<AgentEvent>>(const []);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, c) {
            final wide = c.maxWidth >= 900;
            final chat = ChatPanel(topology: topology);
            final graph = Column(
              children: [
                Expanded(
                  flex: 3,
                  child: GraphPanel(topology: topology, eventLog: log),
                ),
                Expanded(flex: 2, child: const EventLogPanel()),
              ],
            );
            if (wide) {
              return Row(
                children: [
                  Expanded(flex: 5, child: graph),
                  Container(width: 1, color: SciTheme.grid),
                  Expanded(flex: 3, child: chat),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: graph),
                Container(height: 1, color: SciTheme.grid),
                Expanded(child: chat),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ApiKeyGate extends StatefulWidget {
  const _ApiKeyGate({required this.onSubmit});
  final void Function(String) onSubmit;

  @override
  State<_ApiKeyGate> createState() => _ApiKeyGateState();
}

class _ApiKeyGateState extends State<_ApiKeyGate> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AGENIX · LIVE TOPOLOGY',
                  style: TextStyle(
                    color: SciTheme.cyan,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Paste a Gemini API key to boot the demo. '
                  'It stays in memory for this session only.',
                  style: TextStyle(
                    color: SciTheme.dim,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _c,
                  obscureText: true,
                  style: const TextStyle(
                    color: SciTheme.fg,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'AIza…',
                    hintStyle: const TextStyle(color: SciTheme.dim),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: SciTheme.grid),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: SciTheme.cyan),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onSubmitted: widget.onSubmit,
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_c.text.trim().isNotEmpty) {
                        widget.onSubmit(_c.text.trim());
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SciTheme.cyan.withValues(alpha: 0.15),
                      foregroundColor: SciTheme.cyan,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: const BorderSide(color: SciTheme.cyan),
                      ),
                    ),
                    child: const Text(
                      'ENGAGE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Tip: build with --dart-define=GEMINI_API_KEY=… to skip this screen.',
                  style: TextStyle(
                    color: SciTheme.dim,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
