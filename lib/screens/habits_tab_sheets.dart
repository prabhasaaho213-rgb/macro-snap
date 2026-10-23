part of 'habits_tab.dart';

// Split out of habits_tab.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _HabitsSheets on _HabitsTabState {
  // ─── HABIT ACTIONS (Edit, Reset Streak, or Delete) ─────────
  void _showHabitActions(BuildContext context, Habit h, bool isDark) {
    final streak = h.currentStreak();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
        decoration: BoxDecoration(
          color: isDark ? MacroSnapTheme.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.borderSubtle(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Habit info header
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: MacroSnapTheme.emojiContainer(h.color),
                  child: Center(
                    child: Text(h.emoji, style: MacroSnapTheme.emojiStyle()),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: MacroSnapTheme.neonPink,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$streak · ${h.frequency}',
                            style: TextStyle(
                              fontSize: 13,
                              color: MacroSnapTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Edit Habit
            _actionTile(
              icon: Icons.edit_rounded,
              iconColor: MacroSnapTheme.neonCyan,
              title: 'Edit Habit',
              subtitle: 'Change name, icon, schedule or reminder',
              isDark: isDark,
              onTap: () {
                Navigator.pop(ctx);
                _showCreateHabitSheet(context, existing: h);
              },
            ),
            const SizedBox(height: 8),

            // Reset Streak
            _actionTile(
              icon: Icons.refresh_rounded,
              iconColor: MacroSnapTheme.neonOrange,
              title: 'Reset Streak',
              subtitle: 'Clear all progress, keep the habit',
              isDark: isDark,
              onTap: () {
                Navigator.pop(ctx);
                h.completedDates.clear();
                h.skippedDates.clear();
                // Completion-state change only — the reminder schedule is
                // unchanged, so skip the zonedSchedule cancel+recreate churn
                // (consistent with the mission-card swipe/tap paths).
                store.update(h, syncReminder: false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Streak reset for ${h.name}'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            // Delete
            _actionTile(
              icon: Icons.delete_rounded,
              iconColor: MacroSnapTheme.neonPink,
              title: 'Delete Habit',
              subtitle: 'Remove this habit permanently',
              isDark: isDark,
              onTap: () async {
                Navigator.pop(ctx);
                await store.remove(h);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── DAY DETAIL BOTTOM SHEET ────────────────────────────
  void _showDayDetail(DateTime date, int count, List<String> habitNames) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final dayDate = DateTime(date.year, date.month, date.day);
    final todayDate = DateTime(now.year, now.month, now.day);

    String title;
    if (dayDate == todayDate) {
      title = 'Today';
    } else if (dayDate == todayDate.subtract(const Duration(days: 1))) {
      title = 'Yesterday';
    } else {
      title = _monthDay(date);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
        decoration: BoxDecoration(
          color: isDark ? MacroSnapTheme.cardDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.borderSubtle(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.calendar_today_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        '$count/${habitNames.length} habits completed',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (habitNames.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      Text('😴', style: const TextStyle(fontSize: 36)),
                      const SizedBox(height: 8),
                      Text(
                        'Nothing logged this day',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...habitNames.map(
                (name) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: MacroSnapTheme.neonGreen.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: MacroSnapTheme.neonGreen,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── PRO UPSELL ────────────────────────────────────────────
  void _showProUpsell(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: MacroSnapTheme.neonGreen,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Habit limit reached',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Free users get ${HabitStore.freeHabitLimit} habits.\nGo Pro for unlimited habits, AI scans & more.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: MacroSnapTheme.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              GradientButton(
                // Short label so the CTA reads fully on narrow screens.
                label: 'GO PRO · ₹1 first month, then ₹49/mo',
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen(),
                    ),
                  );
                },
                height: 48,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    fontSize: 14,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CREATE / EDIT HABIT SHEET ─────────────────────────────
  /// Opens the habit form. Pass [existing] to edit an existing habit.
  Future<void> _showCreateHabitSheet(
    BuildContext context, {
    Habit? existing,
  }) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var emoji = existing?.emoji ?? '✨';
    var frequency = existing?.frequency ?? 'Daily';
    var color = existing?.colorValue ?? Habit.defaultColorValue;
    var weeklyDay = existing?.weeklyDay ?? DateTime.now().weekday;
    var reminderEnabled = existing?.reminderEnabled ?? false;
    var reminderHour = existing?.reminderHour ?? 20;
    var reminderMinute = existing?.reminderMinute ?? 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Edit mission' : 'Create a mission',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: nameCtrl,
                  autofocus: !isEdit,
                  decoration: InputDecoration(
                    hintText: 'What do you want to build?',
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      'Choose an icon',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    // Live preview of the currently selected emoji
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        emoji,
                        style: MacroSnapTheme.emojiStyle(fontSize: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...[
                      '✨',
                      '💧',
                      '📚',
                      '🏃',
                      '🧘',
                      '🎸',
                      '🍎',
                      '💻',
                      '🎯',
                      '😴',
                      '🧠',
                      '☕',
                    ].map(
                      (e) => ChoiceChip(
                        // Flat style — no drop shadow under the glyph, which
                        // previously rendered as a ghost reflection on the chip.
                        label: Text(e, style: const TextStyle(fontSize: 20)),
                        selected: emoji == e,
                        onSelected: (_) => setModalState(() => emoji = e),
                      ),
                    ),
                    // Paste an emoji copied from anywhere (messages, web, etc.)
                    ActionChip(
                      avatar: const Icon(
                        Icons.content_paste_rounded,
                        size: 16,
                        color: MacroSnapTheme.neonCyan,
                      ),
                      label: const Text(
                        'Paste',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: MacroSnapTheme.neonCyan.withValues(
                        alpha: 0.1,
                      ),
                      side: BorderSide(
                        color: MacroSnapTheme.neonCyan.withValues(alpha: 0.4),
                      ),
                      onPressed: () => _pasteEmojiFromClipboard(
                        context,
                        setModalState,
                        (v) => emoji = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Frequency',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: ['Daily', 'Weekdays', 'Weekly']
                      .map(
                        (e) => ChoiceChip(
                          label: Text(e),
                          selected: frequency == e,
                          onSelected: (_) => setModalState(() => frequency = e),
                        ),
                      )
                      .toList(),
                ),
                if (frequency == 'Weekly') ...{
                  const SizedBox(height: 14),
                  const Text(
                    'Weekly day',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: List.generate(7, (index) {
                      final wd = index + 1;
                      return ChoiceChip(
                        label: Text(weekdayLabel(wd)),
                        selected: weeklyDay == wd,
                        onSelected: (_) => setModalState(() => weeklyDay = wd),
                      );
                    }),
                  ),
                },
                const SizedBox(height: 18),
                const Text(
                  'Color',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children:
                      [
                            Habit.defaultColorValue,
                            0xFFFF007F,
                            0xFF6C3BFF,
                            0xFFFF9500,
                            0xFF34C759,
                            0xFF00B8D4,
                          ]
                          .map(
                            (value) => GestureDetector(
                              onTap: () => setModalState(() => color = value),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Color(value),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: color == value
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurface
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 18),

                // ─── Reminder toggle + time picker ───────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: MacroSnapTheme.neonGreen.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: MacroSnapTheme.neonGreen,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Daily reminder',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              reminderEnabled
                                  ? 'Every day at ${_formatTime(reminderHour, reminderMinute)}'
                                  : 'Get a nudge to complete this habit',
                              style: TextStyle(
                                fontSize: 12,
                                color: MacroSnapTheme.textTertiary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: reminderEnabled,
                        activeTrackColor: MacroSnapTheme.neonGreen,
                        onChanged: (v) =>
                            setModalState(() => reminderEnabled = v),
                      ),
                    ],
                  ),
                ),
                if (reminderEnabled) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: reminderHour,
                            minute: reminderMinute,
                          ),
                        );
                        if (picked != null) {
                          setModalState(() {
                            reminderHour = picked.hour;
                            reminderMinute = picked.minute;
                          });
                        }
                      },
                      icon: const Icon(Icons.access_time_rounded, size: 18),
                      label: Text(
                        'Remind me at ${_formatTime(reminderHour, reminderMinute)}',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: MacroSnapTheme.neonGreen,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      if (isEdit) {
                        existing
                          ..name = nameCtrl.text.trim()
                          ..emoji = emoji
                          ..colorValue = color
                          ..frequency = frequency
                          ..weeklyDay = weeklyDay
                          ..reminderEnabled = reminderEnabled
                          ..reminderHour = reminderHour
                          ..reminderMinute = reminderMinute;
                        await store.update(existing);
                      } else {
                        final habit = Habit(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          name: nameCtrl.text.trim(),
                          emoji: emoji,
                          colorValue: color,
                          frequency: frequency,
                          weeklyDay: weeklyDay,
                          reminderEnabled: reminderEnabled,
                          reminderHour: reminderHour,
                          reminderMinute: reminderMinute,
                        );
                        await store.add(habit);
                        if (context.mounted) Navigator.pop(context);
                        return;
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(
                      isEdit ? 'SAVE CHANGES' : 'CREATE MISSION',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
  }
}
