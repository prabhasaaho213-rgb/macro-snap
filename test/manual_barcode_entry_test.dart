import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/core/theme.dart';
import 'package:macro_snap/screens/manual_barcode_entry_screen.dart';
import 'package:macro_snap/services/barcode_db.dart';

/// The manual-entry form used to be an `AlertDialog` opened from the scanner
/// callback, and typed input never reached its fields on device — so an
/// unknown barcode could not be added at all. It is a page now; these tests
/// hold the two things that matter: the text lands in the form, and the values
/// come back as a loggable [BarcodeFood].
void main() {
  /// Pushes the page the same way the scanner does and captures the result.
  Future<void> openSheet(
    WidgetTester tester, {
    required void Function(BarcodeFood?) onResult,
  }) async {
    // A tall surface so the whole form (six fields plus the save button) is
    // laid out at once, the way it is on a phone.
    tester.view.physicalSize = const Size(500, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: MacroSnapTheme.dark,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.push<BarcodeFood>(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => const ManualBarcodeEntryScreen(
                        barcode: '8901234567890',
                      ),
                    ),
                  );
                  onResult(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('typed values are read back as a barcode food', (tester) async {
    BarcodeFood? captured;
    await openSheet(tester, onResult: (r) => captured = r);

    await tester.enterText(find.byType(TextFormField).at(0), 'Masala Oats');
    await tester.enterText(find.byType(TextFormField).at(1), '380');
    await tester.enterText(find.byType(TextFormField).at(2), '8.5');
    await tester.enterText(find.byType(TextFormField).at(3), '61');
    await tester.enterText(find.byType(TextFormField).at(4), '10');
    await tester.pump();

    await tester.tap(find.text('Use these values'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.barcode, '8901234567890');
    expect(captured!.name, 'Masala Oats');
    expect(captured!.brand, 'Manual Entry');
    expect(captured!.caloriesPer100g, 380);
    expect(captured!.proteinPer100g, 8.5);
    expect(captured!.carbsPer100g, 61);
    expect(captured!.fatsPer100g, 10);
  });

  testWidgets('a nameless product is refused, with the error shown', (
    tester,
  ) async {
    var called = false;
    await openSheet(tester, onResult: (_) => called = true);

    await tester.enterText(find.byType(TextFormField).at(1), '250');
    await tester.tap(find.text('Use these values'));
    await tester.pumpAndSettle();

    expect(called, isFalse, reason: 'the page stays open');
    expect(find.text('Name is required'), findsOneWidget);
  });

  testWidgets('letters cannot be typed into the nutrition fields', (
    tester,
  ) async {
    await openSheet(tester, onResult: (_) {});

    await tester.enterText(find.byType(TextFormField).at(1), '12abc');
    await tester.pump();

    final field = tester.widget<TextFormField>(find.byType(TextFormField).at(1));
    expect(field.controller?.text, '12');
  });

  testWidgets('cancelling returns nothing', (tester) async {
    BarcodeFood? captured;
    var result = 'not called';
    await openSheet(
      tester,
      onResult: (r) {
        captured = r;
        result = 'called';
      },
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, 'called');
    expect(captured, isNull);
  });
}
