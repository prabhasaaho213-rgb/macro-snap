import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/screens/home_screen.dart';
import 'package:macro_snap/services/meal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Three things a new/low-data user meets on Home: what to do when nothing is
/// logged, the moment their first meal lands, and getting a mis-deleted meal
/// back.
MealRecord _meal({String id = 'm1', String name = 'Paneer Bowl'}) => MealRecord(
  id: id,
  date: DateTime.now(),
  name: name,
  category: '',
  calories: 420,
  protein: 24,
  carbs: 38,
  fats: 18,
  fiber: 6,
  serving: '1 bowl',
);

Future<void> pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 1300));
}

/// Home is a lazy sliver list, so the meals section is only built once it is
/// on screen — scroll to it before looking for anything in it.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 80,
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MealStore.instance.reload();
  });

  testWidgets('an empty Home offers the scan instead of hiding the section', (
    tester,
  ) async {
    await pumpHome(tester);
    await scrollTo(tester, find.text('Nothing logged yet today'));

    expect(tester.takeException(), isNull);
    expect(find.text('Nothing logged yet today'), findsOneWidget);
    expect(find.text('Scan your first meal'), findsOneWidget);
  });

  testWidgets('the first meal of the day is celebrated once', (tester) async {
    await pumpHome(tester);
    await scrollTo(tester, find.text('Nothing logged yet today'));

    // `add` writes to disk, and path_provider never answers under flutter_test,
    // so the future is left unawaited — the in-memory store is updated first.
    unawaited(MealStore.instance.add(_meal()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('First meal logged today'),
      findsOneWidget,
      reason: '0 → 1 meal is the app\'s core moment',
    );

    // Let the confetti overlay and the snackbar finish so no timer leaks.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 4));

    // A second meal is not "the first" any more.
    unawaited(MealStore.instance.add(_meal(id: 'm2', name: 'Dal')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('First meal logged today'), findsNothing);
  });

  testWidgets('deleting a meal can be undone', (tester) async {
    unawaited(MealStore.instance.add(_meal()));
    await pumpHome(tester);
    await scrollTo(tester, find.text('Paneer Bowl'));

    expect(find.text('Paneer Bowl'), findsWidgets);

    // The bolt button on the meal card asks for confirmation.
    await tester.tap(find.byIcon(Icons.bolt_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(MealStore.instance.todayMeals, isEmpty);
    expect(find.text('Removed Paneer Bowl'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      MealStore.instance.todayMeals.length,
      1,
      reason: 'undo restores the deleted record',
    );
    expect(find.text('Paneer Bowl'), findsWidgets);
  });
}
