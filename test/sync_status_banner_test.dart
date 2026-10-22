import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/sync_status_service.dart';

/// The cloud-backup warning banner was removed from MainShell (backup is now
/// automatic and silent), but SyncStatusService still drives sync reporting
/// inside MealSyncService — so its state machine stays covered here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Start every test with a clean sync state.
    SyncStatusService.instance.reportSuccess();
  });

  tearDown(() {
    SyncStatusService.instance.reportSuccess();
  });

  // ─── STATE MACHINE UNIT TESTS (no widgets/network) ─────────────────────

  test('reportSuccess clears failure state', () {
    SyncStatusService.instance.reportFailure('x');
    expect(SyncStatusService.instance.backendUnreachable, isTrue);
    SyncStatusService.instance.reportSuccess();
    expect(SyncStatusService.instance.backendUnreachable, isFalse);
    expect(SyncStatusService.instance.lastDetail, isEmpty);
  });

  test('dismiss hides until a NEW failure re-surfaces it', () {
    SyncStatusService.instance.reportFailure('x');
    SyncStatusService.instance.dismiss();
    expect(SyncStatusService.instance.backendUnreachable, isFalse);

    // No notify while already dismissed.
    SyncStatusService.instance.dismiss();
    expect(SyncStatusService.instance.backendUnreachable, isFalse);

    SyncStatusService.instance.reportFailure('y');
    expect(
      SyncStatusService.instance.backendUnreachable,
      isTrue,
      reason: 'a fresh failure must re-show state even after dismiss',
    );
  });

  test('notifyListeners fires on every state transition', () {
    var notified = 0;
    void onNotify() => notified++;
    SyncStatusService.instance.addListener(onNotify);
    SyncStatusService.instance.reportSuccess(); // reset baseline
    final baseline = notified;
    SyncStatusService.instance.reportFailure('a');
    SyncStatusService.instance.reportFailure('b');
    SyncStatusService.instance.reportSuccess();
    SyncStatusService.instance.dismiss();
    expect(
      notified,
      greaterThan(baseline),
      reason: 'each state change must notify listeners',
    );
    SyncStatusService.instance.removeListener(onNotify);
  });
}
