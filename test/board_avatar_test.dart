import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/friends_league_service.dart';
import 'package:macro_snap/services/leaderboard_remote.dart';
import 'package:macro_snap/widgets/snap_avatar.dart';

/// The boards show other people's chosen pictures, so the avatar has to survive
/// the trip through the API and the local cache. A row without one must still
/// render (the initial), never break.
void main() {
  test('a league row carries the member avatar', () {
    final row = FriendsLeagueRow.fromJson({
      'uid': 'u1',
      'name': 'Sanjay',
      'points': 120,
      'isMe': false,
      'avatar': 'art:panda',
    });
    expect(row.avatar, 'art:panda');
    expect(SnapAvatars.byStored(row.avatar)?.id, 'panda');
  });

  test('a row written before avatars existed has none, not a broken value', () {
    final row = FriendsLeagueRow.fromJson({
      'uid': 'u2',
      'name': 'Sandhya',
      'points': 80,
      'isMe': false,
    });
    expect(row.avatar, isEmpty);
    expect(SnapAvatars.byStored(row.avatar), isNull);
  });

  test('board rows default to no avatar and accept one', () {
    const plain = LeaderboardRow(uid: 'a', name: 'A', points: 1, isMe: false);
    const withArt = LeaderboardRow(
      uid: 'b',
      name: 'B',
      points: 2,
      isMe: true,
      avatar: 'art:sunglasses-guy',
    );
    expect(plain.avatar, isEmpty);
    expect(SnapAvatars.byStored(withArt.avatar)?.id, 'sunglasses-guy');
  });
}
