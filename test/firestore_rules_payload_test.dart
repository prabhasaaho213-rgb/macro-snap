import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards added after the 1.5.12 audit; companion to firestore_rules_test.dart.
///
/// Static text checks on the rules, for the same reason the other file uses
/// them: a later edit must not silently re-open a hole or re-break a rule.
void main() {
  late String rules;

  setUpAll(() {
    final file = File('firestore.rules');
    expect(file.existsSync(), isTrue);
    rules = file.readAsStringSync();
  });

  /// Body of `match /<path> { ... }`, brace-balanced. The opening brace is the
  /// first one AFTER the path, so placeholder braces are not counted.
  String blockBody(String path) {
    final start = rules.indexOf('match /$path');
    expect(start, isNonNegative, reason: 'match /$path must exist');
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

  group('habitData after a Pro lapse', () {
    test('a write that does not grow the list is allowed', () {
      final body = blockBody('habitData/{uid}');
      expect(
        body,
        contains('allow update: if signedIn() && isOwner(uid)'),
        reason: 'create and update now carry different conditions',
      );
      expect(
        body,
        contains('request.resource.data.habits.size() <= 3'),
        reason: 'a free account still cannot add a fourth habit',
      );
      expect(
        body,
        contains(
          'request.resource.data.habits.size() <= resource.data.habits.size()',
        ),
        reason: 'a lapsed Pro account with six habits keeps syncing its edits',
      );
    });
  });

  group('owner-written payloads are bounded', () {
    test('profile, recent foods and preferences cap the document', () {
      for (final path in [
        'dietProfiles/{uid}',
        'recentFoods/{uid}',
        'userPreferences/{uid}',
      ]) {
        final body = blockBody(path);
        expect(
          body,
          contains('request.resource.data.size() <='),
          reason: '$path must not accept an unbounded document',
        );
        expect(
          body,
          isNot(contains('allow read, write')),
          reason: 'request.resource is null on a read, so the rules are split',
        );
      }
    });

    test('a meal bounds the item breakdown and the serving weight', () {
      expect(rules, contains("(!('items' in d) || (d.items is list"));
      expect(rules, contains('d.items.size() <= 40'));
      expect(rules, contains("(!('servingGrams' in d)"));
    });
  });
}
