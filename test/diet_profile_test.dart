import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/models/diet_profile.dart';

void main() {
  test('falls back to safe defaults for invalid persisted enum values', () {
    final profile = DietProfile.fromJson({
      'weightKg': 70,
      'heightCm': 175,
      'age': 28,
      'gender': 'unknown',
      'goal': 'unknown',
      'activity': 'unknown',
      'avatar': '😎',
    });

    expect(profile.gender, Gender.male);
    // Neutral default: a missing goal must never silently become a deficit.
    expect(profile.goal, Goal.maintain);
    expect(profile.activity, ActivityLevel.sedentary);
    // A profile saved before the food preference existed is vegetarian - the
    // plan those users were already being shown.
    expect(profile.diet, DietPreference.vegetarian);
  });

  test('an unknown food preference falls back to vegetarian', () {
    final profile = DietProfile.fromJson({'diet': 'pescatarian'});
    expect(profile.diet, DietPreference.vegetarian);
  });

  test('the food preference survives a save/load round trip', () {
    final original = DietProfile(
      weightKg: 80,
      heightCm: 180,
      age: 30,
      gender: Gender.male,
      goal: Goal.gainMuscle,
      activity: ActivityLevel.active,
      diet: DietPreference.nonVegetarian,
    );

    final restored = DietProfile.fromJson(original.toJson());

    expect(restored.diet, DietPreference.nonVegetarian);
    expect(original.toJson()['diet'], 'nonVegetarian');
  });

  group('protein target', () {
    DietProfile profile(double kg, Goal goal) => DietProfile(
      weightKg: kg,
      heightCm: 175,
      age: 30,
      gender: Gender.male,
      goal: goal,
      activity: ActivityLevel.moderate,
    );

    test('scales per kg, by goal', () {
      expect(profile(70, Goal.loseWeight).targetProtein, 70 * 1.8);
      expect(profile(70, Goal.maintain).targetProtein, 70 * 1.6);
      expect(profile(70, Goal.gainMuscle).targetProtein, 70 * 2.2);
    });

    test('is capped, however heavy the user is', () {
      // 2.2 g/kg on 110 kg used to be 242 g a day.
      expect(
        profile(110, Goal.gainMuscle).targetProtein,
        DietProfile.maxProteinGrams,
      );
      expect(profile(150, Goal.loseWeight).targetProtein, 180);
    });

    test('carbs never go negative under the cap', () {
      // A heavy, sedentary, female profile on the loss floor: the cap has to
      // leave something for carbohydrate.
      final p = DietProfile(
        weightKg: 150,
        heightCm: 150,
        age: 60,
        gender: Gender.female,
        goal: Goal.loseWeight,
        activity: ActivityLevel.sedentary,
      );
      expect(p.targetCarbs, greaterThan(0));
    });
  });
}
