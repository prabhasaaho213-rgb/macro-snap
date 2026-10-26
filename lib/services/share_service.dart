import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../models/diet_profile.dart';
import '../models/meal_record.dart';
import 'meal_store.dart';
import 'meal_streak_service.dart';

/// The last 7 days, as one card's worth of numbers.
///
/// Pure data, computed from the meal log — kept separate from the widget so
/// the numbers are unit-testable without a single pixel on screen.
class WeeklySummary {
  /// Days in the window with at least one logged meal (0–7).
  final int daysLogged;

  /// Mean calories per *logged* day. Per logged day, not per calendar day:
  /// averaging over unlogged days would quietly punish a missed day twice.
  final double avgCalories;

  /// Days where protein reached 90% of the target — the same rule the macro
  /// streak uses, so the card and the streak can never disagree.
  final int proteinHitDays;

  /// Current macro-target streak (today's streak if today qualifies).
  final int streakDays;

  /// The protein target the hits were measured against (g).
  final double proteinTarget;

  const WeeklySummary({
    required this.daysLogged,
    required this.avgCalories,
    required this.proteinHitDays,
    required this.streakDays,
    required this.proteinTarget,
  });

  /// Nothing logged in the window — there is no card to share.
  bool get hasData => daysLogged > 0;

  /// The window as "12–18 Oct" style label, ending today.
  String dateRange(DateTime now) {
    final start = DateTime(now.year, now.month, now.day - 6);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (start.month == now.month) {
      return '${start.day}–${now.day} ${months[now.month - 1]}';
    }
    return '${start.day} ${months[start.month - 1]}–'
        '${now.day} ${months[now.month - 1]}';
  }
}

/// The one install link every share points at.
///
/// Kept here rather than inline in each screen: the QR on the share card and
/// the caption text must resolve to the same listing, or a scanned code lands
/// on a dead page while the text link works.
const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.macrosnap.macro_snap';

class ShareService {
  /// Computes the last-[days] summary from [meals].
  ///
  /// [now] is injectable so the window edge (today, and "6 days ago") is
  /// deterministic in tests.
  static WeeklySummary computeWeekly({
    required List<MealRecord> meals,
    required int streakDays,
    required double proteinTarget,
    DateTime? now,
    int days = 7,
  }) {
    final nowDate = now ?? DateTime.now();
    final today = DateTime(nowDate.year, nowDate.month, nowDate.day);
    final cutoff = today.subtract(Duration(days: days - 1));

    var totalCalories = 0.0;
    final proteinByDay = <String, double>{};
    final loggedDays = <String>{};

    for (final meal in meals) {
      final day = DateTime(meal.date.year, meal.date.month, meal.date.day);
      if (day.isBefore(cutoff) || day.isAfter(today)) continue;
      final key = '${day.year}-${day.month}-${day.day}';
      loggedDays.add(key);
      totalCalories += meal.calories;
      proteinByDay[key] = (proteinByDay[key] ?? 0) + meal.protein;
    }

    // Same 90% rule as MealStreakService, so "protein goal hit" on this card
    // is exactly the streak's own definition of a hit.
    final threshold = proteinTarget * 0.9;
    final hitDays = proteinByDay.values.where((p) => p >= threshold).length;

    return WeeklySummary(
      daysLogged: loggedDays.length,
      avgCalories: loggedDays.isEmpty ? 0 : totalCalories / loggedDays.length,
      proteinHitDays: hitDays,
      streakDays: streakDays,
      proteinTarget: proteinTarget,
    );
  }

  static Future<WeeklySummary> _summaryFromStores() async {
    final streak = await MealStreakService.getCurrent();
    final profile = DietPlanService.instance.profile;
    return computeWeekly(
      meals: MealStore.instance.allMeals,
      streakDays: streak,
      proteinTarget: (profile?.targetProtein ?? 150).toDouble(),
    );
  }

  /// The text fallback, also used as the share caption beside the image.
  static String weekSummaryText(WeeklySummary s) {
    final range = s.dateRange(DateTime.now());
    return '''📊 MacroSnap Weekly Summary ($range)
━━━━━━━━━━━━━━━━━━
📅 ${s.daysLogged}/7 days logged
🔥 Streak: ${s.streakDays} ${s.streakDays == 1 ? 'day' : 'days'}
${s.daysLogged >= 6
        ? '⭐ Great consistency!'
        : s.daysLogged >= 4
        ? '👍 Good effort!'
        : '💪 Keep going!'}

🔥 Avg: ${s.avgCalories.toStringAsFixed(0)} kcal/day
💪 Protein goal hit: ${s.proteinHitDays}/7 days
━━━━━━━━━━━━━━━━━━
Track every meal with MacroSnap 🍽️
$kPlayStoreUrl''';
  }

  /// Renders the branded weekly card off-screen, captures it to a PNG in the
  /// temp dir and opens the share sheet with the image (plus the text summary
  /// as caption, so messaging apps that ignore images still get the numbers).
  ///
  /// Returns false when there is nothing to share (no meals this week) or the
  /// capture failed — the caller then falls back to [shareWeekSummary].
  static Future<bool> shareWeeklyCard(BuildContext context) async {
    final summary = await _summaryFromStores();
    if (!summary.hasData) return false;
    // The await above is a BuildContext gap: the caller may have popped.
    if (!context.mounted) return false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boundaryKey = GlobalKey();

    // The card is inserted into the root overlay far off-screen: laid out at
    // the real screen width (so the text wraps exactly as it would on device)
    // but never seen — only captured.
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: -4000,
              top: -4000,
              child: RepaintBoundary(
                key: boundaryKey,
                child: WeeklyShareCard(summary: summary, isDark: isDark),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    try {
      // Let the first frame lay out and the fonts paint before capturing.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return false;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return false;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/macrosnap_weekly_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles([
        XFile(file.path),
      ], text: weekSummaryText(summary));
      return true;
    } finally {
      entry.remove();
    }
  }

  /// Text-only share (used when there is no card: nothing logged, or the
  /// off-screen capture failed on an exotic device).
  static Future<bool> shareWeekSummary() async {
    final summary = await _summaryFromStores();
    if (!summary.hasData) return false;
    await Share.share(weekSummaryText(summary));
    return true;
  }
}

/// The branded share card: one glance — average calories, protein goal days,
/// streak and how many days were logged.
///
/// It ignores the app theme and always renders on the dark brand gradient:
/// the image leaves the app, and a mid-grey "light mode" card looks like a
/// screenshot of a bug, not a shareable moment.
class WeeklyShareCard extends StatelessWidget {
  const WeeklyShareCard({
    super.key,
    required this.summary,
    required this.isDark,
  });

  final WeeklySummary summary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final range = summary.dateRange(DateTime.now());
    return Container(
      width: MediaQuery.sizeOf(context).width,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12161C), Color(0xFF0C0F14)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: MacroSnapTheme.neonGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: MacroSnapTheme.accentGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Expanded, not a bare Column: the subtitle is as long as the
              // date range makes it, and on a 320 px card (or with large
              // system text) a fixed row would clip the wordmark edge.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MacroSnap',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Weekly Summary · $range',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _StatBlock(
                label: 'AVG / DAY',
                value: summary.avgCalories.toStringAsFixed(0),
                unit: 'kcal',
                color: MacroSnapTheme.neonOrange,
              ),
              const SizedBox(width: 14),
              _StatBlock(
                label: 'PROTEIN GOAL',
                value: '${summary.proteinHitDays}/7',
                unit: 'days hit',
                color: MacroSnapTheme.neonGreen,
              ),
              const SizedBox(width: 14),
              _StatBlock(
                label: 'STREAK',
                value: '${summary.streakDays}',
                unit: summary.streakDays == 1 ? 'day' : 'days',
                color: MacroSnapTheme.neonCyan,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '${summary.daysLogged} of 7 days logged',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(7, (i) {
              final lit = i < summary.daysLogged;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: lit
                      ? MacroSnapTheme.neonGreen.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.06),
                  border: lit
                      ? Border.all(color: MacroSnapTheme.neonGreen, width: 1.5)
                      : null,
                ),
                child: lit
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: MacroSnapTheme.neonGreen,
                      )
                    : null,
              );
            }),
          ),
          const SizedBox(height: 20),
          // The install path, as a QR. A URL printed on a shared image is
          // unreadable where the image usually ends up (a chat thread), so the
          // code is the part that actually converts.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Free on Google Play',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Scan to install MacroSnap',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: QrImageView(
                  data: kPlayStoreUrl,
                  version: QrVersions.auto,
                  size: 52,
                  semanticsLabel: 'MacroSnap on Google Play',
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF12161C),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF12161C),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              unit,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
