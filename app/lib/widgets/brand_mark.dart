import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Chatter's mark: an amber speech bubble carrying three linked phones, a
/// message crossing the mesh. The launcher icons are rendered from this same
/// painter (see tool/render_icons_test.dart), so the two never drift.
class BrandMarkPainter extends CustomPainter {
  final Color bubble;
  final Color ink;

  /// Cuts the network out of the bubble instead of drawing it in [ink], for
  /// single-colour uses such as Android's themed icons.
  final bool knockout;

  /// Heavier nodes and links that survive being drawn at 16–48 pixels.
  final bool small;

  const BrandMarkPainter({
    this.bubble = AppTheme.ember,
    this.ink = AppTheme.onEmber,
    this.knockout = false,
    this.small = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final origin = Offset((size.width - s) / 2, (size.height - s) / 2);
    Offset p(double x, double y) => origin + Offset(x * s, y * s);

    if (knockout) canvas.saveLayer(origin & Size.square(s), Paint());

    // Bubble body with a tail at the lower left
    final body = RRect.fromRectAndRadius(
      Rect.fromPoints(p(0.06, 0.10), p(0.94, 0.76)),
      Radius.circular(s * 0.20),
    );
    final tail = Path()
      ..moveTo(p(0.20, 0.66).dx, p(0.20, 0.66).dy)
      ..lineTo(p(0.16, 0.92).dx, p(0.16, 0.92).dy)
      ..lineTo(p(0.44, 0.74).dx, p(0.44, 0.74).dy)
      ..close();
    final fill = Paint()
      ..color = bubble
      ..isAntiAlias = true;
    canvas.drawPath(Path.combine(PathOperation.union, Path()..addRRect(body), tail), fill);

    // Three nodes, every one linked to the others
    final nodes = [p(0.30, 0.57), p(0.70, 0.57), p(0.50, 0.27)];
    final link = Paint()
      ..color = ink
      ..strokeWidth = s * (small ? 0.075 : 0.05)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final dot = Paint()
      ..color = ink
      ..isAntiAlias = true;
    if (knockout) {
      link.blendMode = BlendMode.clear;
      dot.blendMode = BlendMode.clear;
    }
    for (var i = 0; i < nodes.length; i++) {
      canvas.drawLine(nodes[i], nodes[(i + 1) % nodes.length], link);
    }
    for (final n in nodes) {
      canvas.drawCircle(n, s * (small ? 0.105 : 0.085), dot);
    }

    if (knockout) canvas.restore();
  }

  @override
  bool shouldRepaint(BrandMarkPainter oldDelegate) =>
      oldDelegate.bubble != bubble ||
      oldDelegate.ink != ink ||
      oldDelegate.knockout != knockout ||
      oldDelegate.small != small;
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(size: Size.square(size), painter: const BrandMarkPainter()),
      );
}
