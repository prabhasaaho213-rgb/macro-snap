import 'package:flutter/material.dart';

/// What an achievement is for. Every kind here rewards *showing up* — logging a
/// meal, stepping on the scale, keeping a streak alive — never a weight, a
/// body measurement or a calorie deficit. A badge you can only earn by losing
/// kilos would make the app feel like it is scoring your body.
enum BadgeKind { meals, weighIn, streak }

/// One achievement. The starter set is deliberately small and reachable in the
/// first week, because a badge board that starts empty and unreachable is worse
/// than no badge board at all.
@immutable
class AppBadge {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final BadgeKind kind;

  const AppBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.kind,
  });

  static const firstBite = AppBadge(
    id: 'first_bite',
    title: 'First Bite',
    description: 'Log your first meal',
    icon: Icons.restaurant_rounded,
    kind: BadgeKind.meals,
  );

  static const tenPlates = AppBadge(
    id: 'ten_plates',
    title: 'Ten Plates',
    description: 'Log 10 meals',
    icon: Icons.local_dining_rounded,
    kind: BadgeKind.meals,
  );

  static const firstWeighIn = AppBadge(
    id: 'first_weigh_in',
    title: 'First Weigh-In',
    description: 'Record a weight once — the number does not matter',
    icon: Icons.monitor_weight_outlined,
    kind: BadgeKind.weighIn,
  );

  static const weekWarrior = AppBadge(
    id: 'week_warrior',
    title: 'Week Warrior',
    description: 'Hit your macro targets 7 days in a row',
    icon: Icons.local_fire_department_rounded,
    kind: BadgeKind.streak,
  );

  static const fortnightFlame = AppBadge(
    id: 'fortnight_flame',
    title: 'Fortnight Flame',
    description: 'Hit your macro targets 14 days in a row',
    icon: Icons.whatshot_rounded,
    kind: BadgeKind.streak,
  );

  /// Every badge that exists, in the order the board shows them.
  static const List<AppBadge> all = [
    firstBite,
    tenPlates,
    firstWeighIn,
    weekWarrior,
    fortnightFlame,
  ];

  /// Resolves a stored id. Unknown ids (a badge removed in a later version)
  /// return null so a stale prefs entry can never crash the board.
  static AppBadge? byId(String id) {
    for (final badge in all) {
      if (badge.id == id) return badge;
    }
    return null;
  }
}
