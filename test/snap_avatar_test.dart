import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/widgets/snap_avatar.dart';

/// The avatar id is persisted with the diet profile (and synced to the cloud),
/// so an id that stops resolving leaves a user with a blank or wrong face.
void main() {
  test('every avatar id is unique and round-trips through its stored value', () {
    final ids = SnapAvatars.all.map((style) => style.id).toSet();
    expect(ids.length, SnapAvatars.all.length, reason: 'ids must be unique');

    for (final style in SnapAvatars.all) {
      final stored = SnapAvatars.encode(style.id);
      expect(stored, 'art:${style.id}');
      expect(SnapAvatars.byStored(stored)?.id, style.id);
    }
  });

  test('every avatar points at a bundled image of its own', () {
    // A missing or shared file means a user picks a picture that renders as
    // the error fallback, or two ids that look identical.
    final assets = SnapAvatars.all.map((style) => style.asset).toSet();
    expect(assets.length, SnapAvatars.all.length, reason: 'assets must be unique');
    for (final style in SnapAvatars.all) {
      expect(style.asset, startsWith('assets/images/avatars/'));
      expect(
        File(style.asset).existsSync(),
        isTrue,
        reason: 'missing ${style.asset}',
      );
    }
  });

  test('the set is the 20 supplied avatars, in pack order', () {
    expect(SnapAvatars.all.length, 20);
    expect(SnapAvatars.all.first.id, 'cool-guy');
    expect(SnapAvatars.all.last.id, 'cool-cat');
  });

  test('a legacy emoji or unknown id is not treated as an illustration', () {
    expect(SnapAvatars.byStored('😎'), isNull);
    expect(SnapAvatars.byStored(null), isNull);
    expect(SnapAvatars.byStored(''), isNull);
    // A value written by a newer build must fall back, not crash.
    expect(SnapAvatars.byStored('art:not-in-this-build'), isNull);
  });
}
