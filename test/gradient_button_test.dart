import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/widgets/gradient_button.dart';

/// Pins GradientButton's overflow hardening: a label longer than the button
/// must shrink + ellipsize (never paint outside / throw RenderFlex overflow),
/// and the full label stays reachable via the tooltip.
void main() {
  testWidgets('long label never overflows the button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // A deliberately narrow parent so the label cannot fit.
            child: SizedBox(
              width: 140,
              child: GradientButton(
                label:
                    'SUBSCRIBE - ₹49/mo · AUTO-RENEWS · Cancel anytime anywhere',
                icon: Icons.lock_rounded,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: 'must not overflow');

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);

    // The full label is still accessible via the button's tooltip.
    expect(find.byType(Tooltip), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      contains('Cancel anytime anywhere'),
    );
  });

  testWidgets('short labels render unchanged', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: GradientButton(
                label: 'Pay ₹49 & Subscribe',
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Pay ₹49 & Subscribe'), findsOneWidget);
  });
}
