// lib/widgets/scan_overlay.dart
//
// The shared "scanning" chrome, used by BOTH scanners:
//   • the photo scan (widgets/scan_animation.dart)
//   • the barcode scan (screens/barcode_scan_screen.dart)
//
// One painter, one motion language:
//   • a Lens-style sweep: one direction, bright core line over a soft trail,
//     faded in at the top and out at the bottom so the restart is never seen;
//   • thin white brackets that breathe by a pixel or two;
//   • an optional vignette, so the photo scan's frame reads like a viewfinder
//     while a live camera preview stays untouched.
//
// Everything repaints off the controller (super(repaint: sweep)), so a frame is
// one paint pass: no widget rebuilds and no layout, which is what keeps the
// camera preview underneath smooth.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class ScanOverlayPainter extends CustomPainter {
  /// Drives the sweep. Usually a repeating 0 → 1 controller.
  final Animation<double> sweep;

  /// Accent colour of the trail and glow.
  final Color color;

  /// True once the scan has an answer: the sweep is not drawn.
  final bool revealing;

  /// Darken the edges. Off for a live camera preview, on for a still photo.
  final bool vignette;

  ScanOverlayPainter({
    required this.sweep,
    required this.color,
    this.revealing = false,
    this.vignette = true,
  }) : super(repaint: sweep);

  @override
  void paint(Canvas canvas, Size size) {
    if (vignette) {
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            radius: 0.95,
            colors: [Colors.transparent, Colors.black38],
            stops: [0.55, 1.0],
          ).createShader(rect),
      );
    }

    if (!revealing) _paintSweep(canvas, size);
    _paintBrackets(canvas, size);
  }

  void _paintSweep(Canvas canvas, Size size) {
    final raw = sweep.value.clamp(0.0, 1.0);

    // Fade in at the top and out at the bottom, so the repeat is invisible and
    // the eye never catches a line jumping back to the start.
    final fade = math.min(1.0, math.min(raw / 0.10, (1 - raw) / 0.10));
    if (fade <= 0) return;

    final t = Curves.easeInOutCubic.transform(raw);
    final y = size.height * (0.02 + 0.96 * t);

    // Trail: the light it leaves behind, strongest just above the line.
    final bandHeight = math.min(92.0, size.height * 0.4);
    final band = Rect.fromLTRB(0, y - bandHeight, size.width, y);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.10 * fade),
            color.withValues(alpha: 0.34 * fade),
          ],
        ).createShader(band),
    );

    // Glow under the core line.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color.withValues(alpha: 0.55 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // The line itself: thin, bright, white-hot in the middle.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.35 * fade),
            Colors.white.withValues(alpha: 0.95 * fade),
            Colors.white.withValues(alpha: 0.35 * fade),
          ],
        ).createShader(Rect.fromLTRB(0, y - 1, size.width, y + 1))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintBrackets(Canvas canvas, Size size) {
    // A barely-there breathe, so the frame is alive without drawing attention.
    final breathe = math.sin(sweep.value * math.pi * 2) * 1.5;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: revealing ? 0.95 : 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const inset = 14.0;
    const len = 26.0;
    final l = inset + breathe;
    final t = inset + breathe;
    final r = size.width - inset - breathe;
    final b = size.height - inset - breathe;

    void corner(Offset a, Offset corner, Offset c) {
      canvas.drawLine(a, corner, paint);
      canvas.drawLine(corner, c, paint);
    }

    corner(Offset(l, t + len), Offset(l, t), Offset(l + len, t));
    corner(Offset(r - len, t), Offset(r, t), Offset(r, t + len));
    corner(Offset(l, b - len), Offset(l, b), Offset(l + len, b));
    corner(Offset(r - len, b), Offset(r, b), Offset(r, b - len));
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter old) =>
      old.revealing != revealing ||
      old.color != color ||
      old.vignette != vignette;
}
