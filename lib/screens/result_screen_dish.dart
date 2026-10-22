part of 'result_screen.dart';

// Split out of result_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _ResultDish on _ResultScreenState {
  Widget _buildDishCard(bool isDark, DishItem dish, int totalGrams) {
    final ratio = totalGrams / 100;
    final isBulk = dish.suitableFor == 'bulk';
    final isDiet = dish.suitableFor == 'diet';
    final badgeColor = isBulk
        ? MacroSnapTheme.macroFats
        : isDiet
        ? MacroSnapTheme.macroProtein
        : MacroSnapTheme.greenText(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // The pill hugs the name's length instead of stretching
                  // full width, and long names wrap onto extra lines
                  // instead of being cut off.
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        dish.name,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: MacroSnapTheme.greenText(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(dish.caloriesPer100g * ratio).round()} kcal',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (_stripGrams(dish.portionDescription).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _stripGrams(dish.portionDescription),
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDishMacro(
                    'Protein',
                    (dish.proteinPer100g * ratio),
                    MacroSnapTheme.macroProtein,
                    isDark,
                  ),
                  _buildDishMacro(
                    'Carbs',
                    (dish.carbsPer100g * ratio),
                    MacroSnapTheme.macroCalories,
                    isDark,
                  ),
                  _buildDishMacro(
                    'Fat',
                    (dish.fatsPer100g * ratio),
                    MacroSnapTheme.macroFats,
                    isDark,
                  ),
                  _buildDishMacro(
                    'Fiber',
                    (dish.fiberPer100g * ratio),
                    MacroSnapTheme.neonGreen,
                    isDark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDishMacro(String label, double value, Color color, bool isDark) {
    return Column(
      children: [
        Text(
          value > 0 ? '${value.toStringAsFixed(1)}g' : '—',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
      ],
    );
  }
}
