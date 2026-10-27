import 'dart:io';

import 'package:flutter/material.dart';

import '../models/meal_record.dart';
import '../services/meal_image_store.dart';

/// The photo a meal was logged from, when there still is one.
///
/// Photos are kept for [MealImageStore.retention] and then deleted, and a
/// manual entry never had one, so "there is no picture" is the ordinary case
/// rather than an error — [fallback] is drawn instead, which is how the meal
/// cards keep their usual icon.
///
/// The 24-hour rule is applied here as well as in the store's sweep, so a
/// session left open past the deadline stops showing the photo even though no
/// prune has run yet. A file the OS removed underneath us falls back too.
class MealPhoto extends StatelessWidget {
  final MealRecord meal;

  /// Square size in logical pixels.
  final double size;

  /// Overrides the drawn width when the slot is wider than it is tall (the
  /// detail view's header), while [size] still sets the height.
  final double? width;

  /// Corner radius; defaults to a rounded-square matching the meal cards.
  final double radius;

  /// Drawn when there is no live photo. A transparent box is the sensible
  /// default for layouts that already put an icon underneath.
  final Widget fallback;

  const MealPhoto({
    super.key,
    required this.meal,
    required this.size,
    this.width,
    this.radius = 16,
    this.fallback = const SizedBox.shrink(),
  });

  @override
  Widget build(BuildContext context) {
    final path = meal.imagePath;
    final stillLive =
        path != null &&
        DateTime.now().difference(meal.date) < MealImageStore.retention;
    if (!stillLive) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(path),
        width: width ?? size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
