import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/models/diet_profile.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/models/meal_record.dart';
import 'package:macro_snap/screens/chat_screen.dart';
import 'package:macro_snap/services/guru_service.dart';
import 'package:macro_snap/services/habit_store.dart';
import 'package:macro_snap/services/meal_store.dart';

/// Guru answers from the user's OWN day: every chat request carries a
/// snapshot built by [GuruService.buildGuruContext], which the backend
/// renders into its system instruction. These tests lock in both halves of
/// that contract — the snapshot contents, and that ChatScreen actually
/// attaches it to the request it sends.
///
/// Zone note (same as home_trial_chat_test): MealStore's load/save wait on
/// the path_provider platform channel, which never resolves inside the
/// testWidgets FakeAsync zone. All store seeding therefore happens in setUp
/// (the real-async zone); the widget tests themselves only pump.
///
/// [DietPlanService] is a singleton that keeps its profile in memory, so the
/// "nothing saved yet" test resets it with load().
MealRecord meal(String id, String name, int kcal, double protein) => MealRecord(
  id: id,
  date: DateTime.now(),
  name: name,
  category: 'Snack',
  calories: kcal,
  protein: protein,
  carbs: 10,
  fats: 2,
  fiber: 1,
  serving: '1 tbsp',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'name': 'Aarav'});
    HabitStore.instance.habits.clear();
    HabitStore.instance.waterGoal = 8;
    await MealStore.instance.reload();
    GuruService.mockSender = null;
  });

  group('buildGuruContext', () {
    test(
      'carries name, today\'s meals, macro totals, habits, water and targets',
      () async {
        await MealStore.instance.add(meal('m1', 'Pumpkin seeds', 559, 30.2));
        await MealStore.instance.add(meal('m2', 'Walnuts', 654, 15.2));

        final habit = Habit(
          id: 'h1',
          name: 'Evening walk',
          emoji: 'W',
          colorValue: 0xFF00CC52,
          createdAt: DateTime.now(),
        );
        await HabitStore.instance.add(habit);
        await HabitStore.instance.completeToday(habit);
        HabitStore.instance.addWater();
        HabitStore.instance.addWater();

        await DietPlanService.instance.save(
          DietProfile(
            weightKg: 70,
            heightCm: 175,
            age: 30,
            gender: Gender.male,
            goal: Goal.loseWeight,
            activity: ActivityLevel.moderate,
            diet: DietPreference.vegetarian,
          ),
        );

        final ctx = await GuruService.buildGuruContext();

        expect(ctx['name'], 'Aarav');
        expect(ctx['goal'], 'Weight Loss');
        expect(ctx['diet'], 'Vegetarian');

        final today = ctx['today'] as Map<String, dynamic>;
        expect(today['calories'], 1213);
        expect(today['protein_g'], 45.4);
        final meals = today['meals'] as List;
        expect(meals.map((m) => m['name']).toSet(), {
          'Pumpkin seeds',
          'Walnuts',
        });

        final habits = ctx['habits'] as Map<String, dynamic>;
        expect(habits['due'], 1);
        expect(habits['completed'], 1);
        expect(habits['names'], ['Evening walk']);

        expect(ctx['water'], {'glasses': 2, 'goal': 8});

        final targets = ctx['targets'] as Map<String, dynamic>;
        final profile = DietPlanService.instance.profile!;
        expect(targets['calories'], profile.targetCalories);
        expect(targets['protein_g'], profile.targetProtein);
      },
    );

    test('never carries the account identifier to the AI provider', () async {
      await MealStore.instance.add(meal('m1', 'Oats', 300, 12));

      final ctx = await GuruService.buildGuruContext();
      expect(ctx.containsKey('phone'), isFalse);
      expect(ctx.containsKey('email'), isFalse);
      expect(ctx.toString().contains('phone'), isFalse);
      expect(ctx.toString().contains('email'), isFalse);
    });

    test('degrades gracefully with nothing logged and no profile', () async {
      // Reset the singleton: earlier tests in this file saved a profile.
      await DietPlanService.instance.load();
      expect(
        DietPlanService.instance.profile,
        isNull,
        reason: 'nothing is readable in tests -> no profile',
      );

      final ctx = await GuruService.buildGuruContext();

      expect(
        ctx.containsKey('goal'),
        isFalse,
        reason: 'no diet profile -> no goal/targets section',
      );
      expect(ctx.containsKey('targets'), isFalse);
      final today = ctx['today'] as Map<String, dynamic>;
      expect(today['calories'], 0);
      expect(today['meals'], isEmpty);
    });
  });

  group('ChatScreen request payload', () {
    setUp(() async {
      // Seeded in the real-async zone (see the zone note at the top).
      await MealStore.instance.add(meal('m1', 'Pumpkin seeds', 559, 30.2));
    });

    testWidgets('sends the personalized snapshot along with the message', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      GuruService.mockSender = (payload) async {
        sent = payload;
        return {'reply': 'You are 559 kcal in today.'};
      };

      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      await tester.enterText(find.byType(TextField), 'How am I doing today?');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(sent, isNotNull, reason: 'the send button must issue a request');
      expect(sent!['message'], 'How am I doing today?');

      final context = sent!['context'] as Map<String, dynamic>;
      final today = context['today'] as Map<String, dynamic>;
      expect(
        today['calories'],
        559,
        reason: 'Guru must see the calories logged today',
      );
      expect(today['meals'], hasLength(1));
      expect((today['meals'] as List).single['name'], 'Pumpkin seeds');
      expect(context['name'], 'Aarav');

      expect(find.text('You are 559 kcal in today.'), findsOneWidget);
    });

    testWidgets('a snapshot with nothing in it still lets the chat through', (
      tester,
    ) async {
      Map<String, dynamic>? sent;
      GuruService.mockSender = (payload) async {
        sent = payload;
        return {'reply': 'ok'};
      };

      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      await tester.enterText(find.byType(TextField), 'protein in paneer?');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(sent, isNotNull);
      expect(sent!['context'], isA<Map<String, dynamic>>());
      expect(find.text('ok'), findsOneWidget);
    });
  });

  // Guru is Pro-only: the backend refuses a free user with 403 pro_required.
  // The screen must turn that into the upgrade path, never a bare error code.
  group('ChatScreen Pro gate', () {
    testWidgets('403 pro_required locks the composer and offers the plans', (
      tester,
    ) async {
      GuruService.mockSender = (_) async =>
          throw const GuruProRequiredException();

      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      // The greeting is there to start with, and the composer is usable.
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'protein in paneer?');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Guru is a Pro feature'),
        findsWidgets,
        reason: 'the user must be told why the chat stopped',
      );
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'the composer is gone so no doomed turn can be sent',
      );
      expect(
        find.text('See plans'),
        findsOneWidget,
        reason: 'the upsell must be one tap away',
      );
      expect(
        find.textContaining('pro_required'),
        findsNothing,
        reason: 'a machine error code must never reach the user',
      );
    });

    testWidgets('a rate-limited reply shows the human message, not the code', (
      tester,
    ) async {
      GuruService.mockSender = (_) async => {
        'error': 'rate_limited',
        'message': 'Too many requests. Please wait a moment and try again.',
      };

      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Too many requests. Please wait a moment and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('rate_limited'), findsNothing);
      // A soft failure must NOT lock the composer — they can retry.
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
