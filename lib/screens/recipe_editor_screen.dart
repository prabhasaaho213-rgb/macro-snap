import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';

class RecipeEditorScreen extends StatefulWidget {
  final String? recipeId;

  const RecipeEditorScreen({super.key, this.recipeId});

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  final _nameCtrl = TextEditingController();
  final _servingsCtrl = TextEditingController(text: '4');
  final _ingredientNameCtrl = TextEditingController();
  final _gramsCtrl = TextEditingController(text: '100');
  final _calCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatsCtrl = TextEditingController();
  final _fiberCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<RecipeIngredient> _ingredients = [];

  @override
  void initState() {
    super.initState();
    if (widget.recipeId != null) {
      final r = RecipeService.instance.getById(widget.recipeId!);
      if (r != null) {
        _nameCtrl.text = r.name;
        _servingsCtrl.text = r.servings.toString();
        _ingredients = r.ingredients
            .map(
              (i) => RecipeIngredient(
                name: i.name,
                grams: i.grams,
                caloriesPer100g: i.caloriesPer100g,
                proteinPer100g: i.proteinPer100g,
                carbsPer100g: i.carbsPer100g,
                fatsPer100g: i.fatsPer100g,
                fiberPer100g: i.fiberPer100g,
              ),
            )
            .toList();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _servingsCtrl.dispose();
    _ingredientNameCtrl.dispose();
    _gramsCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatsCtrl.dispose();
    _fiberCtrl.dispose();
    super.dispose();
  }

  void _addIngredient() {
    final name = _ingredientNameCtrl.text.trim();
    final grams = double.tryParse(_gramsCtrl.text) ?? 100;
    if (name.isEmpty) return;
    setState(() {
      _ingredients.add(
        RecipeIngredient(
          name: name,
          grams: grams,
          caloriesPer100g: double.tryParse(_calCtrl.text) ?? 0,
          proteinPer100g: double.tryParse(_proteinCtrl.text) ?? 0,
          carbsPer100g: double.tryParse(_carbsCtrl.text) ?? 0,
          fatsPer100g: double.tryParse(_fatsCtrl.text) ?? 0,
          fiberPer100g: double.tryParse(_fiberCtrl.text) ?? 0,
        ),
      );
      _ingredientNameCtrl.clear();
      _gramsCtrl.text = '100';
      _calCtrl.clear();
      _proteinCtrl.clear();
      _carbsCtrl.clear();
      _fatsCtrl.clear();
      _fiberCtrl.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameCtrl.text.trim();
    final servings = int.tryParse(_servingsCtrl.text) ?? 4;
    if (name.isEmpty || _ingredients.isEmpty) return;

    if (widget.recipeId != null) {
      await RecipeService.instance.update(
        widget.recipeId!,
        name,
        servings,
        _ingredients,
      );
    } else {
      await RecipeService.instance.add(name, servings, _ingredients);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalCal = _ingredients.fold(0.0, (s, i) => s + i.calories);
    final servings = int.tryParse(_servingsCtrl.text) ?? 4;
    final perServingCal = servings > 0 ? totalCal / servings : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recipeId != null ? 'Edit Recipe' : 'New Recipe',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: _input('Recipe name', isDark),
              style: _textStyle(isDark),
              validator: (v) =>
                  v?.trim().isEmpty == true ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _servingsCtrl,
              decoration: _input('Number of servings', isDark),
              style: _textStyle(isDark),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 24),
            Text(
              'Ingredients',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 12),
            if (_ingredients.isNotEmpty)
              ..._ingredients.asMap().entries.map(
                (e) => _buildIngredientTile(e.key, isDark),
              ),
            const SizedBox(height: 16),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Ingredient',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MacroSnapTheme.textPrimaryMuted(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ingredientNameCtrl,
                    decoration: _input('Ingredient name', isDark),
                    style: _textStyle(isDark),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _gramsCtrl,
                    decoration: _input('Grams (per serving)', isDark),
                    style: _textStyle(isDark),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Macros per 100g',
                    style: TextStyle(
                      fontSize: 12,
                      color: MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _calCtrl,
                          decoration: _input('Cal', isDark),
                          style: _textStyle(isDark),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _proteinCtrl,
                          decoration: _input('Protein', isDark),
                          style: _textStyle(isDark),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _carbsCtrl,
                          decoration: _input('Carbs', isDark),
                          style: _textStyle(isDark),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _fatsCtrl,
                          decoration: _input('Fats', isDark),
                          style: _textStyle(isDark),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _fiberCtrl,
                    decoration: _input('Fiber', isDark),
                    style: _textStyle(isDark),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  GradientButton(label: 'Add', onPressed: _addIngredient),
                ],
              ),
            ),
            if (_ingredients.isNotEmpty) ...[
              const SizedBox(height: 24),
              GlassCard(
                child: Column(
                  children: [
                    Text(
                      'Recipe Total',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _summaryRow(
                      'Calories',
                      '${totalCal.toStringAsFixed(0)} kcal',
                      '${perServingCal.toStringAsFixed(0)} kcal',
                      isDark,
                    ),
                    _summaryRow(
                      'Protein',
                      '${_ingredients.fold(0.0, (s, i) => s + i.protein).toStringAsFixed(1)}g',
                      '${_ingredients.fold(0.0, (s, i) => s + i.protein) / servings > 0 ? (_ingredients.fold(0.0, (s, i) => s + i.protein) / servings).toStringAsFixed(1) : '0.0'}g',
                      isDark,
                    ),
                    _summaryRow(
                      'Carbs',
                      '${_ingredients.fold(0.0, (s, i) => s + i.carbs).toStringAsFixed(1)}g',
                      '${_ingredients.fold(0.0, (s, i) => s + i.carbs) / servings > 0 ? (_ingredients.fold(0.0, (s, i) => s + i.carbs) / servings).toStringAsFixed(1) : '0.0'}g',
                      isDark,
                    ),
                    _summaryRow(
                      'Fats',
                      '${_ingredients.fold(0.0, (s, i) => s + i.fats).toStringAsFixed(1)}g',
                      '${_ingredients.fold(0.0, (s, i) => s + i.fats) / servings > 0 ? (_ingredients.fold(0.0, (s, i) => s + i.fats) / servings).toStringAsFixed(1) : '0.0'}g',
                      isDark,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            GradientButton(
              label: widget.recipeId != null ? 'Update Recipe' : 'Save Recipe',
              onPressed: _save,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientTile(int index, bool isDark) {
    final ing = _ingredients[index];
    // GlassCard uses a 24px radius in light mode and 28px in dark mode, so the
    // clip must match per-theme — otherwise the delete background's square
    // corners poke out past the rounded card while swiping.
    final radius = isDark ? 28.0 : 24.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Dismissible(
        key: ValueKey('${ing.name}_$index'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: MacroSnapTheme.neonPink,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: const Icon(Icons.delete_rounded, color: Colors.black),
        ),
        onDismissed: (_) => setState(() => _ingredients.removeAt(index)),
        child: GlassCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ing.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      '${ing.grams.toInt()}g · ${ing.caloriesPer100g.toInt()} cal/100g',
                      style: TextStyle(
                        fontSize: 12,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${ing.calories.toStringAsFixed(0)} kcal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.greenText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String total,
    String perServing,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: MacroSnapTheme.textSecondary(context),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              total,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              perServing,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: MacroSnapTheme.greenText(context),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _input(String label, bool isDark) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: isDark ? MacroSnapTheme.cardDark : const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    labelStyle: TextStyle(
      fontSize: 13,
      color: MacroSnapTheme.textTertiary(context),
    ),
  );

  TextStyle _textStyle(bool isDark) => TextStyle(
    fontSize: 15,
    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
  );
}
