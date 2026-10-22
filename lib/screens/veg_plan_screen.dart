import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/theme.dart';
import '../models/diet_profile.dart';
import '../models/meal_record.dart';
import '../services/food_database.dart';
import '../services/meal_store.dart';
import '../services/veg_plan_service.dart';
import '../widgets/glass_card.dart';

/// The vegetarian plan: today's five veg meals sized to the user's targets,
/// plus every vegetarian food in the database as a tappable suggestion.
class VegPlanScreen extends StatefulWidget {
  const VegPlanScreen({super.key});

  @override
  State<VegPlanScreen> createState() => _VegPlanScreenState();
}

class _VegPlanScreenState extends State<VegPlanScreen> {
  DietProfile? _profile;
  int _day = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _day = DateTime.now().difference(DateTime(2024)).inDays;
    _loadProfile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    await DietPlanService.instance.load();
    if (mounted) {
      setState(() => _profile = DietPlanService.instance.profile);
    }
  }

  void _shuffle() {
    HapticFeedback.lightImpact();
    setState(() => _day++);
  }

  void _logFood(FoodItem item) {
    HapticFeedback.lightImpact();
    MealStore.instance.add(
      MealRecord(
        id: const Uuid().v4(),
        date: DateTime.now(),
        name: item.name,
        category: item.category,
        calories: item.calories,
        protein: item.protein,
        carbs: item.carbs,
        fats: item.fats,
        fiber: item.fiber,
        serving: item.serving,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Logged "${item.name}" (${item.calories} kcal)'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: MacroSnapTheme.neonGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  List<VegCategoryGroup> get _filteredGroups {
    final groups = VegPlanService.suggestions();
    if (_searchQuery.isEmpty) return groups;
    final q = _searchQuery.toLowerCase();
    return [
      for (final group in groups)
        if (group.items.any((i) => i.name.toLowerCase().contains(q)))
          VegCategoryGroup(
            category: group.category,
            items: group.items
                .where((i) => i.name.toLowerCase().contains(q))
                .toList(),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final plan = VegPlanService.dayPlan(profile: _profile, day: _day);
    final groups = _filteredGroups;

    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Veg Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle_rounded),
            tooltip: 'Shuffle today\'s plan',
            onPressed: _shuffle,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _buildPlanHeader(plan, isDark),
          const SizedBox(height: 14),
          for (final slot in plan.slots) ...[
            _buildMealCard(slot, isDark),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          _buildSuggestionsHeader(isDark),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search veg foods...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.clear_rounded, size: 18),
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2A2A32)
                    : const Color(0xFFF5F3FF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No veg food matches "$_searchQuery"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            )
          else
            for (final group in groups) ...[
              _buildCategoryLabel(group.category, isDark),
              const SizedBox(height: 8),
              ...group.items.map((item) => _buildSuggestionTile(item, isDark)),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Widget _buildPlanHeader(VegDayPlan plan, bool isDark) {
    final p = _profile;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: at 2x system font the pill plus the calorie count
          // is wider than a 320dp card, and a Row would overflow it.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.macroFiber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Vegetarian',
                  style: TextStyle(
                    color: MacroSnapTheme.greenText(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${plan.totalCalories} / ${plan.targetCalories} kcal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _macroStat(
                'Protein',
                plan.totalProtein,
                MacroSnapTheme.macroProtein,
              ),
              const SizedBox(width: 10),
              _macroStat('Carbs', plan.totalCarbs, MacroSnapTheme.macroCarbs),
              const SizedBox(width: 10),
              _macroStat('Fats', plan.totalFats, MacroSnapTheme.macroFats),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p == null
                ? 'No diet profile yet - showing a default ${VegPlanService.defaultTargetCalories} kcal plan. Set your details in Diet Plan for exact portions.'
                : '${DietPlanService.goalLabel(p.goal)} target - shuffle for another veg day.',
            style: TextStyle(
              fontSize: 12,
              color: MacroSnapTheme.textTertiary(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroStat(String label, double grams, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '${grams.round()}g',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealCard(VegMealSlot slot, bool isDark) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  slot.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              Text(
                '${slot.calories} kcal',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MacroSnapTheme.greenText(context),
                ),
              ),
            ],
          ),
          Text(
            slot.time,
            style: TextStyle(
              fontSize: 11,
              color: MacroSnapTheme.textQuaternary(context),
            ),
          ),
          const SizedBox(height: 10),
          for (final item in slot.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: MacroSnapTheme.macroFiber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${item.name} (${item.serving})',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: MacroSnapTheme.textSecondary(context),
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _logFood(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MacroSnapTheme.macroFiber.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 14,
                        color: MacroSnapTheme.macroFiber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsHeader(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'All Veg Suggestions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: MacroSnapTheme.macroFiber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${VegPlanService.suggestionCount} foods',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: MacroSnapTheme.greenText(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryLabel(String category, bool isDark) {
    return Text(
      category,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white70 : const Color(0xFF334155),
      ),
    );
  }

  Widget _buildSuggestionTile(FoodItem item, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _logFood(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: MacroSnapTheme.habitlyCard(context),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.macroFiber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  color: MacroSnapTheme.macroFiber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.serving} - P${item.protein.round()} C${item.carbs.round()} F${item.fats.round()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.macroFiber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${item.calories}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: MacroSnapTheme.macroFiber,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
