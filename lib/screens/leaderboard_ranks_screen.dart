import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/leaderboard_remote.dart';
import '../widgets/snap_avatar.dart';

/// The full weekly board for one scope: the top [LeaderboardRemote.boardLimit]
/// entries, opened from the Rank page's "View more".
///
/// The Rank card stays short on purpose — five names answer "where am I?" at a
/// glance, and a hundred rows there would bury the week total, the breakdown
/// and the rules underneath it. The whole board still has to be reachable, so
/// it lives here, one push away.
///
/// Live like the card: a Firestore listener, so a score posted on another phone
/// moves this list without a pull-to-refresh.
class LeaderboardRanksScreen extends StatefulWidget {
  final LeaderboardScope scope;
  final String? stateKey;
  final String? district;

  const LeaderboardRanksScreen({
    super.key,
    required this.scope,
    this.stateKey,
    this.district,
  });

  @override
  State<LeaderboardRanksScreen> createState() => _LeaderboardRanksScreenState();
}

class _LeaderboardRanksScreenState extends State<LeaderboardRanksScreen> {
  late final Stream<LeaderboardBoard> _stream = LeaderboardRemote.instance
      .watch(
        week: LeaderboardRemote.weekId(),
        scope: widget.scope,
        stateKey: widget.stateKey,
        districtKey: LeaderboardRemote.slug(widget.district ?? ''),
        limit: LeaderboardRemote.boardLimit,
      );

  /// Where this board is, without the page needing the service's state.
  String get _place => switch (widget.scope) {
    LeaderboardScope.india => 'India',
    LeaderboardScope.state => LeaderboardRemote.stateName(
      widget.stateKey ?? '',
    ),
    LeaderboardScope.district => _titleCase(widget.district ?? ''),
  };

  static String _titleCase(String value) => value
      .split(RegExp(r'[\s-]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColour = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtle = MacroSnapTheme.textTertiary(context);

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
            color: titleColour,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Leaderboard',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<LeaderboardBoard>(
        stream: _stream,
        builder: (context, snapshot) {
          final board = snapshot.data ?? LeaderboardBoard.empty;
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final rows = board.rows;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: MacroSnapTheme.habitlyHeroCard(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_rounded,
                          color: MacroSnapTheme.neonOrange,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _place.isEmpty ? 'This week' : _place,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Top ${LeaderboardRemote.boardLimit} · weekly ranking',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (loading && rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
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
                )
              else if (board.error != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonPink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    board.notDeployed
                        ? '${board.error}\nDeploy them with: firebase deploy '
                              '--only firestore:rules'
                        : board.error!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: MacroSnapTheme.neonPink,
                    ),
                  ),
                )
              else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nobody has scored on this board this week yet.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: subtle,
                    ),
                  ),
                )
              else
                for (var i = 0; i < rows.length; i++)
                  _RankRow(position: i + 1, row: rows[i], subtle: subtle),
              if (board.myRank != null) ...[
                const SizedBox(height: 12),
                Text(
                  board.myRank! > 0
                      ? 'Your rank: #${board.myRank}'
                      : 'Your rank: ${LeaderboardRemote.boardLimit}+',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: titleColour,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One line of the full board. The rank is a badge so a long name cannot push
/// the number out of line, and the top three keep the trophy accent.
class _RankRow extends StatelessWidget {
  final int position;
  final LeaderboardRow row;
  final Color subtle;

  const _RankRow({
    required this.position,
    required this.row,
    required this.subtle,
  });

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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: row.isMe
            ? MacroSnapTheme.neonGreen.withValues(alpha: 0.10)
            : (isDark ? MacroSnapTheme.cardDark : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: row.isMe
              ? MacroSnapTheme.neonGreen.withValues(alpha: 0.45)
              : MacroSnapTheme.borderSubtle(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (medal ?? Colors.white).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$position',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: medal ?? subtle,
              ),
            ),
          ),
          const SizedBox(width: 11),
          SnapAvatar(
            avatar: row.avatar.isEmpty ? null : row.avatar,
            size: 30,
            fallbackInitial: row.name,
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
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: row.isMe ? MacroSnapTheme.neonGreen : nameColour,
            ),
          ),
        ],
      ),
    );
  }
}
