part of 'result_screen.dart';

/// Which total a macro tile edits.
enum _MacroField { calories, protein, carbs, fats }

/// One row of the INGREDIENTS list.
class _IngredientLine {
  const _IngredientLine({
    required this.name,
    required this.grams,
    required this.approximate,
    required this.score,
  });

  final String name;

  /// 0 when the weight is genuinely unknown — the row then shows no grams
  /// rather than an invented number.
  final double grams;

  /// True when [grams] was apportioned from the whole-photo weight because the
  /// dish itself had none (multi-item photos). Rendered with a "≈".
  final bool approximate;

  /// 0–5 health score for this component.
  final int score;
}

/// The result card: what the AI saw, how healthy it is, the macros and their
/// per-value editors, the ingredient breakdown and the tastiness verdict.
///
/// This is a `part` of `result_screen.dart`, so it reads the screen's state
/// directly instead of threading a dozen callbacks through a widget — the
/// screen owns the analysis, and every editor here mutates that one result.
extension _ResultCard on _ResultScreenState {
  /// A meal that is already logged is read-only.
  bool get _cardReadOnly => widget.existingMeal != null;

  int get _cardHealthScore =>
      _healthOverride ?? _computedHealth(_result!).score;

  HealthScore get _cardHealth =>
      HealthScore(_cardHealthScore, _computedHealth(_result!).reasons);

  HealthScore _computedHealth(NutritionResult r) => HealthScore.of(
    caloriesPer100g: r.caloriesPer100g.toDouble(),
    proteinPer100g: r.proteinPer100g,
    carbsPer100g: r.carbsPer100g,
    fatsPer100g: r.fatsPer100g,
    fiberPer100g: r.fiberPer100g,
    sugarPer100g: r.sugarPer100g,
  );

  /// The dish name shown as the card's title (editable).
  String get _cardTitle {
    final override = _titleOverride;
    if (override != null && override.isNotEmpty) return override;
    final r = _result!;
    return r.dishes.length == 1
        ? r.dishes.first.name
        : '${r.dishes.length} items';
  }

  /// The INGREDIENTS list.
  ///
  /// Preferred source is the AI's own component breakdown. When the server did
  /// not send one, the detected dish *is* the ingredient — that is the honest
  /// fallback: no component names or weights are invented here.
  List<_IngredientLine> get _cardIngredients {
    final r = _result!;
    final lines = <_IngredientLine>[];

    for (final dish in r.dishes) {
      if (dish.ingredients.isNotEmpty) {
        for (final part in dish.ingredients) {
          lines.add(
            _IngredientLine(
              name: part.name,
              grams: part.grams,
              approximate: part.grams <= 0,
              // The model's own score wins; otherwise score the component from
              // the nutrition of the dish it belongs to (the best we know).
              score: part.healthScore ?? _dishScore(dish),
            ),
          );
        }
        continue;
      }

      // No breakdown: a single dish weighs exactly what the photo weighs; on a
      // multi-item photo the total is apportioned by calorie share, which is
      // an estimate and is marked as one.
      final multi = r.dishes.length > 1;
      final share = multi && r.caloriesPer100g > 0
          ? dish.caloriesPer100g / r.caloriesPer100g
          : 1.0;
      final grams = dish.grams > 0 ? dish.grams : r.grams * share;
      lines.add(
        _IngredientLine(
          name: dish.name,
          grams: grams,
          approximate: dish.grams <= 0 && multi,
          score: _dishScore(dish),
        ),
      );
    }
    return lines;
  }

  int _dishScore(DishItem dish) => HealthScore.of(
    caloriesPer100g: dish.caloriesPer100g.toDouble(),
    proteinPer100g: dish.proteinPer100g,
    carbsPer100g: dish.carbsPer100g,
    fatsPer100g: dish.fatsPer100g,
    fiberPer100g: dish.fiberPer100g,
    sugarPer100g: dish.sugarPer100g,
  ).score;

  Tastiness? get _cardTastiness =>
      _tastiness ?? Tastiness.fromId(widget.existingMeal?.tastiness);

  Widget _buildNutritionCard(bool isDark, NutritionResult r) {
    final health = _cardHealth;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _cardTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.4,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              if (!_cardReadOnly)
                EditPencil(
                  onTap: _editDishName,
                  semanticLabel: 'Edit dish name',
                ),
            ],
          ),
          const SizedBox(height: 6),
          HealthScorePill(
            score: health.score,
            max: HealthScore.max,
            label: health.label,
            onEdit: _cardReadOnly ? null : _editHealthScore,
          ),
          const SizedBox(height: 16),
          _buildMacroGrid(isDark, r),
          const SizedBox(height: 20),
          _buildIngredients(isDark),
          if (!_cardReadOnly) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showEditDialog(isDark, r),
                icon: const Icon(Icons.edit_rounded, size: 17),
                label: const Text(
                  'Edit',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MacroSnapTheme.neonGreen,
                  backgroundColor: MacroSnapTheme.neonGreen.withValues(
                    alpha: 0.06,
                  ),
                  side: BorderSide(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.25),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _buildTastiness(isDark),
        ],
      ),
    );
  }

  Widget _buildMacroGrid(bool isDark, NutritionResult r) {
    final valueColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: NutritionTile(
                label: 'Calories',
                value: '${r.calories}',
                unit: 'kcal',
                color: MacroSnapTheme.macroCalories,
                icon: Icons.local_fire_department_rounded,
                onEdit: _cardReadOnly
                    ? null
                    : () => _editMacroTotal(r, _MacroField.calories),
                // The slot-machine reveal lives in the tile now: the number
                // still spins up and still triggers the confetti, but the card
                // is laid out like the design instead of one giant headline.
                valueWidget: CalorieReveal(
                  key: _calorieKey,
                  calories: r.calories,
                  protein: r.protein,
                  animate: widget.existingMeal == null,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: valueColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: NutritionTile(
                label: 'Carbs',
                value: '${r.carbs.round()}',
                unit: 'g',
                color: MacroSnapTheme.macroCarbs,
                icon: Icons.grain_rounded,
                onEdit: _cardReadOnly
                    ? null
                    : () => _editMacroTotal(r, _MacroField.carbs),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: NutritionTile(
                label: 'Proteins',
                value: '${r.protein.round()}',
                unit: 'g',
                color: MacroSnapTheme.macroProtein,
                icon: Icons.fitness_center_rounded,
                onEdit: _cardReadOnly
                    ? null
                    : () => _editMacroTotal(r, _MacroField.protein),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: NutritionTile(
                label: 'Fats',
                value: '${r.fats.round()}',
                unit: 'g',
                color: MacroSnapTheme.macroFats,
                icon: Icons.water_drop_rounded,
                onEdit: _cardReadOnly
                    ? null
                    : () => _editMacroTotal(r, _MacroField.fats),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIngredients(bool isDark) {
    final lines = _cardIngredients;
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INGREDIENTS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
        const SizedBox(height: 8),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    line.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                if (line.grams > 0) ...[
                  Text(
                    '${line.approximate ? '≈' : ''}${line.grams.round()} g',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: MacroSnapTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                _buildIngredientScore(line.score),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildIngredientScore(int score) {
    final color = score >= 5
        ? MacroSnapTheme.successGreen
        : score >= 4
        ? MacroSnapTheme.neonGreen
        : score >= 3
        ? MacroSnapTheme.neonYellow
        : MacroSnapTheme.neonRed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.4),
          ),
          child: Text(
            '$score',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ],
    );
  }

  Widget _buildTastiness(bool isDark) {
    final selected = _cardTastiness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Tastiness',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _showTastinessInfo,
              tooltip: 'What is Tastiness?',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in Tastiness.values)
              _buildTastinessPill(value, selected == value),
          ],
        ),
      ],
    );
  }

  Widget _buildTastinessPill(Tastiness value, bool selected) {
    const accent = MacroSnapTheme.neonRed;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? accent : MacroSnapTheme.borderSubtle(context),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Text(
        value.label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected
              ? accent
              : MacroSnapTheme.textSecondary(context),
        ),
      ),
    );
    if (_cardReadOnly) return pill;
    return Semantics(
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _setTastiness(value),
        child: pill,
      ),
    );
  }

  /// Rename the dish. Kept session-only: it labels this analysis (and the
  /// meal if logged), it does not retrain anything.
  Future<void> _editDishName() async {
    final controller = TextEditingController(text: _cardTitle);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? MacroSnapTheme.cardDark
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Dish name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final title = saved?.trim();
    if (title == null || title.isEmpty || !mounted) return;
    HapticFeedback.selectionClick();
    _rebuild(() => _titleOverride = title);
  }

  /// Override the computed health score, with the reasons shown so the number
  /// is explained rather than asserted.
  Future<void> _editHealthScore() async {
    final health = _cardHealth;
    var chosen = health.score;
    final saved = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? MacroSnapTheme.cardDark
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Health Score'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                health.reasons.isEmpty
                    ? 'Computed from protein, fibre, sugar, fat and calorie '
                          'density.'
                    : 'Computed from: ${health.reasons.join(', ').toLowerCase()}.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i <= HealthScore.max; i++)
                    ChoiceChip(
                      label: Text('$i'),
                      selected: chosen == i,
                      onSelected: (_) => setDialogState(() => chosen = i),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, chosen),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    HapticFeedback.selectionClick();
    _rebuild(() => _healthOverride = saved);
  }

  /// Edit one macro total. The value is entered as the total on the card (what
  /// the user is looking at), then converted back to per-100 g through the
  /// serving weight, so the gram adjuster keeps working afterwards.
  Future<void> _editMacroTotal(NutritionResult r, _MacroField field) async {
    final current = switch (field) {
      _MacroField.calories => '${r.calories}',
      _MacroField.protein => r.protein.toStringAsFixed(1),
      _MacroField.carbs => r.carbs.toStringAsFixed(1),
      _MacroField.fats => r.fats.toStringAsFixed(1),
    };
    final label = switch (field) {
      _MacroField.calories => 'Calories (kcal)',
      _MacroField.protein => 'Protein (g)',
      _MacroField.carbs => 'Carbs (g)',
      _MacroField.fats => 'Fats (g)',
    };
    final controller = TextEditingController(text: current);
    final saved = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? MacroSnapTheme.cardDark
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Edit ${label.split(' ').first}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) =>
              Navigator.pop(ctx, double.tryParse(value.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || saved < 0 || !mounted) return;
    _applyMacroEdit(field, saved);
  }

  void _showTastinessInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? MacroSnapTheme.cardDark
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('What is Tastiness?'),
        content: Text(
          'Your own verdict on the meal. It is saved with the meal you log, '
          'so you can look back at what you actually enjoyed eating.\n\n'
          'It never affects your streak, your badges or your targets.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: MacroSnapTheme.textSecondary(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
