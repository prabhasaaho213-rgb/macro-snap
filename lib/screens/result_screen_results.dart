part of 'result_screen.dart';

// Split out of result_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _ResultResults on _ResultScreenState {
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
                        // The photo lives in the OS temp dir; if Android has
                        // cleared it, show a neutral block instead of throwing
                        // a FileImage error into the widget tree.
                        errorBuilder: (_, _, _) => Container(
                          height: 220,
                          width: double.infinity,
                          color: MacroSnapTheme.borderSubtle(context),
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: MacroSnapTheme.textTertiary(context),
                          ),
                        ),
                      ),
                    ),
                  )
                : _buildMealPlaceholder(),
          ),
          const SizedBox(height: 12),

          // Low confidence warning banner (like Cal AI / MyFitnessPal)
          if (_showLowConfidenceWarning && widget.existingMeal == null)
            _buildLowConfidenceBanner(isDark),

          // Total-serving gram adjuster (defaults to 100 g). View mode keeps
          // the logged meal's totals as the source of truth, so it's hidden.
          if (widget.existingMeal == null) _buildGramAdjuster(isDark),

          if (hasMultiDish) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _rebuild(() => _showPerDish = !_showPerDish),
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
                _buildNutritionCard(isDark, r),
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
                        // Calories, protein, carbs and fats are already the
                        // four highlighted cards at the top of this screen —
                        // repeating them here read like two different meals.
                        // This list keeps only what the cards do not show.
                        NutrientRow(
                          'Sugar',
                          r.sugar,
                          'g',
                          const Color(0xFFDB2777),
                          isDark,
                        ),
                        NutrientRow(
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
                            // The name the user sees (possibly renamed) is
                            // the name that gets logged, so the meal list and
                            // the card never disagree.
                            MealStore.instance.add(
                              MealRecord(
                                id: const Uuid().v4(),
                                date: DateTime.now(),
                                name: _cardTitle,
                                category: '',
                                calories: r.calories,
                                protein: r.protein,
                                carbs: r.carbs,
                                fats: r.fats,
                                fiber: r.fiber,
                                serving: r.description,
                                tastiness: _cardTastiness?.id,
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

  /// Total-serving gram adjuster. Defaults to 100 g; the user can raise or
  /// lower it and every item's nutrients rescale from their per-100g values.
  Widget _buildGramAdjuster(bool isDark) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.scale_rounded,
              size: 18,
              color: MacroSnapTheme.textTertiary(context),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                // The label wraps to a second line when the controls crowd it
                // instead of shrinking into "Total Serv…".
                'Total Serving',
                maxLines: 2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _setGrams(_grams >= 50 ? _grams - 25 : 25),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.remove_rounded,
                  size: 18,
                  color: MacroSnapTheme.neonGreen,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$_grams',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'g',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _setGrams(_grams <= 975 ? _grams + 25 : 1000),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: MacroSnapTheme.neonGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
