import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/widgets/scan_animation.dart';

/// The scan view has two phases: a sweeping line while the AI works, then the
/// detected dish names popping onto the photo. The results screen waits
/// [ScanAnimationView.revealDuration] before switching, so that contract is
/// tested here too — if it ever became shorter than the last pop, labels would
/// be cut off mid-animation.
///
/// The sweep controller repeats forever, so these tests pump explicit
/// durations and never use pumpAndSettle.
void main() {
  // A real 1x1 PNG — an undecodable file would make the image stream report an
  // error and drown the test in noise.
  const pngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
      'q842iQAAAABJRU5ErkJggg==';

  late String imagePath;

  setUpAll(() {
    final f = File('${Directory.systemTemp.path}/scan_anim_test.png')
      ..writeAsBytesSync(base64Decode(pngBase64));
    imagePath = f.path;
  });

  tearDownAll(() {
    final f = File(imagePath);
    if (f.existsSync()) f.deleteSync();
  });

  test('revealDuration outlasts the last label pop', () {
    for (final dishes in [1, 2, 3, 5, 9]) {
      final shown = math.min(dishes, ScanAnimationView.maxLabels);
      final lastLabelDelay =
          500 + ScanAnimationView.labelGap.inMilliseconds * (shown - 1);
      const popDurationMs = 520; // _PopLabel's own animation
      expect(
        ScanAnimationView.revealDuration(dishes).inMilliseconds,
        greaterThan(lastLabelDelay + popDurationMs),
        reason: '$dishes dishes: the results must not cut the last pop short',
      );
    }
    // Beyond maxLabels nothing more is shown, so the wait does not grow.
    expect(
      ScanAnimationView.revealDuration(50),
      ScanAnimationView.revealDuration(ScanAnimationView.maxLabels),
    );
  });

  testWidgets('while analysing it shows the photo and no labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ScanAnimationView(imagePath: imagePath)),
    ));
    await tester.pump(const Duration(milliseconds: 900));

    expect(tester.takeException(), isNull, reason: 'must render cleanly');
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Poha'), findsNothing);
  });

  testWidgets('the revealed labels pop onto the photo, capped at maxLabels',
      (tester) async {
    final names = ['Poha', 'Chai', 'Banana', 'Idli', 'Dosa', 'Upma', 'Vada'];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScanAnimationView(imagePath: imagePath, labels: names),
      ),
    ));
    // Let every scheduled pop fire (and finish) before the test ends, or the
    // pending timers fail the test.
    await tester.pump(ScanAnimationView.revealDuration(names.length));

    expect(tester.takeException(), isNull, reason: 'must render cleanly');
    for (final shown in names.take(ScanAnimationView.maxLabels)) {
      expect(find.text(shown), findsOneWidget, reason: '$shown must be labelled');
    }
    expect(find.text('Upma'), findsNothing,
        reason: 'the 6th dish is beyond maxLabels');
    expect(find.text('Vada'), findsNothing);
  });

  testWidgets('blank dish names are never labelled', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScanAnimationView(
          imagePath: imagePath,
          labels: const ['  ', 'Poha', ''],
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    expect(find.text('Poha'), findsOneWidget);
    expect(find.text(''), findsNothing);
    expect(find.text('  '), findsNothing);
  });

  testWidgets('switching from sweep to reveal stops the sweep', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ScanAnimationView(key: key, imagePath: imagePath)),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    // Swap to the reveal phase on the same element.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScanAnimationView(
          key: key,
          imagePath: imagePath,
          labels: const ['Poha'],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 2500));

    expect(tester.takeException(), isNull);
    expect(find.text('Poha'), findsOneWidget);
  });
}
