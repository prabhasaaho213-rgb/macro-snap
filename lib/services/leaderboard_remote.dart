import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/india_districts.dart';
import 'auth_http.dart';
import 'crash_reporting.dart';
import 'gemini_service.dart';
import 'leaderboard_service.dart';
import 'weight_store.dart';

/// The three boards a user can appear on. The score is the same everywhere —
/// appearing on more than one board never earns extra points.
enum LeaderboardScope { district, state, india }

/// One row of a ranking.
class LeaderboardRow {
  final String uid;
  final String name;
  final int points;
  final bool isMe;

  const LeaderboardRow({
    required this.uid,
    required this.name,
    required this.points,
    required this.isMe,
  });
}

/// A fetched board: the visible rows plus where the caller stands.
///
/// [myRank] is null when the caller has no entry on this board (never joined,
/// or joined a different district this week). [error] is a short,
/// user-facing reason when the fetch failed — most often because the
/// leaderboard rules have not been deployed to the Firebase project yet.
class LeaderboardBoard {
  final List<LeaderboardRow> rows;
  final int? myRank;
  final String? error;
  final bool notDeployed;

  const LeaderboardBoard({
    this.rows = const [],
    this.myRank,
    this.error,
    this.notDeployed = false,
  });

  bool get ok => error == null;

  static const LeaderboardBoard empty = LeaderboardBoard();
}

/// What `POST /leaderboard/sync` answered: the server's verdict for the week.
class LeaderboardSyncResult {
  /// The server now considers this account joined (it echoes the flag it
  /// saved, so a restore and a fresh sync agree).
  final bool joined;

  /// This week's server-scored total — the number on the board.
  final int points;

  final String week;
  final String name;
  final String? stateKey;
  final String? districtKey;

  /// The area change was refused because the weekly move limit was reached.
  final bool locationLocked;

  const LeaderboardSyncResult({
    required this.joined,
    required this.points,
    required this.week,
    required this.name,
    this.stateKey,
    this.districtKey,
    this.locationLocked = false,
  });
}

/// Server-scored leaderboard. The phone reports facts, the backend decides
/// every point, and Firestore holds the rows the app reads back.
///
/// Path: `leaderboard/{week}/scopes/{scopeKey}/entries/{uid}`
///
/// The scope lives in the PATH so each board is a plain collection with a
/// single `orderBy('points')` — no composite index to deploy, no cross-board
/// filtering. The backend writes all three rows in one batch so a user is on
/// (or off) all three boards together; this class only READS them.
///
/// The score is verified: `POST /leaderboard/sync` re-reads meals, habits,
/// water and weigh-ins from Firestore, merges the step history the server keeps
/// in `stepLog/{uid}`, and scores the week itself. The app never writes points,
/// so a modified client cannot claim a score — and because the server keeps the
/// step totals and the join, a reinstall restores both instead of starting the
/// week over.
class LeaderboardRemote {
  LeaderboardRemote._();
  static final LeaderboardRemote instance = LeaderboardRemote._();

  /// Points ceiling the rules enforce on a single week document.
  static const int maxWeekPoints = 1000;

  /// Board size the app will read back, and the slice the Rank page's
  /// "View more" shows. The Rank card itself renders only the first few rows.
  static const int boardLimit = 100;

  /// Rows the Rank card shows before "View more".
  static const int cardRows = 5;

  /// The states and union territories offered in the picker. The key is what
  /// goes into the Firestore path, so it must stay stable once released.
  static const List<({String key, String name})> states = [
    (key: 'andhra-pradesh', name: 'Andhra Pradesh'),
    (key: 'arunachal-pradesh', name: 'Arunachal Pradesh'),
    (key: 'assam', name: 'Assam'),
    (key: 'bihar', name: 'Bihar'),
    (key: 'chandigarh', name: 'Chandigarh'),
    (key: 'chhattisgarh', name: 'Chhattisgarh'),
    (
      key: 'dadra-nagar-haveli-daman-diu',
      name: 'Dadra & Nagar Haveli and Daman & Diu',
    ),
    (key: 'delhi', name: 'Delhi'),
    (key: 'goa', name: 'Goa'),
    (key: 'gujarat', name: 'Gujarat'),
    (key: 'haryana', name: 'Haryana'),
    (key: 'himachal-pradesh', name: 'Himachal Pradesh'),
    (key: 'jammu-kashmir', name: 'Jammu & Kashmir'),
    (key: 'jharkhand', name: 'Jharkhand'),
    (key: 'karnataka', name: 'Karnataka'),
    (key: 'kerala', name: 'Kerala'),
    (key: 'ladakh', name: 'Ladakh'),
    (key: 'lakshadweep', name: 'Lakshadweep'),
    (key: 'madhya-pradesh', name: 'Madhya Pradesh'),
    (key: 'maharashtra', name: 'Maharashtra'),
    (key: 'manipur', name: 'Manipur'),
    (key: 'meghalaya', name: 'Meghalaya'),
    (key: 'mizoram', name: 'Mizoram'),
    (key: 'nagaland', name: 'Nagaland'),
    (key: 'odisha', name: 'Odisha'),
    (key: 'puducherry', name: 'Puducherry'),
    (key: 'punjab', name: 'Punjab'),
    (key: 'rajasthan', name: 'Rajasthan'),
    (key: 'sikkim', name: 'Sikkim'),
    (key: 'tamil-nadu', name: 'Tamil Nadu'),
    (key: 'telangana', name: 'Telangana'),
    (key: 'tripura', name: 'Tripura'),
    (key: 'uttar-pradesh', name: 'Uttar Pradesh'),
    (key: 'uttarakhand', name: 'Uttarakhand'),
    (key: 'west-bengal', name: 'West Bengal'),
    (key: 'andaman-nicobar', name: 'Andaman & Nicobar Islands'),
  ];

  static String stateName(String key) => states
      .firstWhere((s) => s.key == key, orElse: () => (key: key, name: key))
      .name;

  /// The districts of [stateKey], sorted for the picker. Empty when the state
  /// is unknown, which the join sheet renders as a disabled district field
  /// rather than an empty menu.
  static List<String> districtsFor(String? stateKey) =>
      stateKey == null ? const [] : (kDistrictsByState[stateKey] ?? const []);

  /// Whether there is an account to attach points to. Guests (no Firebase
  /// user) cannot join: a board needs a stable identity, and an anonymous
  /// device id could be reset to farm a fresh week.
  bool get canJoin {
    try {
      return Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  String? get uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Lowercase, hyphenated form of a free-text district. Kept identical on
  /// every device so "Pune", "pune " and "PUNE" land on one board.
  static String slug(String value) {
    final lowered = value.trim().toLowerCase();
    final buffer = StringBuffer();
    var lastDash = false;
    for (final rune in lowered.runes) {
      final char = String.fromCharCode(rune);
      final isAlphaNumeric =
          (rune >= 0x61 && rune <= 0x7A) || (rune >= 0x30 && rune <= 0x39);
      if (isAlphaNumeric) {
        buffer.write(char);
        lastDash = false;
      } else if (!lastDash && buffer.isNotEmpty) {
        buffer.write('-');
        lastDash = true;
      }
    }
    final result = buffer.toString().replaceAll(RegExp(r'-+$'), '');
    return result.length > 40 ? result.substring(0, 40) : result;
  }

  /// The Firestore scope document id for a board.
  static String scopeKey(
    LeaderboardScope scope, {
    String? stateKey,
    String? districtKey,
  }) => switch (scope) {
    LeaderboardScope.india => 'india',
    LeaderboardScope.state => 'state_${stateKey ?? 'unknown'}',
    LeaderboardScope.district =>
      'district_${stateKey ?? 'unknown'}_${districtKey ?? 'unknown'}',
  };

  /// The ISO week id (`2026-W47`) the board for [day] lives under.
  ///
  /// ISO weeks start on Monday, which is also how the local score is added up
  /// — a board and the number on it cannot disagree about which week it is.
  static String weekId([DateTime? day]) {
    final date = day ?? DateTime.now();
    final local = DateTime(date.year, date.month, date.day);
    // The ISO week belongs to the year its Thursday falls in.
    final thursday = local.add(Duration(days: 4 - local.weekday));
    final jan4 = DateTime(thursday.year, 1, 4);
    final firstMonday = jan4.subtract(Duration(days: jan4.weekday - 1));
    final week = (thursday.difference(firstMonday).inDays ~/ 7) + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  static Uri _url(String path) => Uri.parse('${GeminiService.serverUrl}$path');

  CollectionReference<Map<String, dynamic>> _entries(
    String week,
    String scope,
  ) => FirebaseFirestore.instance
      .collection('leaderboard')
      .doc(week)
      .collection('scopes')
      .doc(scope)
      .collection('entries');

  /// The three board documents a user in [district] belongs on.
  static List<String> boardsFor({
    required String stateKey,
    required String district,
  }) => [
    scopeKey(LeaderboardScope.india),
    scopeKey(LeaderboardScope.state, stateKey: stateKey),
    scopeKey(
      LeaderboardScope.district,
      stateKey: stateKey,
      districtKey: slug(district),
    ),
  ];

  /// Only our own scope ids may ever be used as a path or a delete target.
  /// `previousScopes` is remembered in local prefs; a corrupted value must not
  /// be able to aim a delete at an unrelated document.
  /// `district_<state>` and `district_<state>_<district>` both contain
  /// underscores, so the character class must allow them — an earlier version
  /// did not, and every district scope was rejected as "invalid", which would
  /// have silently skipped the old district row on a move and on leave.
  static final RegExp _scopePattern = RegExp(r'^(state|district)_[a-z0-9_-]+$');

  static bool isValidScope(String scope) =>
      scope == 'india' || _scopePattern.hasMatch(scope);

  /// Boards written earlier this week that the current area no longer covers.
  ///
  /// This is what makes a district change *remove* the old row instead of
  /// leaving the user on two boards at once.
  static List<String> staleScopes(
    List<String> previousScopes,
    List<String> currentScopes,
  ) => [
    for (final scope in previousScopes)
      if (!currentScopes.contains(scope) && isValidScope(scope)) scope,
  ];

  /// The display name used on boards: a nickname if one is set, else the name
  /// on the account, else a generic label. Never an email or a phone number.
  static Future<String> publicName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = (prefs.getString('nickname') ?? prefs.getString('name') ?? '')
          .trim();
      if (raw.isEmpty) return 'MacroSnap user';
      return raw.length > 40 ? raw.substring(0, 40) : raw;
    } catch (_) {
      return 'MacroSnap user';
    }
  }

  /// Pushes this account's activity to the server, which scores the week and
  /// writes the board rows.
  ///
  /// The phone no longer writes points itself. It reports raw facts (name, area
  /// and the stored step total for each day of the week); the server reads
  /// meals, habits, water and weigh-ins from Firestore, scores every day with
  /// `leaderboard.js`, and persists the step history. That is what makes
  /// yesterday's points survive a reinstall, and it is the only place points
  /// are decided.
  Future<LeaderboardSyncResult?> syncWithServer() async {
    final service = LeaderboardService.instance;
    if (!canJoin) return null;
    try {
      final body = <String, dynamic>{
        'name': await publicName(),
        'weekId': weekId(),
        'days': _weekDays(service),
      };
      final state = service.stateKey;
      final district = service.district;
      if (state != null && state.isNotEmpty) body['stateKey'] = state;
      if (district != null && district.isNotEmpty) {
        body['districtKey'] = slug(district);
      }
      final resp = await AuthHttp.post(
        _url('/leaderboard/sync'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      return _applyResponse(service, data);
    } catch (e, st) {
      logError('LeaderboardRemote.syncWithServer', e, st);
      return null;
    }
  }

  /// Restores join state, area and step history for this account.
  ///
  /// Joining used to be a device preference only, so deleting and reinstalling
  /// the app asked an account that was already on the board to join again. The
  /// server remembers the join (`leaderboardMeta`), and this read rebuilds it
  /// on a fresh install. A leave performed on this device is never undone: the
  /// server is told about it before the local flag changes.
  Future<bool> restoreFromServer() async {
    final service = LeaderboardService.instance;
    if (!canJoin) return false;
    try {
      final resp = await AuthHttp.get(
        _url('/leaderboard/me'),
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body);
      if (data is! Map) return false;
      await service.applyServerStepDays(_intMap(data['stepDays']));
      if (data['joined'] != true) return false;
      final state = data['stateKey'];
      final districtKey = data['districtKey'];
      if (state is! String || state.isEmpty) return false;
      if (districtKey is! String || districtKey.isEmpty) return false;
      // The server stores the slug; the picker works with display names.
      final district = districtsFor(state).firstWhere(
        (d) => slug(d) == districtKey,
        orElse: () => districtKey,
      );
      if (!service.optIn ||
          service.stateKey != state ||
          service.district != district) {
        await service.setProfile(
          optIn: true,
          stateKey: state,
          district: district,
        );
      }
      return true;
    } catch (e, st) {
      logError('LeaderboardRemote.restoreFromServer', e, st);
      return false;
    }
  }

  /// Asks the server to take this account off every board for this week.
  ///
  /// Called BEFORE the local "left" flag is written: if the server cannot be
  /// reached the user is still joined, and telling them otherwise would leave a
  /// public row up on a device that believes it left.
  Future<bool> leaveOnServer() async {
    if (!canJoin) return false;
    try {
      final resp = await AuthHttp.post(
        _url('/leaderboard/leave'),
        headers: const {'Content-Type': 'application/json'},
        body: '{}',
      ).timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (e, st) {
      logError('LeaderboardRemote.leaveOnServer', e, st);
      return false;
    }
  }

  LeaderboardSyncResult? _applyResponse(
    LeaderboardService service,
    Map data,
  ) {
    final week = data['week'] as String? ?? weekId();
    final days = <({String dateKey, int points, Map<String, int> buckets})>[];
    final raw = data['dayPoints'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final key = entry['dateKey'];
        if (key is! String) continue;
        days.add((
          dateKey: key,
          points: (entry['points'] as num?)?.toInt() ?? 0,
          buckets: _intMap(entry['buckets']),
        ));
      }
    }
    if (days.isNotEmpty) service.applyServerWeek(week, days);
    unawaited(service.applyServerStepDays(_intMap(data['stepDays'])));

    final state = data['stateKey'];
    final districtKey = data['districtKey'];
    if (state is String && state.isNotEmpty) {
      final district = districtKey is String && districtKey.isNotEmpty
          ? districtsFor(state).firstWhere(
              (d) => slug(d) == districtKey,
              orElse: () => districtKey,
            )
          : null;
      if (district != null &&
          (service.stateKey != state || service.district != district)) {
        unawaited(
          service.setProfile(
            optIn: service.optIn,
            stateKey: state,
            district: district,
          ),
        );
      }
    }

    return LeaderboardSyncResult(
      joined: data['joined'] != false,
      points: (data['points'] as num?)?.toInt() ?? 0,
      week: week,
      name: data['name'] is String ? data['name'] as String : '',
      stateKey: state is String ? state : null,
      districtKey: districtKey is String ? districtKey : null,
      locationLocked: data['locationLocked'] == true,
    );
  }

  static Map<String, int> _intMap(Object? value) {
    final out = <String, int>{};
    if (value is Map) {
      value.forEach((key, raw) {
        if (key is String && raw is num) out[key] = raw.toInt();
      });
    }
    return out;
  }

  /// Monday..today of the current week, with the stored step total and the
  /// weigh-in flag for each day.
  ///
  /// Every day is sent, not only today: a sync after a weekend the app was
  /// closed still scores those days, and the server keeps the highest figure it
  /// has seen for each one. Steps and weigh-ins are the two facts only the
  /// phone knows — meals, habits and water are re-read from Firestore — so a day
  /// is only listed when it has one of them.
  static List<Map<String, dynamic>> _weekDays(LeaderboardService service) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    // Seeded entries come from the diet profile, not from the user standing on
    // a scale, so they must not buy the weigh-in points.
    final weighIns = WeightStore.instance.entries
        .where((e) => !e.seeded)
        .map((e) => _dayKey(e.date))
        .toSet();
    final days = <Map<String, dynamic>>[];
    for (var i = 0; i < 7; i++) {
      final date = start.add(Duration(days: i));
      if (date.isAfter(now)) break;
      final key = _dayKey(date);
      final steps = service.stepsForDay(key);
      final weighedIn = weighIns.contains(key);
      if (steps <= 0 && !weighedIn) continue;
      days.add({
        'dateKey': key,
        'steps': steps,
        'weighIn': weighedIn,
      });
    }
    return days;
  }

  static String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// A live board: a new snapshot is pushed to every listener as soon as any
  /// entry changes, so a score earned on another phone appears here on its own.
  ///
  /// This is a listen, not a poll. Firing a query every second would cost
  /// ~86,000 reads an hour per open board, would still lag behind the write,
  /// and would drain the battery — Firestore's listener is pushed to instead.
  ///
  /// The caller's own document is watched separately from the top slice, so a
  /// user outside the top [boardLimit] still sees that they are on the board
  /// (rank 100+) rather than "not ranked".
  Stream<LeaderboardBoard> watch({
    required String week,
    required LeaderboardScope scope,
    String? stateKey,
    String? districtKey,
    int limit = boardLimit,
  }) {
    final me = uid;
    if (me == null) {
      return Stream.value(
        const LeaderboardBoard(error: 'Sign in to see rankings.'),
      );
    }
    final entries = _entries(
      week,
      scopeKey(scope, stateKey: stateKey, districtKey: districtKey),
    );

    late StreamController<LeaderboardBoard> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? boardSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? mineSub;

    var boardReady = false;
    var hasOwnEntry = false;
    var rows = const <LeaderboardRow>[];
    int? myRank;
    String? error;
    bool notDeployed = false;

    void emit() {
      if (controller.isClosed || !boardReady) return;
      controller.add(
        LeaderboardBoard(
          rows: rows,
          // -1 is "on the board, below the visible slice".
          myRank: myRank ?? (hasOwnEntry ? -1 : null),
          error: error,
          notDeployed: notDeployed,
        ),
      );
    }

    void fail(Object e) {
      final denied = e is FirebaseException && e.code == 'permission-denied';
      error = denied
          ? 'The leaderboard rules are not deployed on this project yet.'
          : 'Could not load the rankings right now.';
      notDeployed = denied;
      if (e is! FirebaseException) {
        logError('LeaderboardRemote.watch', e);
      }
      if (!boardReady) {
        boardReady = true;
        rows = const [];
      }
      emit();
    }

    controller = StreamController<LeaderboardBoard>(
      onListen: () {
        boardSub = entries
            .orderBy('points', descending: true)
            .limit(limit)
            .snapshots()
            .listen((snapshot) {
              final next = <LeaderboardRow>[];
              int? rank;
              for (var i = 0; i < snapshot.docs.length; i++) {
                final doc = snapshot.docs[i];
                final data = doc.data();
                final name = (data['name'] as String?)?.trim() ?? '';
                if (doc.id == me) rank = i + 1;
                next.add(
                  LeaderboardRow(
                    uid: doc.id,
                    name: name.isEmpty ? 'MacroSnap user' : name,
                    points: (data['points'] as num?)?.toInt() ?? 0,
                    isMe: doc.id == me,
                  ),
                );
              }
              rows = next;
              myRank = rank;
              error = null;
              notDeployed = false;
              boardReady = true;
              emit();
            }, onError: fail);

        mineSub = entries.doc(me).snapshots().listen((doc) {
          hasOwnEntry = doc.exists;
          emit();
        }, onError: fail);
      },
      onCancel: () async {
        await boardSub?.cancel();
        await mineSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Reads one board, highest score first, and finds the caller's rank.
  Future<LeaderboardBoard> fetch({
    required String week,
    required LeaderboardScope scope,
    String? stateKey,
    String? districtKey,
    int limit = boardLimit,
  }) async {
    final me = uid;
    if (me == null) {
      return const LeaderboardBoard(error: 'Sign in to see rankings.');
    }
    try {
      final snapshot = await _entries(
        week,
        scopeKey(scope, stateKey: stateKey, districtKey: districtKey),
      ).orderBy('points', descending: true).limit(limit).get();

      final rows = <LeaderboardRow>[];
      int? myRank;
      for (var i = 0; i < snapshot.docs.length; i++) {
        final doc = snapshot.docs[i];
        final data = doc.data();
        final points = (data['points'] as num?)?.toInt() ?? 0;
        final name = (data['name'] as String?)?.trim() ?? '';
        if (doc.id == me) myRank = i + 1;
        rows.add(
          LeaderboardRow(
            uid: doc.id,
            name: name.isEmpty ? 'MacroSnap user' : name,
            points: points,
            isMe: doc.id == me,
          ),
        );
      }
      if (myRank == null) {
        // Outside the visible slice (or not on this board). Still report an
        // honest position by counting the board's top slice only.
        final mine = await _entries(
          week,
          scopeKey(scope, stateKey: stateKey, districtKey: districtKey),
        ).doc(me).get();
        if (mine.exists) myRank = -1; // has an entry, below the visible slice
      }
      return LeaderboardBoard(rows: rows, myRank: myRank);
    } on FirebaseException catch (e) {
      // permission-denied almost always means firestore.rules has not been
      // deployed to this project yet — say that instead of "something failed".
      final denied = e.code == 'permission-denied';
      return LeaderboardBoard(
        error: denied
            ? 'The leaderboard rules are not deployed on this project yet.'
            : 'Could not load the rankings right now.',
        notDeployed: denied,
      );
    } catch (e, st) {
      logError('LeaderboardRemote.fetch', e, st);
      return const LeaderboardBoard(
        error: 'Could not load the rankings right now.',
      );
    }
  }
}
