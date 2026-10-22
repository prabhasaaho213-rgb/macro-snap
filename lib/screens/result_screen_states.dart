part of 'result_screen.dart';

// Split out of result_screen.dart. Same library, so these builders keep access to
// the screen's private state without threading parameters through.
extension _ResultStates on _ResultScreenState {
  /// The scan view sits OUTSIDE the shimmer: ShimmerLoading paints a white
  /// sweep across everything inside it, which would wash the photo out.
  Widget _buildLoadingState(bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: ScanAnimationView(
            imagePath: widget.imagePath,
            labels: _revealing && _result != null
                ? _result!.dishes.map((d) => d.name).toList()
                : null,
          ),
        ),
        Expanded(child: _buildSkeletons(isDark)),
      ],
    );
  }

  Widget _buildSkeletons(bool isDark) {
    return ShimmerLoading(
      isLoading: true,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
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
    final isScanLimit = _error?.toLowerCase().contains('free scans') == true;
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
                  ? 'Free Scans Used Today'
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
                    _rebuild(() {
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
                  _rebuild(() {
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
}
