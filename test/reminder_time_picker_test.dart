import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/widgets/reminder_time_picker.dart';

/// The reminder picker exists because the Material dial buzzes on every minute
/// it passes. These tests pin the parts that must survive that replacement:
/// the sheet opens at the habit's current time and hands the same time back.
void main() {
  testWidgets('opens at the reminder time and returns it unchanged', (
    tester,
  ) async {
    TimeOfDay? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showReminderTimePicker(
                    context: context,
                    initial: const TimeOfDay(hour: 20, minute: 15),
                  );
                },
                child: const Text('open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();

    // Starts on the habit's own time, in 12-hour form.
    expect(find.text('8:15 PM'), findsOneWidget);
    expect(find.text('SET REMINDER'), findsOneWidget);

    await tester.tap(find.text('SET REMINDER'));
    await tester.pumpAndSettle();

    expect(picked, const TimeOfDay(hour: 20, minute: 15));
  });

  testWidgets('cancel returns nothing, so the saved time is untouched', (
    tester,
  ) async {
    TimeOfDay? picked;
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showReminderTimePicker(
                    context: context,
                    initial: const TimeOfDay(hour: 7, minute: 0),
                  );
                  completed = true;
                },
                child: const Text('open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(picked, isNull);
  });
}
