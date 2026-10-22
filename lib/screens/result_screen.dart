import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../core/theme.dart';
import '../models/health_score.dart';
import '../models/meal_record.dart';
import '../services/gemini_service.dart';
import '../services/meal_store.dart';
import '../services/recent_food_service.dart';
import '../services/scan_gate.dart';
import '../widgets/animations.dart';
import '../widgets/calorie_reveal.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/scan_animation.dart';
import '../services/crash_reporting.dart';
import '../widgets/nutrient_row.dart';
import '../widgets/nutrition_tile.dart';

part 'result_screen_states.dart';
part 'result_screen_results.dart';
part 'result_screen_dish.dart';
part 'result_screen_dialogs.dart';
part 'result_screen_card.dart';

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

  /// Current total serving in grams. Starts at 100 g (the baseline the AI
  /// reports per-100g values against) and is replaced by the weight the
  /// analyzer estimated for the whole photo as soon as the result arrives.
  /// The +/- adjuster always lets the user override it.
  int _grams = 100;
  bool _showPerDish = false;

  /// True while the detected dish names are popping onto the photo (phase 2 of
  /// the scan animation). The results UI only appears once the reveal ends.
  bool _revealing = false;

  /// Keeps the calorie reveal's state — and so its spin — alive across the
  /// "Show per Dish" rebuilds instead of replaying it.
  final GlobalKey _calorieKey = GlobalKey();

  /// Session-only overrides applied on top of the analysis: a renamed dish, a
  /// hand-picked health score, and the user's tastiness verdict. They describe
  /// this one result, so they reset with the screen instead of being stored on
  /// their own (tastiness rides along on the meal when it is logged).
  String? _titleOverride;
  int? _healthOverride;
  Tastiness? _tastiness;
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
      // Never overwrite the reveal's own captions.
      if (mounted && _isAnalyzing && !_revealing) {
        setState(() {
          _analysisStage = 'Still working...';
          _analysisSub =
              'Food identification may take a moment\nfor complex dishes';
        });
      }
    });
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isAnalyzing && !_revealing) {
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

      final isUnidentified =
          result.confidence < 0.5 ||
          result.dishes.any((d) => d.name.toLowerCase() == 'unknown');

      if (isUnidentified) {
        // Low confidence / unidentified — the scan is NOT counted. The server
        // refunds its reservation for exactly these cases (confidence < 0.5 or
        // an "Unknown" dish), so mirror the numbers it just returned.
        //
        // Skipping this used to leave the local count stale: the badge showed
        // the scan as free while the server had already spent it, the two
        // drifted apart, and a later scan 403'd with no warning. Recording the
        // server's answer in BOTH branches keeps them in step.
        if (result.serverScansKnown) {
          await ScanGate.recordServerCounts(
            used: result.scansUsed,
            limit: result.scansLimit,
            resetAt: result.serverResetAt,
          );
        }
        if (!mounted) return;
        setState(() {
          _result = result;
          _grams = result.grams;
          _isAnalyzing = false;
          _showLowConfidenceWarning = true;
        });
        _animController.forward();
      } else {
        // Good identification — the scan counts. The SERVER is the authority
        // (it has already incremented its own per-IST-day counter), so mirror
        // the numbers it reported; the local counter stays a display estimate.
        await ScanGate.incrementScan();
        if (result.serverScansKnown) {
          await ScanGate.recordServerCounts(
            used: result.scansUsed,
            limit: result.scansLimit,
            resetAt: result.serverResetAt,
          );
        }
        // Re-check after the async count — the screen may have been
        // closed while the count was being persisted.
        if (!mounted) return;

        // Save to recent foods for quick re-add
        if (result.dishes.isNotEmpty) {
          final dish = result.dishes.first;
          await RecentFoodService.instance.add(
            RecentFood(
              id: const Uuid().v4(),
              name: dish.name,
              calories: (dish.caloriesPer100g * result.grams / 100).round(),
              protein: dish.proteinPer100g * result.grams / 100,
              carbs: dish.carbsPer100g * result.grams / 100,
              fats: dish.fatsPer100g * result.grams / 100,
              fiber: dish.fiberPer100g * result.grams / 100,
              serving: result.description,
              scannedAt: DateTime.now(),
            ),
          );
        }

        // The analysis is done but the "magic trick" is not: pop the detected
        // dish names onto the photo one by one, and only then show the results.
        setState(() {
          _result = result;
          // Start at the weight the AI saw in the photo (two eggs ≈ 100 g).
          // The +/- adjuster still overrides it.
          _grams = result.grams;
          _revealing = true;
          _analysisStage = result.dishes.length == 1
              ? 'Found it!'
              : 'Found ${result.dishes.length} items!';
          _analysisSub = 'Calculating your macros...';
        });
        await Future.delayed(
          ScanAnimationView.revealDuration(result.dishes.length),
        );
        if (!mounted) return;
        setState(() {
          _isAnalyzing = false;
          _revealing = false;
        });
        _animController.forward();
      }
    } catch (e) {
      // Scan limit reached is not a recognition failure — show the clear
      // upsell message.
      if (e.toString().contains('Scan limit')) {
        // The server refused the scan: today's free allowance is gone. Record
        // it as used-up so the UI immediately shows 0 scans left.
        await ScanGate.markLimitReached();
        if (!mounted) return;
        setState(() {
          _error =
              'Your ${ScanGate.freeLimitPerDay} free scans for today are used.\n'
              'They reset at midnight.';
          _isAnalyzing = false;
        });
        return;
      }
      if (e.toString().contains('sign in')) {
        if (mounted) {
          setState(() {
            _error = 'Please sign in to use AI scans.';
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

  /// Applies a new total serving size: updates the slider value AND rebuilds
  /// the [NutritionResult] with the new grams so every macro (calories,
  /// protein, carbs, fats, fiber, sugar) rescales from its per-100g value.
  void _setGrams(int g) {
    setState(() {
      _grams = g;
      final r = _result;
      if (r != null) _result = r.withGrams(g);
    });
  }

  void _setTastiness(Tastiness value) {
    HapticFeedback.selectionClick();
    _rebuild(() => _tastiness = value);
  }

  /// Replaces one macro total, scaling every dish's per-100 g value by the
  /// same factor so a multi-item plate keeps its proportions instead of
  /// dumping the whole correction onto the first dish.
  ///
  /// The edit arrives as a total (what the card shows) and is converted back
  /// through the serving weight, so the gram adjuster still rescales correctly
  /// afterwards. Editing a macro the dish has none of (0 g protein) puts the
  /// value on the first dish rather than multiplying by infinity.
  void _applyMacroEdit(_MacroField field, double value) {
    final r = _result;
    if (r == null || value < 0) return;
    final ratio = (r.grams > 0 ? r.grams : 100) / 100.0;
    final old = switch (field) {
      _MacroField.calories => r.calories.toDouble(),
      _MacroField.protein => r.protein,
      _MacroField.carbs => r.carbs,
      _MacroField.fats => r.fats,
    };
    final factor = old > 0 ? value / old : 0.0;

    double edited(double per100, int index) => old > 0
        ? per100 * factor
        : (index == 0 ? per100 + value / ratio : per100);

    DishItem next(DishItem dish, int index) => DishItem(
      name: dish.name,
      portionDescription: dish.portionDescription,
      caloriesPer100g: field == _MacroField.calories
          ? edited(dish.caloriesPer100g.toDouble(), index).round()
          : dish.caloriesPer100g,
      proteinPer100g: field == _MacroField.protein
          ? edited(dish.proteinPer100g, index)
          : dish.proteinPer100g,
      carbsPer100g: field == _MacroField.carbs
          ? edited(dish.carbsPer100g, index)
          : dish.carbsPer100g,
      fatsPer100g: field == _MacroField.fats
          ? edited(dish.fatsPer100g, index)
          : dish.fatsPer100g,
      fiberPer100g: dish.fiberPer100g,
      sugarPer100g: dish.sugarPer100g,
      suitableFor: dish.suitableFor,
      grams: dish.grams,
      ingredients: dish.ingredients,
    );

    HapticFeedback.selectionClick();
    _rebuild(() {
      _result = NutritionResult(
        dishes: [
          for (var i = 0; i < r.dishes.length; i++) next(r.dishes[i], i),
        ],
        description: r.description,
        confidence: r.confidence,
        scansUsed: r.scansUsed,
        scansLimit: r.scansLimit,
        grams: r.grams,
        serverScansKnown: r.serverScansKnown,
        serverResetAt: r.serverResetAt,
      );
    });
  }

  /// Rebuild helper for the builders that now live in part files.
  ///
  /// `setState` is `@protected`, and an extension is not a `State` subclass,
  /// so calling it directly from a part file is rejected by the analyzer.
  /// Routing through a real member keeps the lint honest instead of silencing it.
  void _rebuild(VoidCallback fn) => setState(fn);

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
    } catch (e, st) {
      logError('ResultScreen.dispose (temp image)', e, st);
    }
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

  /// Serving-weight parentheticals like "(6g)", "(400 g)" or "(approx. 10g)"
  /// are stripped from every display on this screen: per-item gram weights
  /// are hidden, and nutrition is always calculated from the adjustable
  /// total-serving baseline (default 100 g) shown in the gram adjuster.
  String _stripGrams(String text) => text.replaceAll(
    RegExp(r'\s*\([^)]*\b\d+(?:\.\d+)?\s*g\b[^)]*\)', caseSensitive: false),
    '',
  );
}
