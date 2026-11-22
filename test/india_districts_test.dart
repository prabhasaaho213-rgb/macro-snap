import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/data/india_districts.dart';
import 'package:macro_snap/services/leaderboard_remote.dart';

/// The district picker is the only way onto a district board now, so its data
/// has to hold three things: every state in the picker has districts, no state
/// list is orphaned, and two districts in one state cannot slug to the same
/// board. `LeaderboardRemote.slug` is the path segment, so a collision would
/// merge two districts into one board.
void main() {
  test('every state in the picker has districts', () {
    for (final state in LeaderboardRemote.states) {
      expect(
        LeaderboardRemote.districtsFor(state.key),
        isNotEmpty,
        reason: '${state.name} (${state.key}) has no districts to pick',
      );
    }
  });

  test('no district list is keyed to a state the picker cannot select', () {
    final stateKeys = LeaderboardRemote.states.map((s) => s.key).toSet();
    expect(
      kDistrictsByState.keys.where((k) => !stateKeys.contains(k)),
      isEmpty,
    );
  });

  test('districts in one state map to distinct, valid board ids', () {
    for (final entry in kDistrictsByState.entries) {
      final slugs = entry.value.map(LeaderboardRemote.slug).toList();
      expect(
        slugs.where((slug) => slug.isEmpty),
        isEmpty,
        reason: 'an empty slug in ${entry.key} would file under "unknown"',
      );
      expect(
        slugs.toSet().length,
        slugs.length,
        reason: 'two districts in ${entry.key} share a board id',
      );
      for (final slug in slugs) {
        final scope = LeaderboardRemote.scopeKey(
          LeaderboardScope.district,
          stateKey: entry.key,
          districtKey: slug,
        );
        expect(
          LeaderboardRemote.isValidScope(scope),
          isTrue,
          reason: '$scope must be an acceptable path and delete target',
        );
      }
    }
  });

  test('an unknown or missing state yields an empty picker, not a crash', () {
    expect(LeaderboardRemote.districtsFor(null), isEmpty);
    expect(LeaderboardRemote.districtsFor('atlantis'), isEmpty);
  });

  group('search', () {
    test('matches a fragment, ignoring case and outer spaces', () {
      expect(matchesSearch('Pune', 'pun'), isTrue);
      expect(matchesSearch('Pune', '  PUNE '), isTrue);
      expect(matchesSearch('Pune', 'mumbai'), isFalse);
    });

    test('an empty query keeps the whole list browsable', () {
      expect(matchesSearch('Pune', ''), isTrue);
      expect(matchesSearch('Pune', '   '), isTrue);
    });

    test('finds one district inside a state with dozens', () {
      final matches = kDistrictsByState['uttar-pradesh']!
          .where((d) => matchesSearch(d, 'luck'))
          .toList();
      expect(matches, contains('Lucknow'));
      expect(matches.length, lessThan(5));
    });

    test('every state and district name is findable from its own text', () {
      for (final state in LeaderboardRemote.states) {
        expect(matchesSearch(state.name, state.name.toLowerCase()), isTrue);
        for (final district in LeaderboardRemote.districtsFor(state.key)) {
          expect(
            matchesSearch(district, district.toLowerCase()),
            isTrue,
            reason: '$district must be findable in ${state.name}',
          );
        }
      }
    });
  });
}
