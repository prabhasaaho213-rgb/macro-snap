part of 'habits_tab.dart';

// Split out of habits_tab.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _HabitsMission on _HabitsTabState {
  // ─── MISSION CARD ──────────────────────────────────────────
  Widget _missionCard(Habit h, bool isDark, {required int index}) {
    final done = h.isCompleted(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // Clip the whole swipe tile to the card's rounded shape: the reveal
      // background is drawn edge-to-edge behind the card, so without a clip
      // its square corners show past the card's rounded corners while
      // swiping. 28px matches habitlyCard()/habitlyHeroCard().
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        // Reveal stack, bottom to top:
        //  1. Base layer in the card's own base tone — Dismissible translates
        //     the foreground card over the static reveal background, and at
        //     sub-pixel slide offsets the two never quite butt up, so a
        //     hairline of the page background can bleed through the seam.
        //     This layer guarantees any such gap shows card-tone instead.
        //  2. Static rounded outline — the moving card no longer paints its
        //     own border (a border riding the moving edge showed as a
        //     lavender seam line mid-swipe); the outline stays at the tile's
        //     true edges so the at-rest look is unchanged.
        //  3. The Dismissible (reveal backgrounds + moving card).
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: isDark ? const Color(0xFF050508) : Colors.white,
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF353550)
                        : const Color(0xFFC8BEFF),
                  ),
                ),
              ),
            ),
            Dismissible(
              key: ValueKey('dismiss_${h.id}'),
              direction: DismissDirection.horizontal,
              background: SwipeActionBackground(rightSwipe: true),
              secondaryBackground: SwipeActionBackground(rightSwipe: false),
              confirmDismiss: (direction) async {
                HapticFeedback.mediumImpact();
                if (direction == DismissDirection.startToEnd) {
                  // Swipe right → COMPLETE today's task (explicit: swiping right
                  // again on an already-completed card stays completed, it never
                  // un-completes). IDEMPOTENT: guard the add — completedDates is a
                  // List, so an unguarded add stacks a duplicate of today per swipe,
                  // and each duplicate later needs its own left swipe to undo.
                  // Mutate NOW so the state is correct, but persist AFTER the
                  // Dismissible snaps back.
                  final key = dateKey(DateTime.now());
                  if (!h.completedDates.contains(key)) {
                    h.completedDates.add(key);
                  }
                  h.skippedDates.remove(key);
                } else {
                  // Swipe left → UN-COMPLETE today's task. This is NOT a streak
                  // reset: previous days' history and skipped marks stay intact.
                  // Remove EVERY occurrence of today (also flushes duplicate entries
                  // stacked by older builds) so ONE swipe always fully undoes,
                  // no matter how many times it was completed.
                  final key = dateKey(DateTime.now());
                  h.completedDates.removeWhere((k) => k == key);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${h.name} marked as not completed'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
                Future.delayed(const Duration(milliseconds: 350), () {
                  store.update(h, syncReminder: false);
                });
                return false; // Snap back — don't dismiss
              },
              // card on some GPUs while swiping, so the card itself renders as
              // plain widgets.
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  h.toggle(DateTime.now());
                  // Completion toggle only — the reminder schedule is unchanged,
                  // so skip the zonedSchedule cancel+recreate churn.
                  store.update(h, syncReminder: false);
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  _showHabitActions(context, h, isDark);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  // The MOVING card keeps its rounded corners so the swiping card
                  // has soft edges (a flat rectangle reads as a glitch mid-swipe).
                  // No border though — a card-painted border rode the moving edge
                  // as a lavender seam line. The square reveal sits flush behind,
                  // the base layer catches sub-pixel gaps, and the static outline
                  // (in the Stack above) owns the at-rest border.
                  decoration: MacroSnapTheme.habitlyCard(
                    context,
                    showBorder: false,
                  ),
                  child: Row(
                    children: [
                      // Emoji container. Its glow/blur shadow is the ONLY thing
                      // that smears during a swipe, so it gets its own
                      // RepaintBoundary right here — isolating this tile rather
                      // than the whole card (a whole-card raster layer rendered a
                      // black rectangle on some GPUs).
                      //
                      // NOTE: NOT wrapped in a ReorderableDragStartListener — that
                      // long-press recognizer competed with the Dismissible's
                      // horizontal drag on the same surface, so slow swipes got
                      // hijacked into reorder drags (the swipe glitch). Reordering
                      // is grip-only (see the drag-grip icon below).
                      RepaintBoundary(
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: MacroSnapTheme.emojiContainer(h.color),
                          child: Center(
                            child: Text(
                              h.emoji,
                              style: MacroSnapTheme.emojiStyle(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: done
                                    ? (MacroSnapTheme.textTertiary(context))
                                    : (isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A1A)),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: MacroSnapTheme.neonPink,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${h.currentStreak()} · ${h.frequency}',
                                  style: TextStyle(
                                    color: MacroSnapTheme.textSecondary(
                                      context,
                                    ),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Check/Bolt status indicator
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: done
                              ? MacroSnapTheme.neonGreen
                              : MacroSnapTheme.neonGreen.withValues(
                                  alpha: 0.12,
                                ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          done ? Icons.check_rounded : Icons.bolt_rounded,
                          color: done ? Colors.black : MacroSnapTheme.neonGreen,
                          size: 27,
                        ),
                      ),
                      // Drag grip icon
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: MacroSnapTheme.textQuaternary(context),
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
