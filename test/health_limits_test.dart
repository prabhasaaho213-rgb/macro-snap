import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/bmi.dart';
import 'package:macro_snap/models/diet_profile.dart';
import 'package:macro_snap/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Health-safety limits: these numbers are the difference between a diet and
/// a crash diet, so every one of them is pinned here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('calorie floor', () {
    DietProfile profile({
      required double kg,
      required double cm,
      required int age,
      required Gender gender,
      required Goal goal,
      ActivityLevel activity = ActivityLevel.sedentary,
    }) => DietProfile(
      weightKg: kg,
      heightCm: cm,
      age: age,
      gender: gender,
      goal: goal,
      activity: activity,
    );

    test('a small woman on a deficit is floored at 1200 kcal', () {
      // The reported case: 45 kg, 150 cm, 25, sedentary, weight loss.
      // TDEE − 500 used to land on 822 kcal/day.
      final p = profile(
        kg: 45,
        cm: 150,
        age: 25,
        gender: Gender.female,
        goal: Goal.loseWeight,
      );
      expect(p.targetCalories, greaterThanOrEqualTo(1200));
      expect(p.targetCalories, greaterThanOrEqualTo(p.bmr.round()));
      expect(p.targetCalories, lessThan(822 + 500), reason: 'still a deficit');
    });

    test('a small man is floored at 1500 kcal', () {
      final p = profile(
        kg: 55,
        cm: 160,
        age: 30,
        gender: Gender.male,
        goal: Goal.loseWeight,
      );
      expect(p.targetCalories, greaterThanOrEqualTo(1500));
      expect(p.targetCalories, greaterThanOrEqualTo(p.bmr.round()));
    });

    test('a larger body still gets a real deficit, just not below BMR', () {
      final p = profile(
        kg: 85,
        cm: 175,
        age: 30,
        gender: Gender.male,
        goal: Goal.loseWeight,
      );
      // For a sedentary profile TDEE − 500 can sit under BMR; the floor keeps
      // the target at BMR, which is still a deficit against TDEE.
      expect(p.targetCalories, greaterThanOrEqualTo(p.bmr.round()));
      expect(p.targetCalories, lessThan(p.tdee.round()));
    });

    test('underweight is detected from the profile', () {
      expect(
        profile(
          kg: 40,
          cm: 150,
          age: 25,
          gender: Gender.female,
          goal: Goal.maintain,
        ).isUnderweight,
        isTrue,
      );
      expect(
        profile(
          kg: 60,
          cm: 165,
          age: 25,
          gender: Gender.female,
          goal: Goal.maintain,
        ).isUnderweight,
        isFalse,
      );
    });
  });

  group('BMI display agrees with its band', () {
    test('24.97 prints 25.0 and is labelled Overweight', () {
      // The exact mismatch a user could see: 60 kg at 155 cm.
      final raw = BmiCalculator.value(weightKg: 60, heightCm: 155)!;
      expect(raw, closeTo(24.97, 0.01));

      final shown = BmiCalculator.displayValue(raw);
      expect(shown, 25.0);
      // The label follows the printed number, not the hidden decimals.
      expect(BmiCalculator.categoryFor(shown), BmiCategory.overweight);
      expect(BmiCalculator.categoryFor(raw), BmiCategory.normal);
    });

    test('rounding never moves a value across a band it is not in', () {
      for (var bmi = 13.0; bmi <= 42.0; bmi += 0.01) {
        final shown = BmiCalculator.displayValue(bmi);
        final shownLabel = BmiCalculator.categoryFor(shown).rangeLabel;
        // The printed one-decimal value must itself fall inside the label it
        // is given — that is the invariant the legend promises.
        final category = BmiCalculator.categoryFor(shown);
        expect(
          shown >= category.min && shown < category.max,
          isTrue,
          reason: '$shown labelled ${category.label} ($shownLabel)',
        );
      }
    });
  });

  group('profile defaults', () {
    test('a profile with no saved goal defaults to maintain, not lose', () {
      final p = DietProfile.fromJson({
        'weightKg': 70.0,
        'heightCm': 170.0,
        'age': 30,
        'gender': 'male',
        'activity': 'sedentary',
        'diet': 'vegetarian',
      });
      expect(p.goal, Goal.maintain);
    });
  });

  group('subscription expiry', () {
    test(
      'a referral pro_until window that ends while the app is open stops '
      'reporting Pro',
      () async {
        // Trials are gone; the only remaining timed Pro window is a referral
        // reward (pro_until). It is evaluated live so an expired window cannot
        // keep showing Pro until the next restart.
        final end = DateTime.now().add(const Duration(days: 2));
        SharedPreferences.setMockInitialValues({
          'email': 'user@example.com',
          'subscribed': true,
          'subscribed_at': DateTime.now().toIso8601String(),
          'pro_until': end.toIso8601String(),
        });
        await SubscriptionService.instance.load();

        expect(
          SubscriptionService.instance.isSubscribedAt(
            DateTime.now().add(const Duration(hours: 1)),
          ),
          isTrue,
          reason: 'referral window still running',
        );
        expect(
          SubscriptionService.instance.isSubscribedAt(
            end.add(const Duration(minutes: 1)),
          ),
          isFalse,
          reason: 'expiry is evaluated live, not only inside load()',
        );
      },
    );
  });
}
