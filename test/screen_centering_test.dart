import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/core/theme.dart';
import 'package:macro_snap/screens/onboarding_screen.dart';
import 'package:macro_snap/screens/phone_login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins that the onboarding intro pages and the login page keep their key
/// text CENTERED on every phone size — small (320dp) through large (430dp).
///
/// History: the login page was top-aligned (headline sat 15–28% above center,
/// worse on tall phones) and the intro content overflowed on small screens
/// (title 16% below center). The login page now vertically centers its whole
/// block (scroll fallback), and the intro content was compacted to fit.
///
/// Thresholds: ±15% of screen height everywhere, EXCEPT the login page on a
/// 320×568 screen, where the content block (~500px) physically fills the
/// viewport — the headline can never reach center there, so it gets a
/// documented ±20% allowance. Every modern phone (360dp+) is covered by 15%.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final sizes = <String, Size>{
    '320dp': const Size(320, 568), // small phone (physical floor for login)
    '360dp': const Size(360, 640), // mid phone
    '393dp': const Size(393, 852), // modern tall phone
    '430dp': const Size(430, 932), // large phone
  };

  Future<double> verticalOffsetFraction(
    WidgetTester tester,
    String text,
  ) async {
    final center = tester.getCenter(find.text(text));
    final screenHeight = tester.view.physicalSize.height;
    return (center.dy - screenHeight / 2) / screenHeight;
  }

  Future<void> pumpAt(WidgetTester tester, Widget screen, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: MacroSnapTheme.light, home: screen),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  for (final entry in sizes.entries) {
    final name = entry.key;
    final size = entry.value;

    testWidgets('login page centers its headline on $name', (tester) async {
      await pumpAt(tester, const PhoneLoginScreen(), size);

      final offset = await verticalOffsetFraction(
        tester,
        'Welcome to MacroSnap',
      );
      final limit = name == '320dp' ? 0.20 : 0.15;
      expect(
        offset.abs(),
        lessThan(limit),
        reason:
            'headline centered on $name, actual offset: '
            '${(offset * 100).toStringAsFixed(1)}% of height',
      );
    });

    testWidgets('onboarding page 1 centers its title on $name', (tester) async {
      await pumpAt(
        tester,
        const OnboardingScreen(nextScreen: Scaffold(body: SizedBox())),
        size,
      );

      final offset = await verticalOffsetFraction(
        tester,
        'Welcome to\nMacroSnap',
      );
      expect(
        offset.abs(),
        lessThan(0.15),
        reason:
            'intro title centered on $name, actual offset: '
            '${(offset * 100).toStringAsFixed(1)}% of height',
      );
    });
  }
}
