import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'peer_display.dart';

/// Who your phone can reach right now, drawn as the mesh it is: you in the
/// middle, people in range on the inner ring linked to you, everyone else
/// faded on the outer ring. The link style is the transport: solid for
/// Wi-Fi, dashed for Bluetooth, dotted for reached through other phones.
class MeshMap extends StatefulWidget {
  /// [ApplicationAPI.peers] status maps.
  final List<Map<String, dynamic>> peers;
  final String myName;
  final double height;

  const MeshMap({super.key, required this.peers, required this.myName, this.height = 200});

  /// What the map shows, in words, for screen readers and the caption.
  static String summary(List<Map<String, dynamic>> peers) {
    final direct = peers.where((p) => p['wifi'] == true || p['bt'] == true).length;
    final relayed = peers.where((p) => p['online'] == true && p['wifi'] != true && p['bt'] != true).length;
    if (direct + relayed == 0) {
      return peers.isEmpty ? 'No one in range yet' : 'No one in range right now';
    }
    return [
      if (direct > 0) '$direct in range',
      if (relayed > 0) '$relayed through other phones',
    ].join(', ');
  }

  @override
  State<MeshMap> createState() => _MeshMapState();
}

class _MeshMapState extends State<MeshMap> with SingleTickerProviderStateMixin {
  // The links draw out from you once, when the map first appears
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    } else if (!_reveal.isAnimating && _reveal.value == 0) {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Mesh map. ${MeshMap.summary(widget.peers)}',
      excludeSemantics: true,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _MeshPainter(
            peers: widget.peers,
            myName: widget.myName,
            progress: CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic),
            colors: ChatterColors.of(context),
            brightness: theme.brightness,
          ),
        ),
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final List<Map<String, dynamic>> peers;
  final String myName;
  final Animation<double> progress;
  final ChatterColors colors;
  final Brightness brightness;

  _MeshPainter({
    required this.peers,
    required this.myName,
    required this.progress,
    required this.colors,
    required this.brightness,
  }) : super(repaint: progress);

  // Enough to stay readable on a phone; the caption gives the full count
  static const _maxOnline = 8;
  static const _maxOffline = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = Size(math.min(size.width / 2 - 22, 190), size.height / 2 - 18);
    final inner = Size(math.min(size.width / 2 - 44, 132), size.height / 2 - 44);
    final t = progress.value;

    // Range rings
    final ringPaint = Paint()
      ..color = colors.faint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    _dashedEllipse(canvas, c, outer, ringPaint, dash: 3, gap: 7);
    _dashedEllipse(canvas, c, inner, ringPaint, dash: 6, gap: 6);

    final online = peers.where((p) => p['online'] == true).take(_maxOnline).toList();
    final offline = peers.where((p) => p['online'] != true).take(_maxOffline).toList();

    Offset onEllipse(Size r, double angle) => c + Offset(math.cos(angle) * r.width, math.sin(angle) * r.height);
    const start = -2.4;

    for (var i = 0; i < offline.length; i++) {
      final angle = start + math.pi / math.max(offline.length, 1) + i * 2 * math.pi / offline.length;
      final p = offline[i];
      paintPeerNode(canvas, onEllipse(outer, angle), 12,
          peerId: p['id'] as String,
          name: p['name'] as String? ?? '?',
          online: false,
          brightness: brightness,
          ring: colors.reach,
          faded: true);
    }

    final link = Paint()
      ..color = colors.link
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < online.length; i++) {
      final angle = start + i * 2 * math.pi / online.length;
      final at = onEllipse(inner, angle);
      final p = online[i];
      final end = Offset.lerp(c, at, t)!;
      if (p['wifi'] == true) {
        canvas.drawLine(c, end, link);
      } else if (p['bt'] == true) {
        _dashedLine(canvas, c, end, link, dash: 8, gap: 6);
      } else {
        _dashedLine(canvas, c, end, link, dash: 0.1, gap: 7);
      }
      if (t > 0.6) {
        paintPeerNode(canvas, at, 17,
            peerId: p['id'] as String,
            name: p['name'] as String? ?? '?',
            online: true,
            brightness: brightness,
            ring: colors.reach);
      }
    }

    // You: an ember node with a soft halo
    canvas.drawCircle(c, 31, Paint()..color = AppTheme.ember.withValues(alpha: 0.16));
    canvas.drawCircle(c, 23, Paint()..color = AppTheme.ember);
    final trimmed = myName.trim();
    final me = TextPainter(
      text: TextSpan(
        text: trimmed.isEmpty ? 'You' : trimmed.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontSize: trimmed.isEmpty ? 11 : 19,
          fontWeight: FontWeight.w700,
          color: AppTheme.onEmber,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    me.paint(canvas, c - Offset(me.width / 2, me.height / 2));
    me.dispose();
  }

  static void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint, {required double dash, required double gap}) {
    final length = (b - a).distance;
    if (length == 0) return;
    final dir = (b - a) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, length), paint);
    }
  }

  static void _dashedEllipse(Canvas canvas, Offset c, Size r, Paint paint, {required double dash, required double gap}) {
    final path = Path()..addOval(Rect.fromCenter(center: c, width: r.width * 2, height: r.height * 2));
    for (final ui.PathMetric metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.peers != peers || old.myName != myName || old.colors != colors || old.brightness != brightness;
}

/// A small key for the map's line styles, shown beside it.
class MeshLegend extends StatelessWidget {
  const MeshLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget item(String label, MeshLink link) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeshLinkSample(link),
            const SizedBox(width: 6),
            Text(label, style: style),
          ],
        );

    return ExcludeSemantics(
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          item('Wi-Fi', MeshLink.wifi),
          item('Bluetooth', MeshLink.bluetooth),
          item('Relayed', MeshLink.relayed),
        ],
      ),
    );
  }
}

/// How a peer is linked to you, as the mesh map draws it.
enum MeshLink { wifi, bluetooth, relayed }

/// One of the mesh map's link lines on its own: solid for Wi-Fi, dashed for
/// Bluetooth, dotted for relayed.
class MeshLinkSample extends StatelessWidget {
  final MeshLink link;
  final double width;

  const MeshLinkSample(this.link, {super.key, this.width = 22});

  @override
  Widget build(BuildContext context) {
    final (dash, gap) = switch (link) {
      MeshLink.wifi => (0.0, 0.0),
      MeshLink.bluetooth => (6.0, 4.0),
      MeshLink.relayed => (0.1, 5.0),
    };
    return CustomPaint(size: Size(width, 10), painter: _LegendLine(ChatterColors.of(context).link, dash, gap));
  }
}

class _LegendLine extends CustomPainter {
  final Color color;
  final double dash;
  final double gap;
  _LegendLine(this.color, this.dash, this.gap);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (dash == 0) {
      canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), paint);
    } else {
      _MeshPainter._dashedLine(canvas, Offset(1, y), Offset(size.width - 1, y), paint, dash: dash, gap: gap);
    }
  }

  @override
  bool shouldRepaint(_LegendLine old) => old.color != color;
}
