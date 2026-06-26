import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../agents/agent_setup.dart';
import '../event_bus.dart';
import 'theme.dart';

/// Live visualisation of the agent topology. Nodes pulse when their agent is
/// thinking; edges glow when a delegation or tool call fires.
class GraphPanel extends StatefulWidget {
  const GraphPanel({super.key, required this.topology, required this.eventLog});

  final AgentTopology topology;
  final ValueNotifier<List<AgentEvent>> eventLog;

  @override
  State<GraphPanel> createState() => _GraphPanelState();
}

class _NodeFx {
  double pulse = 0.0; // 0..1, decays
  double activity = 0.0; // sustained 0..1 while thinking
  bool error = false;
}

class _EdgeFx {
  double pulse = 0.0; // animated 0..1
  bool error = false;
}

class _GraphPanelState extends State<GraphPanel>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  late StreamSubscription<AgentEvent> _sub;

  final Map<String, _NodeFx> _nodes = {};
  final Map<String, _EdgeFx> _edges = {};

  @override
  void initState() {
    super.initState();
    for (final spec in widget.topology.agents) {
      _nodes[spec.name] = _NodeFx();
      for (final t in spec.tools) {
        _nodes['tool:$t'] = _NodeFx();
        _edges['${spec.name}->tool:$t'] = _EdgeFx();
      }
    }
    // Coordinator -> specialists edges (delegation paths).
    final coord = widget.topology.coordinator.name;
    for (final spec in widget.topology.agents) {
      if (spec.role == AgentRole.specialist) {
        _edges['$coord->${spec.name}'] = _EdgeFx();
      }
    }

    _sub = AgentEventBus.instance.stream.listen(_onEvent);
    _ticker = createTicker((d) {
      _elapsed = d;
      _onTick(d);
    })..start();
  }

  void _onEvent(AgentEvent e) {
    switch (e.kind) {
      case AgentEventKind.agentThinking:
        final fx = _nodes[e.source];
        if (fx != null) {
          fx.activity = 1.0;
          fx.pulse = 1.0;
          fx.error = false;
        }
        // If the source isn't the coordinator, light the delegation edge too.
        final coord = widget.topology.coordinator.name;
        if (e.source != coord) {
          final edge = _edges['$coord->${e.source}'];
          if (edge != null) edge.pulse = 1.0;
        }
      case AgentEventKind.agentResponded:
        final fx = _nodes[e.source];
        if (fx != null) {
          fx.activity = 0.0;
          fx.pulse = 1.0;
          fx.error = e.detail == 'error';
        }
      case AgentEventKind.agentDelegated:
        if (e.target != null) {
          final edge = _edges['${e.source}->${e.target}'];
          if (edge != null) edge.pulse = 1.0;
        }
      case AgentEventKind.toolInvoked:
        if (e.target != null) {
          final edge = _edges['${e.source}->tool:${e.target}'];
          if (edge != null) edge.pulse = 1.0;
          final node = _nodes['tool:${e.target}'];
          if (node != null) {
            node.activity = 1.0;
            node.pulse = 1.0;
            node.error = false;
          }
        }
      case AgentEventKind.toolCompleted:
      case AgentEventKind.toolFailed:
        if (e.target != null) {
          final node = _nodes['tool:${e.target}'];
          if (node != null) {
            node.activity = 0.0;
            node.pulse = 1.0;
            node.error = e.kind == AgentEventKind.toolFailed;
          }
          final edge = _edges['${e.source}->tool:${e.target}'];
          if (edge != null) {
            edge.error = e.kind == AgentEventKind.toolFailed;
          }
        }
      case AgentEventKind.userMessage:
        break;
    }
    setState(() {});
  }

  void _onTick(Duration _) {
    for (final fx in _nodes.values) {
      fx.pulse = math.max(0, fx.pulse - 0.03);
    }
    for (final fx in _edges.values) {
      fx.pulse = math.max(0, fx.pulse - 0.02);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SciTheme.panel,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, c) {
                return CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _GraphPainter(
                    topology: widget.topology,
                    nodes: _nodes,
                    edges: _edges,
                    t: _elapsed.inMilliseconds / 1000.0,
                  ),
                );
              },
            ),
          ),
          _legend(),
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
          _BlinkingDot(),
          const SizedBox(width: 8),
          const Text(
            'AGENT TOPOLOGY · LIVE',
            style: TextStyle(
              color: SciTheme.cyan,
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            '${widget.topology.agents.length} agents · '
            '${_nodes.keys.where((k) => k.startsWith('tool:')).length} tools',
            style: const TextStyle(
              color: SciTheme.dim,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SciTheme.grid)),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        children: const [
          _LegendChip(color: SciTheme.cyan, label: 'agent thinking'),
          _LegendChip(color: SciTheme.magenta, label: 'tool firing'),
          _LegendChip(color: SciTheme.lime, label: 'idle / ready'),
          _LegendChip(color: SciTheme.danger, label: 'error'),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: SciTheme.dim,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Color.lerp(SciTheme.lime, SciTheme.cyan, _c.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: SciTheme.cyan.withValues(alpha: 0.5 + 0.5 * _c.value),
                blurRadius: 10,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Painter that lays out the topology and renders the live overlay.
class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.topology,
    required this.nodes,
    required this.edges,
    required this.t,
  });

  final AgentTopology topology;
  final Map<String, _NodeFx> nodes;
  final Map<String, _EdgeFx> edges;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    final coord = topology.coordinator;
    final specialists =
        topology.agents.where((a) => a.role == AgentRole.specialist).toList();

    // Layout: coordinator near the top, specialists in a row below, tools
    // arrayed around each specialist.
    final cx = size.width / 2;
    final coordPos = Offset(cx, size.height * 0.18);

    final positions = <String, Offset>{coord.name: coordPos};
    final rowY = size.height * 0.55;
    for (var i = 0; i < specialists.length; i++) {
      final x = size.width * ((i + 1) / (specialists.length + 1));
      positions[specialists[i].name] = Offset(x, rowY);
    }
    // Tools arc below each specialist.
    for (final spec in specialists) {
      final parent = positions[spec.name]!;
      final n = spec.tools.length;
      for (var i = 0; i < n; i++) {
        final spread = (n == 1) ? 0.0 : (i / (n - 1) - 0.5);
        final tx = parent.dx + spread * 110;
        final ty = parent.dy + 130;
        positions['tool:${spec.tools[i]}'] = Offset(tx, ty);
      }
    }

    // Edges.
    edges.forEach((key, fx) {
      final parts = key.split('->');
      final from = positions[parts[0]];
      final to = positions[parts[1]];
      if (from == null || to == null) return;
      _drawEdge(canvas, from, to, fx);
    });

    // Nodes.
    positions.forEach((key, pos) {
      final fx = nodes[key] ?? _NodeFx();
      if (key.startsWith('tool:')) {
        _drawToolNode(canvas, pos, key.substring(5), fx);
      } else if (key == coord.name) {
        _drawAgentNode(canvas, pos, 'COORDINATOR', fx, isCoordinator: true);
      } else {
        final spec = specialists.firstWhere((s) => s.name == key);
        _drawAgentNode(canvas, pos, spec.label.toUpperCase(), fx);
      }
    });
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = SciTheme.grid.withValues(alpha: 0.4)
          ..strokeWidth = 0.5;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawEdge(Canvas canvas, Offset a, Offset b, _EdgeFx fx) {
    final base =
        fx.error
            ? SciTheme.danger
            : (fx.pulse > 0.05 ? SciTheme.magenta : SciTheme.grid);
    final alpha = 0.25 + 0.75 * fx.pulse;
    final paint =
        Paint()
          ..color = base.withValues(alpha: alpha)
          ..strokeWidth = 1.0 + 2.5 * fx.pulse
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, paint);

    // Travelling spark while pulsing.
    if (fx.pulse > 0.05) {
      final p = ((t * 1.5) % 1.0);
      final sparkPos = Offset.lerp(a, b, p)!;
      final spark =
          Paint()
            ..color = base
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(sparkPos, 3.5, spark);
      canvas.drawCircle(sparkPos, 1.5, Paint()..color = Colors.white);
    }
  }

  void _drawAgentNode(
    Canvas canvas,
    Offset pos,
    String label,
    _NodeFx fx, {
    bool isCoordinator = false,
  }) {
    final active = fx.activity > 0.1 || fx.pulse > 0.05;
    final color =
        fx.error
            ? SciTheme.danger
            : active
            ? SciTheme.cyan
            : (isCoordinator ? SciTheme.amber : SciTheme.lime);

    final radius = isCoordinator ? 32.0 : 26.0;

    // Outer glow halo (scales with pulse).
    final haloR = radius + 18 + 12 * fx.pulse;
    final halo =
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.45 * (0.4 + fx.pulse)),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: pos, radius: haloR));
    canvas.drawCircle(pos, haloR, halo);

    // Rotating ring while thinking.
    if (fx.activity > 0.1) {
      final ringPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: 0.8);
      final rect = Rect.fromCircle(center: pos, radius: radius + 8);
      final sweep = math.pi * 0.8;
      final start = (t * 3) % (math.pi * 2);
      canvas.drawArc(rect, start, sweep, false, ringPaint);
      canvas.drawArc(rect, start + math.pi, sweep, false, ringPaint);
    }

    // Body.
    final body = Paint()..color = SciTheme.bg;
    canvas.drawCircle(pos, radius, body);
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color;
    canvas.drawCircle(pos, radius, stroke);

    // Center dot.
    canvas.drawCircle(pos, 3, Paint()..color = color);

    _drawLabel(canvas, pos.translate(0, radius + 16), label, color);
  }

  void _drawToolNode(Canvas canvas, Offset pos, String name, _NodeFx fx) {
    final active = fx.activity > 0.1 || fx.pulse > 0.05;
    final color =
        fx.error ? SciTheme.danger : (active ? SciTheme.magenta : SciTheme.dim);

    final rect = Rect.fromCenter(center: pos, width: 22, height: 22);

    // Glow.
    final glowR = 16 + 10 * fx.pulse;
    final halo =
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.5 * (0.3 + fx.pulse)),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: pos, radius: glowR));
    canvas.drawCircle(pos, glowR, halo);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(math.pi / 4);
    final r = Rect.fromCenter(center: Offset.zero, width: 18, height: 18);
    canvas.drawRect(r, Paint()..color = SciTheme.bg);
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = color,
    );
    canvas.restore();

    _drawLabel(
      canvas,
      pos.translate(0, 22),
      name,
      color,
      mono: true,
      small: true,
    );
    rect.toString(); // silence unused
  }

  void _drawLabel(
    Canvas canvas,
    Offset pos,
    String text,
    Color color, {
    bool mono = false,
    bool small = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: small ? 9.5 : 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos.translate(-tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
