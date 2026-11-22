import 'dart:async';

import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme.dart';
import '../services/leaderboard_remote.dart';
import '../services/leaderboard_service.dart';
import '../widgets/animations.dart';
import '../widgets/glass_card.dart';

/// Fitness points — what the user earned this week, where those points came
/// from, and the leaderboard scopes they will rank in.
///
/// Opened only from Home's Quick Actions: this is a "how am I doing" page, not
/// a fifth tab, and it should not compete with Home, Scan, Habits or Health.
///
/// Points are computed by [LeaderboardService] from the app's own stores, so
/// the numbers here are never a separate copy that can drift from the meal log,
/// the habits, the water log, a weigh-in or the step count.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  LeaderboardService get _service => LeaderboardService.instance;

  /// Which board is on screen. District is the default because it is the one
  /// a user can plausibly top; the other two are a tap away.
  LeaderboardScope _scope = LeaderboardScope.district;
  LeaderboardBoard _board = LeaderboardBoard.empty;
  bool _loadingBoard = false;
  bool _publishing = false;

  /// A score change that landed while a write was in flight, so the newer total
  /// is not dropped.
  bool _pendingPublish = false;

  /// The live board listener and the debounce for republishing our own score.
  StreamSubscription<LeaderboardBoard>? _boardSub;
  Timer? _publishTimer;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _boardSub?.cancel();
    _publishTimer?.cancel();
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _schedulePublish();
  }

  /// Pushes a score change out shortly after it happens, so the board other
  /// people are watching moves while this page is open instead of waiting for
  /// the next visit. Debounced: three water glasses in a row are one write.
  void _schedulePublish() {
    if (!_service.optIn || !_service.hasLocation) return;
    _publishTimer?.cancel();
    _publishTimer = Timer(
      const Duration(milliseconds: 900),
      () => unawaited(_publish()),
    );
  }

  Future<void> _refresh() async {
    await _service.load();
    // Re-reads today from the stores: opening the page after a meal logged on
    // another tab must show that meal's points, not the ones from last open.
    await _service.sync();
    await _publish();
    await _listen();
  }

  /// Writes this week's score to the public boards, when the user has joined.
  ///
  /// Called on open, on pull-to-refresh and after joining — not on every
  /// change, because a Firestore write per water glass would be noise for a
  /// number that is read back on the next open anyway.
  Future<void> _publish() async {
    if (!_service.optIn || !_service.hasLocation) return;
    if (_publishing) {
      // Do not drop a change that arrived mid-write: run again when this one
      // finishes, so joining at 0 and then earning is never lost.
      _pendingPublish = true;
      return;
    }
    _publishing = true;
    try {
      do {
        _pendingPublish = false;
        await LeaderboardRemote.instance.publishIfJoined(
          points: _service.weekPoints,
        );
      } while (_pendingPublish);
    } finally {
      _publishing = false;
    }
  }

  /// (Re)subscribes the visible board. Called on open, on a scope change and
  /// after joining or moving.
  ///
  /// Browsing needs only a signed-in account: India is readable straight away,
  /// and the district/state boards once an area is set. Joining is what puts
  /// this user's own score on them.
  Future<void> _listen() async {
    await _boardSub?.cancel();
    _boardSub = null;
    final remote = LeaderboardRemote.instance;
    final canBrowse =
        remote.canJoin &&
        (_scope == LeaderboardScope.india || _service.hasLocation);
    if (!canBrowse) {
      if (!mounted) return;
      setState(() {
        _board = LeaderboardBoard.empty;
        _loadingBoard = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _loadingBoard = true);
    _boardSub = remote
        .watch(
          week: LeaderboardRemote.weekId(),
          scope: _scope,
          stateKey: _service.stateKey,
          districtKey: LeaderboardRemote.slug(_service.district ?? ''),
        )
        .listen((board) {
          if (!mounted) return;
          setState(() {
            _board = board;
            _loadingBoard = false;
          });
        });
  }

  Future<void> _openJoinSheet() async {
    unawaited(Haptics.light());
    final result = await showModalBottomSheet<_LeaderboardLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinSheet(
        initialStateKey: _service.stateKey,
        initialDistrict: _service.district,
      ),
    );
    if (result == null) return;
    await _service.setProfile(
      optIn: true,
      stateKey: result.stateKey,
      district: result.district,
    );
    await _publish();
    await _listen();
  }

  Future<void> _leave() async {
    final stateKey = _service.stateKey;
    final district = _service.district;
    final week = LeaderboardRemote.weekId();
    await _service.setProfile(optIn: false);

    if (stateKey != null && district != null) {
      // Every row this account put up this week: the current area's three, plus
      // any board remembered from before a move.
      final scopes = {
        ...LeaderboardRemote.boardsFor(
          stateKey: stateKey,
          district: district,
        ),
        ..._service.publishedScopes(week),
      }.toList();

      // Record the intent first. If the delete cannot reach Firestore (offline),
      // the next launch retries instead of silently leaving the user on the
      // board with their name and score still visible.
      await _service.setPendingLeave(week: week, scopes: scopes);
      final gone = await LeaderboardRemote.instance.removeScopes(
        week: week,
        scopes: scopes,
      );
      if (gone) {
        await _service.clearPendingLeave();
        await _service.clearPublished(week);
      }
    }
    await _listen();
  }

  void _selectScope(LeaderboardScope scope) {
    if (scope == _scope) return;
    unawaited(Haptics.light());
    setState(() {
      _scope = scope;
      _loadingBoard = true;
    });
    unawaited(_listen());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Leaderboard',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () {
              unawaited(Haptics.light());
              unawaited(_refresh());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: MacroSnapTheme.neonGreen,
        backgroundColor: isDark
            ? MacroSnapTheme.cardDark
            : MacroSnapTheme.surfaceLight,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            AnimatedEntrance(delayMs: 20, child: _buildHero(context, isDark)),
            const SizedBox(height: 14),
            AnimatedEntrance(delayMs: 70, child: _buildWeekStrip(context, isDark)),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 120,
              child: _buildBreakdown(context, isDark),
            ),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 170,
              child: _buildRankings(context, isDark),
            ),
            const SizedBox(height: 14),
            AnimatedEntrance(delayMs: 210, child: _buildRules(context, isDark)),
          ],
        ),
      ),
    );
  }

  /// This week's total, today's total and the active-day streak.
  Widget _buildHero(BuildContext context, bool isDark) {
    final week = _service.weekPoints;
    final today = _service.todayPoints;
    final streak = _service.activeStreak;
    final possible = LeaderboardService.dailyMax * 7;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: MacroSnapTheme.habitlyHeroCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'THIS WEEK',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (streak > 0)
                Text(
                  '$streak-day streak 🔥',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedValue(
                target: week.toDouble(),
                duration: const Duration(milliseconds: 700),
                builder: (context, v) => Text(
                  '${v.round()}',
                  style: const TextStyle(
                    fontSize: 52,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'pts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'of $possible possible this week',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: possible == 0 ? 0 : (week / possible).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.today_rounded,
                size: 15,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                '$today points today',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Monday..Sunday strip: which days paid, and how much.
  Widget _buildWeekStrip(BuildContext context, bool isDark) {
    final week = _service.currentWeek;
    final today = DateTime.now();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This week',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (:date, :points) in week)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: points.isEmpty
                              ? MacroSnapTheme.borderSubtle(
                                  context,
                                ).withValues(alpha: 0.35)
                              : MacroSnapTheme.neonGreen.withValues(
                                  alpha: 0.16,
                                ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _sameDay(date, today)
                                ? MacroSnapTheme.neonGreen
                                : Colors.transparent,
                            width: 1.4,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${points.total}',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                color: points.isEmpty
                                    ? MacroSnapTheme.textTertiary(context)
                                    : (isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A1A)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'pts',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                                color: MacroSnapTheme.textTertiary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _weekdayLetter(date.weekday),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: _sameDay(date, today)
                              ? MacroSnapTheme.neonGreen
                              : MacroSnapTheme.textTertiary(context),
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

  /// Where today's points came from, against each bucket's daily ceiling.
  Widget _buildBreakdown(BuildContext context, bool isDark) {
    final points = _service.dayPoints(DateTime.now());
    final rows = <({IconData icon, Color colour, String label, String hint, int value, int cap})>[
      (
        icon: Icons.directions_walk_rounded,
        colour: MacroSnapTheme.neonCyan,
        label: 'Movement',
        hint: 'Daily step goal reached',
        value: points.movement,
        cap: LeaderboardService.stepGoalDailyCap,
      ),
      (
        icon: Icons.restaurant_rounded,
        colour: MacroSnapTheme.neonPurple,
        label: 'Nutrition',
        hint: 'Meals logged + calorie goal',
        value: points.nutrition,
        cap: LeaderboardService.nutritionDailyCap,
      ),
      (
        icon: Icons.checklist_rounded,
        colour: MacroSnapTheme.neonGreen,
        label: 'Habits',
        hint: 'Completed habits',
        value: points.habits,
        cap: LeaderboardService.habitDailyCap,
      ),
      (
        icon: Icons.water_drop_rounded,
        colour: MacroSnapTheme.neonCyan,
        label: 'Hydration',
        hint: 'Water logged + daily goal',
        value: points.hydration,
        cap: LeaderboardService.hydrationDailyCap,
      ),
      (
        icon: Icons.monitor_weight_rounded,
        colour: MacroSnapTheme.neonOrange,
        label: 'Body',
        hint: 'A weigh-in',
        value: points.body,
        cap: LeaderboardService.weighInPoints,
      ),
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "Today's points",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              Text(
                '${points.total} / ${LeaderboardService.dailyMax}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final row in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: row.colour.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(row.icon, size: 17, color: row.colour),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              row.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                row.hint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: MacroSnapTheme.textTertiary(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: row.cap == 0
                                ? 0
                                : (row.value / row.cap).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: MacroSnapTheme.borderSubtle(
                              context,
                            ).withValues(alpha: 0.5),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              row.colour,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${row.value}/${row.cap}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: row.value >= row.cap
                          ? row.colour
                          : MacroSnapTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The weekly board: District / State / India, live from Firestore.
  ///
  /// Every number is read back from `leaderboard/{week}/scopes/{scope}/entries`
  /// through a listener, so a score posted on someone else's phone shows up
  /// here on its own — no pull-to-refresh, no polling timer, and no "refresh
  /// every second" cost (a listener is pushed to, it does not re-read).
  ///
  /// Reading a board only needs a signed-in account; joining is the separate
  /// step that puts *you* on it. That order matters: a new user can look at
  /// their district before deciding to share their own score.
  Widget _buildRankings(BuildContext context, bool isDark) {
    final remote = LeaderboardRemote.instance;
    final canJoin = remote.canJoin;
    final joined = _service.optIn && _service.hasLocation;
    final needsLocation =
        _scope != LeaderboardScope.india && !_service.hasLocation;
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtle = MacroSnapTheme.textTertiary(context);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fitness leaderboard',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: titleColour,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'MacroSnap community',
                          style: TextStyle(fontSize: 12.5, color: subtle),
                        ),
                        const SizedBox(width: 6),
                        if (joined)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: MacroSnapTheme.neonGreen.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _LiveDot(),
                                SizedBox(width: 4),
                                Text(
                                  'LIVE',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w900,
                                    color: MacroSnapTheme.neonGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.emoji_events_rounded,
                color: MacroSnapTheme.neonOrange,
                size: 26,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Scope tabs ────────────────────────────────────────────
          _buildScopeTabs(context, isDark, enabled: canJoin, subtle: subtle),

          if (!canJoin) ...[
            const SizedBox(height: 14),
            Text(
              'Sign in with Google to see the board and join it. Until then '
              'your points stay private on this phone.',
              style: TextStyle(fontSize: 12, height: 1.45, color: subtle),
            ),
          ] else if (needsLocation) ...[
            const SizedBox(height: 14),
            Text(
              _scope == LeaderboardScope.state
                  ? 'Choose your state to see how it is doing this week.'
                  : 'Choose your state and district to see your local board.',
              style: TextStyle(fontSize: 12, height: 1.45, color: subtle),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _openJoinSheet,
                style: FilledButton.styleFrom(
                  backgroundColor: MacroSnapTheme.neonOrange,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text(
                  'Choose my area',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            // Where this board is, and what it measures.
            Text(
              '${_scopePlace(context)} · Weekly ranking',
              style: TextStyle(fontSize: 11.5, color: subtle),
            ),
            const SizedBox(height: 10),

            if (_loadingBoard)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MacroSnapTheme.neonOrange,
                    ),
                  ),
                ),
              )
            else if (_board.error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonPink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _board.notDeployed
                      ? '${_board.error}\nDeploy them with: firebase deploy '
                            '--only firestore:rules'
                      : _board.error!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: MacroSnapTheme.neonPink,
                  ),
                ),
              )
            else if (_board.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  joined
                      ? 'Nobody has scored on this board this week yet. Your '
                            'entry goes up as soon as it loads.'
                      : 'Nobody has scored on this board this week yet — join '
                            'and this is the easiest #1 you will ever take.',
                  style: TextStyle(fontSize: 12, height: 1.45, color: subtle),
                ),
              )
            else
              for (var i = 0; i < _board.rows.length && i < 10; i++)
                _buildRankRow(
                  context,
                  isDark,
                  position: i + 1,
                  row: _board.rows[i],
                ),

            const Divider(height: 22),

            if (!joined) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _openJoinSheet,
                  style: FilledButton.styleFrom(
                    backgroundColor: MacroSnapTheme.neonOrange,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text(
                    _service.weekPoints > 0
                        ? 'Join with my ${_service.weekPoints} pts'
                        : 'Join with my district',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Only your name and weekly points are shared — never your '
                'meals, health data or contact details.',
                style: TextStyle(fontSize: 10.5, height: 1.4, color: subtle),
              ),
            ] else ...[
              // ── Your row ──────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your rank: ${_myRankLabel()}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: titleColour,
                      ),
                    ),
                  ),
                  Text(
                    '${_service.weekPoints} pts',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: titleColour,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scores are reported by the app and are not verified by '
                      'a server yet.',
                      style: TextStyle(fontSize: 10.5, color: subtle),
                    ),
                  ),
                  TextButton(
                    onPressed: _openJoinSheet,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: MacroSnapTheme.neonOrange,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _leave,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Leave',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: subtle,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Three equal tabs, the selected one filled. Taps are ignored when nobody
  /// is signed in, because there is no account to read a board with.
  Widget _buildScopeTabs(
    BuildContext context,
    bool isDark, {
    required bool enabled,
    required Color subtle,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MacroSnapTheme.borderSubtle(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final scope in LeaderboardScope.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled && scope != _scope
                    ? () => _selectScope(scope)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scope == _scope
                        ? (isDark
                              ? const Color(0xFF2E2E33)
                              : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    switch (scope) {
                      LeaderboardScope.district => 'District',
                      LeaderboardScope.state => 'State',
                      LeaderboardScope.india => 'India',
                    },
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: scope == _scope
                          ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                          : (enabled ? subtle : subtle.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRankRow(
    BuildContext context,
    bool isDark, {
    required int position,
    required LeaderboardRow row,
  }) {
    final colour = row.isMe
        ? MacroSnapTheme.neonGreen
        : (isDark ? Colors.white : const Color(0xFF1A1A1A));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$position. ${row.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: colour,
              ),
            ),
          ),
          if (row.isMe)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: MacroSnapTheme.neonGreen.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: MacroSnapTheme.neonGreen,
                ),
              ),
            ),
          Text(
            '${row.points} pts',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }

  /// "Pune · Maharashtra" style label for the current board.
  String _scopePlace(BuildContext context) {
    final district = _titleCase(_service.district ?? '');
    final state = LeaderboardRemote.stateName(_service.stateKey ?? '');
    return switch (_scope) {
      LeaderboardScope.district => district.isEmpty ? state : district,
      LeaderboardScope.state => state,
      LeaderboardScope.india => 'India',
    };
  }

  String _myRankLabel() {
    final rank = _board.myRank;
    if (rank == null) return '—';
    if (rank < 0) return '50+';
    return '#$rank';
  }

  static String _titleCase(String value) => value
      .split(RegExp(r'[\s-]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');

  /// What pays, how much, and how often — the same table the scoring code uses.
  Widget _buildRules(BuildContext context, bool isDark) {
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final rules = <({String label, String points, String limit})>[
      (label: 'Reach your step goal', points: '+20', limit: 'once a day'),
      (label: 'Log a meal', points: '+10', limit: 'up to 3 meals'),
      (label: 'Meet your calorie goal', points: '+10', limit: 'once a day'),
      (label: 'Complete a habit', points: '+5', limit: 'up to 3 habits'),
      (label: 'Record a weigh-in', points: '+5', limit: 'once a day'),
      (label: 'Reach your water goal', points: '+5', limit: 'once a day'),
      (label: 'Log a glass of water', points: '+1', limit: 'up to 5'),
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How points work',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: titleColour,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Points are for doing the habits, not for eating less or losing '
            'weight. Editing or deleting a logged action never pays twice.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
          const SizedBox(height: 8),
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rule.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xFF3A3A3A),
                      ),
                    ),
                  ),
                  Text(
                    rule.points,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: MacroSnapTheme.neonGreen,
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text(
                      rule.limit,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _weekdayLetter(int weekday) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// The pulsing dot next to LIVE — the board really is push-updated, and the
/// dot is the one bit of motion that says so.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_controller),
      child: Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: MacroSnapTheme.neonGreen,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// What the join sheet returns: the state to file under, and the district the
/// user typed.
class _LeaderboardLocation {
  final String stateKey;
  final String district;

  const _LeaderboardLocation({required this.stateKey, required this.district});
}

/// One-step join: state from a fixed list (so the same state is not spelled
/// five ways) plus a free-text district (India has thousands, and a stale
/// list would quietly drop people off their own board).
class _JoinSheet extends StatefulWidget {
  final String? initialStateKey;
  final String? initialDistrict;

  const _JoinSheet({this.initialStateKey, this.initialDistrict});

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  late String? _stateKey = widget.initialStateKey;
  late final TextEditingController _district = TextEditingController(
    text: widget.initialDistrict ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _district.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _stateKey != null && LeaderboardRemote.slug(_district.text).length >= 3;

  void _submit() {
    if (!_canSave) return;
    unawaited(Haptics.light());
    Navigator.of(context).pop(
      _LeaderboardLocation(
        stateKey: _stateKey!,
        district: _district.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtle = MacroSnapTheme.textTertiary(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.borderSubtle(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Join the leaderboard',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: titleColour,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your name and weekly points appear on your district, state and '
              'India boards. Nothing else is shared.',
              style: TextStyle(fontSize: 12, height: 1.45, color: subtle),
            ),
            const SizedBox(height: 16),
            // Country is fixed: MacroSnap's points board is India-only today.
            // Showing it as a read-only row is honest about that, rather than
            // offering a picker with one option.
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: MacroSnapTheme.borderSubtle(context),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Country',
                      style: TextStyle(fontSize: 13, color: subtle),
                    ),
                  ),
                  Text(
                    'India',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: titleColour,
                    ),
                  ),
                ],
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _stateKey,
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: const InputDecoration(labelText: 'State or UT'),
              hint: const Text('Select your state'),
              items: [
                for (final state in LeaderboardRemote.states)
                  DropdownMenuItem(
                    value: state.key,
                    child: Text(state.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _stateKey = value),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _district,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'District or city',
                hintText: 'e.g. Pune',
                counterText: '',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
                setState(() {});
              },
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: MacroSnapTheme.neonPink,
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: MacroSnapTheme.neonOrange,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: MacroSnapTheme.borderSubtle(
                    context,
                  ).withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Join leaderboard',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'You can leave any time; leaving removes your entry from the '
              'current week\'s boards.',
              style: TextStyle(fontSize: 10.5, color: subtle),
            ),
          ],
        ),
      ),
    );
  }
}
