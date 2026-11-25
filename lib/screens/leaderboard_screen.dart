import 'dart:async';

import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme.dart';
import '../data/india_districts.dart';
import '../services/leaderboard_remote.dart';
import '../services/leaderboard_service.dart';
import '../services/subscription_service.dart';
import '../widgets/animations.dart';
import '../widgets/glass_card.dart';
import 'friends_league_screen.dart';
import 'leaderboard_ranks_screen.dart';
import 'subscription_screen.dart';

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
  // True until the first listener answer: without this the card painted its
  // "nobody has scored yet" empty state on the first frames and then swapped
  // to the real rows.
  bool _loadingBoard = true;
  bool _publishing = false;

  /// A score change that landed while a write was in flight, so the newer total
  /// is not dropped.
  bool _pendingPublish = false;

  /// Bumped on every (re)subscribe so a snapshot from the board that was on
  /// screen before a tab switch cannot paint itself under the new tab.
  int _listenToken = 0;

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

    // The RANKING NAMES come from the board listener, so subscribe to it before
    // the network work below. It used to run last, after restore + publish —
    // two round-trips — and the list sat blank (or on its skeleton) for the
    // length of them on every open, which is the "names take a few seconds"
    // the page showed.
    //
    // A fresh install does not know its area until the restore answers, so that
    // case waits for it; everyone else is listening while it is in flight.
    final wasState = _service.stateKey;
    final wasDistrict = _service.district;
    var listening = _service.hasLocation ? _listen() : null;
    await LeaderboardRemote.instance.restoreFromServer();
    // The restore is the account's copy of the area and can correct what is on
    // the device; if it did, the board subscribed above is the wrong one.
    final moved =
        wasState != _service.stateKey || wasDistrict != _service.district;
    if (listening == null || moved) listening = _listen();
    // The write is the slow part and changes only this user's row — the board
    // is already on screen while it happens.
    await _publish();
    await listening;
  }

  /// Sends this week's activity to the server, which scores it and writes the
  /// public boards.
  ///
  /// Called on open, on pull-to-refresh, after joining and after a score
  /// change (debounced). The phone sends facts only — the server decides the
  /// points — so what this page shows and what the board holds cannot drift.
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
        await LeaderboardRemote.instance.syncWithServer();
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
    final token = ++_listenToken;
    await _boardSub?.cancel();
    _boardSub = null;
    if (token != _listenToken) return;
    final remote = LeaderboardRemote.instance;
    final canBrowse =
        remote.canJoin &&
        (_scope == LeaderboardScope.india || _service.hasLocation);
    if (!canBrowse) {
      if (!mounted || token != _listenToken) return;
      setState(() {
        _board = LeaderboardBoard.empty;
        _loadingBoard = false;
      });
      return;
    }
    if (!mounted || token != _listenToken) return;
    final week = LeaderboardRemote.weekId();
    final stateKey = _service.stateKey;
    final districtKey = LeaderboardRemote.slug(_service.district ?? '');
    // Paint the last board this device saw while Firestore answers, so the
    // names are on screen immediately (and something is readable offline).
    if (_board.rows.isEmpty) {
      final cached = await remote.cachedBoard(
        week: week,
        scope: _scope,
        stateKey: stateKey,
        districtKey: districtKey,
      );
      if (!mounted || token != _listenToken) return;
      if (cached != null) setState(() => _board = cached);
    }
    setState(() => _loadingBoard = _board.rows.isEmpty);
    _boardSub = remote
        .watch(
          week: week,
          scope: _scope,
          stateKey: stateKey,
          districtKey: districtKey,
        )
        .listen((board) {
          if (!mounted || token != _listenToken) return;
          setState(() {
            _board = board;
            _loadingBoard = false;
          });
          unawaited(
            remote.cacheBoard(
              week: week,
              scope: _scope,
              stateKey: stateKey,
              districtKey: districtKey,
              board: board,
            ),
          );
        });
  }

  Future<void> _openJoinSheet() async {
    unawaited(Haptics.light());
    final result = await showModalBottomSheet<_LeaderboardLocation>(
      context: context,
      isScrollControlled: true,
      // An opaque sheet over a dimmed page. A transparent route made the page
      // underneath repaint through the sheet while it opened, closed or made
      // room for the keyboard — the two screens blended for a moment.
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      useSafeArea: true,
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
    // Joining writes the board on the SERVER. If that cannot be reached, say
    // so: the join is saved on this device and the next sync retries, but the
    // user must not be left believing they are already ranked.
    final synced = await LeaderboardRemote.instance.syncWithServer();
    if (!mounted) return;
    if (synced == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Joined on this device. Your score will appear on the board once '
            'you are back online.',
          ),
        ),
      );
    }
    await _listen();
  }

  Future<void> _leave() async {
    // The server owns the public row, so it is asked FIRST. If it cannot be
    // reached the local flag stays "joined": believing you left while the
    // board still shows your name is worse than an honest failure.
    final left = await LeaderboardRemote.instance.leaveOnServer();
    if (!mounted) return;
    if (!left) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not leave the leaderboard. Check your connection and try '
            'again.',
          ),
        ),
      );
      return;
    }
    await _service.setProfile(optIn: false);
    await _listen();
  }

  void _selectScope(LeaderboardScope scope) {
    if (scope == _scope) return;
    unawaited(Haptics.light());
    setState(() {
      _scope = scope;
      // Drop the previous board's rows and rank at once: showing the district's
      // numbers under the India tab for a frame is the "two screens" look a
      // switch used to have.
      _board = LeaderboardBoard.empty;
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
            // The board is the page's headline: it leads, on the same violet
            // hero gradient as Home, Habits and Health. The week total, the
            // breakdown and the rules follow it.
            AnimatedEntrance(delayMs: 20, child: _buildRankings(context)),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 45,
              child: _buildFriendsCard(context, isDark),
            ),
            const SizedBox(height: 14),
            AnimatedEntrance(delayMs: 70, child: _buildHero(context, isDark)),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 120,
              child: _buildWeekStrip(context, isDark),
            ),
            const SizedBox(height: 14),
            AnimatedEntrance(
              delayMs: 170,
              child: _buildBreakdown(context, isDark),
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
              const Icon(Icons.today_rounded, size: 15, color: Colors.white70),
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
    final rows =
        <
          ({
            IconData icon,
            Color colour,
            String label,
            String hint,
            int value,
            int cap,
          })
        >[
          (
            icon: Icons.directions_walk_rounded,
            colour: MacroSnapTheme.neonCyan,
            label: 'Movement',
            hint: 'Every 5,000 steps',
            value: points.movement,
            cap: LeaderboardService.movementDailyCap,
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

  /// The private, invite-only board.
  ///
  /// Pro-gated at the tap rather than hidden: this card is the only place a
  /// user learns the feature exists, so a locked card that opens the plans is
  /// more useful than a card that is not there.
  Widget _buildFriendsCard(BuildContext context, bool isDark) {
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    return GlassCard(
      padding: EdgeInsets.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openFriendsLeague,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonPurple.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  size: 19,
                  color: MacroSnapTheme.neonPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Friends league',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: titleColour,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MacroSnapTheme.neonOrange.withValues(
                              alpha: 0.16,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PRO',
                            style: TextStyle(
                              fontSize: 8.5,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w900,
                              color: MacroSnapTheme.neonOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A private weekly board for the people you invite',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFriendsLeague() async {
    unawaited(Haptics.light());
    if (!await SubscriptionService.instance.unlocksPro()) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendsLeagueScreen()),
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
  Widget _buildRankings(BuildContext context) {
    final remote = LeaderboardRemote.instance;
    final canJoin = remote.canJoin;
    final joined = _service.optIn && _service.hasLocation;
    final needsLocation =
        _scope != LeaderboardScope.india && !_service.hasLocation;
    // The card sits on the dark violet hero gradient, so its text is white
    // rather than the theme's on-surface colour.
    const titleColour = Colors.white;
    final subtle = Colors.white.withValues(alpha: 0.75);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: MacroSnapTheme.habitlyHeroCard(context),
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
          _buildScopeTabs(context, enabled: canJoin, subtle: subtle),

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
            else ...[
              // Five names is what "where do I stand?" needs. The rest of the
              // board is one tap away instead of pushing the week total,
              // breakdown and rules off the page.
              for (
                var i = 0;
                i < _board.rows.length && i < LeaderboardRemote.cardRows;
                i++
              )
                _buildRankRow(context, position: i + 1, row: _board.rows[i]),
              if (_board.rows.length > LeaderboardRemote.cardRows)
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _openFullBoard,
                    iconAlignment: IconAlignment.end,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                    label: const Text(
                      'View more',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],

            Divider(height: 22, color: Colors.white.withValues(alpha: 0.18)),

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

  /// Three equal tabs with a single sliding highlight. Taps are ignored when
  /// nobody is signed in, because there is no account to read a board with.
  ///
  /// The highlight is one background that moves between positions. Giving each
  /// tab its own AnimatedContainer meant that for the 180 ms of a switch two
  /// half-transparent pills were on screen at once — a double highlight that
  /// read as one screen blending into another.
  Widget _buildScopeTabs(
    BuildContext context, {
    required bool enabled,
    required Color subtle,
  }) {
    final index = LeaderboardScope.values.indexOf(_scope);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MacroSnapTheme.borderSubtle(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment(-1 + index.toDouble(), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / LeaderboardScope.values.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final scope in LeaderboardScope.values)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled && scope != _scope
                        ? () => _selectScope(scope)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(
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
                                ? const Color(0xFF1A1A1A)
                                : (enabled
                                      ? subtle
                                      : subtle.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRankRow(
    BuildContext context, {
    required int position,
    required LeaderboardRow row,
  }) {
    final colour = row.isMe ? MacroSnapTheme.neonGreen : Colors.white;
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
    if (rank < 0) return '${LeaderboardRemote.boardLimit}+';
    return '#$rank';
  }

  /// Opens the whole board (top [LeaderboardRemote.boardLimit]) for the scope
  /// on screen. The card keeps showing five rows, so this is the only way to
  /// see everyone — and it carries the same area and tab the user is on.
  void _openFullBoard() {
    unawaited(Haptics.light());
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LeaderboardRanksScreen(
          scope: _scope,
          stateKey: _service.stateKey,
          district: _service.district,
        ),
      ),
    );
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
      (label: 'Walk 5,000 steps', points: '+10', limit: 'per 5k, up to 50k'),
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
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF3A3A3A),
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

/// What the join sheet returns: the state to file under, and the district.
class _LeaderboardLocation {
  final String stateKey;
  final String district;

  const _LeaderboardLocation({required this.stateKey, required this.district});
}

/// District dropdown value that swaps the list for a text field.
const String _kOtherDistrict = '__other__';

/// One-step join: a state from a fixed list, then one of that state's districts.
///
/// The district is picked from a list rather than typed because it is part of
/// the board's path: "Pune", "pune" and "Poona" typed by three people made
/// three half-empty boards. "Other (type it)" keeps an area the list does not
/// carry possible, filed exactly as the old free-text field did.
///
/// The sheet is opaque and scrollable on purpose. The page underneath kept
/// repainting through the transparent route while the sheet opened, closed or
/// moved for the keyboard, which looked like two screens blended together.
class _JoinSheet extends StatefulWidget {
  final String? initialStateKey;
  final String? initialDistrict;

  const _JoinSheet({this.initialStateKey, this.initialDistrict});

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  late String? _stateKey = widget.initialStateKey;
  String _country = 'India';
  String? _pickedDistrict;
  bool _customDistrict = false;
  final TextEditingController _districtText = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDistrict?.trim() ?? '';
    if (initial.isEmpty) return;
    final slug = LeaderboardRemote.slug(initial);
    final match = LeaderboardRemote.districtsFor(
      _stateKey,
    ).where((d) => LeaderboardRemote.slug(d) == slug);
    if (match.isNotEmpty) {
      _pickedDistrict = match.first;
    } else {
      // Filed before this list existed, or an area the list does not carry.
      // Keep the name, shown as the typed value it is.
      _customDistrict = true;
      _districtText.text = initial;
    }
  }

  @override
  void dispose() {
    _districtText.dispose();
    super.dispose();
  }

  bool get _hasDistrict => _customDistrict
      ? LeaderboardRemote.slug(_districtText.text).length >= 3
      : _pickedDistrict != null;

  bool get _canSave => _stateKey != null && _hasDistrict;

  /// Country, state and district each open the same searchable list: Uttar
  /// Pradesh alone has 75 districts, and scrolling a dropdown to reach one is
  /// worse than typing two letters.
  Future<void> _pickCountry() async {
    final picked = await _showSearchPicker<String>(
      context: context,
      title: 'Country',
      hint: 'Search a country',
      items: const ['India'],
      labelOf: (country) => country,
      selected: _country,
      note:
          'MacroSnap boards cover India today. Every other country needs its '
          'own boards before it can appear here.',
    );
    if (picked == null || !mounted) return;
    setState(() => _country = picked);
  }

  Future<void> _pickState() async {
    ({String key, String name})? selected;
    for (final state in LeaderboardRemote.states) {
      if (state.key == _stateKey) selected = state;
    }
    final picked = await _showSearchPicker<({String key, String name})>(
      context: context,
      title: 'State or UT',
      hint: 'Search a state or union territory',
      items: LeaderboardRemote.states,
      labelOf: (state) => state.name,
      selected: selected,
    );
    if (picked == null || !mounted || picked.key == _stateKey) return;
    setState(() {
      _stateKey = picked.key;
      // A district belongs to one state: a leftover pick would file the user
      // under a district that state does not have.
      _pickedDistrict = null;
      _customDistrict = false;
      _districtText.clear();
    });
  }

  Future<void> _pickDistrict() async {
    final picked = await _showSearchPicker<String>(
      context: context,
      title: 'District',
      hint: 'Search a district',
      items: [...LeaderboardRemote.districtsFor(_stateKey), _kOtherDistrict],
      labelOf: (district) =>
          district == _kOtherDistrict ? 'Other (type it)' : district,
      selected: _customDistrict ? _kOtherDistrict : _pickedDistrict,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customDistrict = picked == _kOtherDistrict;
      if (_customDistrict) {
        _pickedDistrict = null;
      } else {
        _pickedDistrict = picked;
        _districtText.clear();
      }
    });
  }

  void _submit() {
    if (!_canSave) return;
    unawaited(Haptics.light());
    final district =
        (_customDistrict ? _districtText.text : (_pickedDistrict ?? '')).trim();
    Navigator.of(
      context,
    ).pop(_LeaderboardLocation(stateKey: _stateKey!, district: district));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColour = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtle = MacroSnapTheme.textTertiary(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.88 - keyboard)
        .clamp(320.0, MediaQuery.sizeOf(context).height);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sheetColour,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
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
                    'Your name and weekly points appear on your district, '
                    'state and India boards. Nothing else is shared.',
                    style: TextStyle(fontSize: 12, height: 1.45, color: subtle),
                  ),
                  const SizedBox(height: 14),
                  _LocationField(
                    label: 'Country',
                    value: _country,
                    hint: 'Search your country',
                    icon: Icons.public_rounded,
                    onTap: _pickCountry,
                  ),
                  const SizedBox(height: 14),
                  _LocationField(
                    label: 'State or UT',
                    value: _stateKey == null
                        ? null
                        : LeaderboardRemote.stateName(_stateKey!),
                    hint: 'Search your state',
                    icon: Icons.map_rounded,
                    onTap: _pickState,
                  ),
                  const SizedBox(height: 14),
                  _LocationField(
                    label: 'District',
                    value: _customDistrict
                        ? 'Other (type it)'
                        : _pickedDistrict,
                    hint: _stateKey == null
                        ? 'Select your state first'
                        : 'Search your district',
                    icon: Icons.location_on_rounded,
                    onTap: _stateKey == null ? null : _pickDistrict,
                  ),
                  if (_customDistrict) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _districtText,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'District or city',
                        hintText: 'e.g. Pune',
                        counterText: '',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
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
                    'You can leave any time; leaving removes your entry from '
                    "the current week's boards.",
                    style: TextStyle(fontSize: 10.5, color: subtle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A read-only field that opens a searchable list. It is drawn like the sheet's
/// text fields so country, state and district read as one set of answers rather
/// than a mix of menus and boxes.
class _LocationField extends StatelessWidget {
  final String label;
  final String? value;
  final String hint;
  final IconData icon;
  final VoidCallback? onTap;

  const _LocationField({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtle = MacroSnapTheme.textTertiary(context);
    final filled = (value ?? '').isNotEmpty;
    final enabled = onTap != null;
    // Drawn by hand instead of with [InputDecorator]. A read-only field with a
    // child and `isEmpty: true` put the decoration's own label inline, on top
    // of the value text: on the join sheet "State or UT" printed over "Choose
    // your state". A small label stacked above the value cannot collide at any
    // text scale, and it reads the same as the sheet's other fields.
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MacroSnapTheme.borderSubtle(context)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: subtle),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.1,
                          letterSpacing: 0.2,
                          fontWeight: FontWeight.w700,
                          color: subtle,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        filled ? value! : hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: filled
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: filled ? titleColour : subtle,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.search_rounded, size: 18, color: subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [items] under a search box and returns the picked one, or null when
/// the sheet is dismissed.
Future<T?> _showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required String hint,
  required List<T> items,
  required String Function(T item) labelOf,
  T? selected,
  String? note,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _SearchPickerSheet<T>(
      title: title,
      hint: hint,
      items: items,
      labelOf: labelOf,
      selected: selected,
      note: note,
    ),
  );
}

/// A searchable list in a sheet. The query filters as it is typed; an empty
/// query shows everything, so the list is still browsable.
///
/// Searching matters most for districts: Uttar Pradesh has 75 of them, and a
/// dropdown of 75 rows is a scroll with no way to jump.
class _SearchPickerSheet<T> extends StatefulWidget {
  final String title;
  final String hint;
  final List<T> items;
  final String Function(T item) labelOf;
  final T? selected;
  final String? note;

  const _SearchPickerSheet({
    required this.title,
    required this.hint,
    required this.items,
    required this.labelOf,
    this.selected,
    this.note,
  });

  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtle = MacroSnapTheme.textTertiary(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.75 - keyboard)
        .clamp(260.0, MediaQuery.sizeOf(context).height);
    final matches = [
      for (final item in widget.items)
        if (matchesSearch(widget.labelOf(item), _query.text)) item,
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.borderSubtle(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: titleColour,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _query.clear();
                                setState(() {});
                              },
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (widget.note != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                    child: Text(
                      widget.note!,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: subtle,
                      ),
                    ),
                  ),
                Flexible(
                  child: matches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          child: Text(
                            'No match for "${_query.text.trim()}".',
                            style: TextStyle(fontSize: 12.5, color: subtle),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final item = matches[index];
                            final isSelected = item == widget.selected;
                            return ListTile(
                              dense: true,
                              title: Text(
                                widget.labelOf(item),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? MacroSnapTheme.neonGreen
                                      : titleColour,
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      size: 20,
                                      color: MacroSnapTheme.neonGreen,
                                    )
                                  : null,
                              onTap: () => Navigator.of(context).pop(item),
                            );
                          },
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
