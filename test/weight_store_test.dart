import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/weight_store.dart';
import 'package:macro_snap/widgets/weight_trend_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Weight history is a user record: a lost day, a duplicated reading or a
/// trend that pointed the wrong way would all look like plausible numbers on
/// screen. These tests pin the one-point-per-day rule, ordering, persistence
/// and the delta the card reports.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WeightStore.instance.resetForTest();
    await WeightStore.instance.load();
  });

  test('a second reading on the same day replaces the first', () async {
    final day = DateTime(2026, 10, 21);
    await WeightStore.instance.record(70, date: day);
    await WeightStore.instance.record(71.5, date: day);

    expect(WeightStore.instance.entries.length, 1);
    expect(WeightStore.instance.latestKg, 71.5);
  });

  test('entries stay chronological whatever order they arrive in', () async {
    final today = DateTime.now();
    await WeightStore.instance.record(70, date: today);
    await WeightStore.instance.record(
      72,
      date: today.subtract(const Duration(days: 20)),
    );
    await WeightStore.instance.record(
      71,
      date: today.subtract(const Duration(days: 10)),
    );

    final entries = WeightStore.instance.entries;
    expect(entries.length, 3);
    for (var i = 1; i < entries.length; i++) {
      expect(
        entries[i].date.isAfter(entries[i - 1].date),
        isTrue,
        reason: 'history must be oldest-first for the trend line',
      );
    }
  });

  test('summary measures first-to-last over the window', () async {
    final today = DateTime.now();
    await WeightStore.instance.record(
      72,
      date: today.subtract(const Duration(days: 20)),
    );
    await WeightStore.instance.record(
      71,
      date: today.subtract(const Duration(days: 10)),
    );
    await WeightStore.instance.record(70, date: today);

    final summary = WeightStore.instance.summary(days: 30);
    expect(summary.points.length, 3);
    expect(summary.deltaKg, closeTo(-2.0, 0.001));
    expect(summary.direction, WeightTrend.losing);
    expect(summary.spanDays, 20);
  });

  test('a single point inside the window is baselined before it', () async {
    final today = DateTime.now();
    await WeightStore.instance.record(
      71,
      date: today.subtract(const Duration(days: 10)),
    );
    await WeightStore.instance.record(70, date: today);

    // 7 days is too short for the earlier point, but the delta still needs a
    // baseline — otherwise the card would show nothing or a fake 0.0.
    final summary = WeightStore.instance.summary(days: 7);
    expect(summary.points.length, 2);
    expect(summary.deltaKg, closeTo(-1.0, 0.001));
    expect(summary.direction, WeightTrend.losing);
  });

  test('changes under 300 g read as holding, not losing or gaining', () async {
    final today = DateTime.now();
    await WeightStore.instance.record(
      70.0,
      date: today.subtract(const Duration(days: 10)),
    );
    await WeightStore.instance.record(70.2, date: today);

    expect(
      WeightStore.instance.summary(days: 30).direction,
      WeightTrend.holding,
    );
  });

  test('history survives a reload from prefs', () async {
    final today = DateTime.now();
    await WeightStore.instance.record(
      73.5,
      date: today.subtract(const Duration(days: 3)),
    );
    await WeightStore.instance.record(72.9, date: today);

    WeightStore.instance.resetForTest();
    await WeightStore.instance.load();

    expect(WeightStore.instance.entries.length, 2);
    expect(WeightStore.instance.latestKg, closeTo(72.9, 0.001));
  });

  test('a corrupt row is dropped without losing the rest of the history',
      () async {
    SharedPreferences.setMockInitialValues({
      'weight_log': '[{"date":"nonsense","kg":70},'
          '{"date":"${DateTime(2026, 10, 20).toIso8601String()}","kg":68.4}]',
    });
    WeightStore.instance.resetForTest();
    await WeightStore.instance.load();

    expect(WeightStore.instance.entries.length, 1);
    expect(WeightStore.instance.latestKg, closeTo(68.4, 0.001));
  });

  test('load announces itself to listeners', () async {
    WeightStore.instance.resetForTest();
    var bumps = 0;
    void listener() => bumps++;
    WeightStore.instance.addListener(listener);
    addTearDown(() => WeightStore.instance.removeListener(listener));

    await WeightStore.instance.load();

    // Home can be on screen before the startup gate lifts — a silent load
    // would leave its trend line empty for the session.
    expect(bumps, 1);
  });

  group('WeightTrendChart', () {
    Widget host(Widget child) =>
        MaterialApp(home: Scaffold(body: child));

    testWidgets('draws nothing with fewer than two points', (tester) async {
      await tester.pumpWidget(
        host(
          const WeightTrendChart(
            points: [],
            height: 44,
            animate: false,
          ),
        ),
      );
      expect(tester.getSize(find.byType(WeightTrendChart)).height, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draws a line when there are two or more points',
        (tester) async {
      final today = DateTime.now();
      final points = [
        WeightEntry(date: today.subtract(const Duration(days: 6)), kg: 72),
        WeightEntry(date: today.subtract(const Duration(days: 3)), kg: 71),
        WeightEntry(date: today, kg: 70),
      ];
      await tester.pumpWidget(
        host(WeightTrendChart(points: points, height: 44, animate: false)),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(WeightTrendChart)).height, 44);
      expect(tester.takeException(), isNull);
    });
  });
}
