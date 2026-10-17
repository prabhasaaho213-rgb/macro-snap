import 'dart:math';
import 'package:flutter/material.dart';

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String weekdayLabel(int weekday) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return labels[(weekday - 1).clamp(0, 6)];
}

class Habit {
  /// Default habit color — the brand burnt-orange. The old default was the
  /// retired neon green (0xFF00FF66) from the pre-redesign palette, which
  /// no longer exists anywhere in the app's theme.
  static const int defaultColorValue = 0xFFF4511E;

  final String id;
  String name;
  String emoji;
  int colorValue;
  String frequency;
  List<String> completedDates;
  List<String> skippedDates;
  bool paused;
  bool streakProtection;
  bool reminderEnabled;
  int reminderHour;
  int reminderMinute;
  int weeklyDay;
  int order;
  DateTime createdAt;

  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    this.frequency = 'Daily',
    List<String>? completedDates,
    List<String>? skippedDates,
    this.paused = false,
    this.streakProtection = false,
    this.reminderEnabled = false,
    this.reminderHour = 20,
    this.reminderMinute = 0,
    int? weeklyDay,
    DateTime? createdAt,
    this.order = 0,
  })  : completedDates = completedDates ?? [],
        skippedDates = skippedDates ?? [],
        weeklyDay = weeklyDay ?? (createdAt ?? DateTime.now()).weekday,
        createdAt = createdAt ?? DateTime.now();

  Color get color => Color(colorValue);

  bool isCompleted(DateTime d) => completedDates.contains(dateKey(d));
  bool isSkipped(DateTime d) => skippedDates.contains(dateKey(d));

  bool isDueOn(DateTime d) {
    switch (frequency) {
      case 'Weekdays':
        return d.weekday <= DateTime.friday;
      case 'Weekly':
        return d.weekday == weeklyDay;
      default:
        return true;
    }
  }

  void toggle(DateTime d) {
    final key = dateKey(d);
    if (completedDates.contains(key)) {
      completedDates.remove(key);
    } else {
      completedDates.add(key);
      skippedDates.remove(key);
    }
  }

  void toggleSkip(DateTime d) {
    final key = dateKey(d);
    if (skippedDates.contains(key)) {
      skippedDates.remove(key);
    } else {
      skippedDates.add(key);
      completedDates.remove(key);
    }
  }

  int currentStreak([DateTime? reference]) {
    final ref = dayOnly(reference ?? DateTime.now());
    var d = ref;

    // If today is due but NOT completed (still pending), count from yesterday
    if (isDueOn(ref) && !isCompleted(ref) && !(streakProtection && isSkipped(ref))) {
      d = ref.subtract(const Duration(days: 1));
    }

    var count = 0;
    while (true) {
      if (!isDueOn(d)) {
        d = d.subtract(const Duration(days: 1));
        continue;
      }
      final valid = isCompleted(d) || (streakProtection && isSkipped(d));
      if (!valid) break;
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }

  int bestStreak() {
    final validDates = <DateTime>{
      ...completedDates.map(DateTime.parse).map(dayOnly),
      if (streakProtection) ...skippedDates.map(DateTime.parse).map(dayOnly),
    };

    if (validDates.isEmpty) return 0;

    final sorted = validDates.toList()..sort();
    var cursor = sorted.first;
    final end = sorted.last;
    var run = 0;
    var best = 0;

    while (!cursor.isAfter(end)) {
      if (isDueOn(cursor)) {
        if (validDates.contains(cursor)) {
          run++;
          best = max(best, run);
        } else {
          run = 0;
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return best;
  }

  double completionRate({int days = 30}) {
    final now = dayOnly(DateTime.now());
    var due = 0;
    var done = 0;
    for (var i = 0; i < days; i++) {
      final d = now.subtract(Duration(days: i));
      if (!isDueOn(d)) continue;
      due++;
      if (isCompleted(d)) done++;
    }
    return due == 0 ? 0 : done / due;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'colorValue': colorValue,
        'frequency': frequency,
        'completedDates': completedDates,
        'skippedDates': skippedDates,
        'paused': paused,
        'streakProtection': streakProtection,
        'reminderEnabled': reminderEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'weeklyDay': weeklyDay,
        'order': order,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Parses one habit, returning null instead of throwing when the entry is
  /// malformed. One corrupt row must not cost the user every other habit.
  static Habit? tryFromJson(Map<String, dynamic> j) {
    try {
      return Habit.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'] as String,
        name: j['name'] as String,
        emoji: j['emoji'] as String? ?? '✨',
        colorValue: j['colorValue'] as int? ?? defaultColorValue,
        frequency: j['frequency'] as String? ?? 'Daily',
        completedDates: List<String>.from(j['completedDates'] ?? const []),
        skippedDates: List<String>.from(j['skippedDates'] ?? const []),
        paused: j['paused'] as bool? ?? false,
        streakProtection: j['streakProtection'] as bool? ?? false,
        reminderEnabled: j['reminderEnabled'] as bool? ?? false,
        reminderHour: j['reminderHour'] as int? ?? 20,
        reminderMinute: j['reminderMinute'] as int? ?? 0,
        weeklyDay: j['weeklyDay'] as int? ??
            (DateTime.tryParse(j['createdAt'] as String? ?? '')?.weekday ?? 1),
        order: j['order'] as int? ?? 0,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
