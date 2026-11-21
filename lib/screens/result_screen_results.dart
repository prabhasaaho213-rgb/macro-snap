part of 'result_screen.dart';

// Split out of result_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _ResultResults on _ResultScreenState {
  Widget _buildResults(bool isDark) {
    final r = _result!;
    final hasMultiDish = r.dishes.length > 1;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          FadeTransition(
            opacity: _fadeAnim,
            child: widget.existingMeal == null
                ? Hero(
                    tag: 'food_image_${widget.imagePath}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.file(
                        File(widget.imagePath),
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        // The photo lives in the OS temp dir; if Android has
                        // cleared it, show a neutral block instead of throwing
                        // a FileImage error into the widget tree.
                        errorBuilder: (_, _, _) => Container(
                          height: 220,
                          width: double.infinity,
                          color: MacroSnapTheme.borderSubtle(context),
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: MacroSnapTheme.textTertiary(context),
                          ),
                        ),
                      ),
                    ),
                  )
                : _buildMealPlaceholder(),
          ),
          const SizedBox(height: 12),

          // Low confidence warning banner (like Cal AI / MyFitnessPal)
          if (_showLowConfidenceWarning && widget.existingMeal == null)
            _buildLowConfidenceBanner(isDark),

          // Total-serving gram adjuster (defaults to 100 g). View mode keeps
          // the logged meal's totals as the source of truth, so it's hidden.
          if (widget.existingMeal == null) _buildGramAdjuster(isDark),

          if (hasMultiDish) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _rebuild(() => _showPerDish = !_showPerDish),
                  icon: Icon(
                    _showPerDish
                        ? Icons.view_agenda_rounded
                        : Icons.dashboard_rounded,
                    size: 16,
                    color: MacroSnapTheme.neonGreen,
                  ),
                  label: Text(
                    _showPerDish ? 'Show Totals' : 'Show per Dish',
                    style: TextStyle(
                      fontSize: 13,
                      color: MacroSnapTheme.greenText(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SlideTransition(
            position: _slideAnim,
            child: Column(
              children: [
                if (_showPerDish && hasMultiDish)
                  ...r.dishes.map((d) => _buildDishCard(isDark, d, r.grams)),
                _buildNutritionCard(isDark, r),
                const SizedBox(height: 16),
                SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: _animController,
                          curve: const Interval(
                            0.3,
                            1.0,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      ),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nutrition Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Calories, protein, carbs and fats are already the
                        // four highlighted cards at the top of this screen —
                        // repeating them here read like two different meals.
                        // This list keeps only what the cards do not show.
                        NutrientRow(
                          'Sugar',
                          r.sugar,
                          'g',
                          const Color(0xFFDB2777),
                          isDark,
                        ),
                        NutrientRow(
                          'Fiber',
                          r.fiber,
                          'g',
                          MacroSnapTheme.greenText(context),
                          isDark,
                        ),
                      ],
                    ),
                  ),
                ),
                if (r.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _animController,
                            curve: const Interval(
                              0.5,
                              1.0,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                        ),
                    child: GlassCard(
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: MacroSnapTheme.neonGreen.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              widget.existingMeal == null
                                  ? Icons.auto_awesome_rounded
                                  : Icons.description_outlined,
                              color: MacroSnapTheme.neonGreen,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.existingMeal == null
                                      ? 'AI Breakdown (${r.dishes.length} item${r.dishes.length > 1 ? 's' : ''})'
                                      : 'Meal Description',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1A1A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.existingMeal == null
                                      ? '${(r.confidence * 100).round()}% confidence · ${_stripGrams(r.description)}'
                                      : _stripGrams(r.description),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: MacroSnapTheme.textTertiary(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // View mode: the meal is already logged, so edit/log actions
                // don't apply — the close (X) button dismisses the screen.
                if (widget.existingMeal == null)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showEditDialog(isDark, r),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text(
                            'Edit',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MacroSnapTheme.neonGreen,
                            side: BorderSide(
                              color: MacroSnapTheme.neonGreen.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: GradientButton(
                          label: 'Log This Meal',
                          onPressed: () async {
                            unawaited(HapticFeedback.heavyImpact());
                            final id = const Uuid().v4();
                            final loggedAt = DateTime.now();
                            // Keep the photo for the next 24 hours so the
                            // logged meal card and the history can show what
                            // was actually scanned. The file the scanner
                            // handed us lives in the OS temp directory and is
                            // deleted when this screen goes away, so it is
                            // copied before the meal is recorded — and the
                            // copy is stamped with the log time, which is
                            // what its 24 hours are measured from.
                            final keptImage = await MealImageStore.instance
                                .save(
                                  mealId: id,
                                  sourcePath: widget.imagePath,
                                  at: loggedAt,
                                );
                            // The name the user sees (possibly renamed) is
                            // the name that gets logged, so the meal list and
                            // the card never disagree.
                            await MealStore.instance.add(
                              MealRecord(
                                id: id,
                                date: loggedAt,
                                name: _cardTitle,
                                category: '',
                                calories: r.calories,
                                protein: r.protein,
                                carbs: r.carbs,
                                fats: r.fats,
                                fiber: r.fiber,
                                serving: r.description,
                                // The scan's per-item breakdown rides on
                                // the record, so reopening this meal later
                                // shows item names, gram weights and the
                                // per-dish cards exactly as the scan did.
                                items: [
                                  for (final d in r.dishes)
                                    MealItem(
                                      name: d.name,
                                      serving: d.portionDescription,
                                      grams: d.grams,
                                      calories: d.caloriesPer100g,
                                      protein: d.proteinPer100g,
                                      carbs: d.carbsPer100g,
                                      fats: d.fatsPer100g,
                                      fiber: d.fiberPer100g,
                                      ingredients: [
                                        for (final i in d.ingredients)
                                          MealIngredient(
                                            name: i.name,
                                            grams: i.grams,
                                          ),
                                      ],
                                    ),
                                ],
                                servingGrams: r.grams,
                                tastiness: _cardTastiness?.id,
                                imagePath: keptImage,
                              ),
                            );
                            if (mounted) {
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Low confidence warning banner — shown when AI couldn't identify food.
  /// Offers retry (same photo) and manual entry options.
  Widget _buildLowConfidenceBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A1A00) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MacroSnapTheme.neonOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: MacroSnapTheme.neonOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Food not identified clearly',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Tips
          Text(
            'The AI couldn\'t identify this food with confidence. This scan was NOT counted against your free limit.',
            style: TextStyle(
              fontSize: 13,
              color: MacroSnapTheme.textSecondary(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              // Retry button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retryScan,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Retry Photo',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MacroSnapTheme.neonOrange,
                    side: BorderSide(
                      color: MacroSnapTheme.neonOrange.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Manual entry button
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showManualEntryDialog(isDark),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text(
                    'Enter Manually',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: MacroSnapTheme.neonOrange,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Total-serving gram adjuster. Defaults to 100 g; the user can raise or
  /// lower it and every item's nutrients rescale from their per-100g values.
  ///
  /// The grams value itself is tappable: tapping it opens a numeric keypad so
  /// the user can type an exact weight (e.g. 120 g) and commit it with Enter.
  /// Every macro then recomputes from the new total, the same way the +/- and
  /// the Edit sheet do.
  Widget _buildGramAdjuster(bool isDark) {
    return SemanticTapTarget(
      onTap: () => _editTotalGrams(isDark),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.scale_rounded,
                size: 18,
                color: MacroSnapTheme.textTertiary(context),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  // The label wraps to a second line when the controls crowd it
                  // instead of shrinking into "Total Serv…".
                  'Total Serving',
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ),
              const Spacer(),
              Semantics(
                button: true,
                label: 'Decrease serving size',
                child: GestureDetector(
                  onTap: () => _setGrams(_grams >= 50 ? _grams - 25 : 25),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.remove_rounded,
                      size: 18,
                      color: MacroSnapTheme.neonGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: 'Serving size in grams: $_grams',
                child: GestureDetector(
                  onTap: () => _editTotalGrams(isDark),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: MacroSnapTheme.neonGreen.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_grams',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'g',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: MacroSnapTheme.textTertiary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: 'Increase serving size',
                child: GestureDetector(
                  onTap: () => _setGrams(_grams <= 975 ? _grams + 25 : 1000),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: MacroSnapTheme.neonGreen,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the numeric keypad so the user can type the total serving weight.
  /// On Enter, the new total is committed and every macro is recomputed from
  /// its per-100 g value, including the dish cards and the ingredients list.
  Future<void> _editTotalGrams(bool isDark) async {
    final controller = TextEditingController(text: _grams.toString());
    final entered = await showDialog<int>(
      context: context,
      builder: (ctx) => _GramKeypadDialog(
        controller: controller,
        initial: _grams,
      ),
    );
    controller.dispose();
    if (entered == null || !mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    _setGrams(entered);
  }
}

/// A small numeric keypad so the user can type a serving weight in grams.
/// This is the tap-to-edit path for the Total Serving card: the user taps the
/// grams value, gets a visible keypad, types a number, and commits it with the
/// Enter button ("Save").
class _GramKeypadDialog extends StatefulWidget {
  final TextEditingController controller;
  final int initial;

  const _GramKeypadDialog(
    {required this.controller, required this.initial});

  @override
  State<_GramKeypadDialog> createState() => _GramKeypadDialogState();
}

class _GramKeypadDialogState extends State<_GramKeypadDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _append(String digit) {
    if (digit == '.' && _ctrl.text.contains('.')) return;
    final raw = _ctrl.text;
    if (digit == '.' && raw.endsWith('.')) return;
    final candidate = raw + digit;
    if (int.tryParse(candidate) == null && !candidate.contains('.')) return;
    final parsed = double.tryParse(candidate);
    if (parsed == null) return;
    // Keep reasonable bounds: 1 g to 10000 g.
    if (parsed < 1 || parsed > 10000) return;
    _ctrl.text = parsed == parsed.roundToDouble()
        ? parsed.round().toString()
        : parsed.toString();
  }

  void _backspace() {
    if (_ctrl.text.isEmpty) return;
    _ctrl.text = _ctrl.text.trimRight();
    if (_ctrl.text.isEmpty) _ctrl.text = '0';
  }

  static const _inputMaxLength = 6;

  int? _commit() {
    // A pasted or manually entered value longer than the cap is reduced to
    // the first _inputMaxLength characters so the parser and the 40-sp preview
    // never see an absurdly long string.
    if (_ctrl.text.length > _inputMaxLength) {
      _ctrl.text = _ctrl.text.substring(0, _inputMaxLength);
    }
    final text = _ctrl.text.trim();
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null) {
      final doubleParsed = double.tryParse(text);
      if (doubleParsed == null) return null;
      if (doubleParsed < 1 || doubleParsed > 10000) return null;
      return doubleParsed.round();
    }
    if (parsed < 1 || parsed > 10000) return null;
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.edit_rounded,
              color: MacroSnapTheme.neonGreen,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Edit serving size'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Big read-only preview of what the user is typing.
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: isDark
                  ? MacroSnapTheme.neonGreen.withValues(alpha: 0.06)
                  : MacroSnapTheme.neonGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: MacroSnapTheme.neonGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              _ctrl.text.isEmpty ? '0' : _ctrl.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                letterSpacing: -1.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'grams',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
          const SizedBox(height: 16),
          // Numeric keypad.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                _KeypadButton(
                  label: digit,
                  onTap: () {
                    _append(digit);
                    HapticFeedback.selectionClick();
                  },
                ),
              _KeypadButton(
                label: '.',
                onTap: () {
                  _append('.');
                  HapticFeedback.selectionClick();
                },
              ),
              _KeypadButton(
                label: '0',
                onTap: () {
                  _append('0');
                  HapticFeedback.selectionClick();
                },
              ),
              _KeypadButton(
                label: '⌫',
                onTap: () {
                  _backspace();
                  HapticFeedback.selectionClick();
                },
              ),
              _KeypadButton(
                label: 'Clear',
                onTap: () {
                  _ctrl.text = '0';
                  HapticFeedback.selectionClick();
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = _commit();
            if (value == null) {
              HapticFeedback.selectionClick();
              _ctrl.text = '0';
              return;
            }
            HapticFeedback.mediumImpact();
            Navigator.pop(context, value);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KeypadButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAction = label == 'Clear' || label == '⌫';
    return SizedBox(
      width: 64,
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: isAction
              ? MacroSnapTheme.textTertiary(context).withValues(alpha: 0.10)
              : MacroSnapTheme.neonGreen,
          foregroundColor: isAction
              ? MacroSnapTheme.textTertiary(context)
              : Colors.black,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Marks a tappable widget for a11y while keeping one clear visual tap target.
class SemanticTapTarget extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const SemanticTapTarget({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Edit total serving weight in grams',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: child,
      ),
    );
  }
}

