import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme.dart';

/// Opens the reminder time picker: hour and minute wheels plus AM/PM.
///
/// Why not [showTimePicker]: the Material clock dial asks the platform for
/// feedback on *every* minute it passes under the finger, so a slow drag
/// machine-guns clicks and a fast fling smears them into one long buzz — the
/// exact reason the old reminder picker felt rough. A wheel carries the same
/// information and lets this file decide when a tick is earned: once per
/// settled step, and throttled so overlapping scroll callbacks cannot stack.
Future<TimeOfDay?> showReminderTimePicker({
  required BuildContext context,
  required TimeOfDay initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ReminderTimeSheet(initial: initial),
  );
}

class _ReminderTimeSheet extends StatefulWidget {
  final TimeOfDay initial;

  const _ReminderTimeSheet({required this.initial});

  @override
  State<_ReminderTimeSheet> createState() => _ReminderTimeSheetState();
}

class _ReminderTimeSheetState extends State<_ReminderTimeSheet> {
  /// Minimum gap between ticks. A fling reports dozens of detents in a few
  /// hundred milliseconds; without this the motor never gets to stop and the
  /// whole gesture reads as a rattle instead of a scroll.
  static const Duration _minGap = Duration(milliseconds: 35);

  late int _hour12;
  late int _minute;
  late bool _pm;

  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;
  late final FixedExtentScrollController _periodCtrl;

  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    final h = widget.initial.hour;
    _pm = h >= 12;
    _hour12 = h % 12 == 0 ? 12 : h % 12;
    _minute = widget.initial.minute;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
    _periodCtrl = FixedExtentScrollController(initialItem: _pm ? 1 : 0);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _periodCtrl.dispose();
    super.dispose();
  }

  /// One detent, one tick — and never two inside [_minGap].
  void _tick() {
    final now = DateTime.now();
    final last = _lastTick;
    if (last != null && now.difference(last) < _minGap) return;
    _lastTick = now;
    Haptics.tap();
  }

  String get _label {
    final m = _minute.toString().padLeft(2, '0');
    return '$_hour12:$m ${_pm ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : const Color(0xFF1A1A1A);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: text.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Remind me at',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _label,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                color: MacroSnapTheme.greenText(context),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 168,
              child: Row(
                children: [
                  _wheel(
                    controller: _hourCtrl,
                    count: 12,
                    label: (i) => '${i + 1}',
                    selected: _hour12 - 1,
                    isDark: isDark,
                    semanticsLabel: 'Hour',
                    onChanged: (i) {
                      if (i + 1 == _hour12) return;
                      setState(() => _hour12 = i + 1);
                      _tick();
                    },
                  ),
                  _wheel(
                    controller: _minuteCtrl,
                    count: 60,
                    label: (i) => i.toString().padLeft(2, '0'),
                    selected: _minute,
                    isDark: isDark,
                    semanticsLabel: 'Minute',
                    onChanged: (i) {
                      if (i == _minute) return;
                      setState(() => _minute = i);
                      _tick();
                    },
                  ),
                  _wheel(
                    controller: _periodCtrl,
                    count: 2,
                    label: (i) => i == 1 ? 'PM' : 'AM',
                    selected: _pm ? 1 : 0,
                    isDark: isDark,
                    semanticsLabel: 'AM or PM',
                    onChanged: (i) {
                      final pm = i == 1;
                      if (pm == _pm) return;
                      setState(() => _pm = pm);
                      _tick();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: MacroSnapTheme.textSecondary(context),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: MacroSnapTheme.neonGreen,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Haptics.light();
                      Navigator.pop(
                        context,
                        TimeOfDay(
                          hour: (_hour12 % 12) + (_pm ? 12 : 0),
                          minute: _minute,
                        ),
                      );
                    },
                    child: const Text('SET REMINDER'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) label,
    required int selected,
    required bool isDark,
    required String semanticsLabel,
    required ValueChanged<int> onChanged,
  }) {
    return Expanded(
      child: Semantics(
        label: semanticsLabel,
        child: CupertinoPicker(
          scrollController: controller,
          itemExtent: 44,
          diameterRatio: 1.6,
          squeeze: 1.05,
          useMagnifier: true,
          magnification: 1.06,
          selectionOverlay: Container(
            margin: const EdgeInsets.symmetric(vertical: 62),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.06,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onSelectedItemChanged: onChanged,
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text(
                  label(i),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: i == selected
                        ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                        : MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
