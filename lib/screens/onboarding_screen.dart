import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../models/bmi.dart';
import '../models/diet_profile.dart';
import '../services/meal_sync_service.dart';

/// Cal AI-style onboarding: collects user profile data before first use.
///
/// Flow: Welcome → Name → Gender → Age → Weight → Height → Goal → Activity
/// Features scroll-wheel dial pickers for age/weight/height, animated number
/// transitions, gradient glow effects, and haptic feedback on every interaction.
class OnboardingScreen extends StatefulWidget {
  final Widget nextScreen;

  const OnboardingScreen({super.key, required this.nextScreen});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  // Focus node for the name field, held explicitly so the keyboard can be
  // dismissed the moment the user leaves this step (see _dismissKeyboard).
  final _nameFocus = FocusNode();
  final ValueNotifier<int> _page = ValueNotifier(0);

  // Page entrance animation
  late AnimationController _entranceAnim;
  late Animation<double> _entranceOpacity;
  late Animation<Offset> _entranceSlide;

  // User data
  String _name = '';
  Gender _gender = Gender.male;
  int _age = 25;
  double _weight = 70;
  double _height = 170;
  bool _isKg = true;
  bool _isCm = true;
  // Neutral default — see diet_plan_screen: a deficit is never pre-selected.
  Goal _goal = Goal.maintain;
  ActivityLevel _activity = ActivityLevel.moderate;
  DietPreference _diet = DietPreference.vegetarian;

  static const _totalSteps = 9;

  @override
  void initState() {
    super.initState();
    _entranceAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _entranceAnim, curve: Curves.easeOut));
    _entranceSlide =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(parent: _entranceAnim, curve: Curves.easeOutCubic),
        );
    _entranceAnim.forward();
  }

  @override
  void dispose() {
    _entranceAnim.dispose();
    _pageController.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _page.dispose();
    super.dispose();
  }

  /// Closes the soft keyboard.
  ///
  /// Tapping NEXT / BACK (or Skip) is NOT a focus change in Flutter — the
  /// name field keeps focus and the keyboard stays up over every step that
  /// follows, which is why it seemed to "stick" after entering a name.
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// BMI from the dials as they currently stand.
  double? get _bmi => BmiCalculator.value(
    weightKg: _isKg ? _weight : _weight * 0.453592,
    heightCm: _isCm ? _height : _height * 2.54,
  );

  bool get _isUnderweight {
    final bmi = _bmi;
    return bmi != null && bmi < DietProfile.underweightBmi;
  }

  /// Blocks a "Lose Weight" goal when the measurements entered put the user
  /// below the healthy BMI range.
  ///
  /// The diet plan already refuses to save a deficit for an underweight user,
  /// but onboarding could still hand them one-step-earlier: they left this
  /// screen with `loseWeight` stored and no explanation. Returns true when the
  /// goal has been switched to Maintain and onboarding may continue.
  Future<bool> _confirmHealthyGoal() async {
    final bmi = _bmi;
    if (bmi == null) return true;
    final keep = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lose Weight is not safe at this BMI'),
        content: Text(
          'Your BMI is ${BmiCalculator.displayValue(bmi).toStringAsFixed(1)}, '
          'below the healthy range (18.5–24.9). A calorie deficit can do more '
          'harm than good here, so we will keep your goal at Maintain Weight. '
          'You can change it later in Diet Plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Go Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Use Maintain Weight'),
          ),
        ],
      ),
    );
    if (keep != true) return false;
    setState(() => _goal = Goal.maintain);
    return true;
  }

  Future<void> _complete() async {
    _dismissKeyboard();
    HapticFeedback.heavyImpact();
    // Skip lands here too, so the safe-goal check cannot be bypassed by
    // jumping straight to the end of onboarding.
    if (_goal == Goal.loseWeight && _isUnderweight) {
      if (!await _confirmHealthyGoal()) return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_v2_done', true);
    final name = _name.isNotEmpty ? _name : _nameController.text.trim();
    if (name.isNotEmpty) {
      await prefs.setString('name', name);
      userNameNotifier.value = name;
      // Auto-save the name to the cloud too (no-op for guests).
      MealSyncService.syncPreferences({'name': name});
    }

    final profile = DietProfile(
      weightKg: _isKg ? _weight : _weight * 0.453592,
      heightCm: _isCm ? _height : _height * 2.54,
      age: _age,
      gender: _gender,
      goal: _goal,
      activity: _activity,
      diet: _diet,
    );
    DietPlanService.instance.save(profile);

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => widget.nextScreen));
    }
  }

  Future<void> _next() async {
    _dismissKeyboard();
    HapticFeedback.lightImpact();
    if (_page.value < _totalSteps - 1) {
      // Page 6 is the goal step: stop an underweight user from walking out of
      // it with a deficit selected.
      if (_page.value == 6 && _goal == Goal.loseWeight && _isUnderweight) {
        if (!await _confirmHealthyGoal()) return;
      }
      // Reset entrance animation for next page
      _entranceAnim.reset();
      _entranceAnim.forward();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _complete();
    }
  }

  void _prev() {
    _dismissKeyboard();
    HapticFeedback.lightImpact();
    if (_page.value > 0) {
      _entranceAnim.reset();
      _entranceAnim.forward();
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subText = MacroSnapTheme.textSecondary(context);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip + progress
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ValueListenableBuilder<int>(
                valueListenable: _page,
                builder: (_, p, _) => Row(
                  children: [
                    if (p > 0)
                      IconButton(
                        onPressed: _prev,
                        icon: Icon(Icons.arrow_back_rounded, color: textColor),
                      )
                    else
                      const SizedBox(width: 48),
                    const Spacer(),
                    Text(
                      '${p + 1}/$_totalSteps',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: subText,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _complete,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: subText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Progress bar
            ValueListenableBuilder<int>(
              valueListenable: _page,
              builder: (_, p, _) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (p + 1) / _totalSteps,
                    backgroundColor: isDark
                        ? Colors.white10
                        : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation(
                      MacroSnapTheme.neonGreen,
                    ),
                    minHeight: 4,
                  ),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) {
                  _page.value = i;
                  // Leaving the name step always drops keyboard focus, so the
                  // field can never hold it while it is off screen.
                  if (i != 1) _dismissKeyboard();
                },
                itemCount: _totalSteps,
                itemBuilder: (_, i) =>
                    _buildPage(i, textColor, subText, isDark),
              ),
            ),
            // Next / Done button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: ValueListenableBuilder<int>(
                valueListenable: _page,
                builder: (_, p, _) => SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: MacroSnapTheme.neonGreen,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      p == _totalSteps - 1 ? 'GET STARTED' : 'NEXT',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(int i, Color textColor, Color subText, bool isDark) {
    switch (i) {
      case 0:
        return _buildWelcome(textColor, subText, isDark);
      case 1:
        return _buildName(textColor, subText, isDark);
      case 2:
        return _buildGender(textColor, subText, isDark);
      case 3:
        return _buildDialPage<int>(
          title: 'How old are you?',
          value: _age < 18 ? 18 : _age,
          display: '${_age < 18 ? 18 : _age}',
          unit: 'years',
          // 18+, not 14+: every calorie target and BMI band in the app is an
          // adult formula, and India's DPDP Act treats under-18s as children
          // (parental consent). A 14-year-old was being handed an adult deficit.
          min: 18,
          max: 100,
          step: 1,
          onChanged: (v) => setState(() => _age = v),
          textColor: textColor,
          subText: subText,
          isDark: isDark,
        );
      case 4:
        return _buildWeightDial(textColor, subText, isDark);
      case 5:
        return _buildHeightDial(textColor, subText, isDark);
      case 6:
        return _buildGoal(textColor, subText, isDark);
      case 7:
        return _buildActivity(textColor, subText, isDark);
      case 8:
        return _buildDietPreference(textColor, subText, isDark);
      default:
        return const SizedBox();
    }
  }

  // ── Animated entrance wrapper ────────────────────────────────

  Widget _animateIn(Widget child) {
    return FadeTransition(
      opacity: _entranceOpacity,
      child: SlideTransition(position: _entranceSlide, child: child),
    );
  }

  // ── Page builders ──────────────────────────────────────────────

  Widget _buildWelcome(Color textColor, Color subText, bool isDark) {
    return _animateIn(
      // Scrollable + minHeight: keeps the page vertically centered at normal
      // font sizes, but lets it scroll instead of overflowing a RenderFlex
      // at large accessibility font scales on small phones (regression-
      // tested at 2x on 320dp).
      LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing circle icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          MacroSnapTheme.neonGreen.withValues(alpha: 0.2),
                          MacroSnapTheme.neonGreen.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: MacroSnapTheme.neonGreen.withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('📸', style: TextStyle(fontSize: 52)),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Welcome to\nMacroSnap',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Let's set up your profile for personalized calorie and macro targets.",
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: subText, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildName(Color textColor, Color subText, bool isDark) {
    return _animateIn(
      _buildQuestion(
        'What is your name?',
        textColor,
        Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
              child: const Center(
                child: Text('👋', style: TextStyle(fontSize: 40)),
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              // Tapping the background closes the keyboard too.
              onTapOutside: (_) => _dismissKeyboard(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: 'Enter your name',
                hintStyle: TextStyle(color: subText.withValues(alpha: 0.5)),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: MacroSnapTheme.neonGreen,
                    width: 2,
                  ),
                ),
              ),
              onChanged: (v) => _name = v.trim(),
              onSubmitted: (_) => _next(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGender(Color textColor, Color subText, bool isDark) {
    return _animateIn(
      _buildQuestion(
        'What is your gender?',
        textColor,
        Row(
          children: [
            Expanded(
              child: _genderOption(
                '👨',
                'Male',
                Gender.male,
                isDark,
                textColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _genderOption(
                '👩',
                'Female',
                Gender.female,
                isDark,
                textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDietPreference(Color textColor, Color subText, bool isDark) {
    return _animateIn(
      _buildQuestion(
        'Are you vegetarian or non-vegetarian?',
        textColor,
        Column(
          children: [
            Text(
              'This personalises your AI diet plans and meal suggestions.',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: subText, height: 1.5),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _dietOption(
                    '🥦',
                    'Vegetarian',
                    DietPreference.vegetarian,
                    isDark,
                    textColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _dietOption(
                    '🍗',
                    'Non-Vegetarian',
                    DietPreference.nonVegetarian,
                    isDark,
                    textColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dietOption(
    String emoji,
    String label,
    DietPreference value,
    bool isDark,
    Color textColor,
  ) {
    final selected = _diet == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _diet = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          color: selected
              ? MacroSnapTheme.neonGreen.withValues(alpha: 0.12)
              : (isDark ? const Color(0xFF1A1A22) : Colors.white),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? MacroSnapTheme.neonGreen : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            AnimatedScale(
              scale: selected ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: Text(emoji, style: const TextStyle(fontSize: 48)),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _genderOption(
    String emoji,
    String label,
    Gender value,
    bool isDark,
    Color textColor,
  ) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _gender = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          color: selected
              ? MacroSnapTheme.neonGreen.withValues(alpha: 0.12)
              : (isDark ? const Color(0xFF1A1A22) : Colors.white),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? MacroSnapTheme.neonGreen : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            AnimatedScale(
              scale: selected ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: Text(emoji, style: const TextStyle(fontSize: 48)),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cal AI-style DIAL picker pages ────────────────────────────

  Widget _buildDialPage<T>({
    required String title,
    required T value,
    required String display,
    required String unit,
    required T min,
    required T max,
    required int step,
    required ValueChanged<T> onChanged,
    required Color textColor,
    required Color subText,
    required bool isDark,
    bool isDouble = false,
  }) {
    final itemCount = ((max as dynamic) - (min as dynamic)) ~/ step + 1;
    final currentIndex = isDouble
        ? ((value as double) - (min as double)) ~/ step
        : ((value as int) - (min as int)) ~/ step;

    return _animateIn(
      _buildQuestion(
        title,
        textColor,
        Column(
          children: [
            // Glowing number display
            _GlowingNumber(text: display),
            const SizedBox(height: 4),
            Text(unit, style: TextStyle(fontSize: 16, color: subText)),
            const SizedBox(height: 24),
            // Cal AI-style scroll dial
            _DialPicker(
              currentIndex: currentIndex.clamp(0, itemCount - 1).toInt(),
              itemCount: itemCount,
              isDark: isDark,
              onSelected: (index) {
                HapticFeedback.mediumImpact();
                if (isDouble) {
                  onChanged((min as double) + index * step as T);
                } else {
                  onChanged((min as int) + index * step as T);
                }
              },
              labelBuilder: (index) {
                final val = isDouble
                    ? ((min as double) + index * step).toStringAsFixed(1)
                    : '${(min as int) + index * step}';
                return val;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightDial(Color textColor, Color subText, bool isDark) {
    final minW = _isKg ? 30.0 : 66.0;
    final maxW = _isKg ? 200.0 : 440.0;
    final step = _isKg ? 1.0 : 1.0;
    final display = _isKg ? _weight : _weight / 0.453592;
    final itemCount = ((maxW - minW) / step).round();
    final currentIndex = ((display - minW) / step).round().clamp(
      0,
      itemCount - 1,
    );

    return _animateIn(
      _buildQuestion(
        'What is your weight?',
        textColor,
        Column(
          children: [
            // Unit toggle with glow
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isKg = !_isKg);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  _isKg ? 'kg' : 'lbs',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: MacroSnapTheme.neonGreen,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _GlowingNumber(text: display.toStringAsFixed(1)),
            const SizedBox(height: 4),
            Text(
              _isKg ? 'kilograms' : 'pounds',
              style: TextStyle(fontSize: 16, color: subText),
            ),
            const SizedBox(height: 24),
            _DialPicker(
              currentIndex: currentIndex,
              itemCount: itemCount,
              isDark: isDark,
              onSelected: (index) {
                HapticFeedback.mediumImpact();
                final val = minW + index * step;
                setState(() => _weight = val);
              },
              labelBuilder: (index) {
                final val = minW + index * step;
                return val.toStringAsFixed(1);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeightDial(Color textColor, Color subText, bool isDark) {
    final minH = _isCm ? 100.0 : 48.0;
    final maxH = _isCm ? 220.0 : 84.0;
    final step = _isCm ? 1.0 : 1.0;
    final display = _isCm ? _height : _height / 2.54;
    final itemCount = ((maxH - minH) / step).round();
    final currentIndex = ((display - minH) / step).round().clamp(
      0,
      itemCount - 1,
    );

    return _animateIn(
      _buildQuestion(
        'What is your height?',
        textColor,
        Column(
          children: [
            // Unit toggle
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _isCm = !_isCm);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  _isCm ? 'cm' : 'in',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: MacroSnapTheme.neonGreen,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _GlowingNumber(text: display.toStringAsFixed(1)),
            const SizedBox(height: 4),
            Text(
              _isCm ? 'centimeters' : 'inches',
              style: TextStyle(fontSize: 16, color: subText),
            ),
            const SizedBox(height: 24),
            _DialPicker(
              currentIndex: currentIndex,
              itemCount: itemCount,
              isDark: isDark,
              onSelected: (index) {
                HapticFeedback.mediumImpact();
                final val = minH + index * step;
                setState(() => _height = val);
              },
              labelBuilder: (index) {
                final val = minH + index * step;
                return _isCm ? '${val.round()}' : val.toStringAsFixed(1);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoal(Color textColor, Color subText, bool isDark) {
    return _animateIn(
      _buildQuestion(
        'What is your goal?',
        textColor,
        Column(
          children: [
            _goalOption(
              '🔥',
              'Lose Weight',
              'Calorie deficit for fat loss',
              Goal.loseWeight,
              isDark,
            ),
            const SizedBox(height: 12),
            _goalOption(
              '⚖️',
              'Maintain Weight',
              'Stay at your current weight',
              Goal.maintain,
              isDark,
            ),
            const SizedBox(height: 12),
            _goalOption(
              '💪',
              'Gain Muscle',
              'Calorie surplus for muscle gain',
              Goal.gainMuscle,
              isDark,
            ),
            // The BMI screen already tells an underweight user to eat a small
            // surplus; this is the same message at the moment the choice is
            // made, instead of a contradiction two screens later.
            if (_isUnderweight) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonYellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: MacroSnapTheme.neonYellow.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your BMI is '
                        '${BmiCalculator.displayValue(_bmi!).toStringAsFixed(1)} '
                        '— below the healthy range. A calorie deficit is not a '
                        'safe goal right now; Maintenance or a small surplus is.',
                        style: TextStyle(fontSize: 12, color: subText),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _goalOption(
    String emoji,
    String title,
    String subtitle,
    Goal value,
    bool isDark,
  ) {
    final selected = _goal == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _goal = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? MacroSnapTheme.neonGreen.withValues(alpha: 0.12)
              : (isDark ? const Color(0xFF1A1A22) : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? MacroSnapTheme.neonGreen : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            AnimatedScale(
              scale: selected ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: Text(emoji, style: const TextStyle(fontSize: 32)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: MacroSnapTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                color: MacroSnapTheme.neonGreen,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivity(Color textColor, Color subText, bool isDark) {
    final levels = [
      (ActivityLevel.sedentary, 'Sedentary', 'Desk job, little exercise'),
      (ActivityLevel.light, 'Light', '1-2 days/week exercise'),
      (ActivityLevel.moderate, 'Moderate', '3-5 days/week exercise'),
      (ActivityLevel.active, 'Active', '6-7 days/week exercise'),
      (ActivityLevel.veryActive, 'Very Active', 'Twice a day / physical job'),
    ];
    return _animateIn(
      _buildQuestion(
        'How active are you?',
        textColor,
        Column(
          children: levels.map((l) {
            final selected = _activity == l.$1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _activity = l.$1);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: selected
                        ? MacroSnapTheme.neonGreen.withValues(alpha: 0.12)
                        : (isDark ? const Color(0xFF1A1A22) : Colors.white),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? MacroSnapTheme.neonGreen
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: MacroSnapTheme.neonGreen.withValues(
                                alpha: 0.12,
                              ),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: subText),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          color: MacroSnapTheme.neonGreen,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Shared widgets ──────────────────────────────────────────────

  Widget _buildQuestion(String title, Color textColor, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Cal AI-style glowing number display
// ═══════════════════════════════════════════════════════════════════

class _GlowingNumber extends StatelessWidget {
  final String text;
  const _GlowingNumber({required this.text});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0.85, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (_, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              MacroSnapTheme.neonGreen.withValues(alpha: 0.08),
              MacroSnapTheme.neonGreen.withValues(alpha: 0.15),
              MacroSnapTheme.neonGreen.withValues(alpha: 0.08),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: MacroSnapTheme.neonGreen.withValues(alpha: 0.2),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            color: MacroSnapTheme.neonGreen,
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Cal AI-style circular scroll dial picker
// ═══════════════════════════════════════════════════════════════════

class _DialPicker extends StatefulWidget {
  final int currentIndex;
  final int itemCount;
  final bool isDark;
  final ValueChanged<int> onSelected;
  final String Function(int) labelBuilder;

  const _DialPicker({
    required this.currentIndex,
    required this.itemCount,
    required this.isDark,
    required this.onSelected,
    required this.labelBuilder,
  });

  @override
  State<_DialPicker> createState() => _DialPickerState();
}

class _DialPickerState extends State<_DialPicker> {
  late FixedExtentScrollController _scrollController;
  late int _selectedIndex;
  bool _userScrolling = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.currentIndex;
    _scrollController = FixedExtentScrollController(
      initialItem: widget.currentIndex,
    );
  }

  @override
  void didUpdateWidget(covariant _DialPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only animate when parent changes currentIndex EXTERNALLY
    // (e.g. unit toggle). Skip if user is scrolling — it fights the gesture.
    if (oldWidget.currentIndex != widget.currentIndex &&
        !_userScrolling &&
        widget.currentIndex != _selectedIndex) {
      _selectedIndex = widget.currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollController.animateToItem(
            widget.currentIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _getItemExtent() => 56.0;

  @override
  Widget build(BuildContext context) {
    final neonGreen = MacroSnapTheme.neonGreen;

    return SizedBox(
      height: 320,
      child: ListWheelScrollView.useDelegate(
        controller: _scrollController,
        itemExtent: _getItemExtent(),
        perspective: 0.004,
        diameterRatio: 2.5,
        squeeze: 1.0,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (index) {
          if (index != _selectedIndex) {
            HapticFeedback.mediumImpact();
            setState(() {
              _userScrolling = true;
              _selectedIndex = index;
            });
            widget.onSelected(index);
            // Reset flag after parent rebuild settles
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) setState(() => _userScrolling = false);
            });
          }
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.itemCount,
          builder: (context, index) {
            final distance = (index - _selectedIndex).abs().toDouble().clamp(
              0.0,
              3.0,
            );
            final opacity = (1.0 - (distance * 0.25)).clamp(0.3, 1.0);
            final scale = (1.0 - (distance * 0.08));
            final isSelected = index == _selectedIndex;
            final label = widget.labelBuilder(index);

            return GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                _scrollController.animateToItem(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                );
              },
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: isSelected ? 24 : 18,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected
                        ? neonGreen
                        : (widget.isDark ? Colors.white54 : Colors.black38),
                  ),
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(scale: scale, child: Text(label)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
