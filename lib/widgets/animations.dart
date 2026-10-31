import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─── PAGE TRANSITIONS (Habit Flow style) ──────────────────────

/// A Hero-style page route that slides up with a spring curve,
/// mimicking the Habit Flow app feel.
Route<T> habitFlowRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, animation, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            ),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 300),
  );
}

/// A route that slides from the right (like a push nav).
Route<T> slideRightRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, animation, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.15, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            ),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
  );
}

// ─── SCALE ON PRESS (micro-interaction) ───────────────────────

/// Wraps a child widget and applies a subtle scale-down + shadow effect
/// on tap, mimicking the Habit Flow card press animation.
class ScaleOnPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleAmount;
  final Duration duration;

  const ScaleOnPress({
    super.key,
    required this.child,
    this.onTap,
    this.scaleAmount = 0.96,
    this.duration = const Duration(milliseconds: 120),
  });

  @override
  State<ScaleOnPress> createState() => _ScaleOnPressState();
}

class _ScaleOnPressState extends State<ScaleOnPress>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: widget.scaleAmount,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _controller.forward();
  void _onTapUp(_) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, child) {
        return Transform.scale(scale: _scaleAnim.value, child: child);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: widget.child,
      ),
    );
  }
}

class _StaggeredItem extends StatefulWidget {
  final int index;
  final Duration staggerDelay;
  final Widget child;

  const _StaggeredItem({
    required this.index,
    required this.staggerDelay,
    required this.child,
  });

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(widget.staggerDelay * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(opacity: _fadeAnim, child: widget.child),
    );
  }
}
class AnimatedValue extends StatefulWidget {
  final double target;
  final Widget Function(BuildContext context, double value) builder;
  final Duration duration;
  final Curve curve;

  const AnimatedValue({
    super.key,
    required this.target,
    required this.builder,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<AnimatedValue> createState() => _AnimatedValueState();
}

class _AnimatedValueState extends State<AnimatedValue>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;
  late double _from;
  late double _to;

  /// The value currently on screen (accounts for a mid-flight animation).
  double get _displayed => _from + _anim.value * (_to - _from);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _controller, curve: widget.curve);
    _from = 0;
    _to = widget.target;
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      // Resume from where the bar/ring currently is and glide to the new
      // target instead of restarting from zero (which read as a jump).
      _from = _displayed;
      _to = widget.target;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => widget.builder(context, _displayed),
    );
  }
}

/// A circular progress ring that fills up smoothly instead of jumping.
///
/// Renders the ring at its full [size] (so it never silently shrinks to
/// `CircularProgressIndicator`'s 36px default inside a loose-fit Stack) and
/// keeps the % label inside the stroke via padding + FittedBox. Both the ring
/// and the label are driven by the same animated value, so the percentage
/// counts up as the ring fills.
class AnimatedProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;
  final TextStyle? labelStyle;

  const AnimatedProgressRing({
    super.key,
    required this.value,
    this.size = 72,
    this.strokeWidth = 7,
    required this.color,
    required this.backgroundColor,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedValue(
      target: value.clamp(0.0, 1.0),
      builder: (context, v) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: strokeWidth,
                  backgroundColor: backgroundColor,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${(v * 100).round()}%', style: labelStyle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── ANIMATED ENTRANCE for any widget ─────────────────────────

/// Wraps any widget with a spring-entrance slide+fade animation.
class AnimatedEntrance extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final Offset? slideOffset;

  const AnimatedEntrance({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.slideOffset,
  });

  @override
  State<AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<AnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset = widget.slideOffset ?? const Offset(0, 0.04);
    return SlideTransition(
      position: Tween<Offset>(begin: offset, end: Offset.zero).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      ),
      child: FadeTransition(opacity: _controller, child: widget.child),
    );
  }
}

// ─── SHAKE WIDGET (for error feedback) ────────────────────────

class ShakeWidget extends StatefulWidget {
  final AnimationController controller;
  final Widget child;

  const ShakeWidget({super.key, required this.controller, required this.child});

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            math.sin(widget.controller.value * 4 * math.pi) * 6,
            0,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─── ANIMATED PROGRESS BAR ────────────────────────────────────

// ─── SKELETON SHIMMER LOADING ──────────────────────────────

/// Animated shimmer skeleton with a sweeping gradient.
/// Shows card-shaped placeholders while content is loading.
class ShimmerLoading extends StatefulWidget {
  final bool isLoading;
  final Widget child;
  final Duration duration;

  const ShimmerLoading({
    super.key,
    required this.isLoading,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) return widget.child;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Colors.transparent,
              Colors.transparent,
              Color(0x44FFFFFF),
              Color(0x88FFFFFF),
              Color(0x44FFFFFF),
              Colors.transparent,
              Colors.transparent,
            ],
            stops: [
              0.0,
              (_anim.value - 0.4).clamp(0.0, 1.0),
              (_anim.value - 0.2).clamp(0.0, 1.0),
              _anim.value.clamp(0.0, 1.0),
              (_anim.value + 0.2).clamp(0.0, 1.0),
              (_anim.value + 0.4).clamp(0.0, 1.0),
              1.0,
            ],
          ).createShader(bounds),
          child: widget.child,
        );
      },
    );
  }
}

/// A single skeleton placeholder rectangle/circle.
/// Used inside [ShimmerLoading] to create structured placeholders.
class SkeletonPlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final bool isCircle;

  const SkeletonPlaceholder({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 12,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}

// ─── ANIMATED PROGRESS BAR ────────────────────────────────────

/// A rounded progress bar that fills up smoothly and glides between value
/// changes (it never resets to zero mid-way). Pass [backgroundColor] to keep
/// a specific track color; otherwise a dark/light default is used.
class AnimatedProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final Color? backgroundColor;
  final double height;

  const AnimatedProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.backgroundColor,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedValue(
      target: value.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, v) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: LinearProgressIndicator(
            value: v,
            minHeight: height,
            backgroundColor:
                backgroundColor ??
                (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        );
      },
    );
  }
}
