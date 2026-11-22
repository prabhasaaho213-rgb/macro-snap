/// Public web pages the app links to.
///
/// One constant per page, so the login screen and Settings cannot drift apart
/// again: they used to point at a raw `raw.githubusercontent.com` file and at a
/// GitHub Pages page respectively, meaning the same policy was linked in two
/// different forms. This is the Pages build of the project's own repository; if
/// the policy ever moves to its own domain, this is the only line to change.
class SiteLinks {
  SiteLinks._();

  static const String privacyPolicy =
      'https://prabhasaaho213-rgb.github.io/macro-snap/';
}
