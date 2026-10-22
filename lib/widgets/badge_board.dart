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
              Text(
                '$earned/$total',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: MacroSnapTheme.neonOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final badge in AppBadge.all)
            _BadgeRow(
              badge: badge,
              earned: BadgeService.instance.isEarned(badge.id),
            ),
        ],
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.badge, required this.earned});

  final AppBadge badge;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = MacroSnapTheme.neonOrange;
    final iconColor = earned
        ? accent
        : (isDark ? Colors.white30 : const Color(0xFFB0B0B0));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: earned
                  ? accent.withValues(alpha: 0.14)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF0F0F0)),
              border: earned ? Border.all(color: accent, width: 1.5) : null,
            ),
            child: Icon(
              earned ? badge.icon : Icons.lock_rounded,
              size: 19,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: earned
                        ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                        : (isDark ? Colors.white60 : const Color(0xFF8A8A8A)),
                  ),
                ),
                Text(
                  badge.description,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          if (earned)
            Icon(Icons.check_circle_rounded, size: 17, color: accent)
          else
            Icon(
              Icons.radio_button_unchecked_rounded,
              size: 17,
              color: MacroSnapTheme.textTertiary(context),
            ),
        ],
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

  @override
  void initState() {
    super.initState();
    BadgeService.instance.justEarned.addListener(_onEarned);
  }

  void _onEarned() {
    final badge = BadgeService.instance.justEarned.value;
    if (badge == null || !mounted) return;
    _show(badge);
  }

  void _show(AppBadge badge) {
    _entry?.remove();
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
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Transform.translate(
              offset: Offset(0, -40 * (1 - t)),
              child: Opacity(opacity: t, child: child),
            ),
            child: _BadgeToast(badge: badge),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (_entry == entry) {
        entry.remove();
        _entry = null;
        // Clear so re-earning (after a reset) can fire again.
        if (mounted) BadgeService.instance.justEarned.value = null;
      }
    });
  }

  @override
  void dispose() {
    BadgeService.instance.justEarned.removeListener(_onEarned);
    _entry?.remove();
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF17171D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: MacroSnapTheme.neonOrange.withValues(alpha: 0.5),
        ),
        boxShadow: [
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
