import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/friends_league_service.dart';

/// The board is rendered straight from this payload, so a missing or mistyped
/// field must degrade to a safe label rather than throw in the list.
void main() {
  test('a league parses its rows, rank and owner flag', () {
    final league = FriendsLeague.fromJson({
      'id': 'abc123',
      'name': '  Gym Buddies ',
      'code': 'ABC123',
      'ownerUid': 'u1',
      'isOwner': true,
      'memberCount': 2,
      'week': '2026-W48',
      'points': 40,
      'rank': 1,
      'rows': [
        {'uid': 'u1', 'name': 'Asha', 'points': 40, 'isMe': true},
        {'uid': 'u2', 'name': '   ', 'points': 0, 'isMe': false},
      ],
    });

    expect(league.id, 'abc123');
    expect(league.name, 'Gym Buddies');
    expect(league.code, 'ABC123');
    expect(league.isOwner, isTrue);
    expect(league.rank, 1);
    expect(league.points, 40);
    expect(league.rows, hasLength(2));
    expect(league.rows.first.isMe, isTrue);
    expect(league.rows.first.points, 40);
    expect(
      league.rows.last.name,
      'MacroSnap user',
      reason: 'a blank name must not render as an empty row',
    );
  });

  test('a league with no score yet is unranked, not rank zero', () {
    final league = FriendsLeague.fromJson({
      'id': 'abc123',
      'name': 'Friends league',
      'memberCount': 1,
      'week': '2026-W48',
      'rows': [],
    });

    expect(league.rank, isNull);
    expect(league.rows, isEmpty);
    expect(league.code, '');
    expect(league.isOwner, isFalse);
  });
}
