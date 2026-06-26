import 'package:agenix/agenix.dart';
import 'package:flutter/material.dart';

import '../agents/agent_setup.dart';
import '../event_bus.dart';
import 'theme.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.topology});
  final AgentTopology topology;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _convoId = 'demo-${DateTime.now().millisecondsSinceEpoch}';
  final _input = TextEditingController();
  final List<_ChatLine> _lines = [
    _ChatLine.system(
      'Coordinator is online. Ask anything — it will route through researcher → '
      'analyst → writer, lighting up each tool as it runs.',
    ),
  ];
  bool _busy = false;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _busy = true;
      _lines.add(_ChatLine.user(text));
    });
    AgentEventBus.instance.emitNow(
      AgentEventKind.userMessage,
      'user',
      detail: text,
    );

    try {
      final reply = await widget.topology.coordinator.generateResponse(
        convoId: _convoId,
        userMessage: AgentMessage(
          content: text,
          generatedAt: DateTime.now(),
          isFromAgent: false,
        ),
      );
      setState(() => _lines.add(_ChatLine.agent(reply.content)));
    } catch (e) {
      setState(() => _lines.add(_ChatLine.error('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SciTheme.bg,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              itemCount: _lines.length,
              itemBuilder: (ctx, i) => _LineView(line: _lines[i]),
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SciTheme.grid)),
      ),
      child: Row(
        children: [
          const Text(
            'TERMINAL · CHAT',
            style: TextStyle(
              color: SciTheme.magenta,
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            'convo=$_convoId',
            style: const TextStyle(
              color: SciTheme.dim,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SciTheme.grid)),
      ),
      child: Row(
        children: [
          const Text(
            '>',
            style: TextStyle(
              color: SciTheme.cyan,
              fontFamily: 'monospace',
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_busy,
              style: const TextStyle(
                color: SciTheme.fg,
                fontFamily: 'monospace',
              ),
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'ask the coordinator something…',
                hintStyle: TextStyle(
                  color: SciTheme.dim,
                  fontFamily: 'monospace',
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _busy ? null : _send,
            style: ElevatedButton.styleFrom(
              backgroundColor: SciTheme.cyan.withValues(alpha: 0.15),
              foregroundColor: SciTheme.cyan,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: const BorderSide(color: SciTheme.cyan),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SciTheme.cyan,
                    ),
                  )
                : const Text(
                    'SEND',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      letterSpacing: 1.4,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

enum _Kind { user, agent, system, error }

class _ChatLine {
  _ChatLine(this.kind, this.text);
  factory _ChatLine.user(String t) => _ChatLine(_Kind.user, t);
  factory _ChatLine.agent(String t) => _ChatLine(_Kind.agent, t);
  factory _ChatLine.system(String t) => _ChatLine(_Kind.system, t);
  factory _ChatLine.error(String t) => _ChatLine(_Kind.error, t);
  final _Kind kind;
  final String text;
}

class _LineView extends StatelessWidget {
  const _LineView({required this.line});
  final _ChatLine line;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (line.kind) {
      _Kind.user => ('user', SciTheme.fg),
      _Kind.agent => ('coordinator', SciTheme.cyan),
      _Kind.system => ('system', SciTheme.dim),
      _Kind.error => ('error', SciTheme.danger),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[$label]',
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 10,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            line.text,
            style: TextStyle(
              color: line.kind == _Kind.system ? SciTheme.dim : SciTheme.fg,
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
