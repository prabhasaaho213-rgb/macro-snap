// lib/widgets/scan_animation.dart
//
// "Magic trick" scan animation for MacroSnap.
//
//  Phase 1 (labels == null): the photo drifts slowly under a vignette, corner
//                            brackets frame it and a glowing line sweeps top to
//                            bottom while the AI is analysing.
//  Phase 2 (labels != null): the sweep fades out and each detected dish pops
//                            onto the photo one by one with a haptic tick.
//
// The motion is modelled on the scan screens people already know:
//   • Google Lens — a soft gradient trail above a bright core line, sweeping one
//     direction and fading at the ends so the restart is never seen.
//   • Cal AI / SnapCalorie — the still photo keeps a very slow zoom, so the
//     frame feels alive instead of frozen, and chips land with a small overshoot
//     rather than a bouncy elastic pop.
//   • Apple Visual Look Up — a quiet vignette and thin brackets: the chrome stays
//     still so the sweep is the only thing moving.
//
// Everything that moves is drawn in ONE CustomPainter that repaints off the
// controller (no per-frame layout, no widget rebuilds), and the photo's zoom is
// a transform inside a RepaintBoundary. That is what keeps it smooth on a
// mid-range phone.
//
// NOTE: the backend does not return bounding boxes, so labels are placed at
// fixed spread-out spots on the photo, not on the exact food position.

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import 'scan_overlay.dart';

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

  /// Gap between two labels popping. Short enough to read as a cascade; the old
  /// 450 ms made the reveal feel stalled.
  static const Duration labelGap = Duration(milliseconds: 200);

  /// When the first chip appears, after the sweep has had a moment to land.
  static const Duration _firstLabelDelay = Duration(milliseconds: 320);

  /// How long one chip takes to arrive.
  static const Duration _popDuration = Duration(milliseconds: 360);

  /// How long the reveal needs. Wait this long after setting [labels] before
  /// switching to the results screen so the pops are not cut short.
  static Duration revealDuration(int dishCount) {
    final n = math.min(dishCount, maxLabels);
    return Duration(
      milliseconds:
          _firstLabelDelay.inMilliseconds +
          labelGap.inMilliseconds * n +
          _popDuration.inMilliseconds +
          420,
    );
  }

  @override
  State<ScanAnimationView> createState() => _ScanAnimationViewState();
}

class _ScanAnimationViewState extends State<ScanAnimationView>
    with TickerProviderStateMixin {
  /// One continuous top-to-bottom pass. It repeats (not reverse) and fades at
  /// both ends, so there is no visible bounce or jump at the wrap.
  late final AnimationController _sweep;

  /// A very slow zoom on the photo, so a still frame does not look like a
  /// screenshot. Small on purpose: 1.0 → 1.05 is felt, not noticed.
  late final AnimationController _drift;
  late final Animation<double> _driftScale;

  bool _reduceMotion = false;

  bool get _revealing => widget.labels != null;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    );
    _driftScale = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _drift, curve: Curves.easeInOutSine));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant ScanAnimationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_reduceMotion) {
      // Static, readable frame: no sweep, no zoom, no motion sickness.
      _sweep.stop();
      _sweep.value = 0.5;
      _drift.stop();
      _drift.value = 1.0;
      return;
    }
    if (_revealing) {
      // Let the current pass finish instead of snapping the line away; the
      // painter fades it out on its own.
      if (_sweep.isAnimating) _sweep.stop();
      if (_drift.isAnimating) _drift.stop();
      return;
    }
    if (!_sweep.isAnimating) _sweep.repeat();
    if (!_drift.isAnimating) _drift.repeat(reverse: true);
  }

  @override
  void dispose() {
    _sweep.dispose();
    _drift.dispose();
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
            // Slow drift, isolated in its own layer so the zoom never forces a
            // repaint of the painter above it.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _driftScale,
                builder: (context, child) =>
                    Transform.scale(scale: _driftScale.value, child: child),
                child: Image.file(
                  File(widget.imagePath),
                  fit: BoxFit.cover,
                  cacheWidth: 900,
                  errorBuilder: (_, _, _) => Container(color: Colors.black26),
                ),
              ),
            ),

            // A light dim that lifts once the dishes are found, so the chips
            // read against the photo without washing it out.
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              color: Colors.black.withValues(alpha: _revealing ? 0.10 : 0.24),
            ),

            // Vignette, sweep and brackets: one paint pass, repainting straight
            // off the controller.
            RepaintBoundary(
              child: CustomPaint(
                painter: ScanOverlayPainter(
                  sweep: _sweep,
                  color: accent,
                  revealing: _revealing,
                ),
              ),
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
                    milliseconds:
                        ScanAnimationView._firstLabelDelay.inMilliseconds +
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

// ─── Label chip: a short, confident landing (not a rubber-band bounce) ──

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
      duration: ScanAnimationView._popDuration,
    );
    // easeOutBack lands with a few pixels of overshoot — the same feel as the
    // chips in Cal AI — where elasticOut wobbled for half a second.
    _scale = Tween<double>(
      begin: 0.86,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // A few pixels of rise on arrival, tied to the fade.
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - _fade.value)),
            child: Transform.scale(scale: _scale.value, child: child),
          ),
        );
      },
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
    );
  }
}
