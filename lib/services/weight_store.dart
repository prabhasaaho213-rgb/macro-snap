import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_partition.dart';
import 'badge_service.dart';

/// One weigh-in. The date is stored as a calendar day (local midnight) so a
/// day can only ever hold one value — re-weighing updates today's point
/// instead of creating a second one that makes the trend jumpy.
class WeightEntry {
  final DateTime date;
  final double kg;

  /// True when this point was SEEDED from the profile rather than recorded.
  ///
  /// The BMI calculator seeds the profile weight so the trend has a first
  /// point. That point draws a line, but it is not evidence that the user ever
  /// stepped on a scale — so it must not earn "First Weigh-In", and it must
  /// keep not earning it on the next launch, when the badge backfill runs.
  /// Persisted for exactly that reason.
  final bool seeded;

  const WeightEntry({
    required this.date,
    required this.kg,
    this.seeded = false,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'kg': kg,
    if (seeded) 'seeded': true,
  };

  factory WeightEntry.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    final kg = (json['kg'] as num?)?.toDouble();
    if (date == null || kg == null || kg <= 0) {
      throw const FormatException('bad weight entry');
    }
    // Absent means a real entry: everything logged before seeding existed was
    // typed in by the user, so the default must be false.
    return WeightEntry(
      date: date,
      kg: kg,
      seeded: json['seeded'] == true,
    );
  }

  static WeightEntry? tryFromJson(Map<String, dynamic> json) {
    try {
      return WeightEntry.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

/// Direction of travel over a window, for the "+0.4 kg / 30d" style readout.
enum WeightTrend { losing, holding, gaining }

/// The last [points] days of weigh-ins plus what they add up to.
class WeightSummary {
  /// Points in the window, oldest first. Always has at least one entry when
  /// the user has any history at all.
  final List<WeightEntry> points;

  /// Last minus first within the window; null when there is only one point.
  final double? deltaKg;

  const WeightSummary({required this.points, this.deltaKg});

  int get spanDays {
    if (points.length < 2) return 0;
    return points.last.date.difference(points.first.date).inDays;
  }

  /// Anything under 300 g is noise from a scale, not a real change.
  WeightTrend get direction {
    final delta = deltaKg;
    if (delta == null || delta.abs() < 0.3) return WeightTrend.holding;
    return delta > 0 ? WeightTrend.gaining : WeightTrend.losing;
  }
}

/// Chronological weight history, per account.
///
/// Why it exists: a single BMI number says nothing about direction, and the
/// BMI card is on Home where people look daily. This keeps one point per day
/// (capped at a year) so the card and the calculator can draw a trend line.
class WeightStore extends ChangeNotifier {
  static final WeightStore _instance = WeightStore._();
  static WeightStore get instance => _instance;
  WeightStore._();

  static const _prefsKey = 'weight_log';

  /// A year of daily weigh-ins is plenty; older points age out on write.
  static const int maxEntries = 365;

  List<WeightEntry> _entries = [];
  bool _loaded = false;

  /// Oldest first. Unmodifiable so a caller can never corrupt the trend.
  List<WeightEntry> get entries => List.unmodifiable(_entries);

  /// Most recent weigh-in, or null before anything has been recorded.
  double? get latestKg => _entries.isEmpty ? null : _entries.last.kg;

  SharedPreferences? _prefs;

  /// Partition suffix for the signed-in account: guests (no account) get the
  /// empty suffix and keep the plain key, exactly like every other store.
  static String _suffixOf(SharedPreferences prefs) =>
      AccountPartition.suffix(AccountPartition.activeFromPrefs(prefs));

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    try {
      final raw = _prefs!.getString(
        AccountPartition.key(_prefsKey, _suffixOf(_prefs!)),
      );
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          // Parsed per entry: one corrupt row must not throw away the whole
          // year of history.
          _entries =
              decoded
                  .whereType<Map>()
                  .map(
                    (e) =>
                        WeightEntry.tryFromJson(Map<String, dynamic>.from(e)),
                  )
                  .whereType<WeightEntry>()
                  .toList()
                ..sort((a, b) => a.date.compareTo(b.date));
        }
      }
    } catch (_) {
      _entries = [];
    }
    _loaded = true;
    // Announce the load: Home builds as soon as the startup gate opens, so a
    // load finishing late must still reach the UI.
    notifyListeners();
  }

  /// Records a weigh-in for [date] (today by default). A second reading on the
  /// same day replaces the first.
  ///
  /// [awardBadge] is false for a SEED: a value carried over from the profile so
  /// the chart has a first point. Merely opening the BMI calculator is not a
  /// weigh-in, and it should not hand out "First Weigh-In".
  ///
  /// A seed is also stored as seeded, because the badge backfill recomputes
  /// achievements from this history on every launch — a seed that looked like a
  /// recorded weight would hand out the badge one launch later instead of
  /// immediately.
  Future<void> record(
    double kg, {
    DateTime? date,
    bool awardBadge = true,
  }) async {
    if (kg <= 0) return;
    if (!_loaded) await load();

    final day = _startOfDay(date ?? DateTime.now());
    // A real reading replaces a seed on the same day; the flag follows the
    // call, so re-recording a day as a seed (never done in practice) would
    // downgrade it rather than silently keep the badge.
    _entries.removeWhere((e) => _sameDay(e.date, day));
    _entries.add(WeightEntry(date: day, kg: kg, seeded: !awardBadge));
    _entries.sort((a, b) => a.date.compareTo(b.date));
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(_entries.length - maxEntries);
    }
    notifyListeners();
    unawaited(_save());
    // Achievement side effect: one recorded weigh-in earns the badge, whatever
    // the number says. Fire-and-forget so the save is never gated on it.
    if (awardBadge) unawaited(BadgeService.instance.noteWeighIn());
  }

  /// True when the user has ever recorded a weight themselves.
  ///
  /// Seeds do not count: this is what the achievement backfill asks, and a
  /// profile weight copied in by the BMI screen is not a weigh-in.
  bool get hasRealWeighIn => _entries.any((e) => !e.seeded);

  /// The last [days] days of history, oldest first (at least the newest point
  /// when any exists, so callers always have something to show).
  List<WeightEntry> recent(int days) {
    if (_entries.isEmpty) return const [];
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final inWindow = _entries.where((e) => !e.date.isBefore(cutoff)).toList();
    return inWindow.isEmpty ? [_entries.last] : inWindow;
  }

  /// Summary over a window, with the baseline point included so the delta is
  /// measured from the last reading before the window.
  WeightSummary summary({int days = 30}) {
    if (_entries.isEmpty) return const WeightSummary(points: []);
    final cutoff = DateTime.now().subtract(Duration(days: days));
    var points = _entries.where((e) => !e.date.isBefore(cutoff)).toList();
    if (points.isEmpty) return WeightSummary(points: [_entries.last]);
    if (points.length == 1) {
      final before = _entries.lastWhere(
        (e) => e.date.isBefore(points.first.date),
        orElse: () => _entries.first,
      );
      points = [before, ...points];
    }
    return WeightSummary(
      points: points,
      deltaKg: points.last.kg - points.first.kg,
    );
  }

  /// Test hook: forgets everything loaded so the next [load] re-reads prefs.
  @visibleForTesting
  void resetForTest() {
    _entries = [];
    _loaded = false;
    _prefs = null;
  }

  Future<void> _save() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      await prefs.setString(
        AccountPartition.key(_prefsKey, _suffixOf(prefs)),
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving weight log: $e');
    }
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
