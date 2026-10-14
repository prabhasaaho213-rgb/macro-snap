import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../core/theme.dart';
import '../models/meal_record.dart';
import '../services/gemini_service.dart';
import '../services/meal_store.dart';
import '../services/recent_food_service.dart';
import '../services/scan_gate.dart';
import '../widgets/animations.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';

class ResultScreen extends StatefulWidget {
  final String imagePath;

  /// When set, the screen renders as a read-only detail view for an
  /// already-logged meal (no photo, no AI analysis, no edit/log actions) —
  /// the same nutrition layout shown right after a scan.
  final MealRecord? existingMeal;

  const ResultScreen({super.key, required this.imagePath, this.existingMeal});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _isAnalyzing = true;
  String? _error;
  NutritionResult? _result;
  bool _showPerDish = false;
  String _analysisStage = 'Analyzing your meal...';
  String _analysisSub =
      'Our AI is identifying each dish\nand calculating nutrition';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    final existing = widget.existingMeal;
    if (existing != null) {
      // View mode: render the logged meal's stored nutrition directly —
      // nothing to analyze and no scan counted.
      _result = NutritionResult(
        dishes: [
          DishItem(
            name: existing.name,
            portionDescription: existing.serving,
            caloriesPer100g: existing.calories,
            proteinPer100g: existing.protein,
            carbsPer100g: existing.carbs,
            fatsPer100g: existing.fats,
            fiberPer100g: existing.fiber,
          ),
        ],
        description: existing.serving,
        confidence: 1.0,
        grams: 100,
      );
      _isAnalyzing = false;
      _animController.forward();
    } else {
      _analyze();
      _animateStages();
    }
  }

  void _animateStages() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isAnalyzing) {
        setState(() {
          _analysisStage = 'Still working...';
          _analysisSub =
              'Food identification may take a moment\nfor complex dishes';
        });
      }
    });
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isAnalyzing) {
        setState(() {
          _analysisStage = 'Taking longer than expected';
          _analysisSub = 'The server may be busy. Please retry in a moment.';
        });
      }
    });
  }

  Future<void> _analyze() async {
    // AI is the ONLY identifier — there is no offline fallback. If the AI
    // can't be reached or fails, show a clear error instead of a wrong
    // offline guess.
    if (!GeminiService.hasServerUrl) {
      if (mounted) {
        setState(() {
          _error = 'no_url';
          _isAnalyzing = false;
        });
      }
      return;
    }
    try {
      final result = await GeminiService.analyzeFoodImage(widget.imagePath);
      if (!mounted) return;

      final isUnidentified = result.confidence < 0.5 ||
          result.dishes.any((d) => d.name.toLowerCase() == 'unknown');

      if (isUnidentified) {
        // Low confidence / unidentified — show warning, don't count scan
        if (mounted) {
          setState(() {
            _result = result;
            _isAnalyzing = false;
            _showLowConfidenceWarning = true;
          });
          _animController.forward();
        }
      } else {
        // Good identification — count the scan
        await ScanGate.incrementScan();
        // Re-check after the async count — the screen may have been
        // closed while the count was being persisted.
        if (!mounted) return;

        // Save to recent foods for quick re-add
        if (result.dishes.isNotEmpty) {
          final dish = result.dishes.first;
          await RecentFoodService.instance.add(RecentFood(
            id: const Uuid().v4(),
            name: dish.name,
            calories: (dish.caloriesPer100g * result.grams / 100).round(),
            protein: dish.proteinPer100g * result.grams / 100,
            carbs: dish.carbsPer100g * result.grams / 100,
            fats: dish.fatsPer100g * result.grams / 100,
            fiber: dish.fiberPer100g * result.grams / 100,
            serving: result.description,
            scannedAt: DateTime.now(),
          ));
        }

        setState(() {
          _result = result;
          _isAnalyzing = false;
        });
        _animController.forward();
      }
    } catch (e) {
      // Scan limit reached is not a recognition failure — show the clear
      // upsell message.
      if (e.toString().contains('Scan limit')) {
        if (mounted) {
          setState(() {
            _error = 'Free scans used up.\nSubscribe for unlimited scans.';
            _isAnalyzing = false;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _error = _friendlyErrorMessage(e.toString());
          _isAnalyzing = false;
        });
      }
      _animController.forward();
    }
  }

  /// Convert raw error messages to user-friendly guidance.
  String _friendlyErrorMessage(String raw) {
    final msg = raw.replaceFirst('Exception: ', '').toLowerCase();
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'Analysis timed out.\n\nTips for better results:\n• Take a clearer photo\n• Ensure good lighting\n• Get closer to the food';
    }
    if (msg.contains('cannot reach') || msg.contains('connection')) {
      return 'Cannot connect to server.\n\nMake sure:\n• You\'re on the same WiFi\n• The backend is running';
    }
    if (msg.contains('image') || msg.contains('file')) {
      return 'Could not read the image.\n\nTry:\n• Taking a new photo\n• Checking camera permissions';
    }
    return 'Could not identify the food.\n\nTips:\n• Take a clearer photo\n• Ensure food is well-lit\n• Get closer to the dish\n• Avoid blurry images';
  }

  /// Whether to show the low-confidence warning banner.
  bool _showLowConfidenceWarning = false;

  /// Retry the scan with the same image.
  void _retryScan() {
    setState(() {
      _showLowConfidenceWarning = false;
      _isAnalyzing = true;
      _result = null;
      _error = null;
    });
    _analyze();
  }

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
              child: const Icon(Icons.edit_rounded, color: MacroSnapTheme.neonGreen, size: 18),
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
              setState(() {
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
              await RecentFoodService.instance.add(RecentFood(
                id: const Uuid().v4(),
                name: name,
                calories: cal,
                protein: pro,
                carbs: carb,
                fats: fat,
                serving: 'Manually entered',
                scannedAt: DateTime.now(),
              ));
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

  /// View-mode header tile: a branded placeholder filling the same slot the
  /// scanned screen uses for the food photo (logged meals don't keep the
  /// original image).
  Widget _buildMealPlaceholder() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MacroSnapTheme.neonGreen.withValues(alpha: 0.35),
            MacroSnapTheme.neonGreen.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.restaurant_rounded,
            color: MacroSnapTheme.greenText(context),
            size: 44,
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(bool isDark, NutritionResult r) async {
    final calCtrl = TextEditingController(text: r.calories.toString());
    final proCtrl = TextEditingController(text: r.protein.toStringAsFixed(1));
    final carbCtrl = TextEditingController(text: r.carbs.toStringAsFixed(1));
    final fatCtrl = TextEditingController(text: r.fats.toStringAsFixed(1));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? MacroSnapTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Edit Nutrition'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              setState(() {
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
                    caloriesPer100g: ((cal / ratio) / r.dishes.length).round(),
                    proteinPer100g: (pro / ratio) / r.dishes.length,
                    carbsPer100g: (carb / ratio) / r.dishes.length,
                    fatsPer100g: (fat / ratio) / r.dishes.length,
                    fiberPer100g: d.fiberPer100g,
                    sugarPer100g: d.sugarPer100g,
                    suitableFor: d.suitableFor,
                  );
                  final adjustedDishes = [adjustedDish, ...r.dishes.sublist(1)];
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
    );
    calCtrl.dispose();
    proCtrl.dispose();
    carbCtrl.dispose();
    fatCtrl.dispose();
  }

  @override
  void dispose() {
    _animController.stop();
    _animController.dispose();
    // Clean up temp image file
    try {
      final file = File(widget.imagePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) { debugPrint("Error: $e"); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            size: 24,
          ),
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
        title: Text(
          _isAnalyzing
              ? 'Analyzing...'
              : _error != null
              ? 'Error'
              : widget.existingMeal != null
              ? widget.existingMeal!.name
              : 'Results',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: SafeArea(
          child: _isAnalyzing
              ? _buildLoadingState(isDark)
              : _error != null
              ? _buildError(isDark)
              : _buildResults(isDark),
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return ShimmerLoading(
      isLoading: true,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Image skeleton
            const SkeletonPlaceholder(height: 220),
            const SizedBox(height: 12),

            // Gram adjuster skeleton
            const SkeletonPlaceholder(height: 40),
            const SizedBox(height: 16),

            // Nutrition card skeleton
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A22) : Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  // Header badge skeleton
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SkeletonPlaceholder(
                        width: 100,
                        height: 28,
                        borderRadius: 14,
                      ),
                      const SkeletonPlaceholder(
                        width: 100,
                        height: 28,
                        borderRadius: 14,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Calories skeleton
                  const SkeletonPlaceholder(
                    width: 100,
                    height: 60,
                    borderRadius: 8,
                  ),
                  const SizedBox(height: 16),
                  // Macro circles row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      3,
                      (_) => const SkeletonPlaceholder(
                        width: 56,
                        height: 56,
                        isCircle: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Nutrition details skeleton
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A22) : Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                children: [
                  SkeletonPlaceholder(width: 150, height: 20, borderRadius: 4),
                  SizedBox(height: 20),
                  SkeletonPlaceholder(height: 16, borderRadius: 4),
                  SizedBox(height: 16),
                  SkeletonPlaceholder(height: 16, borderRadius: 4),
                  SizedBox(height: 16),
                  SkeletonPlaceholder(height: 16, borderRadius: 4),
                  SizedBox(height: 16),
                  SkeletonPlaceholder(height: 16, borderRadius: 4),
                  SizedBox(height: 16),
                  SkeletonPlaceholder(height: 16, borderRadius: 4),
                  SizedBox(height: 16),
                  SkeletonPlaceholder(height: 16, borderRadius: 4),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Analysis stage text below skeletons
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Text(
                    _analysisStage,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _analysisSub,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: MacroSnapTheme.textTertiary(context),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(bool isDark) {
    final isNoUrl = _error == 'no_url';
    final isScanLimit = _error?.contains('Free scans') == true;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNoUrl
                  ? Icons.cloud_off_rounded
                  : isScanLimit
                      ? Icons.lock_rounded
                      : Icons.help_outline_rounded,
              size: 56,
              color: isNoUrl
                  ? MacroSnapTheme.macroProtein
                  : isScanLimit
                      ? MacroSnapTheme.neonPink
                      : MacroSnapTheme.neonOrange,
            ),
            const SizedBox(height: 12),
            Text(
              isNoUrl
                  ? 'Server Not Set'
                  : isScanLimit
                      ? 'Free Scans Used'
                      : 'Could Not Identify',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  isNoUrl
                      ? 'Enter your server URL in Settings to enable AI food analysis.'
                      : _error ?? 'Something went wrong. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: MacroSnapTheme.textSecondary(context),
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            if (isNoUrl)
              GradientButton(
                label: 'Go Back',
                onPressed: () => Navigator.pop(context),
              )
            else ...[
              // Retry button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _isAnalyzing = true;
                      _error = null;
                      _result = null;
                    });
                    _analyze();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'TRY AGAIN',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: MacroSnapTheme.neonGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Manual entry option
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _result = NutritionResult(
                      dishes: [],
                      description: '',
                      confidence: 1.0,
                    );
                  });
                  _showManualEntryDialog(isDark);
                },
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Enter Food Manually'),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
                      ),
                    ),
                  )
                : _buildMealPlaceholder(),
          ),
          const SizedBox(height: 12),

          // Low confidence warning banner (like Cal AI / MyFitnessPal)
          if (_showLowConfidenceWarning && widget.existingMeal == null)
            _buildLowConfidenceBanner(isDark),

          if (hasMultiDish) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _showPerDish = !_showPerDish),
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
                GlassCard(
                  child: Column(
                    children: [
                      _buildMealHeader(isDark, r),
                      const Divider(height: 32),
                      _buildTotalCalories(isDark, r),
                      const SizedBox(height: 24),
                      _buildMacroRow(isDark, r),
                    ],
                  ),
                ),
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
                        _buildNutrientRow(
                          'Calories',
                          r.calories,
                          'kcal',
                          MacroSnapTheme.macroCalories,
                          isDark,
                        ),
                        _buildNutrientRow(
                          'Protein',
                          r.protein,
                          'g',
                          MacroSnapTheme.macroProtein,
                          isDark,
                        ),
                        _buildNutrientRow(
                          'Carbs',
                          r.carbs,
                          'g',
                          MacroSnapTheme.macroCalories,
                          isDark,
                        ),
                        _buildNutrientRow(
                          'Sugar',
                          r.sugar,
                          'g',
                          const Color(0xFFDB2777),
                          isDark,
                        ),
                        _buildNutrientRow(
                          'Fats',
                          r.fats,
                          'g',
                          MacroSnapTheme.macroFats,
                          isDark,
                        ),
                        _buildNutrientRow(
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
                            HapticFeedback.heavyImpact();
                            final combinedName = hasMultiDish
                                ? r.dishes.map((d) => d.name).join(', ')
                                : r.dishes.first.name;
                            MealStore.instance.add(
                              MealRecord(
                                id: const Uuid().v4(),
                                date: DateTime.now(),
                                name: combinedName,
                                category: '',
                                calories: r.calories,
                                protein: r.protein,
                                carbs: r.carbs,
                                fats: r.fats,
                                fiber: r.fiber,
                                serving: r.description,
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

  /// Serving-weight parentheticals like "(6g)" or "(400 g)" are stripped
  /// from every display on this screen: nutrition here always calculates
  /// from the 100 g baseline, so a gram weight would contradict the numbers
  /// shown next to it.
  String _stripGrams(String text) =>
      text.replaceAll(RegExp(r'\s*\(\s*\d+(?:\.\d+)?\s*g\s*\)'), '');

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

  Widget _buildMealHeader(bool isDark, NutritionResult r) {
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              r.dishes.length == 1
                  ? r.dishes.first.name
                  : '${r.dishes.length} Items',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MacroSnapTheme.neonGreen,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildSuitabilityBadge(isDark, r),
      ],
    );
  }

  Widget _buildSuitabilityBadge(bool isDark, NutritionResult r) {
    final isBulk = r.suitableFor == 'bulk';
    final isDiet = r.suitableFor == 'diet';
    final color = isBulk
        ? MacroSnapTheme.macroFats
        : isDiet
        ? MacroSnapTheme.macroProtein
        : MacroSnapTheme.greenText(context);
    final icon = isBulk
        ? Icons.fitness_center_rounded
        : isDiet
        ? Icons.eco_rounded
        : Icons.check_circle_rounded;
    final label = isBulk
        ? 'Best for Bulk'
        : isDiet
        ? 'Best for Diet'
        : 'Balanced';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCalories(bool isDark, NutritionResult r) {
    return Column(
      children: [
        Text(
          '${r.calories}',
          style: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            letterSpacing: -2,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'kilocalories',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MacroSnapTheme.textTertiary(context),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildMacroRow(bool isDark, NutritionResult r) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildMacroItem(
          'Protein',
          '${r.protein.toInt()}g',
          MacroSnapTheme.macroProtein,
          isDark,
        ),
        _buildMacroItem(
          'Carbs',
          '${r.carbs.toInt()}g',
          MacroSnapTheme.macroCalories,
          isDark,
        ),
        _buildMacroItem(
          'Fats',
          '${r.fats.toInt()}g',
          MacroSnapTheme.macroFats,
          isDark,
        ),
      ],
    );
  }

  Widget _buildMacroItem(String label, String value, Color color, bool isDark) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.1),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: MacroSnapTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildNutrientRow(
    String label,
    num value,
    String unit,
    Color color,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: MacroSnapTheme.textPrimaryMuted(context),
            ),
          ),
          const Spacer(),
          Text(
            '${value.toStringAsFixed(value is int ? 0 : 1)} $unit',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}
