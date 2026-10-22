import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/screens/payment_result_screen.dart';
import 'package:macro_snap/services/razorpay_service.dart';

/// The purchase now happens inside the app, so the three outcomes each get a
/// full screen. These tests pin what the user sees and what each screen hands
/// back to the subscription page (retry vs. done), plus the fallback decision
/// for Razorpay's recurring-plan SDK bug.
void main() {
  testWidgets('success screen celebrates and reports done', (tester) async {
    PaymentAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<PaymentAction>(
                MaterialPageRoute(
                  builder: (_) => const PaymentSuccessScreen(
                    celebrate: false, // confetti is infinite-ish; skip in tests
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text("You're Pro"), findsOneWidget);
    expect(find.text('₹29/month · cancel anytime'), findsOneWidget);
    expect(find.text('Unlimited AI food scans'), findsOneWidget);

    await tester.tap(find.text('Start using MacroSnap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, PaymentAction.done);
  });

  testWidgets('failure screen shows the reason and can retry', (tester) async {
    PaymentAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<PaymentAction>(
                MaterialPageRoute(
                  builder: (_) => const PaymentFailureScreen(
                    message: 'Your bank declined the payment.',
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Payment did not go through'), findsOneWidget);
    expect(find.text('Your bank declined the payment.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, PaymentAction.retry);
  });

  testWidgets('pending screen says it is unconfirmed when the check fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentPendingScreen(
          message: 'Finish the payment in the page we opened.',
          onCheckAgain: () async => false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Confirming your payment'), findsOneWidget);
    expect(
      find.text('Finish the payment in the page we opened.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Check again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Not confirmed yet — this can take a few minutes.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  group('Razorpay recurring-plan fallback', () {
    test('the SDK recurrence bug is recognised', () {
      // The message razorpay_flutter returns on affected builds — the reason
      // the app used to send everyone to a browser page instead of checkout.
      expect(
        RazorpayService.looksLikeRecurrenceBug(
          'INCORRECT RECURRENCE PATTERN RULE',
        ),
        isTrue,
      );
      expect(
        RazorpayService.looksLikeRecurrenceBug(
          'Incorrect pattern for recurring payment',
        ),
        isTrue,
      );
    });

    test('ordinary declines are not mistaken for the bug', () {
      // A real decline must reach the failure screen, not a silent fallback.
      expect(
        RazorpayService.looksLikeRecurrenceBug('Payment failed: card declined'),
        isFalse,
      );
      expect(RazorpayService.looksLikeRecurrenceBug(''), isFalse);
    });
  });
}
