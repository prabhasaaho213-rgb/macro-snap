import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_http.dart';
import 'crash_reporting.dart';
import 'gemini_service.dart';
import 'leaderboard_remote.dart';
import 'leaderboard_service.dart';

/// One line of a private league's weekly board.
class FriendsLeagueRow {
  final String uid;
  final String name;
  final int points;
  final bool isMe;

  /// The avatar this member chose (`art:hood`), or empty when they have not
  /// picked one — the row then shows their initial instead.
  final String avatar;

  const FriendsLeagueRow({
    required this.uid,
    required this.name,
    required this.points,
    required this.isMe,
    this.avatar = '',
  });

  factory FriendsLeagueRow.fromJson(Map data) => FriendsLeagueRow(
    uid: data['uid'] is String ? data['uid'] as String : '',
    name: data['name'] is String && (data['name'] as String).trim().isNotEmpty
        ? (data['name'] as String).trim()
        : 'MacroSnap user',
    points: (data['points'] as num?)?.toInt() ?? 0,
    isMe: data['isMe'] == true,
    avatar: data['avatar'] is String ? (data['avatar'] as String).trim() : '',
  );
}

/// A private, invite-only weekly board.
///
/// The score is the same server-scored number as the public board — this class
/// only carries the league's identity, its code and the rows the backend
/// returned. Nothing here computes points, so a private league can never pay
/// more than the public one.
class FriendsLeague {
  final String id;
  final String name;
  final String code;
  final String ownerUid;
  final bool isOwner;
  final int memberCount;
  final String week;
  final int points;
  final int? rank;
  final List<FriendsLeagueRow> rows;

  /// Names of members who arrived through an invite (newest first), so the
  /// inviter sees the invite working instead of having to guess.
  final List<String> invitedNames;

  const FriendsLeague({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerUid,
    required this.isOwner,
    required this.memberCount,
    required this.week,
    required this.points,
    required this.rank,
    required this.rows,
    this.invitedNames = const [],
  });

  factory FriendsLeague.fromJson(Map data) {
    final rawRows = data['rows'];
    final rawInvites = data['invites'];
    return FriendsLeague(
      id: data['id'] is String ? data['id'] as String : '',
      name: data['name'] is String && (data['name'] as String).trim().isNotEmpty
          ? (data['name'] as String).trim()
          : 'Friends league',
      code: data['code'] is String ? data['code'] as String : '',
      ownerUid: data['ownerUid'] is String ? data['ownerUid'] as String : '',
      isOwner: data['isOwner'] == true,
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      week: data['week'] is String ? data['week'] as String : '',
      points: (data['points'] as num?)?.toInt() ?? 0,
      rank: (data['rank'] as num?)?.toInt(),
      rows: rawRows is List
          ? [
              for (final row in rawRows)
                if (row is Map) FriendsLeagueRow.fromJson(row),
            ]
          : const [],
      invitedNames: rawInvites is List
          ? [
              for (final member in rawInvites)
                if (member is Map &&
                    member['name'] is String &&
                    (member['name'] as String).trim().isNotEmpty)
                  (member['name'] as String).trim(),
            ]
          : const [],
    );
  }
}

/// What an invite code points at, read before joining.
class InvitePreview {
  final String name;
  final int memberCount;
  final bool full;
  final bool alreadyMember;

  const InvitePreview({
    required this.name,
    required this.memberCount,
    required this.full,
    required this.alreadyMember,
  });
}

/// A user-facing reason a league action failed (bad code, not Pro, offline).
class FriendsLeagueException implements Exception {
  final String message;
  const FriendsLeagueException(this.message);

  @override
  String toString() => message;
}

/// Private friends leagues, Pro only.
///
/// The phone never decides a member's points: [syncScore] sends the same raw
/// facts the public leaderboard sends and the backend scores them once, writing
/// a row into every league the account belongs to. Creating and joining are the
/// Pro-gated acts (enforced by the server, not by this class); an existing
/// member keeps reading and scoring if their Pro lapses, so one expired card
/// cannot silently drop them off a board their friends still see.
class FriendsLeagueService {
  FriendsLeagueService._();
  static final FriendsLeagueService instance = FriendsLeagueService._();

  /// Device-level cache of "this account is in at least one league", so the
  /// background points push does not call a route that would answer "none"
  /// for every user who never opened this feature.
  static const String hasLeagueKey = 'friends_league_has';

  Uri _url(String path) => Uri.parse('${GeminiService.serverUrl}$path');

  Future<bool> get hasLeague async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(hasLeagueKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setHasLeague(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(hasLeagueKey, value);
    } catch (_) {
      // A prefs failure only costs an extra request later.
    }
  }

  /// Every league this account belongs to, with this week's rows.
  Future<List<FriendsLeague>> list() async {
    final resp = await AuthHttp.get(
      _url('/friends/leagues'),
    ).timeout(const Duration(seconds: 12));
    final data = _decode(resp);
    final leagues = _leaguesFrom(data);
    await _setHasLeague(leagues.isNotEmpty);
    return leagues;
  }

  /// Creates a league and returns it. The server decides the invite code.
  Future<FriendsLeague> create({
    required String name,
    required String displayName,
  }) async {
    final resp = await AuthHttp.post(
      _url('/friends/league'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'displayName': displayName,
        'avatar': LeaderboardRemote.publicAvatar(),
      }),
    ).timeout(const Duration(seconds: 15));
    final data = _decode(resp);
    final league = _leagueFrom(data);
    await _setHasLeague(true);
    return league;
  }

  /// Joins the league [code] points at. Idempotent on the server.
  Future<FriendsLeague> join({
    required String code,
    required String displayName,
  }) async {
    final resp = await AuthHttp.post(
      _url('/friends/join'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'displayName': displayName,
        'avatar': LeaderboardRemote.publicAvatar(),
      }),
    ).timeout(const Duration(seconds: 15));
    final data = _decode(resp);
    final league = _leagueFrom(data);
    await _setHasLeague(true);
    return league;
  }

  /// What an invite code points at, without joining.
  ///
  /// An expired code or a full league gets its own answer here, before the
  /// screen opens a board or a free account is sent into the paywall.
  Future<InvitePreview> previewInvite(String code) async {
    final resp = await AuthHttp.get(
      _url('/friends/invite/$code'),
    ).timeout(const Duration(seconds: 10));
    final data = _decode(resp);
    return InvitePreview(
      name: data['name'] is String ? data['name'] as String : 'Friends league',
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      full: data['full'] == true,
      alreadyMember: data['alreadyMember'] == true,
    );
  }

  /// Leaves [leagueId]. The last member out deletes the league server-side.
  Future<void> leave(String leagueId) async {
    final resp = await AuthHttp.post(
      _url('/friends/leave'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'leagueId': leagueId}),
    ).timeout(const Duration(seconds: 15));
    _decode(resp);
    final leagues = await list();
    await _setHasLeague(leagues.isNotEmpty);
  }

  /// Scores this week and writes the row into every league the account is in.
  ///
  /// Returns false when there is nothing to do (signed out, no league) or the
  /// server could not be reached — never throws, because this rides on the
  /// background points push.
  Future<bool> syncScore() async {
    if (!LeaderboardRemote.instance.canJoin) return false;
    if (!await hasLeague) return false;
    try {
      final body = <String, dynamic>{
        'name': await LeaderboardRemote.publicName(),
        'avatar': LeaderboardRemote.publicAvatar(),
        'days': LeaderboardRemote.weekDaysForSync(LeaderboardService.instance),
      };
      final resp = await AuthHttp.post(
        _url('/friends/sync'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body);
      if (data is Map && data['leagues'] is List) {
        await _setHasLeague((data['leagues'] as List).isNotEmpty);
      }
      return true;
    } catch (e, st) {
      logError('FriendsLeagueService.syncScore', e, st);
      return false;
    }
  }

  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body);
        if (data is Map) return Map<String, dynamic>.from(data);
      } catch (e, st) {
        logError('FriendsLeagueService._decode', e, st);
      }
      throw const FriendsLeagueException(
        'Friends leagues are unavailable right now.',
      );
    }
    throw FriendsLeagueException(_messageFor(resp.statusCode, resp.body));
  }

  FriendsLeague _leagueFrom(Map<String, dynamic> data) {
    final raw = data['league'];
    if (raw is Map) return FriendsLeague.fromJson(raw);
    throw const FriendsLeagueException(
      'Friends leagues are unavailable right now.',
    );
  }

  List<FriendsLeague> _leaguesFrom(Map<String, dynamic> data) {
    final raw = data['leagues'];
    if (raw is! List) return const [];
    return [
      for (final league in raw)
        if (league is Map) FriendsLeague.fromJson(league),
    ];
  }

  /// A message a user can act on, keyed by the server's own error code.
  static String _messageFor(int status, String body) {
    String? code;
    try {
      final data = jsonDecode(body);
      if (data is Map && data['error'] is String) {
        code = data['error'] as String;
      }
    } catch (_) {}

    switch (status) {
      case 400:
        return 'A code is six letters and numbers.';
      case 403:
        return code == 'pro_required'
            ? 'Friends leagues are a Pro feature.'
            : 'You do not have access to that league.';
      case 404:
        return 'That invite code does not match a league.';
      case 409:
        return code == 'league_full'
            ? 'That league is full.'
            : 'You are already in the maximum number of leagues.';
      case 429:
        return 'Too many attempts. Wait a minute and try again.';
      case 503:
        return 'Friends leagues are unavailable right now.';
      default:
        return 'Could not reach friends leagues. Check your connection.';
    }
  }
}
