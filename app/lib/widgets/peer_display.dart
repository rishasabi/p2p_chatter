import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How a peer can be reached right now, from an [ApplicationAPI.peerStatus]
/// map, in words people use ("Bluetooth", not "BLUETOOTH").
String reachLabel(Map<String, dynamic> status) {
  final wifi = status['wifi'] == true;
  final bt = status['bt'] == true;
  if (wifi && bt) return 'Wi-Fi and Bluetooth';
  if (wifi) return 'Wi-Fi';
  if (bt) return 'Bluetooth';
  if (status['mesh'] == true) return 'Via mesh relay';
  return 'Offline';
}

/// Long sentence form for the chat header and screen readers.
String reachSentence(Map<String, dynamic> status) {
  if (status['online'] != true) return 'Offline';
  if (status['mesh'] == true && status['wifi'] != true && status['bt'] != true) {
    return 'Reachable through other phones';
  }
  return 'Online over ${reachLabel(status)}';
}

/// Peer IDs are long; keep the start and end so two IDs stay tell-apart.
String compactPeerId(String id) =>
    id.length > 26 ? '${id.substring(0, 12)}…${id.substring(id.length - 6)}' : id;

/// Paints one person as a mesh node: a disc tinted from their peer ID (the
/// same person always gets the same colour) carrying their initial, and a
/// ring round it while they're reachable. Shared by [PeerAvatar] and the
/// mesh map so a person looks the same everywhere.
void paintPeerNode(
  Canvas canvas,
  Offset center,
  double radius, {
  required String peerId,
  required String name,
  required bool online,
  required Brightness brightness,
  required Color ring,
  bool faded = false,
}) {
  // Ember means "you", so peers never get an amber hue
  const hues = [200.0, 152.0, 265.0, 340.0, 185.0, 300.0, 120.0];
  final hue = hues[peerId.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff) % hues.length];
  final dark = brightness == Brightness.dark;
  var bg = (dark ? HSLColor.fromAHSL(1, hue, 0.34, 0.32) : HSLColor.fromAHSL(1, hue, 0.55, 0.85)).toColor();
  var fg = (dark ? HSLColor.fromAHSL(1, hue, 0.70, 0.88) : HSLColor.fromAHSL(1, hue, 0.60, 0.22)).toColor();
  if (faded) {
    bg = bg.withValues(alpha: 0.45);
    fg = fg.withValues(alpha: 0.7);
  }

  final disc = online ? radius * 0.8 : radius;
  canvas.drawCircle(center, disc, Paint()..color = bg);
  if (online) {
    canvas.drawCircle(
      center,
      radius - radius * 0.06,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.12
        ..color = ring,
    );
  }

  final trimmed = name.trim();
  final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  final text = TextPainter(
    text: TextSpan(
      text: initial,
      style: TextStyle(
        fontFamily: AppTheme.displayFont,
        fontSize: disc * 0.82,
        fontWeight: FontWeight.w700,
        color: fg,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  text.dispose();
}

/// A person's node, in lists and headers. Fixed to its circle: an initial
/// that grew with system text would overflow rather than get more legible.
class PeerAvatar extends StatelessWidget {
  final String peerId;
  final String name;
  final bool online;
  final double size;

  const PeerAvatar({
    super.key,
    required this.peerId,
    required this.name,
    this.online = false,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final ring = ChatterColors.of(context).reach;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _NodePainter((canvas, s) => paintPeerNode(
              canvas,
              s.center(Offset.zero),
              s.shortestSide / 2,
              peerId: peerId,
              name: name,
              online: online,
              brightness: brightness,
              ring: ring,
            )),
      ),
    );
  }
}

class _NodePainter extends CustomPainter {
  final void Function(Canvas canvas, Size size) draw;
  _NodePainter(this.draw);

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  // Cheap to draw and rebuilt with new values whenever the avatar rebuilds
  @override
  bool shouldRepaint(_NodePainter oldDelegate) => true;
}

/// A channel's mark in lists and headers: a # for an open channel, a lock for
/// a private one, on a neutral disc (ember means "you"; peer hues mean people).
class ChannelAvatar extends StatelessWidget {
  final bool private;
  final double size;

  const ChannelAvatar({super.key, required this.private, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle),
        child: SizedBox.square(
          dimension: size,
          child: Icon(private ? Icons.lock_outline : Icons.tag, size: size * 0.5, color: cs.onSecondaryContainer),
        ),
      ),
    );
  }
}
