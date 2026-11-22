/// The user-visible app version, in one place.
///
/// `pubspec.yaml` drives what the build stamps (versionName/versionCode); this
/// constant is what code *talks* about — the Open Food Facts user-agent and the
/// "What's New" screen. `test/release_version_test.dart` fails if this drifts
/// from `pubspec.yaml`, so a release bump cannot forget it.
///
/// It lives in `core/` rather than on a screen so a service can use it without
/// importing a widget: the barcode client's user-agent was hardcoded to 1.5.9
/// and stayed there for seven releases.
const String kAppVersion = '1.5.21';
