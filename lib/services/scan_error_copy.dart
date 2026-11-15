/// Turns a raw scan failure into the guidance the result screen shows.
///
/// Top-level (rather than a private method on the screen) so tests can pin the
/// mapping: the timeout copy is "The scan took too long. Check your
/// connection…", which names the connection, and the connection branch used to
/// swallow it — a slow scan was told to fix its WiFi.
///
/// Order matters. The timeout check runs first, then connectivity, then the
/// image/file cases, and the generic "take a clearer photo" advice is the
/// fallback rather than the answer to everything.
String scanErrorCopy(String raw) {
  final msg = raw.replaceFirst('Exception: ', '').toLowerCase();
  if (msg.contains('timeout') ||
      msg.contains('timed out') ||
      msg.contains('took too long')) {
    return 'Analysis timed out.\n\nTips for better results:\n'
        '• Take a clearer photo\n• Ensure good lighting\n'
        '• Get closer to the food';
  }
  if (msg.contains('cannot reach') || msg.contains('connection')) {
    return 'Cannot reach the server.\n\n'
        'Check your internet connection and try again.';
  }
  if (msg.contains('image') || msg.contains('file')) {
    return 'Could not read the image.\n\nTry:\n'
        '• Taking a new photo\n• Checking camera permissions';
  }
  return 'Could not identify the food.\n\nTips:\n'
      '• Take a clearer photo\n• Ensure food is well-lit\n'
      '• Get closer to the dish\n• Avoid blurry images';
}
