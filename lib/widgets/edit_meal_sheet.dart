import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/meal_record.dart';

/// Bottom sheet for correcting an already-logged meal.
///
/// A logged meal used to be final. The scan card lets you fix macros BEFORE
/// saving, but once it was in the log the only way to correct a wrong estimate
/// was to delete the meal and scan again — which spends another of the three
/// daily scans and loses the photo. That is a lot of friction for the single
/// most common complaint an AI food app gets ("it guessed 600 kcal, it was
/// 400"), so the logged record is editable here.
///
/// Only the values a person can actually know are editable: the name, the
/// calories and the three macros, and the serving description. The date, the
/// scan's per-dish breakdown and the photo are preserved by
/// [MealRecord.copyWith], so an edit never detaches a meal from its history.
Future<MealRecord?> showEditMealSheet(
  BuildContext context,
  MealRecord meal,
) {
  return showModalBottomSheet<MealRecord>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _EditMealSheet(meal: meal),
  );
}

class _EditMealSheet extends StatefulWidget {
  final MealRecord meal;
  const _EditMealSheet({required this.meal});

  @override
  State<_EditMealSheet> createState() => _EditMealSheetState();
}

class _EditMealSheetState extends State<_EditMealSheet> {
  late final TextEditingController _name;
  late final TextEditingController _serving;
  late final TextEditingController _calories;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fats;

  String? _error;

  @override
  void initState() {
    super.initState();
    final m = widget.meal;
    _name = TextEditingController(text: m.name);
    _serving = TextEditingController(text: m.serving);
    _calories = TextEditingController(text: m.calories.toString());
    _protein = TextEditingController(text: _format(m.protein));
    _carbs = TextEditingController(text: _format(m.carbs));
    _fats = TextEditingController(text: _format(m.fats));
  }

  /// Macro text without a pointless `.0` — "12" rather than "12.0".
  static String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void dispose() {
    // The dialog helpers elsewhere in the app create controllers and never
    // dispose them; this one does, because the sheet can be opened repeatedly
    // from the same card.
    _name.dispose();
    _serving.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fats.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give this meal a name.');
      return;
    }
    final calories = int.tryParse(_calories.text.trim());
    if (calories == null || calories < 0 || calories > 10000) {
      setState(() => _error = 'Calories must be a number between 0 and 10000.');
      return;
    }
    final protein = double.tryParse(_protein.text.trim());
    final carbs = double.tryParse(_carbs.text.trim());
    final fats = double.tryParse(_fats.text.trim());
    if (protein == null || carbs == null || fats == null) {
      setState(() => _error = 'Macros must be numbers.');
      return;
    }
    if ([protein, carbs, fats].any((v) => v < 0 || v > 1000)) {
      setState(() => _error = 'Each macro must be between 0 and 1000 g.');
      return;
    }
    Navigator.pop(
      context,
      widget.meal.copyWith(
        name: name,
        serving: _serving.text.trim(),
        calories: calories,
        protein: protein,
        carbs: carbs,
        fats: fats,
        // An edited meal is no longer a guess, so a confidence-driven "maybe
        // this is wrong" state on the card no longer applies. Nothing else on
        // the record is touched.
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? MacroSnapTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.textTertiary(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.edit_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Edit meal',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Fix what the scan got wrong. The photo and the scan breakdown '
                'stay with the meal.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: MacroSnapTheme.textTertiary(context),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              _field(
                controller: _name,
                label: 'Meal name',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      controller: _calories,
                      label: 'Calories (kcal)',
                      numeric: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(controller: _serving, label: 'Serving'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      controller: _protein,
                      label: 'Protein (g)',
                      numeric: true,
                      decimal: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      controller: _carbs,
                      label: 'Carbs (g)',
                      numeric: true,
                      decimal: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      controller: _fats,
                      label: 'Fats (g)',
                      numeric: true,
                      decimal: true,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: MacroSnapTheme.neonPink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: MacroSnapTheme.neonGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Save changes',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool numeric = false,
    bool decimal = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      keyboardType: numeric
          ? TextInputType.numberWithOptions(decimal: decimal)
          : TextInputType.text,
      inputFormatters: numeric
          ? [
              FilteringTextInputFormatter.allow(
                decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
              ),
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
