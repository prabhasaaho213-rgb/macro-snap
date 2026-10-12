import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/theme.dart';
import '../models/diet_profile.dart';
import '../services/gemini_service.dart';
import '../services/meal_store.dart';
import '../services/subscription_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/animations.dart';
import 'subscription_screen.dart';

class DietPlanScreen extends StatefulWidget {
  const DietPlanScreen({super.key});

  @override
  State<DietPlanScreen> createState() => _DietPlanScreenState();
}

class _DietPlanScreenState extends State<DietPlanScreen> {
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  Gender _gender = Gender.male;
  Goal _goal = Goal.loseWeight;
  ActivityLevel _activity = ActivityLevel.sedentary;
  DietPreference _diet = DietPreference.vegetarian;
  DietProfile? _profile;
  String _avatar = '😎';
  bool _subscribed = false;
  bool _generating = false;
  Map<String, dynamic>? _aiPlan;
  String _aiError = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    await DietPlanService.instance.load();
    final p = DietPlanService.instance.profile;
    await SubscriptionService.instance.load();
    final subscribed = SubscriptionService.instance.isSubscribed;
    if (mounted) {
      setState(() => _subscribed = subscribed);
      if (p != null) {
        setState(() {
          _profile = p;
          _avatar = p.avatar;
          _weightCtrl.text = p.weightKg.toStringAsFixed(1);
          _heightCtrl.text = p.heightCm.toStringAsFixed(1);
          _ageCtrl.text = p.age.toString();
          _gender = p.gender;
          _goal = p.goal;
          _activity = p.activity;
          _diet = p.diet;
        });
      }
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  void _calculate() {
    final w = double.tryParse(_weightCtrl.text);
    final h = double.tryParse(_heightCtrl.text);
    final a = int.tryParse(_ageCtrl.text);
    if (w == null || h == null || a == null || w <= 0 || h <= 0 || a <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter valid weight, height & age'),
          backgroundColor: MacroSnapTheme.macroProtein,
        ),
      );
      return;
    }
    final profile = DietProfile(
      weightKg: w,
      heightCm: h,
      age: a,
      gender: _gender,
      goal: _goal,
      activity: _activity,
      diet: _diet,
      avatar: _avatar,
    );
    HapticFeedback.heavyImpact();
    DietPlanService.instance.save(profile);
    setState(() => _profile = profile);
  }

  Future<void> _generateAiPlan() async {
    if (_profile == null) return;
    if (!_subscribed) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      );
      return;
    }
    setState(() {
      _generating = true;
      _aiError = '';
      _aiPlan = null;
    });
    try {
      final resp = await http.post(
        Uri.parse('${GeminiService.serverUrl}/generate-diet-plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'weight': _profile!.weightKg,
          'height': _profile!.heightCm,
          'age': _profile!.age,
          'gender': _profile!.gender.name,
          'goal': _profile!.goal.name,
          'activity': _profile!.activity.name,
          // The generated plan has to respect the food preference too.
          'diet': _profile!.diet.name,
        }),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200) {
        throw Exception(data['error'] ?? 'Failed to generate');
      }
      if (mounted) {
        setState(() {
          _aiPlan = data;
          _generating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiError = e.toString().replaceFirst('Exception: ', '');
          _generating = false;
        });
      }
    }
  }

  void _reset() {
    DietPlanService.instance.save(
      DietProfile(
        weightKg: 70,
        heightCm: 170,
        age: 25,
        gender: Gender.male,
        goal: Goal.maintain,
        activity: ActivityLevel.moderate,
        diet: DietPreference.vegetarian,
      ),
    );
    _weightCtrl.text = '70';
    _heightCtrl.text = '170';
    _ageCtrl.text = '25';
    setState(() {
      _gender = Gender.male;
      _goal = Goal.maintain;
      _activity = ActivityLevel.moderate;
      _diet = DietPreference.vegetarian;
      _profile = null;
      _avatar = '😎';
      _aiPlan = null;
      _aiError = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Diet Plan'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reset),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInputSection(isDark),
            if (_profile != null) ...[
              const SizedBox(height: 20),
              _buildTargetsCard(isDark),
              const SizedBox(height: 16),
              _buildAiSection(isDark),
              const SizedBox(height: 16),
              _buildProgressCard(isDark),
              const SizedBox(height: 16),
              _buildMealPlan(isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection(bool isDark) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          // Row 1: Weight + Height (related metrics, side by side)
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _weightCtrl,
                  label: 'Weight',
                  hint: 'kg',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _heightCtrl,
                  label: 'Height',
                  hint: 'cm',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: Age (full width for readability)
          AppTextField(
            controller: _ageCtrl,
            label: 'Age',
            hint: 'years',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Gender>(
            initialValue: _gender,
            decoration: InputDecoration(
              labelText: 'Gender',
              filled: true,
              fillColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: MacroSnapTheme.borderSubtle(context),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
            // isExpanded: the selected label ellipsizes instead of overflowing
            // the form at large system font scales.
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: Gender.male, child: Text('Male')),
              DropdownMenuItem(value: Gender.female, child: Text('Female')),
            ],
            onChanged: (v) => setState(() => _gender = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Goal>(
            initialValue: _goal,
            decoration: InputDecoration(
              labelText: 'Goal',
              filled: true,
              fillColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: MacroSnapTheme.borderSubtle(context),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
            // isExpanded: the selected label ellipsizes instead of overflowing
            // the form at large system font scales.
            isExpanded: true,
            items: Goal.values
                .map(
                  (g) => DropdownMenuItem(
                    value: g,
                    child: Text(DietPlanService.goalLabel(g)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _goal = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ActivityLevel>(
            initialValue: _activity,
            decoration: InputDecoration(
              labelText: 'Activity Level',
              filled: true,
              fillColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: MacroSnapTheme.borderSubtle(context),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
            isExpanded: true,
            items: ActivityLevel.values
                .map(
                  (a) => DropdownMenuItem(
                    value: a,
                    child: Text(DietPlanService.activityLabel(a)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _activity = v!),
          ),
          const SizedBox(height: 12),
          // Food preference - drives the suggested meal plan below.
          DropdownButtonFormField<DietPreference>(
            initialValue: _diet,
            decoration: InputDecoration(
              labelText: 'Food Preference',
              filled: true,
              fillColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: MacroSnapTheme.borderSubtle(context),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
            isExpanded: true,
            items: DietPreference.values
                .map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(DietPlanService.dietLabel(d)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _diet = v!),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Calculate & Save',
            onPressed: _calculate,
            height: 52,
          ),
        ],
      ),
    );
  }

  Widget _buildTargetsCard(bool isDark) {
    final p = _profile!;
    final bmi = p.weightKg / ((p.heightCm / 100) * (p.heightCm / 100));
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  DietPlanService.goalLabel(p.goal),
                  style: TextStyle(
                    color: MacroSnapTheme.greenText(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${p.targetCalories} kcal',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'BMI ${bmi.toStringAsFixed(1)} | BMR ${p.bmr.round()} kcal | TDEE ${p.tdee.round()} kcal',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _targetItem(
                'Protein',
                p.targetProtein.toInt(),
                'g',
                MacroSnapTheme.macroProtein,
                isDark,
              ),
              _targetItem(
                'Carbs',
                p.targetCarbs.toInt(),
                'g',
                MacroSnapTheme.macroCalories,
                isDark,
              ),
              _targetItem(
                'Fats',
                p.targetFats.toInt(),
                'g',
                MacroSnapTheme.macroFats,
                isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetItem(
    String label,
    int value,
    String unit,
    Color color,
    bool isDark,
  ) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.1),
          ),
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$label ($unit)',
          style: TextStyle(
            fontSize: 12,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildAiSection(bool isDark) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      MacroSnapTheme.neonGreen,
                      MacroSnapTheme.neonGreen,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Personalized Meal Plan',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_aiPlan != null) ...[
            _buildAiMeals(isDark),
            if (_aiPlan!['plan'] is Map &&
                (_aiPlan!['plan'] as Map)['tips'] != null) ...[
              const SizedBox(height: 12),
              ...((_aiPlan!['plan'] as Map)['tips'] as List).map(
                (tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 ',
                        style: TextStyle(
                          fontSize: 12,
                          color: MacroSnapTheme.textTertiary(context),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '$tip',
                          style: TextStyle(
                            fontSize: 12,
                            color: MacroSnapTheme.textTertiary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_aiPlan!['plan'] is Map &&
                (_aiPlan!['plan'] as Map)['water'] != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.water_drop,
                      size: 16,
                      color: MacroSnapTheme.macroFats,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_aiPlan!['plan']['water']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: MacroSnapTheme.textTertiary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ] else ...[
            if (_aiError.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? MacroSnapTheme.macroProtein.withValues(alpha: 0.15)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _aiError,
                  style: TextStyle(
                    color: isDark
                        ? MacroSnapTheme.macroProtein
                        : const Color(0xFFDC2626),
                    fontSize: 12,
                  ),
                ),
              ),
            GradientButton(
              label: _generating
                  ? 'Generating...'
                  : _subscribed
                  ? 'Generate AI Meal Plan'
                  : 'Subscribe to Unlock AI Plan',
              icon: _generating
                  ? null
                  : _subscribed
                  ? Icons.auto_awesome_rounded
                  : Icons.lock_outline_rounded,
              onPressed: _generating ? null : _generateAiPlan,
              loading: _generating,
              height: 48,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAiMeals(bool isDark) {
    if (_aiPlan!['plan'] is! Map) return const SizedBox.shrink();
    final meals = (_aiPlan!['plan'] as Map)['meals'] as List? ?? [];
    if (meals.isEmpty) return const SizedBox.shrink();
    return Column(
      children: meals.map((m) {
        final meal = m as Map<String, dynamic>;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        meal['time'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: MacroSnapTheme.greenText(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${meal['calories'] ?? 0} kcal',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  meal['name'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meal['description'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _macroChip(
                      'P ${meal['protein_g'] ?? 0}g',
                      MacroSnapTheme.macroProtein,
                    ),
                    const SizedBox(width: 6),
                    _macroChip(
                      'C ${meal['carbs_g'] ?? 0}g',
                      MacroSnapTheme.macroCalories,
                    ),
                    const SizedBox(width: 6),
                    _macroChip(
                      'F ${meal['fats_g'] ?? 0}g',
                      MacroSnapTheme.macroFats,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _macroChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildProgressCard(bool isDark) {
    final p = _profile!;
    final cal = MealStore.instance.todayCalories;
    final protein = MealStore.instance.todayProtein;
    final ratio = (cal / p.targetCalories).clamp(0.0, 1.0);
    final protRatio = (protein / p.targetProtein).clamp(0.0, 1.0);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's Progress",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          _progressRow(
            'Calories',
            cal,
            p.targetCalories,
            ratio,
            MacroSnapTheme.macroCalories,
            isDark,
          ),
          const SizedBox(height: 12),
          _progressRow(
            'Protein',
            protein.toInt(),
            p.targetProtein.toInt(),
            protRatio,
            MacroSnapTheme.macroProtein,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _progressRow(
    String label,
    int current,
    int target,
    double ratio,
    Color color,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
            Text(
              '$current / $target',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedProgressBar(value: ratio, color: color, height: 8),
      ],
    );
  }

  Widget _buildMealPlan(bool isDark) {
    final p = _profile!;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested Meal Plan',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${DietPlanService.dietLabel(p.diet)} plan - '
            'change it under Food Preference above.',
            style: TextStyle(
              fontSize: 12,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
          const SizedBox(height: 16),
          _mealItem(
            Icons.wb_sunny_rounded,
            'Breakfast (~${(p.targetCalories * 0.25).round()} kcal)',
            _breakfastSuggestion(p),
            MacroSnapTheme.macroCalories,
            isDark,
          ),
          _mealItem(
            Icons.free_breakfast_rounded,
            'Morning Snack (~${(p.targetCalories * 0.1).round()} kcal)',
            _snackSuggestion(p),
            MacroSnapTheme.neonGreen,
            isDark,
          ),
          _mealItem(
            Icons.wb_cloudy_rounded,
            'Lunch (~${(p.targetCalories * 0.3).round()} kcal)',
            _lunchSuggestion(p),
            MacroSnapTheme.macroFats,
            isDark,
          ),
          _mealItem(
            Icons.nightlight_round,
            'Evening Snack (~${(p.targetCalories * 0.1).round()} kcal)',
            _snackSuggestion(p),
            MacroSnapTheme.neonGreen,
            isDark,
          ),
          _mealItem(
            Icons.nights_stay_rounded,
            'Dinner (~${(p.targetCalories * 0.25).round()} kcal)',
            _dinnerSuggestion(p),
            MacroSnapTheme.macroProtein,
            isDark,
          ),
          const SizedBox(height: 16),
          Text(
            'Portion sizes are approximate. Adjust based on your appetite and progress.',
            style: TextStyle(
              fontSize: 12,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealItem(
    IconData icon,
    String title,
    String suggestion,
    Color color,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  suggestion,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _breakfastSuggestion(DietProfile p) {
    final nonVeg = p.diet == DietPreference.nonVegetarian;
    if (p.goal == Goal.loseWeight) {
      return nonVeg
          ? '3 boiled egg whites + 1 multigrain roti + curd + mixed veggies'
          : '1 multigrain roti + 1 bowl curd + mixed veggies + 5 almonds';
    }
    return nonVeg
        ? '3 whole eggs + 2 multigrain roti + sprouts salad + 1 banana'
        : '2 multigrain roti + 1 bowl sprouts salad + 1 banana + milk';
  }

  String _lunchSuggestion(DietProfile p) {
    final nonVeg = p.diet == DietPreference.nonVegetarian;
    if (p.goal == Goal.loseWeight) {
      return nonVeg
          ? '1 roti + grilled chicken (150g) + green veg sabzi + salad'
          : '1 roti + dal + green veg sabzi + salad + buttermilk';
    }
    if (p.goal == Goal.gainMuscle) {
      return nonVeg
          ? '2 roti + chicken curry (200g) + rice + curd + salad'
          : '2 roti + dal + paneer bhurji + rice + curd + salad';
    }
    return nonVeg
        ? '2 roti + fish/chicken curry (150g) + seasonal veg + salad'
        : '2 roti + dal + seasonal veg + salad + curd';
  }

  String _dinnerSuggestion(DietProfile p) {
    final nonVeg = p.diet == DietPreference.nonVegetarian;
    if (p.goal == Goal.loseWeight) {
      return nonVeg
          ? 'Grilled chicken/fish + stir-fried veggies + soup'
          : 'Paneer tikka + stir-fried veggies + soup';
    }
    if (p.goal == Goal.gainMuscle) {
      return nonVeg
          ? 'Grilled chicken/fish + rice + veggies + 1 glass milk'
          : 'Paneer/soya chunks + rice + veggies + 1 glass milk';
    }
    return nonVeg
        ? 'Grilled chicken/fish + roti + salad'
        : 'Light roti/kichdi + veg curry + salad';
  }

  // Snacks are the same for both preferences - none of these contain meat.
  String _snackSuggestion(DietProfile p) {
    if (p.goal == Goal.loseWeight) {
      return '1 apple + 5 almonds or green tea / black coffee';
    }
    if (p.goal == Goal.gainMuscle) {
      return 'Handful dry fruits + 1 glass milk + 1 banana';
    }
    return '1 fruit + buttermilk or handful of roasted chana';
  }
}
