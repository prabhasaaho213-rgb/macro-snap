import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/theme.dart';
import '../models/meal_record.dart';
import '../services/barcode_db.dart';
import '../services/barcode_lookup.dart';
import '../services/meal_store.dart';
import '../widgets/animations.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import 'manual_barcode_entry_screen.dart';

/// Turns a barcode product plus a portion into the meal that gets logged.
///
/// Barcode nutrition is always per 100 g, so everything is scaled by the eaten
/// weight — logging the raw per-100 g numbers was wrong for every packet that
/// is not eaten a whole 100 g at a time. Pure, so the arithmetic is testable
/// without a camera.
MealRecord mealFromBarcode(BarcodeFood food, int grams, {DateTime? now}) {
  final ratio = grams / 100.0;
  return MealRecord(
    id: 'barcode_${(now ?? DateTime.now()).millisecondsSinceEpoch}',
    date: now ?? DateTime.now(),
    name: food.name,
    category: food.brand,
    calories: (food.caloriesPer100g * ratio).round(),
    protein: food.proteinPer100g * ratio,
    carbs: food.carbsPer100g * ratio,
    fats: food.fatsPer100g * ratio,
    fiber: food.fiberPer100g * ratio,
    serving: '${grams}g',
  );
}

class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  BarcodeFood? _found;
  bool _scanning = true;

  /// Set while a barcode is being resolved. Also stops the scanner for that
  /// moment, so one package does not fire five lookups and five dialogs.
  bool _lookingUp = false;
  String? _pendingCode;

  /// How many grams were eaten. Barcode nutrition is per 100 g, but a packet
  /// is never eaten a full 100 g at a time — without this the meal was logged
  /// as exactly 100 g every single scan, with no way to correct it.
  final TextEditingController _gramsCtrl = TextEditingController(text: '100');

  @override
  void dispose() {
    _gramsCtrl.dispose();
    super.dispose();
  }

  /// Parsed portion, clamped to something a single meal can plausibly be.
  int get _grams {
    final typed = int.tryParse(_gramsCtrl.text.trim()) ?? 100;
    return typed.clamp(1, 2000);
  }

  double get _ratio => _grams / 100.0;

  void _setGrams(int grams) {
    setState(() => _gramsCtrl.text = grams.toString());
    HapticFeedback.selectionClick();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning || _lookingUp) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.trim().isEmpty) return;
    _resolve(code.trim());
  }

  /// Bundled table → Open Food Facts → manual entry.
  ///
  /// The bundled table only ever held a few dozen products, so nearly every
  /// real package used to land on "Product Not Found" with no way out. The
  /// remote lookup is what makes scanning work on an arbitrary label.
  Future<void> _resolve(String code) async {
    setState(() {
      _scanning = false;
      _lookingUp = true;
      _pendingCode = code;
    });
    HapticFeedback.mediumImpact();

    final food = await BarcodeService.lookup(code);
    if (!mounted) return;

    if (food != null) {
      HapticFeedback.heavyImpact();
      setState(() {
        _found = food;
        _lookingUp = false;
      });
      return;
    }

    setState(() => _lookingUp = false);
    final manual = await Navigator.push<BarcodeFood>(
      context,
      habitFlowRoute<BarcodeFood>(ManualBarcodeEntryScreen(barcode: code)),
    );
    if (!mounted) return;
    setState(() {
      _found = manual;
      // Cancel means "scan something else", not a dead end.
      _scanning = manual == null;
      _pendingCode = null;
    });
  }

  Future<void> _log() async {
    final food = _found;
    if (food == null) return;
    MealStore.instance.add(mealFromBarcode(food, _grams));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Scan Barcode',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ),
      body: _found != null ? _buildResult(isDark) : _buildScanner(isDark),
    );
  }

  Widget _buildScanner(bool isDark) {
    return Stack(
      children: [
        MobileScanner(onDetect: _onDetect),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: MacroSnapTheme.neonGreen, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Icon(
                Icons.qr_code_scanner_rounded,
                size: 80,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        if (_lookingUp)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.78),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Looking up ${_pendingCode ?? 'barcode'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Text(
            'Point camera at barcode',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  blurRadius: 10,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(bool isDark) {
    final f = _found!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          GlassCard(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: MacroSnapTheme.neonGreen,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  f.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  f.brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
                const Divider(height: 32),
                _amountEditor(isDark),
                const Divider(height: 32),
                _row(
                  'Calories',
                  '${(f.caloriesPer100g * _ratio).round()} kcal',
                  MacroSnapTheme.macroCalories,
                  isDark,
                ),
                _row(
                  'Protein',
                  '${(f.proteinPer100g * _ratio).toStringAsFixed(1)}g',
                  MacroSnapTheme.macroProtein,
                  isDark,
                ),
                _row(
                  'Carbs',
                  '${(f.carbsPer100g * _ratio).toStringAsFixed(1)}g',
                  MacroSnapTheme.macroCalories,
                  isDark,
                ),
                _row(
                  'Fats',
                  '${(f.fatsPer100g * _ratio).toStringAsFixed(1)}g',
                  MacroSnapTheme.macroFats,
                  isDark,
                ),
                if (f.fiberPer100g > 0)
                  _row(
                    'Fiber',
                    '${(f.fiberPer100g * _ratio).toStringAsFixed(1)}g',
                    MacroSnapTheme.greenText(context),
                    isDark,
                  ),
                if (f.sugarPer100g > 0)
                  _row(
                    'Sugar',
                    '${(f.sugarPer100g * _ratio).toStringAsFixed(1)}g',
                    const Color(0xFFDB2777),
                    isDark,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: GradientButton(label: 'Log It', onPressed: _log),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => setState(() {
                    _found = null;
                    _scanning = true;
                    _gramsCtrl.text = '100';
                  }),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark
                        ? MacroSnapTheme.cardDark
                        : const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    'Scan Again',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: MacroSnapTheme.textPrimaryMuted(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The portion picker. A typable grams box plus the usual packet sizes, so
  /// "I ate 30 g of this" is one tap — or a typed number for anything else.
  Widget _amountEditor(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Amount eaten',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: MacroSnapTheme.textPrimaryMuted(context),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _gramsCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'grams',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final grams in const [30, 50, 100, 150, 200])
              ChoiceChip(
                label: Text('${grams}g', style: const TextStyle(fontSize: 12)),
                selected: _grams == grams,
                onSelected: (_) => _setGrams(grams),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Label values are per 100 g — the numbers below are for $_grams g',
          style: TextStyle(
            fontSize: 11.5,
            color: MacroSnapTheme.textTertiary(context),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
              color: MacroSnapTheme.textPrimaryMuted(context),
            ),
          ),
          const Spacer(),
          Text(
            value,
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
