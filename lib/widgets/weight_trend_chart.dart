import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/weight_store.dart';

/// A small sparkline of weigh-ins: straight segments between points, a soft
/// fill under the line and a dot on the latest reading.
///
/// Deliberately a painter rather than fl_chart — at 64–120 dp the axis labels
/// and grids of a charting package are noise, and this has no package cost.
class WeightTrendChart extends StatelessWidget {
  const WeightTrendChart({
    super.key,
    required this.points,
    this.height = 64,
    this.color,
    this.animate = true,
  });

  final List<WeightEntry> points;
  final double height;
  final Color? color;

  /// A short draw-in on first build. Disabled in tests.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    // Two points is the minimum for a line; one point has no direction yet.
    if (points.length < 2) return const SizedBox.shrink();

    final lineColor = color ?? MacroSnapTheme.neonCyan;

    Widget chart(double reveal) => CustomPaint(
      size: Size(double.infinity, height),
      painter: _SparkPainter(
        points: points,
        color: lineColor,
        reveal: reveal,
      ),
    );

    if (!animate) return chart(1);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, reveal, _) => chart(reveal),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({
    required this.points,
    required this.color,
    required this.reveal,
  });

  final List<WeightEntry> points;
  final Color color;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;

    final padY = size.height * 0.18;
    var minKg = points.first.kg;
    var maxKg = points.first.kg;
    for (final p in points) {
      if (p.kg < minKg) minKg = p.kg;
      if (p.kg > maxKg) maxKg = p.kg;
    }
    // A flat line at exactly min == max would divide by zero — give it half a
    // kilo of room so the line still sits mid-card.
    if (maxKg - minKg < 0.2) {
      minKg -= 0.5;
      maxKg += 0.5;
    }

    final firstMs = points.first.date.millisecondsSinceEpoch;
    final lastMs = points.last.date.millisecondsSinceEpoch;
    final spanMs = (lastMs - firstMs).toDouble();
    if (spanMs <= 0) return;

    Offset at(WeightEntry e) {
      final t = (e.date.millisecondsSinceEpoch - firstMs) / spanMs;
      final y =
          size.height -
          padY -
          ((e.kg - minKg) / (maxKg - minKg)) * (size.height - padY * 2);
      return Offset(t * size.width, y);
    }

    final line = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(at(points[i]).dx, at(points[i]).dy);
    }

    // Clip the draw-in instead of faking it with opacity: the line visibly
    // travels across the card.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * reveal, size.height));

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dot on the newest reading — the value the user is reading next to it.
    final last = at(points.last);
    canvas.drawCircle(last, 7, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(last, 4, Paint()..color = color);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.reveal != reveal ||
      old.color != color ||
      old.points.length != points.length ||
      (points.isNotEmpty &&
          old.points.isNotEmpty &&
          old.points.last != points.last);
}
