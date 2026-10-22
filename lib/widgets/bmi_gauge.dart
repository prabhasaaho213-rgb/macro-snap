import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/bmi.dart';

/// The 270° segmented ring from the calculator: one arc per BMI band, in band
/// colours, with a white marker at the score. Drawn rather than built from
/// widgets so the arcs meet exactly and the marker can sit ON the ring.
class BmiGauge extends StatelessWidget {
  const BmiGauge({
    super.key,
    required this.bmi,
    this.size = 240,
    this.strokeWidth = 18,
    this.child,
    this.animate = true,
  });

  final double bmi;
  final double size;
  final double strokeWidth;

  /// Centre content — usually the score and the "BMI" caption.
  final Widget? child;

  /// A short sweep-in on first build. Disabled in tests (and anywhere the
  /// caller wants the gauge static).
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final painter = _GaugePainter(bmi: bmi, strokeWidth: strokeWidth);
    final canvas = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (animate)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, reveal, _) => CustomPaint(
                size: Size(size, size),
                painter: _GaugePainter(
                  bmi: bmi,
                  strokeWidth: strokeWidth,
                  reveal: reveal,
                ),
              ),
            )
          else
            CustomPaint(size: Size(size, size), painter: painter),
          ?child,
        ],
      ),
    );
    return canvas;
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.bmi,
    required this.strokeWidth,
    this.reveal = 1,
  });

  final double bmi;
  final double strokeWidth;
  final double reveal;

  /// Starts bottom-left and sweeps clockwise, leaving a 90° gap at the bottom
  /// the way the reference design does.
  static const double _start = math.pi * 0.75;
  static const double _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final visibleTo = _start + _sweep * reveal;

    for (final category in BmiCategory.values) {
      final from = BmiCalculator.gaugePosition(category.min);
      final to = BmiCalculator.gaugePosition(
        math.min(category.max, BmiCalculator.scaleMax),
      );
      if (to <= from) continue;

      var a0 = _start + _sweep * from;
      var a1 = _start + _sweep * to;

      // A hairline gap between bands so adjacent colours read as separate
      // zones; skipped when the band is too narrow to survive it.
      const gap = 0.018;
      if (a1 - a0 > gap * 3) {
        a0 += gap;
        a1 -= gap;
      }
      if (a0 >= visibleTo) continue;
      if (a1 > visibleTo) a1 = visibleTo;

      canvas.drawArc(rect, a0, a1 - a0, false, paint..color = category.color);
    }

    if (reveal <= 0) return;

    // Marker: white dot travelling along the ring to the score.
    final pos = BmiCalculator.gaugePosition(bmi);
    final angle = _start + _sweep * pos * reveal;
    final markerCentre = Offset(
      centre.dx + radius * math.cos(angle),
      centre.dy + radius * math.sin(angle),
    );
    final colour = BmiCalculator.categoryFor(bmi).color;

    canvas.drawCircle(
      markerCentre,
      strokeWidth * 0.62,
      Paint()
        ..color = colour.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      markerCentre,
      strokeWidth * 0.42,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.bmi != bmi || old.strokeWidth != strokeWidth || old.reveal != reveal;
}

/// A thin horizontal version of the same scale, for the compact Home card.
class BmiBandBar extends StatelessWidget {
  const BmiBandBar({super.key, required this.bmi, this.height = 8});

  final double bmi;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final pos = BmiCalculator.gaugePosition(bmi);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(height / 2),
                child: Row(
                  children: [
                    for (final category in BmiCategory.values)
                      _segment(category, width),
                  ],
                ),
              ),
              Positioned(
                left: (width * pos - height * 0.9).clamp(
                  0.0,
                  width - height * 1.8,
                ),
                top: -height * 0.4,
                child: Container(
                  width: height * 1.8,
                  height: height * 1.8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: BmiCalculator.categoryFor(bmi).color,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _segment(BmiCategory category, double width) {
    final from = BmiCalculator.gaugePosition(category.min);
    final to = BmiCalculator.gaugePosition(
      math.min(category.max, BmiCalculator.scaleMax),
    );
    final flex = ((to - from) * 1000).round();
    if (flex <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: flex,
      child: Container(color: category.color),
    );
  }
}
