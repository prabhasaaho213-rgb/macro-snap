import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/bmi.dart';
import '../models/diet_profile.dart';
import '../widgets/bmi_gauge.dart';
import '../widgets/gradient_button.dart';
import '../services/weight_store.dart';
import '../widgets/weight_trend_chart.dart';

/// BMI calculator.
///
/// Opens on the user's own numbers — weight and height come straight from the
/// diet profile, so nobody re-types what the app already knows. Adjusting
/// either value recalculates live, and the result can be written back to the
/// profile (which keeps the calorie targets in step).
class BmiScreen extends StatefulWidget {
  const BmiScreen({super.key});

  @override
  State<BmiScreen> createState() => _BmiScreenState();
}

class _BmiScreenState extends State<BmiScreen> {
  /// Fallbacks are only used when the profile has never been filled in; the
  /// screen says so instead of silently pretending these are the user's data.
  static const double _fallbackWeightKg = 70;
  static const double _fallbackHeightCm = 170;

  double _weightKg = _fallbackWeightKg;
  double _heightCm = _fallbackHeightCm;
  bool _loadedProfile = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    // The trend card reads the history, and this screen writes to it.
    WeightStore.instance.addListener(_onWeightChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    WeightStore.instance.removeListener(_onWeightChanged);
    super.dispose();
  }

  void _onWeightChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    await DietPlanService.instance.load();
    final profile = DietPlanService.instance.profile;
    await WeightStore.instance.load();
    // Seed today's/first point from the profile so the very first visit to the
    // calculator already has a line to draw, rather than an empty chart.
    //
    // awardBadge: false — opening the calculator is not a weigh-in. This used
    // to hand out "First Weigh-In" to anyone who tapped the BMI card, which is
    // the opposite of "earned by logging": nothing was measured or entered.
    if (profile != null && WeightStore.instance.entries.isEmpty) {
      await WeightStore.instance.record(
        profile.weightKg,
        awardBadge: false,
      );
    }
    if (!mounted) return;
    setState(() {
      _loadedProfile = profile != null;
      if (profile != null) {
        _weightKg = profile.weightKg;
        _heightCm = profile.heightCm;
      }
    });
  }

  double? get _bmi =>
      BmiCalculator.value(weightKg: _weightKg, heightCm: _heightCm);

  DietProfile? get _profile => DietPlanService.instance.profile;

  Future<void> _edit({required bool weight}) async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => _MetricDialog(
        isWeight: weight,
        initial: weight ? _weightKg : _heightCm,
        currentHeightCm: _heightCm,
      ),
    );
    if (value == null) return;
    setState(() {
      if (weight) {
        _weightKg = value;
      } else {
        _heightCm = value;
      }
      _dirty = true;
    });
  }

  /// Writes the entered numbers back to the diet profile so calorie targets
  /// and future suggestions use them too.
  Future<void> _saveToProfile() async {
    final profile = _profile;
    if (profile == null) return;
    await DietPlanService.instance.save(
      DietProfile(
        weightKg: _weightKg,
        heightCm: _heightCm,
        age: profile.age,
        gender: profile.gender,
        goal: profile.goal,
        activity: profile.activity,
        diet: profile.diet,
        avatar: profile.avatar,
      ),
    );
    // Also land on the timeline: the profile holds "current", this holds
    // "over time" — the two together are what the trend line draws.
    await WeightStore.instance.record(_weightKg);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved to your profile'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Round once, then use that same number for both the label and the
    // printed score — 24.97 must read "25.0 · Overweight", not "25.0 · Normal".
    final raw = _bmi;
    final bmi = raw == null ? null : BmiCalculator.displayValue(raw);
    final category = bmi == null ? null : BmiCalculator.categoryFor(bmi);
    final background = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(
                  children: [
                    Text(
                      'Calculate\nYour BMI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: isDark ? Colors.white : const Color(0xFF0F0F0F),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _buildCalculatorCard(context, isDark, bmi, category),
                    const SizedBox(height: 16),
                    _buildLegend(context, isDark, category),
                    if (WeightStore.instance.entries.length >= 2) ...[
                      const SizedBox(height: 16),
                      _buildTrendCard(context, isDark),
                    ],
                    if (_profile != null) ...[
                      const SizedBox(height: 16),
                      _buildNumbersCard(context, isDark),
                    ],
                    if (_dirty && _profile != null) ...[
                      const SizedBox(height: 18),
                      GradientButton(
                        label: 'Save to my profile',
                        icon: Icons.check_rounded,
                        onPressed: _saveToProfile,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalculatorCard(
    BuildContext context,
    bool isDark,
    double? bmi,
    BmiCategory? category,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: MacroSnapTheme.borderSubtle(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'BMI Calculator',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _stat(
                  context,
                  value:
                      '${_weightKg.toStringAsFixed(_weightKg % 1 == 0 ? 0 : 1)} kg',
                  label: 'Weight',
                  isDark: isDark,
                  onTap: () => _edit(weight: true),
                ),
              ),
              _chevron(context),
              Expanded(
                child: _stat(
                  context,
                  value: BmiCalculator.formatHeight(_heightCm),
                  label: 'Height',
                  isDark: isDark,
                  onTap: () => _edit(weight: false),
                ),
              ),
              _chevron(context),
            ],
          ),
          const SizedBox(height: 8),
          BmiGauge(
            bmi: bmi ?? 0,
            size: 236,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.accessibility_new_rounded,
                  size: 46,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.14),
                ),
                const SizedBox(height: 2),
                Text(
                  bmi == null ? '—' : bmi.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    letterSpacing: -1.5,
                    color: isDark ? Colors.white : const Color(0xFF0F0F0F),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'BMI',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          if (category != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: category.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                category.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: category.color,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              category.advice,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
          ],
          if (!_loadedProfile) ...[
            const SizedBox(height: 10),
            Text(
              'Showing sample numbers — finish your diet profile to use your own.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context, {
    required String value,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2F80ED),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chevron(BuildContext context) {
    return Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: MacroSnapTheme.textTertiary(context),
    );
  }

  Widget _buildLegend(BuildContext context, bool isDark, BmiCategory? current) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: MacroSnapTheme.borderSubtle(context)),
      ),
      child: Column(
        children: [
          for (final category in BmiCategory.values)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                // The user's own band is the only highlighted row — scanning
                // the legend should answer "where am I" in one glance.
                color: category == current
                    ? category.color.withValues(alpha: 0.13)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: category.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      category.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: category == current
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: category == current
                            ? category.color
                            : (isDark
                                  ? Colors.white70
                                  : const Color(0xFF4A4A4A)),
                      ),
                    ),
                  ),
                  Text(
                    category.rangeLabel,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: category == current
                          ? category.color
                          : MacroSnapTheme.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The history section: the last 30 days as a line, what changed over it,
  /// and the low/high of the window. Only appears once there are two or more
  /// points — a single reading has no direction to show.
  Widget _buildTrendCard(BuildContext context, bool isDark) {
    final summary = WeightStore.instance.summary(days: 30);
    final points = summary.points;
    if (points.length < 2) return const SizedBox.shrink();

    var low = points.first.kg;
    var high = points.first.kg;
    for (final p in points) {
      if (p.kg < low) low = p.kg;
      if (p.kg > high) high = p.kg;
    }

    final delta = summary.deltaKg;
    final direction = summary.direction;
    final color = switch (direction) {
      WeightTrend.losing => MacroSnapTheme.successGreen,
      WeightTrend.gaining => MacroSnapTheme.neonOrange,
      WeightTrend.holding => MacroSnapTheme.textSecondary(context),
    };
    final icon = switch (direction) {
      WeightTrend.losing => Icons.trending_down_rounded,
      WeightTrend.gaining => Icons.trending_up_rounded,
      WeightTrend.holding => Icons.trending_flat_rounded,
    };
    final absolute = (delta ?? 0).abs().toStringAsFixed(1);
    final sentence = delta == null
        ? 'Keep logging — two readings make a line.'
        : switch (direction) {
            WeightTrend.losing =>
              'Down $absolute kg in ${summary.spanDays} days',
            WeightTrend.gaining =>
              'Up $absolute kg in ${summary.spanDays} days',
            WeightTrend.holding =>
              'Holding steady over ${summary.spanDays} days',
          };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: MacroSnapTheme.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your trend',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                delta == null
                    ? ''
                    : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            sentence,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          WeightTrendChart(
            points: points,
            height: 120,
            color: MacroSnapTheme.neonCyan,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _trendStat(context, 'Low', '${low.toStringAsFixed(1)} kg'),
              const SizedBox(width: 18),
              _trendStat(context, 'High', '${high.toStringAsFixed(1)} kg'),
              const SizedBox(width: 18),
              _trendStat(
                context,
                'Now',
                '${points.last.kg.toStringAsFixed(1)} kg',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trendStat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  /// BMR / TDEE / calorie target, recomputed with the weight currently on
  /// screen — so "what does this weight imply for my plan" is answered without
  /// leaving the calculator.
  Widget _buildNumbersCard(BuildContext context, bool isDark) {
    final profile = _profile!;
    final current = DietProfile(
      weightKg: _weightKg,
      heightCm: _heightCm,
      age: profile.age,
      gender: profile.gender,
      goal: profile.goal,
      activity: profile.activity,
      diet: profile.diet,
      avatar: profile.avatar,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: isDark ? MacroSnapTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: MacroSnapTheme.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your numbers',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 10),
          _numberRow(
            context,
            'BMR',
            '${current.bmr.round()} kcal',
            'burned at complete rest',
          ),
          _numberRow(
            context,
            'TDEE',
            '${current.tdee.round()} kcal',
            'with your activity level',
          ),
          _numberRow(
            context,
            'Daily target',
            '${current.targetCalories} kcal',
            'for your ${current.goal.name.replaceAll('Weight', ' weight').replaceAll('Muscle', ' muscle')} goal',
            highlight: true,
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _numberRow(
    BuildContext context,
    String label,
    String value,
    String hint, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                    color: highlight
                        ? MacroSnapTheme.neonOrange
                        : MacroSnapTheme.textSecondary(context),
                  ),
                ),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: highlight
                  ? MacroSnapTheme.neonOrange
                  : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF1A1A1A)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Owns its own [TextEditingController] so the controller outlives the
/// dialog's exit animation — disposing it as soon as `showDialog` returns
/// leaves the closing TextField rebuilding with a dead controller.
class _MetricDialog extends StatefulWidget {
  const _MetricDialog({
    required this.isWeight,
    required this.initial,
    required this.currentHeightCm,
  });

  final bool isWeight;
  final double initial;
  final double currentHeightCm;

  @override
  State<_MetricDialog> createState() => _MetricDialogState();
}

class _MetricDialogState extends State<_MetricDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.isWeight
        ? widget.initial.toStringAsFixed(1)
        : widget.initial.toStringAsFixed(0),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    final min = widget.isWeight ? 20.0 : 80.0;
    final max = widget.isWeight ? 300.0 : 250.0;
    if (parsed == null || parsed < min || parsed > max) {
      setState(() {
        _error = widget.isWeight
            ? 'Enter a weight between 20 and 300 kg'
            : 'Enter a height between 80 and 250 cm';
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.isWeight ? 'Your weight' : 'Your height'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.isWeight ? 'Weight (kg)' : 'Height (cm)',
          helperText: widget.isWeight
              ? 'e.g. 59.3'
              : 'Now ${BmiCalculator.formatHeight(widget.currentHeightCm)}',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
