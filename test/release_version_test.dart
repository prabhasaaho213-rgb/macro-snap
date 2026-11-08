import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/updates_screen.dart';

/// Guards the one version string that is typed by hand.
///
/// `pubspec.yaml` drives the versionCode/versionName the release build stamps,
/// while [UpdatesScreen.latestVersion] drives the "What's New" entry and the
/// dot Settings puts beside it. Bumping only one of them made the app announce
/// the previous release (and left the dot off); this turns that into a failing
/// test instead of a release-day surprise.
void main() {
  test("the What's New version matches pubspec.yaml", () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      UpdatesScreen.latestVersion,
      match!.group(1),
      reason: 'bump UpdatesScreen.latestVersion with every release',
    );
  });
}
