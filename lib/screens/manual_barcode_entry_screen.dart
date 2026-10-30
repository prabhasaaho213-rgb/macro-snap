import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../services/barcode_db.dart';

/// Manual nutrition entry for a scanned barcode no database knows.
///
/// This used to be an `AlertDialog` opened straight from the scanner callback,
/// with three squeezed side-by-side fields labelled "Pro…", "Car…", "Fat…".
/// The dialog never took typed input on device, so the scan dead-ended twice:
/// the product was unknown AND the only way to add it did not accept text.
///
/// It is a full page now — an opaque route, a real `Scaffold`, full-width
/// fields and a form — which is the reliable way to get a keyboard on screen
/// and gives the numbers room to be readable. Returns a [BarcodeFood] (per
/// 100 g, matching how barcode results are logged) or null on cancel.
class ManualBarcodeEntryScreen extends StatefulWidget {
  const ManualBarcodeEntryScreen({super.key, required this.barcode});

  final String barcode;

  @override
  State<ManualBarcodeEntryScreen> createState() =>
      _ManualBarcodeEntryScreenState();
}

class _ManualBarcodeEntryScreenState extends State<ManualBarcodeEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatsCtrl = TextEditingController();
  final _fiberCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatsCtrl.dispose();
    _fiberCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final food = BarcodeFood(
      barcode: widget.barcode,
      name: _nameCtrl.text.trim(),
      brand: 'Manual Entry',
      caloriesPer100g: int.tryParse(_calCtrl.text.trim()) ?? 0,
      proteinPer100g: double.tryParse(_proteinCtrl.text.trim()) ?? 0,
      carbsPer100g: double.tryParse(_carbsCtrl.text.trim()) ?? 0,
      fatsPer100g: double.tryParse(_fatsCtrl.text.trim()) ?? 0,
      fiberPer100g: double.tryParse(_fiberCtrl.text.trim()) ?? 0,
    );
    Navigator.pop(context, food);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Add this product')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                'No database had this barcode',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Barcode ${widget.barcode}. Type the values from the label — '
                'everything is per 100 g, which is how barcode meals are '
                'logged.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Food name',
                  hintText: 'e.g. Masala oats',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),
              _NumberField(
                controller: _calCtrl,
                label: 'Calories (kcal per 100 g)',
                hint: 'e.g. 380',
                formKey: _formKey,
                requiredField: true,
              ),
              const SizedBox(height: 14),
              _NumberField(
                controller: _proteinCtrl,
                label: 'Protein (g per 100 g)',
                hint: 'e.g. 8',
                formKey: _formKey,
              ),
              const SizedBox(height: 14),
              _NumberField(
                controller: _carbsCtrl,
                label: 'Carbs (g per 100 g)',
                hint: 'e.g. 60',
                formKey: _formKey,
              ),
              const SizedBox(height: 14),
              _NumberField(
                controller: _fatsCtrl,
                label: 'Fats (g per 100 g)',
                hint: 'e.g. 11',
                formKey: _formKey,
              ),
              const SizedBox(height: 14),
              _NumberField(
                controller: _fiberCtrl,
                label: 'Fiber (g per 100 g) — optional',
                hint: 'e.g. 2',
                formKey: _formKey,
              ),
              const SizedBox(height: 26),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: MacroSnapTheme.neonGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Use these values',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One full-width numeric field. Decimals are allowed (protein is 3.5 g, not
/// 3), but negative numbers and letters are refused at the keyboard, so the
/// parser in [_save] only ever sees digits and a dot.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.formKey,
    this.requiredField = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final GlobalKey<FormState> formKey;
  final bool requiredField;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        final text = v?.trim() ?? '';
        if (text.isEmpty) {
          return requiredField ? 'Calories are required' : null;
        }
        return double.tryParse(text) == null ? 'Numbers only' : null;
      },
    );
  }
}
