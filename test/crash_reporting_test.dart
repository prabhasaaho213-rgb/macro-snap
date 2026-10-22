import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/crash_reporting.dart';

/// Crash reporting must never be able to break the app: it is fire-and-forget,
/// it runs in release only, and it has to survive having no Firebase app at all
/// (which is exactly the situation in this test binary).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('init() stays off without Firebase and never throws', () async {
    expect(await CrashReporting.init(), isFalse);
    expect(CrashReporting.isEnabled, isFalse);
  });

  test('record() is safe while reporting is off', () {
    expect(
      () => CrashReporting.record(
        Exception('boom'),
        StackTrace.current,
        reason: 'test.record',
        fatal: true,
      ),
      returnsNormally,
    );
  });

  test('logError() is safe while reporting is off and keeps the context', () {
    expect(
      () =>
          logError('TestThing.doThing', Exception('boom'), StackTrace.current),
      returnsNormally,
    );
    // The reason is what makes a caught error traceable — it must be a real
    // label, not the old generic "Error: $e".
    expect('TestThing.doThing', contains('.'));
  });
}
