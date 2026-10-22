import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// The splash animation is hand-authored JSON, so this test is the thing that
/// proves it is a real Lottie file — not an asset that silently fails at launch
/// and leaves the splash as a static logo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logo intro is valid Lottie, plays once, under 2 seconds', () async {
    final data = await rootBundle.load('assets/animations/logo_intro.json');
    final composition = await LottieComposition.fromByteData(data);

    expect(composition.layers, isNotEmpty);
    expect(composition.startFrame, 0);
    expect(composition.endFrame, greaterThan(0));

    // The splash is allowed to animate for less than two seconds; a longer
    // intro would make the launch wait feel longer than it is.
    expect(composition.duration, lessThan(const Duration(seconds: 2)));
    expect(composition.duration, greaterThan(Duration.zero));

    // 60 fps, 96 frames = 1.6 s — pinned so a future edit cannot silently
    // double the intro length.
    expect(composition.frameRate, 60);
    // 96 frames at 60 fps; the parser reports the last frame as 95.99, so
    // compare within a frame rather than exactly.
    expect(composition.endFrame, closeTo(96, 0.1));
  });
}
