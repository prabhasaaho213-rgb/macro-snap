// lib/widgets/scan_animation.dart
//
// "Magic trick" scan animation for MacroSnap.
//
//  Phase 1 (labels == null): the photo is dimmed, corner brackets frame it and
//                            a glowing line sweeps up and down while the AI
//                            is analysing.
//  Phase 2 (labels != null): the sweep stops and each detected dish pops onto
//                            the photo one by one with a haptic tick.
//
// NOTE: the backend does not return bounding boxes, so labels are placed at
// fixed spread-out spots on the photo, not on the exact food position.

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

class ScanAnimationView extends StatefulWidget {
  final String imagePath;

  /// null while analysing. Set to the dish names once the AI has answered.
  final List<String>? labels;

  final double height;
  final double borderRadius;

  const ScanAnimationView({
    super.key,
    required this.imagePath,
    this.labels,
    this.height = 220,
    this.borderRadius = 24,
  });

  /// Max labels shown on the photo.
  static const int maxLabels = 5;

  /// Gap between two labels popping.
  static const Duration labelGap = Duration(milliseconds: 450);

  /// How long the reveal needs. Wait this long after setting [labels] before
  /// switching to the results screen so the pops are not cut short.
  static Duration revealDuration(int dishCount) {
    final n = math.min(dishCount, maxLabels);
    return Duration(milliseconds: 500 + labelGap.inMilliseconds * n + 700);
  }

  @override
  State<ScanAnimationView> createState() => _ScanAnimationViewState();
}

class _ScanAnimationViewState extends State<ScanAnimationView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  bool get _revealing => widget.labels != null;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSweep();
  }

  @override
  void didUpdateWidget(covariant ScanAnimationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSweep();
  }

  void _syncSweep() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_revealing || reduceMotion) {
      if (_sweep.isAnimating) _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  // Spread-out spots (Alignment x, y) for up to 5 labels.
  static const _spots = <Alignment>[
    Alignment(-0.55, -0.45),
    Alignment(0.55, -0.15),
    Alignment(-0.30, 0.25),
    Alignment(0.45, 0.55),
    Alignment(-0.60, 0.65),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = MacroSnapTheme.neonOrange;
    final labels = (widget.labels ?? const <String>[])
        .where((l) => l.trim().isNotEmpty)
        .take(ScanAnimationView.maxLabels)
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(widget.imagePath),
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (_, _, _) => Container(color: Colors.black26),
            ),

            // Dim the photo a little so the scan line and labels stand out.
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              color: Colors.black.withValues(alpha: _revealing ? 0.18 : 0.38),
            ),

            // Corner brackets.
            IgnorePointer(
              child: CustomPaint(
                painter: _BracketPainter(color: accent),
              ),
            ),

            // Sweeping scan line (only while analysing).
            if (!_revealing)
              AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_sweep.value);
                  return Align(
                    alignment: Alignment(0, -1 + 2 * t),
                    child: _ScanLine(color: accent),
                  );
                },
              ),

            // Dish labels popping one by one.
            for (var i = 0; i < labels.length; i++)
              Align(
                alignment: _spots[i % _spots.length],
                child: _PopLabel(
                  key: ValueKey('${labels[i]}_$i'),
                  text: labels[i],
                  color: accent,
                  delay: Duration(
                    milliseconds: 500 +
                        ScanAnimationView.labelGap.inMilliseconds * i,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Scan line with glow ───────────────────────────────────────────────

class _ScanLine extends StatelessWidget {
  final Color color;
  const _ScanLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.0),
              color.withValues(alpha: 0.28),
              color.withValues(alpha: 0.85),
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 2),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.6),
              blurRadius: 14,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Corner brackets ───────────────────────────────────────────────────

class _BracketPainter extends CustomPainter {
  final Color color;
  _BracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const inset = 14.0;
    const len = 26.0;
    final l = inset, t = inset, r = size.width - inset, b = size.height - inset;

    // top-left
    canvas.drawLine(Offset(l, t + len), Offset(l, t), p);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), p);
    // top-right
    canvas.drawLine(Offset(r - len, t), Offset(r, t), p);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), p);
    // bottom-left
    canvas.drawLine(Offset(l, b - len), Offset(l, b), p);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), p);
    // bottom-right
    canvas.drawLine(Offset(r - len, b), Offset(r, b), p);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), p);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter old) => old.color != color;
}

// ─── Label chip that pops in with a bounce ─────────────────────────────

class _PopLabel extends StatefulWidget {
  final String text;
  final Color color;
  final Duration delay;

  const _PopLabel({
    super.key,
    required this.text,
    required this.color,
    required this.delay,
  });

  @override
  State<_PopLabel> createState() => _PopLabelState();
}

class _PopLabelState extends State<_PopLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scale = CurvedAnimation(parent: _c, curve: Curves.elasticOut);
    _fade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      HapticFeedback.selectionClick();
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: widget.color, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.45),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
