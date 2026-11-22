import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/india_districts.dart';
import 'crash_reporting.dart';
import 'leaderboard_service.dart';

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

/// Firestore-first leaderboard: one weekly document per user per scope, read
/// back with an ordered query.
///
/// Path: `leaderboard/{week}/scopes/{scopeKey}/entries/{uid}`
///
/// The scope lives in the PATH so each board is a plain collection with a
/// single `orderBy('points')` — no composite index to deploy, no cross-board
/// filtering. Writes go out as one batch so a user is on (or off) all three
/// boards together.
///
/// What this is NOT: verified. The phone computes its own points and says so.
/// See the note on `firestore.rules` — anyone running a modified client can
/// claim any score up to the rule's cap, or claim a district they are not in.
/// A server-side scoring endpoint that recomputes from event documents is the
/// only thing that fixes that, and it does not exist yet.
class LeaderboardRemote {
  LeaderboardRemote._();
  static final LeaderboardRemote instance = LeaderboardRemote._();

  /// Points ceiling the rules enforce on a single week document.
  static const int maxWeekPoints = 1000;

  /// Board size the app will read back.
  static const int boardLimit = 50;

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

  /// Publishes [points] for this week to the India, state and district boards.
  ///
  /// [previousScopes] are the boards written earlier this week (remembered by
  /// the caller): any the current area no longer covers are deleted in the same
  /// batch, so a district change cannot leave two rows behind.
  ///
  /// Zero points writes no row — but the cleanup still runs, because a user can
  /// move district after their score dropped back to zero, and then the old row
  /// must go even though there is nothing new to write.
  Future<bool> publish({
    required String week,
    required int points,
    required String name,
    required String stateKey,
    required String district,
    List<String> previousScopes = const [],
  }) async {
    final user = uid;
    if (user == null) return false;
    final districtKey = slug(district);
    final current = boardsFor(stateKey: stateKey, district: district);
    final writes = points > 0;
    // A score that fell back to zero takes its rows down rather than leaving a
    // stale higher number on the board for the rest of the week.
    final deletes = writes
        ? staleScopes(previousScopes, current)
        : [
            for (final scope in previousScopes)
              if (isValidScope(scope)) scope,
          ];
    if (!writes && deletes.isEmpty) return false;

    try {
      final db = FirebaseFirestore.instance;
      final weekRef = db.collection('leaderboard').doc(week);
      final batch = db.batch();

      for (final scope in writes ? current : const <String>[]) {
        batch.set(
          weekRef
              .collection('scopes')
              .doc(scope)
              .collection('entries')
              .doc(user),
          {
            'uid': user,
            'name': name,
            'week': week,
            'scope': scope,
            'points': points.clamp(0, maxWeekPoints),
            'stateKey': stateKey,
            'district': district,
            'districtKey': districtKey,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      // Remove boards this account no longer belongs on: a district it moved
      // away from, or every row when there is no score to publish.
      for (final stale in deletes) {
        batch.delete(
          weekRef
              .collection('scopes')
              .doc(stale)
              .collection('entries')
              .doc(user),
        );
      }
      await batch.commit();
      return true;
    } catch (e, st) {
      logError('LeaderboardRemote.publish', e, st);
      return false;
    }
  }

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

  /// Brings this device's rows in line with the saved profile: publishes the
  /// week's points when joined, retries a leave that never reached the server,
  /// and clears rows from an area the user has moved away from.
  ///
  /// Called at launch and from the Rank page — one implementation for both, so
  /// the two paths cannot disagree about which boards a user is on.
  Future<bool> publishIfJoined({required int points}) async {
    final service = LeaderboardService.instance;
    if (!canJoin) return false;

    // A leave that failed while offline is retried here. The rows are only
    // forgotten once they are actually gone, so "Leave" cannot silently leave
    // the user on the board.
    final pending = service.pendingLeave;
    if (pending != null) {
      final gone = await removeScopes(
        week: pending.week,
        scopes: pending.scopes,
      );
      if (!gone) return false;
      await service.clearPendingLeave();
      await service.clearPublished(pending.week);
    }

    if (!service.optIn || !service.hasLocation) return false;

    final week = weekId();
    final stateKey = service.stateKey!;
    final district = service.district!;
    final ok = await publish(
      week: week,
      points: points,
      name: await publicName(),
      stateKey: stateKey,
      district: district,
      previousScopes: service.publishedScopes(week),
    );
    if (ok) {
      // Remember exactly what exists now: the current boards when a score was
      // written, nothing when the write was only a cleanup.
      await service.rememberPublished(
        week,
        points > 0
            ? boardsFor(stateKey: stateKey, district: district)
            : const [],
      );
    }
    return ok;
  }

  /// A live board: a new snapshot is pushed to every listener as soon as any
  /// entry changes, so a score earned on another phone appears here on its own.
  ///
  /// This is a listen, not a poll. Firing a query every second would cost
  /// ~86,000 reads an hour per open board, would still lag behind the write,
  /// and would drain the battery — Firestore's listener is pushed to instead.
  ///
  /// The caller's own document is watched separately from the top slice, so a
  /// user outside the top 50 still sees that they are on the board (rank 50+)
  /// rather than "not ranked".
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

  /// Deletes this account's row from every board in [scopes] for [week].
  ///
  /// The caller passes every board this account wrote this week, not just the
  /// current area's, so leaving also removes a district row left behind by a
  /// move. Leaving must actually take the rows down; otherwise "Leave" would
  /// only hide them on this phone.
  Future<bool> removeScopes({
    required String week,
    required List<String> scopes,
  }) async {
    final user = uid;
    if (user == null) return false;
    final targets = {
      for (final scope in scopes)
        if (isValidScope(scope)) scope,
    };
    if (targets.isEmpty) return false;
    try {
      final db = FirebaseFirestore.instance;
      final weekRef = db.collection('leaderboard').doc(week);
      final batch = db.batch();
      for (final scope in targets) {
        batch.delete(
          weekRef
              .collection('scopes')
              .doc(scope)
              .collection('entries')
              .doc(user),
        );
      }
      await batch.commit();
      return true;
    } catch (e, st) {
      logError('LeaderboardRemote.removeScopes', e, st);
      return false;
    }
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
