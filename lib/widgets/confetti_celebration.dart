import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A full-screen confetti celebration overlay.
/// Shows colorful paper pieces flying up then falling with gravity.
/// Auto-dismisses after [duration]. Triggers haptic feedback on start.
///
/// Usage:
/// ```dart
/// ConfettiCelebration.show(context);
/// ```
class ConfettiCelebration extends StatefulWidget {
  final Duration duration;
  final int particleCount;

  const ConfettiCelebration({
    super.key,
    this.duration = const Duration(milliseconds: 2500),
    this.particleCount = 60,
  });

  /// Convenience method to show the celebration overlay.
  static Future<void> show(BuildContext context, {int particleCount = 60}) async {
    HapticFeedback.heavyImpact();
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: 'celebration',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => ConfettiCelebration(
        particleCount: particleCount,
      ),
    );
  }

  @override
  State<ConfettiCelebration> createState() => _ConfettiCelebrationState();
}

class _ConfettiCelebrationState extends State<ConfettiCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  final _random = Random();

  // Confetti palette — vibrant colors
  static const _colors = [
    Color(0xFFFF6B6B), // Red
    Color(0xFF4ECDC4), // Teal
    Color(0xFFFFE66D), // Yellow
    Color(0xFFA78BFA), // Purple
    Color(0xFF34D399), // Green
    Color(0xFFF472B6), // Pink
    Color(0xFF60A5FA), // Blue
    Color(0xFFFBBF24), // Orange
    Color(0xFF38BDF8), // Sky
    Color(0xFFFB923C), // Amber
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _particles = List.generate(widget.particleCount, (_) => _createParticle());

    _controller.forward().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  _Particle _createParticle() {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return _Particle(
      // Start from center-bottom area
      x: w * 0.3 + _random.nextDouble() * w * 0.4,
      y: h * 0.6 + _random.nextDouble() * h * 0.2,
      // Upward velocity with spread
      vx: (_random.nextDouble() - 0.5) * 8,
      vy: -(8 + _random.nextDouble() * 12),
      // Gravity pulls down
      gravity: 0.15 + _random.nextDouble() * 0.1,
      // Rotation
      rotation: _random.nextDouble() * 2 * pi,
      rotationSpeed: (_random.nextDouble() - 0.5) * 12,
      // Size
      size: 6 + _random.nextDouble() * 8,
      // Color
      color: _colors[_random.nextInt(_colors.length)],
      // Shape: 0 = square, 1 = circle, 2 = rectangle
      shape: _random.nextInt(3),
      // Opacity
      opacity: 0.8 + _random.nextDouble() * 0.2,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Stack(
          children: [
            // Semi-transparent backdrop
            Positioned.fill(
              child: GestureDetector(
                onTap: () {}, // Absorb taps
                child: Container(
                  color: Colors.black.withValues(alpha: 0.05),
                ),
              ),
            ),
            // Particles
            ...List.generate(_particles.length, (i) {
              final p = _particles[i];
              final currentX = p.x + p.vx * t * 60;
              final currentY = p.y + p.vy * t * 60 + 0.5 * p.gravity * (t * 60) * (t * 60);
              final currentRotation = p.rotation + p.rotationSpeed * t * 60;

              // Fade out in last 30%
              final fade = t > 0.7 ? (1.0 - (t - 0.7) / 0.3) : 1.0;

              // Scale down at the end
              final scale = t > 0.8 ? (1.0 - (t - 0.8) / 0.2 * 0.5) : 1.0;

              return Positioned(
                left: currentX - p.size / 2,
                top: currentY - p.size / 2,
                child: Transform.rotate(
                  angle: currentRotation,
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: p.opacity * fade,
                      child: _buildShape(p),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildShape(_Particle p) {
    switch (p.shape) {
      case 0: // Square
        return Container(
          width: p.size,
          height: p.size,
          decoration: BoxDecoration(
            color: p.color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      case 1: // Circle
        return Container(
          width: p.size,
          height: p.size,
          decoration: BoxDecoration(
            color: p.color,
            shape: BoxShape.circle,
          ),
        );
      case 2: // Rectangle (paper strip)
        return Container(
          width: p.size * 0.5,
          height: p.size * 1.5,
          decoration: BoxDecoration(
            color: p.color,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      default:
        return SizedBox(width: p.size, height: p.size);
    }
  }
}

class _Particle {
  final double x, y;
  final double vx, vy;
  final double gravity;
  final double rotation, rotationSpeed;
  final double size;
  final Color color;
  final int shape;
  final double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.gravity,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
    required this.color,
    required this.shape,
    required this.opacity,
  });
}
