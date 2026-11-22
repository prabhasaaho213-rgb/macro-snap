import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/leaderboard_remote.dart';

/// The parts of the Firestore leaderboard that can be checked without a server:
/// which board documents a user belongs on, which rows a move has to delete,
/// and the week key shared with the local scoring engine.
///
/// The write/delete behaviour itself is a batched Firestore call; these tests
/// pin the inputs to it, which is where the three bugs live — a district change
/// that forgets the old row, a leave that misses a row, and a scope string from
/// local prefs being used as a delete target.
void main() {
  String board(LeaderboardScope scope) => LeaderboardRemote.scopeKey(scope);

  group('district slug', () {
    test('is stable for the same district typed differently', () {
      expect(LeaderboardRemote.slug('Pune'), 'pune');
      expect(LeaderboardRemote.slug('  PUNE '), 'pune');
      expect(LeaderboardRemote.slug('Pune City'), 'pune-city');
      expect(LeaderboardRemote.slug('Pune  City!!'), 'pune-city');
      expect(LeaderboardRemote.slug('Pune City'), LeaderboardRemote.slug('pune city'));
    });

    test('cannot produce an empty or oversized path segment from junk', () {
      expect(LeaderboardRemote.slug('---'), '');
      expect(LeaderboardRemote.slug('x' * 100).length, 40);
    });
  });

  group('week id', () {
    test('uses ISO weeks with a Monday start', () {
      expect(LeaderboardRemote.weekId(DateTime(2026, 11, 22)), '2026-W47');
      expect(LeaderboardRemote.weekId(DateTime(2026, 11, 16)), '2026-W47');
      expect(LeaderboardRemote.weekId(DateTime(2026, 11, 15)), '2026-W46');
      expect(LeaderboardRemote.weekId(DateTime(2026, 1, 1)), '2026-W01');
      expect(LeaderboardRemote.weekId(DateTime(2025, 12, 29)), '2026-W01');
    });

    test('every day of one week maps to the same board', () {
      final monday = DateTime(2026, 11, 16);
      for (var i = 0; i < 7; i++) {
        expect(
          LeaderboardRemote.weekId(monday.add(Duration(days: i))),
          '2026-W47',
        );
      }
      expect(LeaderboardRemote.weekId(monday.add(const Duration(days: 7))), '2026-W48');
    });
  });

  group('board placement', () {
    test('the three scopes are distinct paths', () {
      expect(board(LeaderboardScope.india), 'india');
      expect(
        LeaderboardRemote.scopeKey(
          LeaderboardScope.state,
          stateKey: 'maharashtra',
        ),
        'state_maharashtra',
      );
      expect(
        LeaderboardRemote.scopeKey(
          LeaderboardScope.district,
          stateKey: 'maharashtra',
          districtKey: 'pune',
        ),
        'district_maharashtra_pune',
      );
    });

    test('a user is placed on India, their state and their district', () {
      expect(
        LeaderboardRemote.boardsFor(stateKey: 'maharashtra', district: 'Pune'),
        ['india', 'state_maharashtra', 'district_maharashtra_pune'],
      );
    });
  });

  group('moving district', () {
    final pune = LeaderboardRemote.boardsFor(
      stateKey: 'maharashtra',
      district: 'Pune',
    );

    test('the old district row (and old state) must be deleted', () {
      final bengaluru = LeaderboardRemote.boardsFor(
        stateKey: 'karnataka',
        district: 'Bengaluru',
      );
      final stale = LeaderboardRemote.staleScopes(pune, bengaluru);
      expect(stale, contains('district_maharashtra_pune'));
      expect(stale, contains('state_maharashtra'));
      // India is shared by both areas and must NOT be deleted.
      expect(stale, isNot(contains('india')));
      expect(stale, isNot(contains('district_karnataka_bengaluru')));
      expect(stale.length, 2);
    });

    test('moving within the same state keeps the state row', () {
      final mumbai = LeaderboardRemote.boardsFor(
        stateKey: 'maharashtra',
        district: 'Mumbai',
      );
      expect(LeaderboardRemote.staleScopes(pune, mumbai), [
        'district_maharashtra_pune',
      ]);
    });

    test('no move means nothing is deleted', () {
      expect(LeaderboardRemote.staleScopes(pune, pune), isEmpty);
    });

    test('a corrupt remembered scope is never a delete target', () {
      expect(LeaderboardRemote.isValidScope('india'), isTrue);
      expect(LeaderboardRemote.isValidScope('state_maharashtra'), isTrue);
      expect(
        LeaderboardRemote.isValidScope('district_maharashtra_pune'),
        isTrue,
      );
      expect(LeaderboardRemote.isValidScope('../../evil'), isFalse);
      expect(LeaderboardRemote.isValidScope('meals/abc'), isFalse);
      expect(LeaderboardRemote.isValidScope('district_Maharashtra_Pune'), isFalse);
      expect(
        LeaderboardRemote.staleScopes(
          ['../../evil', 'meals/abc', 'india'],
          ['india'],
        ),
        isEmpty,
      );
    });
  });

  test('leaving targets every row the week wrote, without duplicates', () {
    final scopes = {
      ...LeaderboardRemote.boardsFor(
        stateKey: 'maharashtra',
        district: 'Pune',
      ),
      ...LeaderboardRemote.boardsFor(
        stateKey: 'karnataka',
        district: 'Bengaluru',
      ),
    };
    expect(scopes.length, 5); // india is shared, so 6 entries collapse to 5
    expect(scopes, contains('district_maharashtra_pune'));
    expect(scopes, contains('district_karnataka_bengaluru'));
  });
}
