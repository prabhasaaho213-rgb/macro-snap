import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_partition.dart';
import 'crash_reporting.dart';

/// Today's step count from the phone's own step sensor.
///
/// Health Connect is the preferred source: it de-duplicates the phone and a
/// watch, and it is the only source for calories burned. But it is also
/// optional. When it is not installed, not supported, or the user never granted
/// it, the dashboard used to read zero steps forever. This reads Android's
/// `TYPE_STEP_COUNTER` directly over the `macrosnap/steps` event channel
/// implemented in MainActivity.kt, which needs only the activity-recognition
/// permission the manifest already declares — no Health Connect, no separate
/// app, no account, and no plugin dependency.
///
/// The hardware counter is Android-only. iOS keeps HealthKit as its source, so
/// [supported] is false there and the dashboard simply uses the health read.
///
/// ## What the number means
///
  /// The channel emits a CUMULATIVE count since boot, so the day is tracked as
///
///     today = carried + (total − baseline)
///
/// where `baseline` is the counter value when the current segment started and
/// `carried` is everything already counted today in earlier segments. A segment
/// ends when the counter goes BACKWARDS — a reboot restarts it at zero — and,
/// deliberately, when a different account signs in ([resetForNewAccount]).
///
/// All four values are persisted, so:
///   * an app restart continues the same day instead of starting again;
///   * a reboot while the app is closed does NOT lose the day: the persisted
///     total becomes `carried`, the new low counter becomes the baseline;
///   * a new day starts at zero.
///
/// This is exact only for steps taken while the phone's counter is running —
/// which is all day — but the day's total can only be read from the first
/// moment the app starts it ([start]). Steps taken before that first reading of
/// the day are not recoverable from the raw sensor; Health Connect is the only
/// way to get a true midnight-to-now figure, which is why the dashboard labels
/// this number honestly.
class StepCounterService extends ChangeNotifier {
  StepCounterService._();
  static final StepCounterService instance = StepCounterService._();

  /// Per ACCOUNT, not per device: the counter is a property of the phone, but
  /// the steps a day scores belong to whoever was signed in. These keys used to
  /// be global, so the second account on a shared phone inherited the first
  /// one's day (and the leaderboard published it as its own).
  static const String _dayPref = 'sensor_steps_day';
  static const String _baselinePref = 'sensor_steps_baseline';
  static const String _carriedPref = 'sensor_steps_carried';
  static const String _todayPref = 'sensor_steps_today';
  static const String _lastTotalPref = 'sensor_steps_last_total';

  /// The persisted key for [base] in the ACTIVE account's partition. Resolved
  /// per call rather than cached: the account can change between two reads.
  static String _key(SharedPreferences prefs, String base) =>
      AccountPartition.key(
        base,
        AccountPartition.suffix(AccountPartition.activeFromPrefs(prefs)),
      );

  /// A sanity ceiling for one day. Anything above this is a corrupt reading,
  /// not a walk.
  static const int maxDailySteps = 200000;

  /// The `macrosnap/steps` event channel, defined in MainActivity.kt.
  static const EventChannel _channel = EventChannel('macrosnap/steps');

  StreamSubscription<dynamic>? _sub;
  bool _supported = false;
  bool _granted = false;
  bool _failed = false;

  /// Counter value at the start of the current segment.
  int? _baseline;

  /// Steps already counted today before the current segment (earlier boots).
  int _carried = 0;

  /// Steps today, `carried + (total − baseline)`.
  int? _todaySteps;

  /// Last counter value seen in this segment, used to spot a counter reset.
  int? _lastTotal;

  String? _day;

  /// This platform has a step counter that does not need Health Connect.
  bool get supported => _supported;

  /// Listening and permitted — [todaySteps] is a real reading.
  bool get active => _sub != null && _granted;

  /// Today's steps so far, or null before the first reading.
  int? get todaySteps => _todaySteps;

  /// The sensor is supported but the stream reported an error.
  bool get failed => _failed;

  /// Android only: the channel is backed by the Android step-counter sensor.
  /// iOS has no equivalent here, and HealthKit already supplies its steps.
  bool get _platformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Starts listening. Safe to call repeatedly; returns whether the sensor is
  /// usable.
  ///
  /// [requestPermission] is false by default: [main] starts the sensor at
  /// launch, and a permission dialog before the first frame is not acceptable
  /// there. When it is false and the grant is missing, this returns false and
  /// the Health tab asks for it explicitly.
  Future<bool> start({bool requestPermission = false}) async {
    if (!_platformSupported) return false;
    _supported = true;
    if (_sub != null) return _granted;

    if (!await _hasPermission(requestPermission: requestPermission)) {
      _granted = false;
      notifyListeners();
      return false;
    }
    _granted = true;
    await _restore();
    _sub = _channel.receiveBroadcastStream().listen(
      (event) {
        // Kotlin sends the raw sensor value as a Long; accept a num or a string
        // so a channel-type change cannot silently stop the counter.
        final total = event is num ? event.toInt() : int.tryParse('$event');
        if (total != null) _onStepCount(total);
      },
      onError: _onError,
    );
    notifyListeners();
    return true;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _granted = false;
    notifyListeners();
  }

  /// Starts today's count again from zero for a newly signed-in account.
  ///
  /// The sensor measures a PHONE, but the points are banked by an ACCOUNT. On a
  /// shared phone, without this, the next person to sign in would inherit the
  /// previous person's walking as their own leaderboard points. Rebasing means
  /// each account only scores the steps taken while it was the active one.
  Future<void> resetForNewAccount() async {
    _carried = 0;
    _baseline = _lastTotal;
    _todaySteps = 0;
    _day = _dayStamp();
    await _persist();
    notifyListeners();
  }

  /// Android 10+ gates the step counter behind ACTIVITY_RECOGNITION.
  ///
  /// iOS has no permission_handler mapping for motion: CoreMotion prompts on
  /// the first read, and a refusal arrives as an error on the stream (handled
  /// by [_onError]) rather than as a request result.
  Future<bool> _hasPermission({required bool requestPermission}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final status = requestPermission
          ? await Permission.activityRecognition.request()
          : await Permission.activityRecognition.status;
      return status.isGranted || status.isLimited;
    } catch (e, st) {
      logError('StepCounterService.permission', e, st);
      return false;
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_key(prefs, _dayPref)) == _dayStamp()) {
        // −1 means "no reading yet today", which is different from a genuine
        // baseline of 0 (the counter really can start at 0 right after boot).
        // Treating the absent case as 0 would make the first reading count the
        // phone's whole since-boot total as today's steps.
        final baseline = prefs.getInt(_key(prefs, _baselinePref));
        _baseline = (baseline != null && baseline >= 0) ? baseline : null;
        _carried = prefs.getInt(_key(prefs, _carriedPref)) ?? 0;
        _todaySteps = prefs.getInt(_key(prefs, _todayPref));
        // The last counter value is persisted so a restart ABOVE the saved
        // baseline is still recognised as a counter reset. Without it, a reboot
        // whose first reading happened to exceed the baseline was taken as a
        // continuation and the day was undercounted.
        final lastTotal = prefs.getInt(_key(prefs, _lastTotalPref));
        _lastTotal = (lastTotal != null && lastTotal >= 0) ? lastTotal : null;
        _day = _dayStamp();
      } else {
        // A new day: yesterday's baseline would make today's count nonsense.
        _day = null;
        _baseline = null;
        _carried = 0;
        _todaySteps = null;
      }
    } catch (e, st) {
      logError('StepCounterService.restore', e, st);
    }
  }

  void _onStepCount(int total) {
    final today = _dayStamp();
    var changed = false;

    if (_day != today) {
      // First reading of a new day: this is the best available "midnight".
      _day = today;
      _carried = 0;
      _baseline = total;
      _todaySteps = 0;
      changed = true;
    } else if (_baseline == null ||
        total < _baseline! ||
        (_lastTotal != null && total < _lastTotal!)) {
      // A new segment: the counter restarted (the phone rebooted, or the sensor
      // was re-registered) or went backwards. The steps already counted today
      // survive in `_carried`; only the baseline moves. This is what stops a
      // reboot from zeroing the day — and, through noteSteps(0), from taking
      // the leaderboard points back and breaking the step streak.
      _carried = _todaySteps ?? _carried;
      _baseline = total;
      changed = true;
    }

    _lastTotal = total;
    final steps = (_carried + (total - _baseline!)).clamp(
      0,
      maxDailySteps,
    ).toInt();
    if (steps != _todaySteps) changed = true;
    _todaySteps = steps;

    if (changed) {
      unawaited(_persist());
      notifyListeners();
    }
  }

  void _onError(Object error, StackTrace st) {
    _failed = true;
    _granted = false;
    logError('StepCounterService.stream', error, st);
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(prefs, _dayPref), _day ?? _dayStamp());
      await prefs.setInt(_key(prefs, _baselinePref), _baseline ?? -1);
      await prefs.setInt(_key(prefs, _carriedPref), _carried);
      await prefs.setInt(_key(prefs, _todayPref), _todaySteps ?? 0);
      await prefs.setInt(_key(prefs, _lastTotalPref), _lastTotal ?? -1);
    } catch (e, st) {
      logError('StepCounterService.persist', e, st);
    }
  }

  static String _dayStamp() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
