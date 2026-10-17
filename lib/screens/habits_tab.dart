import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/habit.dart';
import '../services/habit_store.dart';
import '../services/subscription_service.dart';
import '../widgets/animations.dart';
import '../widgets/consistency_map.dart';
import '../widgets/gradient_button.dart';
import '../widgets/confetti_celebration.dart';
import '../widgets/streak_flame.dart';
import 'settings_screen.dart';
import 'subscription_screen.dart';

class HabitsTab extends StatefulWidget {
  const HabitsTab({super.key});

  @override
  State<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends State<HabitsTab> {
  HabitStore get store => HabitStore.instance;
  bool _subscribed = false;
  bool _isAdmin = false;
  bool _previousAllDone = false; // Track to detect transition to all-complete
  bool _celebrationBaselineSet = false; // First build must not celebrate

  /// True when this user can create unlimited habits: the owner/admin account
  /// is always exempt (lifetime Pro) even before [SubscriptionService.load]
  /// finishes, and paying subscribers are exempt too.
  bool get _unlimitedHabits => _subscribed || _isAdmin;

  @override
  void initState() {
    super.initState();
    store.addListener(_onChanged);
    _checkSub();
  }

  Future<void> _checkSub() async {
    // Resolve the admin flag FIRST (pure prefs read — instant) and store it on
    // the field immediately, so the owner is never gated even during the async
    // subscription-state load that follows (a defensive guard on top of
    // SubscriptionService.load() already granting admins lifetime Pro).
    _isAdmin = await SubscriptionService.instance.isAdmin();
    await SubscriptionService.instance.load();
    if (mounted) {
      setState(() {
        _subscribed = SubscriptionService.instance.isSubscribed;
      });
    }
  }

  @override
  void dispose() {
    store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      _checkSub();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final today = DateTime.now();
    final active = store.todayHabits;
    final completed = store.todayCompleted;
    final hasHabits = store.habits.isNotEmpty;
    final progress = active.isEmpty ? 0.0 : completed / active.length;
    final waterProgress = store.waterGoal > 0
        ? (store.waterToday / store.waterGoal).clamp(0.0, 1.0)
        : 0.0;

    // 🎉 Detect: all missions JUST completed → confetti celebration.
    // The tab's State is recreated on every visit, so the very first build
    // only records the baseline — a day that was already complete must never
    // replay the celebration when the user switches back to this tab.
    final allDone = active.isNotEmpty && completed >= active.length;
    if (!_celebrationBaselineSet) {
      _celebrationBaselineSet = true;
      _previousAllDone = allDone;
    } else if (allDone && !_previousAllDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ConfettiCelebration.show(context);
      });
      _previousAllDone = true;
    } else {
      _previousAllDone = allDone;
    }

    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      body: SafeArea(
        child: RefreshIndicator(
          color: MacroSnapTheme.neonGreen,
          backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
          onRefresh: () async {
            await store.load();
            await _checkSub();
            if (mounted) setState(() {});
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 120),
            children: [
              // Title row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Habits',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Explicit bright colour: inheriting the ListView's
                      // default style rendered the heading grey-on-grey.
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (hasHabits) ...[
                        _coinPill(isDark),
                        const SizedBox(width: 8),
                      ],
                      IconButton(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          habitFlowRoute(const SettingsScreen()),
                        ),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white10
                                : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.settings_rounded,
                            color: MacroSnapTheme.textTertiary(context),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${weekdayLabel(DateTime.now().weekday)}, ${_monthDay(today)}',
                style: TextStyle(
                  color: MacroSnapTheme.textSecondary(context),
                  fontSize: 14,
                ),
              ),

              // ─── ─── NO HABITS YET ─── SHOW INLINE CREATE ─────
              if (!hasHabits) ...[
                const SizedBox(height: 40),
                _emptyState(isDark),
                const SizedBox(height: 24),
                _createButton(context),
              ]
              // ─── ─── HAS HABITS ─── FULL LAYOUT ──────────────
              else ...[
                const SizedBox(height: 14),

                // ─── 1. Make It Count (Hero Card) ──────────────
                AnimatedEntrance(
                  delayMs: 0,
                  child: _heroCard(progress, completed, active.length, isDark),
                ),
                const SizedBox(height: 18),

                // ─── 2. Today's Missions ────────────────────────
                AnimatedEntrance(
                  delayMs: 50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              "Today's Missions",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                          Text(
                            '$completed/${active.length}',
                            style: TextStyle(
                              color: MacroSnapTheme.greenText(context),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (active.isEmpty)
                        _emptyState(isDark)
                      else
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          // The default drag proxy wraps the dragged card in
                          // an elevated Material whose RECTANGULAR shadow
                          // ignores the card's rounded corners (the grey box
                          // that visually cuts into the card above). Replace
                          // it with a transparent Material + a shadow that
                          // follows the card's own 28px radius.
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                return Material(
                                  type: MaterialType.transparency,
                                  elevation: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.22 * animation.value,
                                          ),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  ),
                                );
                              },
                            );
                          },
                          onReorderItem: (oldI, newI) {
                            Future.delayed(
                              const Duration(milliseconds: 350),
                              () {
                                final h = active[oldI];
                                final reordered = List<Habit>.from(active)
                                  ..removeAt(oldI)
                                  ..insert(newI, h);
                                final reorderedIds = reordered
                                    .map((x) => x.id)
                                    .toSet();
                                final merged = <Habit>[];
                                var vi = 0;
                                for (final habit in store.habits) {
                                  if (reorderedIds.contains(habit.id)) {
                                    merged.add(reordered[vi++]);
                                  } else {
                                    merged.add(habit);
                                  }
                                }
                                store.habits
                                  ..clear()
                                  ..addAll(merged);
                                store.save();
                              },
                            );
                          },
                          children: active.asMap().entries.map((entry) {
                            final i = entry.key;
                            final h = entry.value;
                            // No entrance animation after creating a habit — the
                            // KeyedSubtree keeps the unique key ReorderableListView
                            // requires on its direct children.
                            return KeyedSubtree(
                              key: ValueKey('habit_${h.id}'),
                              child: Material(
                                // Transparent so the framework's default
                                // rectangular Material background is never
                                // painted under the card during a drag.
                                type: MaterialType.transparency,
                                child: _missionCard(h, isDark, index: i),
                              ),
                            );
                          }).toList(),
                        ),

                      // ─── Habit Limit Indicator ───────────────────────
                      // Hidden for subscribers AND the admin (both unlimited).
                      if (!_unlimitedHabits && store.habits.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _habitLimitCard(isDark),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ─── 3. Create Habit Button ─────────────────────
                AnimatedEntrance(delayMs: 100, child: _createButton(context)),
                const SizedBox(height: 18),

                // ─── 4. Water Intake ────────────────────────────
                AnimatedEntrance(
                  delayMs: 150,
                  child: _waterCard(waterProgress, isDark),
                ),
                const SizedBox(height: 24),

                // ─── 5. Consistency Map ─────────────────────────
                AnimatedEntrance(
                  delayMs: 200,
                  child: _consistencyMapCard(isDark),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _createButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: () => _onCreateTap(context),
        icon: Icon(
          store.habitLimitReached && !_unlimitedHabits
              ? Icons.lock_rounded
              : Icons.add_rounded,
        ),
        label: Text(
          store.habitLimitReached && !_unlimitedHabits
              ? 'GO PRO FOR UNLIMITED'
              : 'CREATE HABIT',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: store.habitLimitReached && !_unlimitedHabits
              ? MacroSnapTheme.neonPurple
              : MacroSnapTheme.neonGreen,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  String _monthDay(DateTime d) {
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
    return '${months[d.month - 1]} ${d.day}';
  }

  // ─── COIN PILL ─────────────────────────────────────────────
  Widget _coinPill(bool isDark) {
    final coins = store.totalStreakPower;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF303030) : const Color(0xFFE8DEFF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: MacroSnapTheme.neonPink,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            '$coins',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  // ─── HERO CARD ─────────────────────────────────────────────
  Widget _heroCard(double progress, int completed, int total, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: MacroSnapTheme.habitlyHeroCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TODAY',
                      style: TextStyle(
                        color: isDark
                            ? Colors.white70
                            : MacroSnapTheme.textTertiary(context),
                        fontSize: 12,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Make it count.',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _progressRing(progress, isDark),
            ],
          ),
          const SizedBox(height: 22),
          // Animated fill — glides up as missions are completed.
          AnimatedProgressBar(
            value: progress,
            color: MacroSnapTheme.neonGreen,
            height: 10,
            backgroundColor: isDark ? Colors.white10 : const Color(0xFFE8DEFF),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? 'Create your first habit'
                      : '$completed of $total missions complete',
                  // Allow wrapping — single-line ellipsis hid the tail of the
                  // count on narrow screens ("4 of 4 mission…").
                  style: TextStyle(
                    color: isDark
                        ? Colors.white70
                        : MacroSnapTheme.textSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Streak display (NOT a celebration) — grows with best streak
                    StreakFlame(streak: store.totalStreakPower, fontSize: 15),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${store.totalStreakPower}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : MacroSnapTheme.textSecondary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressRing(double progress, bool isDark) {
    // Animated fill: ring + % count up on load and glide between values.
    // Track is white24 (not white10) to match the Home calorie ring — the
    // test suite treats the two hero rings as sharing one track color, and
    // white10 left an unreadable ring at 0% progress.
    return AnimatedProgressRing(
      value: progress,
      color: MacroSnapTheme.neonPink,
      backgroundColor: isDark ? Colors.white24 : const Color(0xFFE8DEFF),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w900,
        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
        fontSize: 16,
      ),
    );
  }

  // ─── WATER TRACKER ─────────────────────────────────────────
  Widget _waterCard(double progress, bool isDark) {
    final glasses = store.waterToday;
    final goal = store.waterGoal;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('💧', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Text(
                    'Water Intake',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              Text(
                '$glasses / $goal',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MacroSnapTheme.neonCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Water glass icons
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(goal, (i) {
              final filled = i < glasses;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (filled) {
                    store.removeWater();
                  } else {
                    store.addWater();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: filled
                        ? MacroSnapTheme.neonCyan.withValues(alpha: 0.2)
                        : (isDark
                              ? const Color(0xFF303030)
                              : const Color(0xFFE8DEFF)),
                    borderRadius: BorderRadius.circular(10),
                    border: filled
                        ? Border.all(
                            color: MacroSnapTheme.neonCyan.withValues(
                              alpha: 0.4,
                            ),
                          )
                        : null,
                  ),
                  child: Icon(
                    filled
                        ? Icons.water_drop_rounded
                        : Icons.water_drop_outlined,
                    color: filled
                        ? MacroSnapTheme.neonCyan
                        : (MacroSnapTheme.textQuaternary(context)),
                    size: 18,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),

          // Progress bar (animated fill)
          AnimatedProgressBar(
            value: progress,
            color: MacroSnapTheme.neonCyan,
            height: 6,
            backgroundColor: isDark
                ? const Color(0xFF303030)
                : const Color(0xFFE8DEFF),
          ),
        ],
      ),
    );
  }

  // ─── SWIPE BACKGROUND ──────────────────────────────────────
  Widget _swipeActionBackground({required bool rightSwipe}) {
    final color = rightSwipe
        ? MacroSnapTheme.neonGreen
        : MacroSnapTheme.neonOrange;
    final icon = rightSwipe ? Icons.check_circle_rounded : Icons.undo_rounded;
    final label = rightSwipe ? 'Complete' : 'Undo';
    return Container(
      decoration: BoxDecoration(
        color: color,
        // Full-bleed square: the outer ClipRRect(28) owns the tile's rounding.
        // A square reveal sits flush under the moving card's rounded corners
        // at every drag position, so the card's corner cutout always shows
        // reveal color — never a dark gap or the page background.
      ),
      alignment: rightSwipe ? Alignment.centerRight : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: rightSwipe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!rightSwipe) ...[
            Icon(icon, color: Colors.black, size: 28),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ] else ...[
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(width: 10),
            Icon(icon, color: Colors.black, size: 28),
          ],
        ],
      ),
    );
  }

  // ─── MISSION CARD ──────────────────────────────────────────
  Widget _missionCard(Habit h, bool isDark, {required int index}) {
    final done = h.isCompleted(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // Clip the whole swipe tile to the card's rounded shape: the reveal
      // background is drawn edge-to-edge behind the card, so without a clip
      // its square corners show past the card's rounded corners while
      // swiping. 28px matches habitlyCard()/habitlyHeroCard().
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        // Reveal stack, bottom to top:
        //  1. Base layer in the card's own base tone — Dismissible translates
        //     the foreground card over the static reveal background, and at
        //     sub-pixel slide offsets the two never quite butt up, so a
        //     hairline of the page background can bleed through the seam.
        //     This layer guarantees any such gap shows card-tone instead.
        //  2. Static rounded outline — the moving card no longer paints its
        //     own border (a border riding the moving edge showed as a
        //     lavender seam line mid-swipe); the outline stays at the tile's
        //     true edges so the at-rest look is unchanged.
        //  3. The Dismissible (reveal backgrounds + moving card).
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: isDark ? const Color(0xFF050508) : Colors.white,
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF353550)
                        : const Color(0xFFC8BEFF),
                  ),
                ),
              ),
            ),
            Dismissible(
              key: ValueKey('dismiss_${h.id}'),
              direction: DismissDirection.horizontal,
              background: _swipeActionBackground(rightSwipe: true),
              secondaryBackground: _swipeActionBackground(rightSwipe: false),
              confirmDismiss: (direction) async {
                HapticFeedback.mediumImpact();
                if (direction == DismissDirection.startToEnd) {
                  // Swipe right → COMPLETE today's task (explicit: swiping right
                  // again on an already-completed card stays completed, it never
                  // un-completes). IDEMPOTENT: guard the add — completedDates is a
                  // List, so an unguarded add stacks a duplicate of today per swipe,
                  // and each duplicate later needs its own left swipe to undo.
                  // Mutate NOW so the state is correct, but persist AFTER the
                  // Dismissible snaps back.
                  final key = dateKey(DateTime.now());
                  if (!h.completedDates.contains(key)) {
                    h.completedDates.add(key);
                  }
                  h.skippedDates.remove(key);
                } else {
                  // Swipe left → UN-COMPLETE today's task. This is NOT a streak
                  // reset: previous days' history and skipped marks stay intact.
                  // Remove EVERY occurrence of today (also flushes duplicate entries
                  // stacked by older builds) so ONE swipe always fully undoes,
                  // no matter how many times it was completed.
                  final key = dateKey(DateTime.now());
                  h.completedDates.removeWhere((k) => k == key);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${h.name} marked as not completed'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
                Future.delayed(const Duration(milliseconds: 350), () {
                  store.update(h, syncReminder: false);
                });
                return false; // Snap back — don't dismiss
              },
              // card on some GPUs while swiping, so the card itself renders as
              // plain widgets.
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  h.toggle(DateTime.now());
                  // Completion toggle only — the reminder schedule is unchanged,
                  // so skip the zonedSchedule cancel+recreate churn.
                  store.update(h, syncReminder: false);
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  _showHabitActions(context, h, isDark);
                },
            child: Container(
              padding: const EdgeInsets.all(16),
              // The MOVING card keeps its rounded corners so the swiping card
              // has soft edges (a flat rectangle reads as a glitch mid-swipe).
              // No border though — a card-painted border rode the moving edge
              // as a lavender seam line. The square reveal sits flush behind,
              // the base layer catches sub-pixel gaps, and the static outline
              // (in the Stack above) owns the at-rest border.
              decoration: MacroSnapTheme.habitlyCard(
                context,
                showBorder: false,
              ),
              child: Row(
                    children: [
                      // Emoji container. Its glow/blur shadow is the ONLY thing
                      // that smears during a swipe, so it gets its own
                      // RepaintBoundary right here — isolating this tile rather
                      // than the whole card (a whole-card raster layer rendered a
                      // black rectangle on some GPUs).
                      //
                      // NOTE: NOT wrapped in a ReorderableDragStartListener — that
                      // long-press recognizer competed with the Dismissible's
                      // horizontal drag on the same surface, so slow swipes got
                      // hijacked into reorder drags (the swipe glitch). Reordering
                      // is grip-only (see the drag-grip icon below).
                      RepaintBoundary(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: MacroSnapTheme.emojiContainer(h.color),
                          child: Center(
                            child: Text(
                              h.emoji,
                              style: MacroSnapTheme.emojiStyle(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: done
                                    ? (MacroSnapTheme.textTertiary(context))
                                    : (isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A1A)),
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
                                  '${h.currentStreak()} · ${h.frequency}',
                                  style: TextStyle(
                                    color: MacroSnapTheme.textSecondary(
                                      context,
                                    ),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Check/Bolt status indicator
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: done
                              ? MacroSnapTheme.neonGreen
                              : MacroSnapTheme.neonGreen.withValues(
                                  alpha: 0.12,
                                ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          done ? Icons.check_rounded : Icons.bolt_rounded,
                          color: done ? Colors.black : MacroSnapTheme.neonGreen,
                          size: 27,
                        ),
                      ),
                      // Drag grip icon
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: MacroSnapTheme.textQuaternary(context),
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HABIT ACTIONS (Edit, Reset Streak, or Delete) ─────────
  void _showHabitActions(BuildContext context, Habit h, bool isDark) {
    final streak = h.currentStreak();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
        decoration: BoxDecoration(
          color: isDark ? MacroSnapTheme.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.borderSubtle(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Habit info header
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: MacroSnapTheme.emojiContainer(h.color),
                  child: Center(
                    child: Text(h.emoji, style: MacroSnapTheme.emojiStyle()),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: MacroSnapTheme.neonPink,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$streak · ${h.frequency}',
                            style: TextStyle(
                              fontSize: 13,
                              color: MacroSnapTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Edit Habit
            _actionTile(
              icon: Icons.edit_rounded,
              iconColor: MacroSnapTheme.neonCyan,
              title: 'Edit Habit',
              subtitle: 'Change name, icon, schedule or reminder',
              isDark: isDark,
              onTap: () {
                Navigator.pop(ctx);
                _showCreateHabitSheet(context, existing: h);
              },
            ),
            const SizedBox(height: 8),

            // Reset Streak
            _actionTile(
              icon: Icons.refresh_rounded,
              iconColor: MacroSnapTheme.neonOrange,
              title: 'Reset Streak',
              subtitle: 'Clear all progress, keep the habit',
              isDark: isDark,
              onTap: () {
                Navigator.pop(ctx);
                h.completedDates.clear();
                h.skippedDates.clear();
                // Completion-state change only — the reminder schedule is
                // unchanged, so skip the zonedSchedule cancel+recreate churn
                // (consistent with the mission-card swipe/tap paths).
                store.update(h, syncReminder: false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Streak reset for ${h.name}'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            // Delete
            _actionTile(
              icon: Icons.delete_rounded,
              iconColor: MacroSnapTheme.neonPink,
              title: 'Delete Habit',
              subtitle: 'Remove this habit permanently',
              isDark: isDark,
              onTap: () async {
                Navigator.pop(ctx);
                await store.remove(h);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CONSISTENCY MAP CARD ─────────────────────────────────
  Widget _consistencyMapCard(bool isDark) {
    final active = store.habits.where((h) => !h.paused).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: MacroSnapTheme.neonGreen,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Consistency',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Text(
                '${active.length} habits',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (active.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Create habits to see your consistency map',
                  style: TextStyle(
                    fontSize: 13,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ),
            )
          else
            ConsistencyMap(
              habits: active,
              onCellTap: (date, count, names) =>
                  _showDayDetail(date, count, names),
            ),
        ],
      ),
    );
  }

  // ─── HABIT LIMIT CARD ─────────────────────────────────────
  Widget _habitLimitCard(bool isDark) {
    final used = store.habits.length;
    final limit = HabitStore.freeHabitLimit;
    final pct = (used / limit).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: used >= limit
                    ? MacroSnapTheme.neonOrange
                    : MacroSnapTheme.neonGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Habit Limit',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              Text(
                '$used / $limit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: used >= limit
                      ? MacroSnapTheme.neonOrange
                      : MacroSnapTheme.greenText(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedProgressBar(
            value: pct,
            height: 6,
            backgroundColor: isDark
                ? const Color(0xFF303030)
                : const Color(0xFFE8DEFF),
            color: used >= limit
                ? MacroSnapTheme.neonOrange
                : MacroSnapTheme.neonGreen,
          ),
          const SizedBox(height: 10),
          Text(
            used >= limit
                ? 'Upgrade to Pro for unlimited habits'
                : '${limit - used} habit${limit - used == 1 ? '' : 's'} remaining on Free',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MacroSnapTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CREATE TAP HANDLER ────────────────────────────────────
  void _onCreateTap(BuildContext context) {
    if (store.habitLimitReached && !_unlimitedHabits) {
      _showProUpsell(context);
    } else {
      _showCreateHabitSheet(context);
    }
  }

  // ─── DAY DETAIL BOTTOM SHEET ────────────────────────────
  void _showDayDetail(DateTime date, int count, List<String> habitNames) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final dayDate = DateTime(date.year, date.month, date.day);
    final todayDate = DateTime(now.year, now.month, now.day);

    String title;
    if (dayDate == todayDate) {
      title = 'Today';
    } else if (dayDate == todayDate.subtract(const Duration(days: 1))) {
      title = 'Yesterday';
    } else {
      title = _monthDay(date);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
        decoration: BoxDecoration(
          color: isDark ? MacroSnapTheme.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.borderSubtle(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.calendar_today_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        '$count/${habitNames.length} habits completed',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (habitNames.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      Text('😴', style: const TextStyle(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text(
                        'Nothing logged this day',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...habitNames.map(
                (name) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: MacroSnapTheme.neonGreen.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: MacroSnapTheme.neonGreen,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── PRO UPSELL ────────────────────────────────────────────
  void _showProUpsell(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: MacroSnapTheme.neonGreen,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Habit limit reached',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Free users get ${HabitStore.freeHabitLimit} habits.\nGo Pro for unlimited habits, AI scans & more.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: MacroSnapTheme.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              GradientButton(
                // Short label so the CTA reads fully on narrow screens.
                label: 'GO PRO ₹29/mo',
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen(),
                    ),
                  );
                },
                height: 48,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    fontSize: 14,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── EMPTY STATE ───────────────────────────────────────────
  Widget _emptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '✨',
            style: TextStyle(
              fontSize: 40,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Start your rhythm',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'No missions scheduled for today. Tap above to create one!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CREATE / EDIT HABIT SHEET ─────────────────────────────
  /// Opens the habit form. Pass [existing] to edit an existing habit.
  Future<void> _showCreateHabitSheet(
    BuildContext context, {
    Habit? existing,
  }) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var emoji = existing?.emoji ?? '✨';
    var frequency = existing?.frequency ?? 'Daily';
    var color = existing?.colorValue ?? Habit.defaultColorValue;
    var weeklyDay = existing?.weeklyDay ?? DateTime.now().weekday;
    var reminderEnabled = existing?.reminderEnabled ?? false;
    var reminderHour = existing?.reminderHour ?? 20;
    var reminderMinute = existing?.reminderMinute ?? 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Edit mission' : 'Create a mission',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: nameCtrl,
                  autofocus: !isEdit,
                  decoration: InputDecoration(
                    hintText: 'What do you want to build?',
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      'Choose an icon',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    // Live preview of the currently selected emoji
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        emoji,
                        style: MacroSnapTheme.emojiStyle(fontSize: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...[
                      '✨',
                      '💧',
                      '📚',
                      '🏃',
                      '🧘',
                      '🎸',
                      '🍎',
                      '💻',
                      '🎯',
                      '😴',
                      '🧠',
                      '☕',
                    ].map(
                      (e) => ChoiceChip(
                        // Flat style — no drop shadow under the glyph, which
                        // previously rendered as a ghost reflection on the chip.
                        label: Text(e, style: const TextStyle(fontSize: 20)),
                        selected: emoji == e,
                        onSelected: (_) => setModalState(() => emoji = e),
                      ),
                    ),
                    // Paste an emoji copied from anywhere (messages, web, etc.)
                    ActionChip(
                      avatar: const Icon(
                        Icons.content_paste_rounded,
                        size: 16,
                        color: MacroSnapTheme.neonCyan,
                      ),
                      label: const Text(
                        'Paste',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: MacroSnapTheme.neonCyan.withValues(
                        alpha: 0.1,
                      ),
                      side: BorderSide(
                        color: MacroSnapTheme.neonCyan.withValues(alpha: 0.4),
                      ),
                      onPressed: () => _pasteEmojiFromClipboard(
                        context,
                        setModalState,
                        (v) => emoji = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Frequency',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: ['Daily', 'Weekdays', 'Weekly']
                      .map(
                        (e) => ChoiceChip(
                          label: Text(e),
                          selected: frequency == e,
                          onSelected: (_) => setModalState(() => frequency = e),
                        ),
                      )
                      .toList(),
                ),
                if (frequency == 'Weekly') ...{
                  const SizedBox(height: 14),
                  const Text(
                    'Weekly day',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: List.generate(7, (index) {
                      final wd = index + 1;
                      return ChoiceChip(
                        label: Text(weekdayLabel(wd)),
                        selected: weeklyDay == wd,
                        onSelected: (_) => setModalState(() => weeklyDay = wd),
                      );
                    }),
                  ),
                },
                const SizedBox(height: 18),
                const Text(
                  'Color',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children:
                      [
                            Habit.defaultColorValue,
                            0xFFFF007F,
                            0xFF6C3BFF,
                            0xFFFF9500,
                            0xFF34C759,
                            0xFF00B8D4,
                          ]
                          .map(
                            (value) => GestureDetector(
                              onTap: () => setModalState(() => color = value),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Color(value),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: color == value
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurface
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 18),

                // ─── Reminder toggle + time picker ───────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: MacroSnapTheme.neonGreen.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: MacroSnapTheme.neonGreen,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Daily reminder',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              reminderEnabled
                                  ? 'Every day at ${_formatTime(reminderHour, reminderMinute)}'
                                  : 'Get a nudge to complete this habit',
                              style: TextStyle(
                                fontSize: 12,
                                color: MacroSnapTheme.textTertiary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: reminderEnabled,
                        activeTrackColor: MacroSnapTheme.neonGreen,
                        onChanged: (v) =>
                            setModalState(() => reminderEnabled = v),
                      ),
                    ],
                  ),
                ),
                if (reminderEnabled) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: reminderHour,
                            minute: reminderMinute,
                          ),
                        );
                        if (picked != null) {
                          setModalState(() {
                            reminderHour = picked.hour;
                            reminderMinute = picked.minute;
                          });
                        }
                      },
                      icon: const Icon(Icons.access_time_rounded, size: 18),
                      label: Text(
                        'Remind me at ${_formatTime(reminderHour, reminderMinute)}',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: MacroSnapTheme.neonGreen,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      if (isEdit) {
                        existing
                          ..name = nameCtrl.text.trim()
                          ..emoji = emoji
                          ..colorValue = color
                          ..frequency = frequency
                          ..weeklyDay = weeklyDay
                          ..reminderEnabled = reminderEnabled
                          ..reminderHour = reminderHour
                          ..reminderMinute = reminderMinute;
                        await store.update(existing);
                      } else {
                        final habit = Habit(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          name: nameCtrl.text.trim(),
                          emoji: emoji,
                          colorValue: color,
                          frequency: frequency,
                          weeklyDay: weeklyDay,
                          reminderEnabled: reminderEnabled,
                          reminderHour: reminderHour,
                          reminderMinute: reminderMinute,
                        );
                        await store.add(habit);
                        if (context.mounted) Navigator.pop(context);
                        return;
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(
                      isEdit ? 'SAVE CHANGES' : 'CREATE MISSION',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
  }

  String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Reads the clipboard and applies the first emoji found to the picker.
  Future<void> _pasteEmojiFromClipboard(
    BuildContext sheetContext,
    StateSetter setModalState,
    ValueChanged<String> onEmoji,
  ) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      final emoji = _extractFirstEmoji(text);
      if (emoji == null) {
        if (sheetContext.mounted) {
          ScaffoldMessenger.of(sheetContext).showSnackBar(
            SnackBar(
              content: const Text(
                'No emoji found in clipboard. Copy one first!',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: MacroSnapTheme.neonOrange,
            ),
          );
        }
        return;
      }
      setModalState(() => onEmoji(emoji));
      HapticFeedback.lightImpact();
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(
            content: Text('Emoji pasted: $emoji'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: MacroSnapTheme.neonGreen,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(
            content: const Text('Could not read clipboard'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: MacroSnapTheme.neonPink,
          ),
        );
      }
    }
  }

  /// Extracts the first emoji (including multi-code-point emoji like flags
  /// or skin-tone sequences) from arbitrary clipboard text.
  static String? _extractFirstEmoji(String text) {
    if (text.isEmpty) return null;
    // The match must START on a real emoji glyph (excludes U+FE0F / U+200D,
    // which are invisible modifiers) and may then continue through ZWJ
    // sequences, variation selectors, and skin tones so flags/family emoji
    // and '👍🏻' style sequences paste as one unit.
    final re = RegExp(
      r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]'
      r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}]*',
      unicode: true,
    );
    final match = re.firstMatch(text);
    return match?.group(0);
  }
}
