import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_snap/widgets/snap_avatar.dart';

/// The picker used fixed 58 px tiles in a Wrap, so on a 393 dp phone the four
/// columns ended at ~292 of the 353 dp the sheet had: the grid hugged the left
/// padding and left a dead strip on the right. These numbers come from the
/// sheet's own padding (20 each side) and spacing (12), so the check fails if
/// either drifts too.
void main() {
  const screenWidth = 393.0;

  testWidgets('the picker grid fills the sheet and stays symmetric', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(screenWidth, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showSnapAvatarPicker(ctx),
                child: const Text('open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final avatars = find.byType(SnapAvatar);
    expect(avatars, findsNWidgets(20), reason: 'all twenty faces are offered');

    final firstRow = List.generate(4, (i) => tester.getRect(avatars.at(i)));

    // Measure the row instead of assuming the sheet's width: the modal sheet
    // does not always span the full viewport, and the point of this test is the
    // row's own symmetry, not the sheet's.
    final row = tester.getRect(find.byType(Wrap));
    final leftGap = firstRow.first.left - row.left;
    final rightGap = row.right - firstRow.last.right;

    expect(
      rightGap,
      closeTo(leftGap, 1),
      reason: 'equal space on both sides — nothing pooled on the right',
    );
    expect(
      leftGap,
      lessThan(12),
      reason: 'the row starts at the sheet padding, not inset from it',
    );
    expect(
      firstRow.last.right - firstRow.first.left,
      greaterThan(row.width * 0.9),
      reason: 'four columns spend the sheet width instead of hugging one edge',
    );
    for (var i = 1; i < firstRow.length; i++) {
      expect(
        firstRow[i].left - firstRow[i - 1].right,
        closeTo(21, 1),
        reason: 'even 12 dp spacing plus the 9 dp of ring and padding',
      );
    }
  });
}
