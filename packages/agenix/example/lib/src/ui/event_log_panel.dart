import 'dart:async';

import 'package:flutter/material.dart';

import '../event_bus.dart';
import 'theme.dart';

/// Scrolling activity feed sitting below the graph — gives the user a textual
/// trace of every agent and tool event in order.
class EventLogPanel extends StatefulWidget {
  const EventLogPanel({super.key});

  @override
  State<EventLogPanel> createState() => _EventLogPanelState();
}

class _EventLogPanelState extends State<EventLogPanel> {
  final List<AgentEvent> _events = [];
  late final StreamSubscription<AgentEvent> _sub;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _sub = AgentEventBus.instance.stream.listen((e) {
      setState(() {
        _events.add(e);
        if (_events.length > 200) _events.removeAt(0);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SciTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: SciTheme.grid),
                bottom: BorderSide(color: SciTheme.grid),
              ),
            ),
            child: const Text(
              'EVENT STREAM',
              style: TextStyle(
                color: SciTheme.amber,
                fontFamily: 'monospace',
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _events.length,
              itemBuilder: (ctx, i) => _row(_events[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(AgentEvent e) {
    final (color, tag) = switch (e.kind) {
      AgentEventKind.userMessage => (SciTheme.fg, 'USR'),
      AgentEventKind.agentThinking => (SciTheme.cyan, 'THK'),
      AgentEventKind.agentResponded => (SciTheme.lime, 'RSP'),
      AgentEventKind.agentDelegated => (SciTheme.magenta, 'DEL'),
      AgentEventKind.toolInvoked => (SciTheme.magenta, 'TL→'),
      AgentEventKind.toolCompleted => (SciTheme.lime, 'TL✓'),
      AgentEventKind.toolFailed => (SciTheme.danger, 'TL✗'),
    };
    final ts = e.at;
    final time =
        '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}.'
        '${(ts.millisecond ~/ 10).toString().padLeft(2, '0')}';
    final target = e.target == null ? '' : '→${e.target}';
    final detail = e.detail == null ? '' : '  ${_truncate(e.detail!, 60)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          children: [
            TextSpan(
              text: '$time  ',
              style: const TextStyle(color: SciTheme.dim),
            ),
            TextSpan(
              text: tag,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: '  ${e.source}$target',
              style: const TextStyle(color: SciTheme.fg),
            ),
            TextSpan(
              text: detail,
              style: const TextStyle(color: SciTheme.dim),
            ),
          ],
        ),
      ),
    );
  }

  String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}
