import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/in_app_review_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The ask must be earned, once, and silent when it cannot happen.
///
/// The previous prompt asked "Rate 5 Stars" on a launch counter; these tests
/// pin the replacement: nothing before the third saved meal, exactly one ask
/// afterwards, no flag burned when Play cannot show a sheet, and never an
/// exception reaching the save path.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InAppReviewService.resetForTest();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    InAppReviewService.availabilityOverride = () async => true;
  });

  tearDown(() {
    InAppReviewService.resetForTest();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<bool> prompted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(InAppReviewService.promptedKey) ?? false;
  }

  test('does not ask before the third saved meal', () async {
    var requests = 0;
    InAppReviewService.requestOverride = () async => requests++;

    await InAppReviewService.maybeAfterMealSave(0);
    await InAppReviewService.maybeAfterMealSave(1);
    await InAppReviewService.maybeAfterMealSave(2);

    expect(requests, 0);
    expect(await prompted(), isFalse);
  });

  test('asks on the third saved meal', () async {
    var requests = 0;
    InAppReviewService.requestOverride = () async => requests++;

    await InAppReviewService.maybeAfterMealSave(3);

    expect(requests, 1);
    expect(await prompted(), isTrue, reason: 'the ask must never repeat');
  });

  test('never asks twice, however many meals follow', () async {
    var requests = 0;
    InAppReviewService.requestOverride = () async => requests++;

    await InAppReviewService.maybeAfterMealSave(3);
    await InAppReviewService.maybeAfterMealSave(4);
    await InAppReviewService.maybeAfterMealSave(50);

    expect(requests, 1);
  });

  test('a build Play will not review does not burn the ask', () async {
    // Sideloaded APKs and installs without a Play account report unavailable.
    var requests = 0;
    InAppReviewService.availabilityOverride = () async => false;
    InAppReviewService.requestOverride = () async => requests++;

    await InAppReviewService.maybeAfterMealSave(3);
    expect(requests, 0);
    expect(
      await prompted(),
      isFalse,
      reason: 'a real install must still get its one ask later',
    );

    // Once it is available, the next save asks.
    InAppReviewService.availabilityOverride = () async => true;
    await InAppReviewService.maybeAfterMealSave(4);
    expect(requests, 1);
    expect(await prompted(), isTrue);
  });

  test('a failing review sheet never escapes to the caller', () async {
    InAppReviewService.requestOverride = () async =>
        throw StateError('Play Services exploded');

    await expectLater(
      InAppReviewService.maybeAfterMealSave(3),
      completes,
    );
    // It was attempted, so it is marked: retrying a broken sheet on every save
    // is worse than one silent miss.
    expect(await prompted(), isTrue);
  });

  test('a manual ask shows the card even after the automatic one', () async {
    var requests = 0;
    InAppReviewService.requestOverride = () async => requests++;

    await InAppReviewService.maybeAfterMealSave(3);
    expect(requests, 1);

    // Settings' Rate Us: the tap is the user's decision, so it asks again.
    expect(await InAppReviewService.requestNow(), isTrue);
    expect(requests, 2);
  });

  test('a manual ask reports false when Play cannot show the card', () async {
    InAppReviewService.availabilityOverride = () async => false;

    expect(await InAppReviewService.requestNow(), isFalse);
    expect(await prompted(), isFalse, reason: 'the fallback must still run');
  });

  test('nothing happens off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var requests = 0;
    InAppReviewService.requestOverride = () async => requests++;

    await InAppReviewService.maybeAfterMealSave(3);

    expect(requests, 0);
    expect(await prompted(), isFalse);
  });
}
