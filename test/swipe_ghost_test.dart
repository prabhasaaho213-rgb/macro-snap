import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macro_snap/core/theme.dart';
import 'package:macro_snap/screens/habits_tab.dart';
import 'package:macro_snap/models/habit.dart';
import 'package:macro_snap/services/habit_store.dart';

/// Pumps HabitsTab and waits for AnimatedEntrance+_checkSub to settle.
Future<void> pumpHabitsTab(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HabitsTab()));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = HabitStore.instance;
    store.habits.clear();
  });

  // ─── GHOST FIX STRUCTURE ───────────────────────────────────
  // GPU smear during the swipe is a rasterization artifact, but it can only
  // happen if the emoji tile's blur shadows re-rasterize against the moving
  // Dismissible background each frame. The fix wraps the whole card in a
  // RepaintBoundary so it composites as ONE cached layer. These tests pin
  // that structure so a future refactor can't silently drop it.

  testWidgets('emoji tile lives inside a RepaintBoundary inside the Dismissible',
      (tester) async {
    final store = HabitStore.instance;
    store.habits.addAll([
      Habit(
          id: 'v1',
          name: 'Morning Run',
          emoji: '🏃',
          colorValue: 0xFFFF007F,
          frequency: 'Daily'),
    ]);
    await pumpHabitsTab(tester);

    final emoji = find.text('🏃');
    expect(emoji, findsOneWidget);

    // Ghost-fix structure: the emoji tile's glow/blur shadow is the only
    // thing that smears during a swipe, so it must be isolated in its own
    // RepaintBoundary. The boundary must NOT wrap the whole card — a whole-
    // card raster layer renders a black rectangle that slides with the card
    // on some GPUs (the black-box glitch).
    final dismissible = find.byType(Dismissible).first;
    expect(dismissible, findsWidgets,
        reason: 'mission card must be a Dismissible');
    final dismissibleWidget = tester.widget<Dismissible>(dismissible);
    expect(dismissibleWidget.child, isNot(isA<RepaintBoundary>()),
        reason:
            'the whole card must NOT be wrapped in a RepaintBoundary — that '
            'renders a black rectangle sliding with the card on swipe '
            '(black-box fix)');

    final boundary = find.ancestor(
      of: emoji,
      matching: find.byType(RepaintBoundary),
    );
    expect(boundary, findsWidgets,
        reason: 'RepaintBoundary must wrap the emoji tile (swipe-ghost fix)');
  });

  // ─── REORDER DRAG-PROXY FIX (rectangular grey box while dragging) ──
  // ReorderableListView's default drag proxy paints a rectangular elevated
  // Material/shadow that ignores the card's rounded corners. The fix wraps
  // each item in a transparency Material and swaps in a custom proxyDecorator
  // that draws a ROUNDED shadow instead. These tests pin both halves so a
  // future refactor can't silently drop them.

  testWidgets('mission cards sit inside a transparency Material',
      (tester) async {
    final store = HabitStore.instance;
    store.habits.addAll([
      Habit(
          id: 'v1',
          name: 'Morning Run',
          emoji: '🏃',
          colorValue: 0xFFFF007F,
          frequency: 'Daily'),
    ]);
    await pumpHabitsTab(tester);

    // Walk up from the Dismissible: its nearest Material ancestor must be the
    // transparency wrapper (NOT the default opaque/rectangular Material).
    Material? wrapper;
    tester.element(find.byType(Dismissible).first).visitAncestorElements((el) {
      final w = el.widget;
      if (wrapper == null && w is Material) wrapper = w;
      return true;
    });
    expect(wrapper, isNotNull);
    expect(wrapper!.type, MaterialType.transparency,
        reason:
            'each reorderable item must be wrapped in a transparency Material '
            'so the framework never paints its rectangular Material box '
            'under the card while dragging');
  });

  testWidgets('ReorderableListView uses a custom rounded proxyDecorator',
      (tester) async {
    final store = HabitStore.instance;
    store.habits.addAll([
      Habit(
          id: 'v1',
          name: 'Morning Run',
          emoji: '🏃',
          colorValue: 0xFFFF007F,
          frequency: 'Daily'),
    ]);
    await pumpHabitsTab(tester);

    final reorder = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    expect(reorder.proxyDecorator, isNotNull,
        reason:
            'the default drag proxy paints a rectangular elevated box; the '
            'custom proxyDecorator (transparency Material + rounded shadow) '
            'must be set');
  });

  // ─── SWIPE-BACKGROUND CORNER FIX (square reveal edges behind the card) ──
  // The Dismissible's reveal background is drawn edge-to-edge behind the
  // rounded card, so without a clip its square corners show past the card's
  // 28px corners while swiping. The fix wraps the whole Dismissible
  // (background + foreground) in a ClipRRect matching the card radius.
  testWidgets('swipe tile is clipped to the card radius', (tester) async {
    final store = HabitStore.instance;
    store.habits.addAll([
      Habit(
          id: 'v1',
          name: 'Morning Run',
          emoji: '🏃',
          colorValue: 0xFFFF007F,
          frequency: 'Daily'),
    ]);
    await pumpHabitsTab(tester);

    final dismissible = find.byType(Dismissible).first;
    final clip = find.ancestor(
      of: dismissible,
      matching: find.byType(ClipRRect),
    );
    expect(clip, findsOneWidget,
        reason:
            'the Dismissible (background + card) must sit inside a ClipRRect '
            'so the reveal background never paints square corners past the '
            'rounded card');
    final clipWidget = tester.widget<ClipRRect>(clip.first);
    expect(clipWidget.borderRadius, BorderRadius.circular(28),
        reason:
            'clip radius must match habitlyCard()/habitlyHeroCard() 28px '
            'corners');
  });

  // ─── SOFT-EDGE SWIPE FIX (moving card keeps rounded corners) ──
  // The moving card must keep its 28px rounded corners so it reads as a card
  // mid-swipe (a flat rectangle looks like a glitch), but it must NOT paint
  // its own border (that rode the moving edge as a lavender seam line). The
  // reveal backgrounds must be full-bleed squares so the card's corner cutout
  // always shows reveal color — the outer ClipRRect(28) owns the tile's
  // rounding. These pins keep all three halves in place.
  testWidgets('moving card keeps rounded corners, no border; reveal is square',
      (tester) async {
    final store = HabitStore.instance;
    store.habits.addAll([
      Habit(
          id: 'v1',
          name: 'Morning Run',
          emoji: '🏃',
          colorValue: 0xFFFF007F,
          frequency: 'Daily'),
    ]);
    await pumpHabitsTab(tester);

    final dismissible =
        tester.widget<Dismissible>(find.byType(Dismissible).first);

    // 1. Reveal backgrounds are full-bleed squares — no own radius.
    for (final bg in [
      dismissible.background,
      dismissible.secondaryBackground,
    ]) {
      final container = bg as Container;
      final deco = container.decoration! as BoxDecoration;
      expect(deco.borderRadius, isNull,
          reason:
              'reveal must be a full-bleed square — the outer ClipRRect(28) '
              'owns the tile rounding, and a square reveal sits flush under '
              'the card\'s moving corners');
    }

    // 2. The moving card keeps its 28px rounded corners (soft edges)...
    final card = (dismissible.child as GestureDetector).child! as Container;
    final cardDeco = card.decoration! as BoxDecoration;
    expect(cardDeco.borderRadius, BorderRadius.circular(28),
        reason:
            'moving card must keep soft rounded corners while swiping — a '
            'flat rectangle reads as a glitch');

    // ...but paints no border (it rode the moving edge as a seam line).
    expect(cardDeco.border, isNull,
        reason:
            'no border on the moving card — a card-painted border showed as '
            'a lavender seam line between the reveal and the card');
  });

  // ─── GESTURE-CONFLICT FIX (slow swipes were hijacked into reorders) ──
  testWidgets('emoji tile is NOT a reorder handle — the grip is the only one',
      (tester) async {
    final store = HabitStore.instance;
    store.habits.addAll([
      Habit(
          id: 'v1',
          name: 'Morning Run',
          emoji: '🏃',
          colorValue: 0xFFFF007F,
          frequency: 'Daily'),
    ]);
    await pumpHabitsTab(tester);

    final emoji = find.text('🏃');
    expect(emoji, findsOneWidget);

    // A ReorderableDragStartListener on the emoji tile used a long-press
    // drag recognizer that competed with the Dismissible's horizontal drag:
    // slow swipes on the card got hijacked into reorder drags. The tile must
    // NOT carry a reorder listener — only the drag-grip icon may.
    expect(
      find.ancestor(
        of: emoji,
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsNothing,
      reason:
          'emoji tile must not be a reorder handle (slow-swipe glitch fix)',
    );

    final grip = find.byIcon(Icons.drag_handle_rounded);
    expect(grip, findsOneWidget);
    expect(
      find.ancestor(
        of: grip,
        matching: find.byType(ReorderableDragStartListener),
      ),
      findsWidgets,
      reason: 'the drag-grip icon must remain the reorder handle',
    );
  });

  // ─── EMOJI TILE: ACCENT-TINTED, STILL FLAT ─────────────────
  test('emojiContainer tile is accent-tinted but flat (no glow)', () {
    const c = Color(0xFF00FF66);
    final deco = MacroSnapTheme.emojiContainer(c);

    // Still flat: no gradient and no glow/shadow. A shadow paints a dark
    // "ghost reflection" under the glyph, and a glow smears during swipes
    // (the RepaintBoundary around the tile covers the rest).
    expect(deco.gradient, isNull);
    expect(deco.boxShadow, isNull);

    // The caller's accent now reaches the tile: for this green accent the
    // green channel outruns the red one, and the tile is neither the old
    // neutral color nor the card it sits on.
    final tile = deco.color!;
    expect(tile.g, greaterThan(tile.r),
        reason: 'accent hue must reach the tile');
    expect(tile, isNot(MacroSnapTheme.cardDarkLight));
    expect(tile, isNot(MacroSnapTheme.cardDark));

    // The tile must visibly separate from the card. It used to differ by only
    // 8 RGB steps (#1C1C1C on #141414), which made habit icons look invisible.
    // NOTE: Color.r/.g/.b are normalized 0..1 channels — scale by 255 before
    // comparing against a threshold expressed in RGB steps.
    final card = MacroSnapTheme.cardDark;
    final separation = ((tile.r - card.r).abs() +
            (tile.g - card.g).abs() +
            (tile.b - card.b).abs()) *
        255;
    expect(separation, greaterThanOrEqualTo(30),
        reason: 'tile must not blend into the card behind it');

    // Accent-tinted hairline border instead of the neutral gray one.
    final border = deco.border! as Border;
    expect(border.top.width, 1);
    expect(border.top.color, isNot(MacroSnapTheme.cardDarkBorder));
  });

  test('emojiStyle is flat — no ghost shadows on the glyph', () {
    final style = MacroSnapTheme.emojiStyle();
    // Ghost-shadow fix: glyphs must render flat (no drop shadow / halo),
    // otherwise a dark shadow shows through as a ghost reflection on
    // emoji surfaces (picker chips, mission cards, actions sheet).
    expect(style.shadows, isNull);
  });

  // ─── SWIPE BEHAVIOR (still works with the stronger glow) ───
  testWidgets('swipe right completes the habit and the card snaps back',
      (tester) async {
    final store = HabitStore.instance;
    final h = Habit(
        id: 'v1',
        name: 'Morning Run',
        emoji: '🏃',
        colorValue: 0xFFFF007F,
        frequency: 'Daily');
    store.habits.add(h);
    await pumpHabitsTab(tester);

    final now = DateTime.now();
    expect(h.isCompleted(now), isFalse);

    // >0.4 of the ~764px-wide card (Dismissible's default dismissThresholds)
    // so confirmDismiss actually fires. Fixed pumps (never pumpAndSettle):
    // StreakFlame's flicker controller repeats forever, so pumpAndSettle
    // would time out.
    //
    // Persistence is now DEFERRED until after the snap-back (see
    // _missionCard): the Dismissible must finish moving to the dismissed
    // position first, then confirmDismiss runs and starts a 350ms deferred
    // persist timer, which needs one more pump to flush.
    await tester.drag(find.text('Morning Run'), const Offset(500, 0));
    await tester.pump(); // gesture ends → move-to-dismissed starts
    await tester.pump(const Duration(milliseconds: 400)); // move completes → confirmDismiss → 350ms persist timer starts
    await tester.pump(const Duration(milliseconds: 500)); // deferred persist (350ms) fires with margin → store.update + notify
    await tester.pump(const Duration(milliseconds: 300)); // snap-back reverse animation

    expect(h.isCompleted(now), isTrue,
        reason: 'swipe right = complete the habit');
    expect(find.text('Morning Run'), findsOneWidget,
        reason: 'confirmDismiss returns false → card snaps back, not removed');
  });

  testWidgets('swipe left un-completes today (does NOT reset the streak)',
      (tester) async {
    final store = HabitStore.instance;
    final h = Habit(
        id: 'v1',
        name: 'Morning Run',
        emoji: '🏃',
        colorValue: 0xFFFF007F,
        frequency: 'Daily');
    // Pre-complete today + yesterday so there is a streak that must survive.
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    h.completedDates.addAll([dateKey(now), dateKey(yesterday)]);
    store.habits.add(h);
    await pumpHabitsTab(tester);

    expect(h.currentStreak(), greaterThan(0));

    // Fixed pumps — StreakFlame's flicker repeats forever so pumpAndSettle
    // would time out. Same deferred-persist timing as the swipe-right test:
    // move completes → confirmDismiss → 350ms persist timer → flush it.
    await tester.drag(find.text('Morning Run'), const Offset(-500, 0));
    await tester.pump(); // gesture ends → move-to-dismissed starts
    await tester.pump(const Duration(milliseconds: 400)); // move completes → confirmDismiss → 350ms persist timer starts
    await tester.pump(const Duration(milliseconds: 500)); // deferred persist (350ms) fires with margin → store.update + notify + SnackBar
    await tester.pump(const Duration(milliseconds: 300)); // snap-back reverse animation

    expect(h.isCompleted(now), isFalse,
        reason: 'swipe left = un-complete today\'s task');
    expect(h.isCompleted(yesterday), isTrue,
        reason: 'swipe left must NOT reset the streak — past days stay intact');
    expect(find.text('Morning Run'), findsOneWidget,
        reason: 'confirmDismiss returns false → card snaps back, not removed');
  });

  testWidgets('swipe right on an already-completed habit keeps it completed',
      (tester) async {
    final store = HabitStore.instance;
    final h = Habit(
        id: 'v1',
        name: 'Morning Run',
        emoji: '🏃',
        colorValue: 0xFFFF007F,
        frequency: 'Daily');
    final now = DateTime.now();
    h.completedDates.add(dateKey(now)); // already completed
    store.habits.add(h);
    await pumpHabitsTab(tester);

    await tester.drag(find.text('Morning Run'), const Offset(500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.isCompleted(now), isTrue,
        reason: 'swipe right = complete, never un-complete');
    expect(find.text('Morning Run'), findsOneWidget);
  });
}
