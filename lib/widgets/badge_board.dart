import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/app_badge.dart';
import '../services/badge_service.dart';

/// The trophy case: every badge the app ships, earned ones lit, the rest shown
/// as locked-but-reachable.
///
/// Deliberately shows locked badges too — a board with only earned trophies
/// tells a new user nothing about what is possible, which is the whole point
/// of a starter set that is reachable in the first week.
class BadgeBoard extends StatefulWidget {
  const BadgeBoard({super.key});

  @override
  State<BadgeBoard> createState() => _BadgeBoardState();
}

class _BadgeBoardState extends State<BadgeBoard> {
  @override
  void initState() {
    super.initState();
    BadgeService.instance.addListener(_onChange);
    BadgeService.instance.load();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BadgeService.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final earned = BadgeService.instance.earnedCount;
    final total = AppBadge.all.length;
    final progress = total == 0 ? 0.0 : earned / total;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.military_tech_rounded,
                size: 18,
                color: MacroSnapTheme.neonOrange,
              ),
              const SizedBox(width: 8),
              Text(
                'ACHIEVEMENTS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                  color: isDark ? Colors.white70 : const Color(0xFF4A4A4A),
                ),
              ),
              const Spacer(),
              // Count-up: the fraction ticks up over the first second so the
              // board feels alive instead of a static "$earned/$total".
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: earned.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  final shown = value.round().clamp(0, earned).toInt();
                  return Text(
                    '$shown/$total',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: MacroSnapTheme.neonOrange,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFEEEEEE),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0, 1),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: MacroSnapTheme.accentGradient,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in AppBadge.all.asMap().entries)
            _BadgeRow(
              key: ValueKey(entry.value.id),
              badge: entry.value,
              earned: BadgeService.instance.isEarned(entry.value.id),
              index: entry.key,
            ),
        ],
      ),
    );
  }
}

/// One badge row. Handles its own entrance (staggered by [index]) and the
/// earned-state look: a glowing gradient medallion with a slow shine sweep,
/// versus the muted locked circle.
class _BadgeRow extends StatefulWidget {
  const _BadgeRow({
    super.key,
    required this.badge,
    required this.earned,
    required this.index,
  });

  final AppBadge badge;
  final bool earned;
  final int index;

  @override
  State<_BadgeRow> createState() => _BadgeRowState();
}

class _BadgeRowState extends State<_BadgeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _appear;

  @override
  void initState() {
    super.initState();
    // Stagger: each row waits 90 ms longer than the previous one, so the
    // board pops in top-to-bottom instead of as one block.
    final delay = (widget.index * 90) % 900;
    _entrance = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 420 + delay),
    );
    _appear = CurvedAnimation(
      parent: _entrance,
      curve: Interval(delay / (420 + delay), 1, curve: Curves.easeOutBack),
    );
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = MacroSnapTheme.neonOrange;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: AnimatedBuilder(
        animation: _appear,
        builder: (context, child) {
          final t = _appear.value.clamp(0.0, 1.0).toDouble();
          return Transform.translate(
            offset: Offset(24 * (1 - t), 0),
            child: Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.92 + 0.08 * t,
                child: child,
              ),
            ),
          );
        },
        child: Row(
          children: [
            _BadgeMedallion(badge: widget.badge, earned: widget.earned),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.badge.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: widget.earned
                          ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                          : (isDark ? Colors.white60 : const Color(0xFF8A8A8A)),
                    ),
                  ),
                  Text(
                    widget.badge.description,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: MacroSnapTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.earned)
              _EarnedCheck(accent: accent)
            else
              Icon(
                Icons.radio_button_unchecked_rounded,
                size: 17,
                color: MacroSnapTheme.textTertiary(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// The circular badge icon. Earned: orange gradient fill, glow halo and a
/// slow shine sweeping across; locked: flat recessed circle with a lock.
class _BadgeMedallion extends StatefulWidget {
  const _BadgeMedallion({required this.badge, required this.earned});

  final AppBadge badge;
  final bool earned;

  @override
  State<_BadgeMedallion> createState() => _BadgeMedallionState();
}

class _BadgeMedallionState extends State<_BadgeMedallion>
    with TickerProviderStateMixin {
  late final AnimationController _shine;
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    if (widget.earned) {
      _shine = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      )..repeat();
      _pop = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
        value: 1,
      );
    } else {
      _shine = AnimationController(vsync: this);
      _pop = AnimationController(vsync: this, value: 1);
    }
  }

  @override
  void didUpdateWidget(covariant _BadgeMedallion oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A badge earned while the board is open lights up with a bounce + shine.
    if (widget.earned && !oldWidget.earned) {
      _shakeNow();
    }
  }

  Future<void> _shakeNow() async {
    _shine.duration = const Duration(milliseconds: 2200);
    _pop
      ..value = 0
      ..forward(from: 0);
    _shine.forward(from: 0).then((_) {
      if (mounted) _shine.repeat();
    });
  }

  @override
  void dispose() {
    _shine.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = MacroSnapTheme.neonOrange;

    final circle = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: widget.earned
          ? BoxDecoration(
              shape: BoxShape.circle,
              gradient: MacroSnapTheme.accentGradient,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            )
          : BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF0F0F0),
            ),
      child: Icon(
        widget.earned ? widget.badge.icon : Icons.lock_rounded,
        size: 19,
        color: widget.earned ? Colors.black : (isDark ? Colors.white30 : const Color(0xFFB0B0B0)),
      ),
    );

    Widget result = circle;

    if (widget.earned) {
      result = Stack(
        clipBehavior: Clip.none,
        children: [
          // Sweeping highlight across the medallion.
          Positioned.fill(
            child: ClipOval(
              child: AnimatedBuilder(
                animation: _shine,
                builder: (context, _) {
                  final x = (-0.6 + 1.6 * _shine.value) * 38;
          return Transform.translate(
            offset: Offset(x.toDouble(), 0),
            child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.35, 0.5, 0.65],
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          circle,
        ],
      );
      result = AnimatedBuilder(
        animation: _pop,
        builder: (context, child) {
          final curve = Curves.elasticOut.transform(_pop.value.clamp(0.0, 1.0));
          return Transform.scale(scale: 0.6 + 0.4 * curve, child: child);
        },
        child: result,
      );
    }

    return SizedBox(width: 38, height: 38, child: Center(child: result));
  }
}

/// The trailing check mark on an earned row, with a soft pulsing glow so a
/// completed board feels rewarded rather than statically ticked.
class _EarnedCheck extends StatefulWidget {
  const _EarnedCheck({required this.accent});

  final Color accent;

  @override
  State<_EarnedCheck> createState() => _EarnedCheckState();
}

class _EarnedCheckState extends State<_EarnedCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
      value: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Icon(
        Icons.check_circle_rounded,
        size: 17,
        color: Color.lerp(
          widget.accent,
          widget.accent.withValues(alpha: 0.55),
          _pulse.value,
        ),
      ),
    );
  }
}

/// One-shot celebration banner: listens to [BadgeService.justEarned] and slides
/// in a toast whenever a new badge lands.
///
/// Mounted once, above the shell's content, so it can overlay any tab without
/// any screen having to care that achievements exist.
class BadgeCelebration extends StatefulWidget {
  const BadgeCelebration({super.key, required this.child});

  final Widget child;

  @override
  State<BadgeCelebration> createState() => _BadgeCelebrationState();
}

class _BadgeCelebrationState extends State<BadgeCelebration> {
  OverlayEntry? _entry;
  Timer? _timer;

  /// Badges waiting their turn. Two can land in the same tick (the tenth meal
  /// is both "First Bite" for a new account and "Ten Plates"), and the
  /// notifier only remembers the last value — so without a queue the first
  /// toast was silently replaced before it was ever read.
  final Queue<AppBadge> _pending = Queue<AppBadge>();

  @override
  void initState() {
    super.initState();
    BadgeService.instance.justEarned.addListener(_onEarned);
  }

  void _onEarned() {
    final badge = BadgeService.instance.justEarned.value;
    if (badge == null || !mounted) return;
    if (_pending.contains(badge)) return;
    _pending.add(badge);
    if (_entry == null) _showNext();
  }

  void _showNext() {
    if (!mounted) return;
    if (_pending.isEmpty) {
      BadgeService.instance.justEarned.value = null;
      return;
    }
    _show(_pending.removeFirst());
  }

  /// Removes the current toast and either shows the next one or clears the
  /// notifier so the same badge can be celebrated again after a reset.
  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
    _showNext();
  }

  void _show(AppBadge badge) {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.paddingOf(ctx).top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutBack,
            builder: (_, t, child) {
              // Scale-in with a little overshoot, plus the drop from above.
              final drop = -40.0 * (1 - Curves.easeOutCubic.transform(t.clamp(0.0, 1.0)));
              return Transform.translate(
                offset: Offset(0, drop),
                child: Transform.scale(
                  scale: Curves.elasticOut.transform(t.clamp(0.0, 1.0)) * 0.9 + 0.1,
                  child: Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              );
            },
            child: _BadgeToast(badge: badge),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    // A cancellable Timer, not Future.delayed: the delayed callback used to
    // survive dispose() and remove the overlay entry a SECOND time (dispose
    // removed it but left `_entry` set, so its own guard passed), which throws
    // on logout — the moment this widget is most likely to be torn down.
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  @override
  void dispose() {
    BadgeService.instance.justEarned.removeListener(_onEarned);
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
    _pending.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _BadgeToast extends StatelessWidget {
  const _BadgeToast({required this.badge});

  final AppBadge badge;

  @override
  Widget build(BuildContext context) {
    final accent = MacroSnapTheme.neonOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF17171D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 22,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: MacroSnapTheme.accentGradient,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Icon(badge.icon, size: 20, color: Colors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Badge unlocked · ${badge.title}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  badge.description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.emoji_events_rounded,
            size: 20,
            color: MacroSnapTheme.neonOrange,
          ),
        ],
      ),
    );
  }
}
