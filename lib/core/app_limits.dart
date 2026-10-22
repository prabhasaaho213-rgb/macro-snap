/// Product limits that more than one layer needs to agree on.
///
/// The free scan allowance used to exist as three separate 3s: one in
/// `ScanGate`, one as the default `NutritionResult.scansLimit`, and one on the
/// server. Two copies in the client could disagree after an edit; this is the
/// single client-side source. The server remains the authority — it can send a
/// different limit per account, and `ScanGate` trusts that number when present.
class AppLimits {
  AppLimits._();

  /// AI scans a free account gets per IST day.
  static const int freeScansPerDay = 3;
}
