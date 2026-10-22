part of 'result_screen.dart';

// Split out of result_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _ResultDialogs on _ResultScreenState {
  /// Show manual entry dialog for food not identified.
  Future<void> _showManualEntryDialog(bool isDark) async {
    final nameCtrl = TextEditingController();
    final calCtrl = TextEditingController();
    final proCtrl = TextEditingController();
    final carbCtrl = TextEditingController();
    final fatCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
            const Text('Manual Entry'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the food details yourself',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Food Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: calCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Calories (kcal)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: proCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Protein (g)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: carbCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Carbs (g)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: fatCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Fats (g)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final cal = int.tryParse(calCtrl.text) ?? 200;
              final pro = double.tryParse(proCtrl.text) ?? 0;
              final carb = double.tryParse(carbCtrl.text) ?? 0;
              final fat = double.tryParse(fatCtrl.text) ?? 0;
              _rebuild(() {
                _result = NutritionResult(
                  dishes: [
                    DishItem(
                      name: name,
                      caloriesPer100g: cal,
                      proteinPer100g: pro,
                      carbsPer100g: carb,
                      fatsPer100g: fat,
                    ),
                  ],
                  description: 'Manually entered',
                  confidence: 1.0,
                  grams: 100,
                );
                _showLowConfidenceWarning = false;
              });
              // Save to recent foods
              await RecentFoodService.instance.add(
                RecentFood(
                  id: const Uuid().v4(),
                  name: name,
                  calories: cal,
                  protein: pro,
                  carbs: carb,
                  fats: fat,
                  serving: 'Manually entered',
                  scannedAt: DateTime.now(),
                ),
              );
              HapticFeedback.mediumImpact();
              // The recent-food save above awaits — guard the pop for it.
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    calCtrl.dispose();
    proCtrl.dispose();
    carbCtrl.dispose();
    fatCtrl.dispose();
  }

  Future<void> _showEditDialog(bool isDark, NutritionResult r) async {
    final calCtrl = TextEditingController(text: r.calories.toString());
    final proCtrl = TextEditingController(text: r.protein.toStringAsFixed(1));
    final carbCtrl = TextEditingController(text: r.carbs.toStringAsFixed(1));
    final fatCtrl = TextEditingController(text: r.fats.toStringAsFixed(1));

    /// The portion the AI assumed is 1×. Most corrections are "I ate half" or
    /// "that was a double portion", and scaling every number in one tap is far
    /// safer than asking people to retype calories *and* three macros — the
    /// retyping is where wrong numbers get saved.
    var portion = 1.0;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Edit Nutrition'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Portion',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: MacroSnapTheme.textSecondary(context),
                      ),
                    ),
                    const Spacer(),
                    for (final factor in const [0.5, 1.0, 1.5, 2.0])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(
                            factor == 0.5
                                ? '½×'
                                : (factor == 1.0
                                      ? '1×'
                                      : (factor == 1.5 ? '1½×' : '2×')),
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: portion == factor,
                          onSelected: (_) {
                            portion = factor;
                            calCtrl.text = (r.calories * factor)
                                .round()
                                .toString();
                            proCtrl.text = (r.protein * factor).toStringAsFixed(
                              1,
                            );
                            carbCtrl.text = (r.carbs * factor).toStringAsFixed(
                              1,
                            );
                            fatCtrl.text = (r.fats * factor).toStringAsFixed(1);
                            setDialogState(() {});
                            HapticFeedback.selectionClick();
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: calCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Calories (kcal)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: proCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Protein (g)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: carbCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Carbs (g)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: fatCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Fats (g)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final cal = int.tryParse(calCtrl.text) ?? r.calories;
                final pro = double.tryParse(proCtrl.text) ?? r.protein;
                final carb = double.tryParse(carbCtrl.text) ?? r.carbs;
                final fat = double.tryParse(fatCtrl.text) ?? r.fats;
                _rebuild(() {
                  _result = NutritionResult(
                    dishes: r.dishes,
                    description: r.description,
                    confidence: r.confidence,
                    grams: r.grams,
                  );
                  // Override the computed values by modifying dishes
                  if (r.dishes.isNotEmpty) {
                    final ratio = (r.grams > 0 ? r.grams : 100) / 100.0;
                    final d = r.dishes.first;
                    final adjustedDish = DishItem(
                      name: d.name,
                      portionDescription: d.portionDescription,
                      caloriesPer100g: ((cal / ratio) / r.dishes.length)
                          .round(),
                      proteinPer100g: (pro / ratio) / r.dishes.length,
                      carbsPer100g: (carb / ratio) / r.dishes.length,
                      fatsPer100g: (fat / ratio) / r.dishes.length,
                      fiberPer100g: d.fiberPer100g,
                      sugarPer100g: d.sugarPer100g,
                      suitableFor: d.suitableFor,
                    );
                    final adjustedDishes = [
                      adjustedDish,
                      ...r.dishes.sublist(1),
                    ];
                    _result = NutritionResult(
                      dishes: adjustedDishes,
                      description: '${r.description} (edited)',
                      confidence: r.confidence,
                      grams: r.grams,
                    );
                  }
                });
                HapticFeedback.mediumImpact();
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    calCtrl.dispose();
    proCtrl.dispose();
    carbCtrl.dispose();
    fatCtrl.dispose();
  }
}
