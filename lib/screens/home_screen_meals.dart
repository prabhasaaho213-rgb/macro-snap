part of 'home_screen.dart';

// Split out of home_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _HomeMeals on _HomeScreenState {
  // ─── QUICK ACTIONS (Habitly style) ──────────────────────────
  Widget _buildQuickActions(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: MacroSnapTheme.habitlyCard(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            // Wrap, not Row: three actions must still fit a 320dp phone at 2x
            // system font without a RenderFlex overflow.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceAround,
              children: [
                _quickAction(
                  Icons.camera_alt_rounded,
                  'Snap',
                  MacroSnapTheme.neonGreen,
                  isDark,
                  () {
                    Navigator.push(
                      context,
                      habitFlowRoute(const ScanScreen()),
                    ).then((_) => _refresh());
                  },
                ),
                _quickAction(
                  Icons.qr_code_scanner_rounded,
                  'Barcode',
                  MacroSnapTheme.neonCyan,
                  isDark,
                  () {
                    Navigator.push(
                      context,
                      habitFlowRoute(const BarcodeScanScreen()),
                    );
                  },
                ),
                _quickAction(
                  Icons.auto_awesome_rounded,
                  'Diet',
                  MacroSnapTheme.neonPurple,
                  isDark,
                  () async {
                    await DietPlanService.instance.load();
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        habitFlowRoute(const DietPlanScreen()),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Uniform tile width for the Quick Actions row. Narrow enough that five
  /// tiles fit a 320dp phone (the Wrap still wraps rather than overflowing if
  /// the system font is scaled up), wide enough for "Barcode" at 11sp.
  static const double _quickActionWidth = 72;

  Widget _quickAction(
    IconData icon,
    String label,
    Color color,
    bool isDark,
    VoidCallback onTap,
  ) {
    // Fixed width, not intrinsic: sizing the tile to its label made every
    // action a different width ("Snap" narrow) with the icon
    // floating in a skinny pill and the label spilling past the tile edges —
    // which is what made the row look broken. Every tile is now identical and
    // the label ellipsises instead of overflowing.
    return ScaleOnPress(
      // Tap feedback for every quick action (Snap, Barcode, Diet, ...).
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      scaleAmount: 0.93,
      child: Container(
        width: _quickActionWidth,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MacroSnapTheme.textPrimaryMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TODAY'S MISSION (Meals as Habitly-style missions) ──────
  Widget _buildRecentMeals(BuildContext context, bool isDark) {
    final meals = MealStore.instance.todayMeals;
    if (meals.isEmpty) return _buildNoMealsYet(isDark);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Today's Meals",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: MacroSnapTheme.neonPill(MacroSnapTheme.neonGreen),
                child: Text(
                  '${meals.fold(0, (s, m) => s + m.calories)} kcal',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: MacroSnapTheme.greenText(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...meals.take(5).map((m) => _buildMissionMealCard(m, isDark)),
        ],
      ),
    );
  }

  /// What Home shows before anything is logged today. Returning an empty box
  /// here used to leave a new user with no obvious next step at 8 a.m.; this
  /// card names the one action that matters and opens the scanner.
  Widget _buildNoMealsYet(bool isDark) {
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: MacroSnapTheme.habitlyCard(context),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: MacroSnapTheme.emojiContainer(
                MacroSnapTheme.neonGreen,
              ),
              child: const Center(
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: MacroSnapTheme.neonGreen,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing logged yet today',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: titleColour,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Point the camera at your plate — calories and macros land here '
              'in a few seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Habitly-style mission card with emoji + check button.
  /// Tapping the card opens the same meal-info view shown right after a scan
  /// (read-only detail of the logged nutrition); the bolt button deletes.
  Widget _buildMissionMealCard(MealRecord m, bool isDark) {
    final color = _mealIcon(m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          habitFlowRoute(ResultScreen(imagePath: '', existingMeal: m)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: MacroSnapTheme.habitlyCard(context),
          child: Row(
            children: [
              // The photo this meal was scanned from, for the day it is kept;
              // the meal-type icon for everything else (manual entries, older
              // meals, and any photo past its 24 hours).
              MealPhoto(meal: m, size: 52, fallback: _mealIconTile(m, color)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          color: MacroSnapTheme.neonPink,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${m.calories} kcal',
                          style: TextStyle(
                            color: MacroSnapTheme.textSecondary(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (m.serving.isNotEmpty)
                          Flexible(
                            child: Text(
                              ' · ${m.serving}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: MacroSnapTheme.textTertiary(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Check button (Habitly style)
              GestureDetector(
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: isDark
                          ? MacroSnapTheme.cardDark
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      title: const Text(
                        'Delete Meal',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      content: Text('Remove "${m.name}" from your log?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: MacroSnapTheme.neonPink,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    // Keep the record so the delete can be taken back: a
                    // mis-tapped meal used to be gone for good.
                    final removed = m;
                    // Not awaited: the card must leave immediately, and a slow
                    // disk write should never hold the UI (or the snackbar).
                    unawaited(MealStore.instance.remove(m.id));
                    _refresh();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Removed ${removed.name}'),
                        behavior: SnackBarBehavior.floating,
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () =>
                              unawaited(MealStore.instance.add(removed)),
                        ),
                      ),
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 27,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The 52 dp meal-type tile, drawn when there is no live photo.
  Widget _mealIconTile(MealRecord m, Color color) {
    return Container(
      width: 52,
      height: 52,
      decoration: MacroSnapTheme.emojiContainer(color),
      child: Center(child: Icon(_mealIconData(m), color: color, size: 25)),
    );
  }

  Color _mealIcon(MealRecord m) {
    final h = m.date.hour;
    if (h >= 5 && h < 11) return MacroSnapTheme.macroCalories;
    if (h >= 11 && h < 15) return MacroSnapTheme.neonGreen;
    if (h >= 17 && h < 22) return MacroSnapTheme.macroFats;
    return MacroSnapTheme.macroProtein;
  }

  IconData _mealIconData(MealRecord m) {
    final h = m.date.hour;
    if (h >= 5 && h < 11) return Icons.wb_sunny_rounded;
    if (h >= 11 && h < 15) return Icons.restaurant_rounded;
    if (h >= 17 && h < 22) return Icons.nights_stay_rounded;
    return Icons.cookie_rounded;
  }
}
