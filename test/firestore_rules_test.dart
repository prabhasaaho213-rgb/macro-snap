import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guards on firestore.rules.
///
/// These lock the security-critical shape of the rules so a later edit cannot
/// silently re-open a client-side write path:
///
///   - users/{uid} is READ-ONLY for clients (the app only reads it; every
///     field is an entitlement written by the backend's Admin SDK), so a user
///     can never set `subscribed: true` on their own document;
///   - meals/{mealId} must match the caller's uid on UPDATE as well as CREATE,
///     so a meal can never be moved to another account;
///   - money/entitlement records are never client-writable.
///
/// NOTE: this is a static check on the rules text. Proving the behaviour
/// end-to-end needs the Firestore emulator
/// (`firebase emulators:exec --only firestore 'npm test'` with
/// @firebase/rules-unit-testing) — see docs in the repo for that run.
void main() {
  late String rules;

  setUpAll(() {
    final file = File('firestore.rules');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'firestore.rules must live at the project root',
    );
    rules = file.readAsStringSync();
  });

  /// Returns the body of `match /<path> { ... }` (brace-balanced), or fails.
  /// The opening brace is the first `{` AFTER the path — the path itself may
  /// contain placeholders like `{uid}`, whose braces must not be counted.
  String blockBody(String path) {
    final start = rules.indexOf('match /$path');
    expect(
      start,
      isNonNegative,
      reason: 'match /$path must exist in the rules',
    );
    final open = rules.indexOf('{', start + 'match /$path'.length);
    var depth = 0;
    for (var i = open; i < rules.length; i++) {
      if (rules[i] == '{') depth++;
      if (rules[i] == '}') {
        depth--;
        if (depth == 0) return rules.substring(open, i + 1);
      }
    }
    fail('unbalanced braces for match /$path');
  }

  group('users/{uid}', () {
    test('is read-only for clients — no client can grant itself Pro', () {
      final users = blockBody('users/{uid}');

      expect(users, contains('allow read: if signedIn() && isOwner(uid);'));
      expect(users, contains('allow write: if false;'));
      expect(
        users,
        isNot(contains('allow read, write')),
        reason: 'the old read+write rule let a user set subscribed: true',
      );
      expect(
        users,
        isNot(contains('allow create')),
        reason: 'clients must never create their own user doc',
      );
      expect(
        users,
        isNot(contains('allow update')),
        reason: 'clients must never update their own user doc',
      );
    });
  });

  group('meals/{mealId}', () {
    test('create requires the caller as owner', () {
      final meals = blockBody('meals/{mealId}').replaceAll('\r\n', '\n');
      expect(meals, contains('allow create: if signedIn() && validMeal();'));
      // The ownership half of validMeal() must still be there.
      expect(
        rules,
        contains('d.uid == request.auth.uid'),
        reason: 'a meal may only be written as yourself',
      );
    });

    test(
      'update re-checks the uid on BOTH copies, so a meal cannot be moved',
      () {
        final meals = blockBody('meals/{mealId}');
        expect(meals, contains('allow update: if signedIn()'));
        expect(
          meals,
          contains('&& resource.data.uid == request.auth.uid'),
          reason: 'you must own the stored meal',
        );
        expect(
          meals,
          contains('validMeal()'),
          reason: 'and the new payload must still validate',
        );
        expect(
          meals,
          isNot(contains('allow read, update, delete')),
          reason: 'update needs its own, stricter rule',
        );
      },
    );

    test('the payload is bounded — no giant or negative meal docs', () {
      final meals = rules;
      expect(meals, contains('d.name.size() <= 80'));
      expect(meals, contains('d.calories >= 0'));
      expect(
        meals,
        contains('d.size() <= 20'),
        reason: 'field count is capped, so a doc cannot be padded',
      );
    });
  });

  group('server-write-only records', () {
    for (final path in [
      'subscriptions/{subId}',
      'payments/{id}',
      'userIndex/{identifier}',
    ]) {
      test('$path is never client-writable', () {
        final body = blockBody(path);
        expect(
          body,
          contains('allow write: if false;'),
          reason: 'only the Admin SDK may write $path',
        );
      });
    }

    test(
      'referrals/{code} can only be created as yourself and never edited',
      () {
        final referrals = blockBody('referrals/{code}');
        expect(
          referrals,
          contains('request.resource.data.uid == request.auth.uid'),
          reason: 'a user may only publish their OWN referral code',
        );
        expect(referrals, contains('allow update, delete: if false;'));
      },
    );

    test('referrals/{code} is not readable by other signed-in users', () {
      final referrals = blockBody('referrals/{code}');
      expect(
        referrals,
        isNot(contains('allow read: if signedIn();')),
        reason: 'the old rule exposed every user\'s referral document',
      );
      expect(
        referrals,
        contains('resource.data.uid == request.auth.uid'),
        reason: 'reads must be limited to your own code',
      );
    });
  });

  test('owner-only user data is still owner-only', () {
    for (final path in [
      'habitData/{uid}',
      'dietProfiles/{uid}',
      'recentFoods/{uid}',
      'userPreferences/{uid}',
    ]) {
      expect(blockBody(path), contains('signedIn() && isOwner(uid)'));
    }
  });
}
