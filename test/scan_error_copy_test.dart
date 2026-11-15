import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/services/scan_error_copy.dart';

/// The mapping decides which advice a failed scan gets. The timeout message is
/// "The scan took too long. Check your connection and try again." — it names
/// the connection, and the connection branch used to win, so a slow scan was
/// told to fix its WiFi instead of the photo.
void main() {
  test('the timeout message gets the timeout advice, not the connection one', () {
    final copy = scanErrorCopy(
      'Exception: The scan took too long. Check your connection and try again.',
    );
    expect(copy, startsWith('Analysis timed out.'));
    expect(copy, contains('good lighting'));
    expect(copy, isNot(contains('Cannot reach the server')));
  });

  test('a raw TimeoutException still maps to the timeout advice', () {
    expect(
      scanErrorCopy('TimeoutException after 0:00:30.000000'),
      startsWith('Analysis timed out.'),
    );
  });

  test('an unreachable server gets the connection advice', () {
    expect(
      scanErrorCopy(
        'Exception: Cannot reach MacroSnap right now. '
        'Check your internet connection and try again.',
      ),
      startsWith('Cannot reach the server.'),
    );
  });

  test('an unreadable image gets the image advice', () {
    expect(
      scanErrorCopy('Exception: Image file not found at: /tmp/x.jpg'),
      startsWith('Could not read the image.'),
    );
  });

  test('anything else falls back to the identification tips', () {
    expect(
      scanErrorCopy('Exception: Server error (418)'),
      startsWith('Could not identify the food.'),
    );
  });
}
