import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/haptics.dart';
import '../core/theme.dart';
import '../services/friends_league_service.dart';
import '../services/leaderboard_remote.dart';
import '../services/subscription_service.dart';
import '../widgets/glass_card.dart';
import 'subscription_screen.dart';

/// A private weekly board for people you invite — a Pro feature.
///
/// The numbers are not this screen's own: the backend scores the week once with
/// the same table the public board uses and writes a row into every league the
/// account belongs to. This page only creates/joins leagues, shows the invite
/// code and renders the rows.
class FriendsLeagueScreen extends StatefulWidget {
  const FriendsLeagueScreen({super.key});

  @override
  State<FriendsLeagueScreen> createState() => _FriendsLeagueScreenState();
}

class _FriendsLeagueScreenState extends State<FriendsLeagueScreen> {
  bool _loading = true;
  bool _pro = false;
  bool _busy = false;
  String? _error;
  List<FriendsLeague> _leagues = const [];
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  FriendsLeague? get _selected {
    for (final league in _leagues) {
      if (league.id == _selectedId) return league;
    }
    return _leagues.isEmpty ? null : _leagues.first;
  }

  /// Loads the Pro state, pushes this week's score, then reads the boards.
  ///
  /// The score push runs before the read so the rows this screen paints are the
  /// ones the server just wrote, not last visit's.
  Future<void> _load({bool sync = true}) async {
    final pro = await SubscriptionService.instance.unlocksPro();
    if (!mounted) return;
    if (!pro) {
      setState(() {
        _pro = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _pro = true;
      _error = null;
      if (_leagues.isEmpty) _loading = true;
    });
    try {
      if (sync) await FriendsLeagueService.instance.syncScore();
      final leagues = await FriendsLeagueService.instance.list();
      if (!mounted) return;
      setState(() {
        _leagues = leagues;
        _selectedId = leagues.any((l) => l.id == _selectedId)
            ? _selectedId
            : (leagues.isEmpty ? null : leagues.first.id);
        _loading = false;
      });
    } on FriendsLeagueException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your leagues. Check your connection.';
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _perform(
    Future<FriendsLeague> Function() action,
    String done,
  ) async {
    setState(() => _busy = true);
    try {
      final league = await action();
      if (!mounted) return;
      setState(() => _selectedId = league.id);
      await _load(sync: false);
      _toast(done);
    } on FriendsLeagueException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not reach friends leagues. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForText({
    required String title,
    required String hint,
    required String action,
    int maxLength = 30,
    bool code = false,
  }) async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          textCapitalization: code
              ? TextCapitalization.characters
              : TextCapitalization.sentences,
          inputFormatters: code
              ? [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))]
              : null,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();
    return result == null || result.isEmpty ? null : result;
  }

  Future<void> _create() async {
    unawaited(Haptics.light());
    final name = await _askForText(
      title: 'Name your league',
      hint: 'Gym buddies',
      action: 'Create',
    );
    if (name == null || !mounted) return;
    final displayName = await LeaderboardRemote.publicName();
    if (!mounted) return;
    await _perform(
      () => FriendsLeagueService.instance.create(
        name: name,
        displayName: displayName,
      ),
      'League created — share the code',
    );
  }

  Future<void> _join() async {
    unawaited(Haptics.light());
    final code = await _askForText(
      title: 'Join a league',
      hint: 'ABC123',
      action: 'Join',
      maxLength: 6,
      code: true,
    );
    if (code == null || !mounted) return;
    final displayName = await LeaderboardRemote.publicName();
    if (!mounted) return;
    await _perform(
      () => FriendsLeagueService.instance.join(
        code: code.toUpperCase(),
        displayName: displayName,
      ),
      'You joined the league',
    );
  }

  Future<void> _leave(FriendsLeague league) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this league?'),
        content: Text(
          'You will come off "${league.name}" and its board. The last member '
          'to leave deletes the league for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await FriendsLeagueService.instance.leave(league.id);
      if (!mounted) return;
      setState(() => _selectedId = null);
      await _load(sync: false);
      _toast('You left ${league.name}');
    } on FriendsLeagueException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not leave the league. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCode(FriendsLeague league) async {
    await Clipboard.setData(ClipboardData(text: league.code));
    _toast('Invite code copied');
  }

  Future<void> _shareCode(FriendsLeague league) async {
    unawaited(Haptics.light());
    await Share.share(
      'Join my MacroSnap friends league "${league.name}" — code '
      '${league.code}.\n\n'
      'Download MacroSnap: '
      'https://play.google.com/store/apps/details?id=com.macrosnap.macro_snap',
    );
  }

  Future<void> _openSubscription() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
    if (!mounted) return;
    await _load();
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
          'Friends league',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_pro && _leagues.isNotEmpty)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, size: 22),
              onPressed: _busy ? null : () => unawaited(_load()),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: MacroSnapTheme.neonOrange,
        backgroundColor: isDark
            ? MacroSnapTheme.cardDark
            : MacroSnapTheme.surfaceLight,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: _buildBody(context, isDark),
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, bool isDark) {
    if (_loading) {
      return const [
        SizedBox(
          height: 260,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MacroSnapTheme.neonOrange,
              ),
            ),
          ),
        ),
      ];
    }

    if (!_pro) return [_buildProCard(context)];

    if (_error != null && _leagues.isEmpty) {
      return [
        _buildErrorCard(context),
        const SizedBox(height: 14),
        _buildActions(context),
      ];
    }

    if (_leagues.isEmpty) {
      return [
        _buildEmptyCard(context, isDark),
        const SizedBox(height: 14),
        _buildActions(context),
      ];
    }

    final league = _selected!;
    return [
      if (_leagues.length > 1) ...[
        _buildLeagueChips(context),
        const SizedBox(height: 14),
      ],
      _buildInviteCard(context, league),
      const SizedBox(height: 14),
      _buildBoardCard(context, league, isDark),
      const SizedBox(height: 8),
      Center(
        child: TextButton.icon(
          onPressed: _busy ? null : () => _leave(league),
          icon: const Icon(Icons.logout_rounded, size: 16),
          label: Text('Leave ${league.name}'),
          style: TextButton.styleFrom(
            foregroundColor: MacroSnapTheme.textTertiary(context),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      _buildActions(context),
    ];
  }

  Widget _buildProCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: MacroSnapTheme.habitlyHeroCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: MacroSnapTheme.neonOrange.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'PRO',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w900,
                color: MacroSnapTheme.neonOrange,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Friends league is a Pro feature',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a private weekly board and invite the people you actually '
            'compete with. Only members see the names and points on it.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _openSubscription,
              style: FilledButton.styleFrom(
                backgroundColor: MacroSnapTheme.neonOrange,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text(
                'See Pro plans',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MacroSnapTheme.neonPink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        _error!,
        style: const TextStyle(
          fontSize: 12,
          height: 1.45,
          color: MacroSnapTheme.neonPink,
        ),
      ),
    );
  }

  Widget _buildEmptyCard(BuildContext context, bool isDark) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: MacroSnapTheme.neonPurple.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.groups_rounded,
              size: 22,
              color: MacroSnapTheme.neonPurple,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Start your own league',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You get a six-character code. Anyone with Pro who enters it joins '
            'the same weekly board — no phone numbers, no contact list, and '
            'nothing about your meals is shared.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create'),
            style: FilledButton.styleFrom(
              backgroundColor: MacroSnapTheme.neonOrange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _join,
            icon: const Icon(Icons.key_rounded, size: 18),
            label: const Text('Join'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MacroSnapTheme.textSecondary(context),
              padding: const EdgeInsets.symmetric(vertical: 13),
              side: BorderSide(color: MacroSnapTheme.borderSubtle(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeagueChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final league in _leagues)
          ChoiceChip(
            label: Text(league.name),
            selected: league.id == (_selected?.id ?? ''),
            onSelected: _busy
                ? null
                : (_) {
                    unawaited(Haptics.light());
                    setState(() => _selectedId = league.id);
                  },
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: league.id == (_selected?.id ?? '')
                  ? Colors.black
                  : MacroSnapTheme.textSecondary(context),
            ),
            selectedColor: MacroSnapTheme.neonOrange,
            backgroundColor: MacroSnapTheme.borderSubtle(
              context,
            ).withValues(alpha: 0.35),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
      ],
    );
  }

  Widget _buildInviteCard(BuildContext context, FriendsLeague league) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: MacroSnapTheme.habitlyHeroCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                size: 22,
                color: MacroSnapTheme.neonOrange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  league.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              if (league.isOwner)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Text(
                    'OWNER',
                    style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${league.memberCount} '
            '${league.memberCount == 1 ? 'member' : 'members'} · this week',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INVITE CODE',
                        style: TextStyle(
                          fontSize: 8.5,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        league.code,
                        style: const TextStyle(
                          fontSize: 22,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  onPressed: () => _copyCode(league),
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'Share invite',
                  onPressed: () => _shareCode(league),
                  icon: const Icon(
                    Icons.ios_share_rounded,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardCard(
    BuildContext context,
    FriendsLeague league,
    bool isDark,
  ) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'This week',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              if (league.rank != null)
                Text(
                  'You are #${league.rank}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (league.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nobody has scored yet this week. Your row goes up as soon as '
                'your points sync.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            )
          else
            for (var i = 0; i < league.rows.length; i++)
              _FriendRow(position: i + 1, row: league.rows[i]),
          const SizedBox(height: 2),
          Text(
            'Points are scored by the same server rules as the public board, '
            'from meals, habits, water, weigh-ins and steps.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the private board: rank, name, and this week's points.
class _FriendRow extends StatelessWidget {
  final int position;
  final FriendsLeagueRow row;

  const _FriendRow({required this.position, required this.row});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final medal = switch (position) {
      1 => const Color(0xFFF4A340),
      2 => const Color(0xFFC9CBD1),
      3 => const Color(0xFFC98A5B),
      _ => null,
    };
    final nameColour = row.isMe
        ? MacroSnapTheme.neonGreen
        : (isDark ? Colors.white : const Color(0xFF1A1A1A));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (medal ?? Colors.grey).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$position',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: medal ?? MacroSnapTheme.textTertiary(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: row.isMe ? FontWeight.w900 : FontWeight.w700,
                color: nameColour,
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
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: row.isMe ? MacroSnapTheme.neonGreen : nameColour,
            ),
          ),
        ],
      ),
    );
  }
}
