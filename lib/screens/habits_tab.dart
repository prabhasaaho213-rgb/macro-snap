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
import '../widgets/swipe_action_background.dart';

part 'habits_tab_cards.dart';
part 'habits_tab_mission.dart';
part 'habits_tab_sheets.dart';

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
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
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

  // ─── CREATE TAP HANDLER ────────────────────────────────────
  void _onCreateTap(BuildContext context) {
    if (store.habitLimitReached && !_unlimitedHabits) {
      _showProUpsell(context);
    } else {
      _showCreateHabitSheet(context);
    }
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
