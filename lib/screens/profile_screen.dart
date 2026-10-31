import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/haptics.dart';
import '../core/theme.dart';
import '../models/bmi.dart';
import '../models/diet_profile.dart';
import '../services/meal_sync_service.dart';
import '../services/subscription_service.dart';
import '../widgets/animations.dart';
import '../widgets/badge_board.dart';
import '../widgets/pro_badge.dart';
import 'bmi_screen.dart';
import 'diet_plan_screen.dart';
import 'subscription_screen.dart';

/// The one place that answers "what does the app know about me?" — name,
/// contact, body metrics, plan and BMI together, with a way to change each.
///
/// It deliberately reads the same stores the rest of the app does
/// ([DietPlanService], `SubscriptionService`, the `name`/`email`/`phone`
/// prefs) instead of holding its own copy, so a weight edited here and a
/// weight edited in the BMI calculator can never disagree.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = 'User';
  String _email = '';
  String _phone = '';
  bool _subscribed = false;
  bool _isAdmin = false;
  bool _loading = true;

  DietProfile? get _profile => DietPlanService.instance.profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Paints the identity first (prefs are instant) and lets the body metrics
  /// and plan fill in after. A brand-new account with no local profile file
  /// waits on a cloud fetch inside [DietPlanService.load]; holding the whole
  /// screen behind that would leave the user on a spinner for it.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name = prefs.getString('name') ?? 'User';
      _email = prefs.getString('email') ?? '';
      _phone = prefs.getString('phone') ?? '';
      _loading = false;
    });

    await DietPlanService.instance.load();
    await SubscriptionService.instance.load();
    final isAdmin = await SubscriptionService.instance.isAdmin();
    if (!mounted) return;
    setState(() {
      _subscribed = SubscriptionService.instance.isSubscribed;
      _isAdmin = isAdmin;
    });
  }

  bool get _isGuest => _phone.isEmpty || _phone.startsWith('guest_');

  String get _planLabel =>
      _isAdmin ? 'Lifetime Pro' : (_subscribed ? 'Pro Member' : 'Free User');

  /// Where the plan badge and the subtitle get their tone from.
  Color get _planColour => _isAdmin || _subscribed
      ? MacroSnapTheme.neonGreen
      : MacroSnapTheme.neonCyan;

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? MacroSnapTheme.cardDark
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 15,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Your name (max 15 chars)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty || newName == _name) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', newName);
    userNameNotifier.value = newName;
    if (!mounted) return;
    setState(() => _name = newName);
    // Same auto-sync the Settings name editor does.
    MealSyncService.syncPreferences({'name': newName});
  }

  /// Opens the diet profile editor and repaints with whatever came back — a
  /// new weight here must move the BMI on this screen too.
  Future<void> _editDetails() async {
    await Navigator.push(context, habitFlowRoute(const DietPlanScreen()));
    await DietPlanService.instance.load();
    if (mounted) setState(() {});
  }

  Future<void> _openSubscription() async {
    await Navigator.push(context, habitFlowRoute(const SubscriptionScreen()));
    await SubscriptionService.instance.load();
    final isAdmin = await SubscriptionService.instance.isAdmin();
    if (!mounted) return;
    setState(() {
      _subscribed = SubscriptionService.instance.isSubscribed;
      _isAdmin = isAdmin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? MacroSnapTheme.surfaceDark
        : MacroSnapTheme.surfaceLight;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  // Profile is its own tab now, so this screen usually has
                  // nothing to pop; the arrow only appears when it was pushed
                  // from somewhere (and keeps the header aligned either way).
                  if (Navigator.of(context).canPop())
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    const SizedBox(width: 16),
                  Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      children: [
                        AnimatedEntrance(
                          delayMs: 0,
                          child: _buildIdentityCard(context, isDark),
                        ),
                        const SizedBox(height: 16),
                        AnimatedEntrance(
                          delayMs: 90,
                          child: _buildDetailsCard(context, isDark),
                        ),
                        const SizedBox(height: 16),
                        AnimatedEntrance(
                          delayMs: 130,
                          child: const BadgeBoard(),
                        ),
                        const SizedBox(height: 16),
                        AnimatedEntrance(
                          delayMs: 150,
                          child: _buildBmiCard(context, isDark),
                        ),
                        const SizedBox(height: 16),
                        AnimatedEntrance(
                          delayMs: 210,
                          child: _buildAccountCard(context, isDark),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Your details stay on this phone unless you sign in.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: MacroSnapTheme.textTertiary(context),
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

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: child,
    );
  }

  Widget _buildIdentityCard(BuildContext context, bool isDark) {
    final profile = _profile;
    return _card(
      context,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: MacroSnapTheme.accentGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  profile?.avatar ??
                      (_name.isNotEmpty ? _name[0].toUpperCase() : 'U'),
                  style: TextStyle(
                    fontSize: profile == null ? 26 : 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name.isNotEmpty ? _name : 'User',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _email.isNotEmpty
                          ? _email
                          : (_isGuest ? 'Guest account' : _phone),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: MacroSnapTheme.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _planColour.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _planLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _planColour,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Haptics.tap();
                _editName();
              },
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit name'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark
                    ? Colors.white
                    : const Color(0xFF1A1A1A),
                side: BorderSide(color: MacroSnapTheme.borderSubtle(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
        color: isDark ? Colors.white70 : const Color(0xFF4A4A4A),
      ),
    );
  }

  Widget _buildDetailsCard(BuildContext context, bool isDark) {
    final profile = _profile;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'YOUR DETAILS', isDark),
          const SizedBox(height: 6),
          if (profile == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No height, weight or goal saved yet. Add them once and calorie '
                'targets, BMI and the meal plan all use them.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
            )
          else ...[
            _detailRow(
              context,
              'Height',
              BmiCalculator.formatHeight(profile.heightCm),
            ),
            _detailRow(
              context,
              'Weight',
              '${profile.weightKg.toStringAsFixed(profile.weightKg % 1 == 0 ? 0 : 1)} kg',
            ),
            _detailRow(context, 'Age', '${profile.age}'),
            _detailRow(
              context,
              'Gender',
              profile.gender == Gender.male ? 'Male' : 'Female',
            ),
            _detailRow(
              context,
              'Activity',
              DietPlanService.activityLabel(profile.activity),
            ),
            _detailRow(
              context,
              'Goal',
              DietPlanService.goalLabel(profile.goal),
            ),
            _detailRow(
              context,
              'Diet',
              DietPlanService.dietLabel(profile.diet),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Haptics.tap();
                _editDetails();
              },
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                profile == null ? 'Add your details' : 'Edit details',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark
                    ? Colors.white
                    : const Color(0xFF1A1A1A),
                side: BorderSide(color: MacroSnapTheme.borderSubtle(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: MacroSnapTheme.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBmiCard(BuildContext context, bool isDark) {
    final profile = _profile;
    final bmi = profile == null
        ? null
        : BmiCalculator.value(
            weightKg: profile.weightKg,
            heightCm: profile.heightCm,
          );
    final shownBmi = bmi == null ? null : BmiCalculator.displayValue(bmi);
    final category = shownBmi == null
        ? null
        : BmiCalculator.categoryFor(shownBmi);
    final accent = category?.color ?? MacroSnapTheme.neonCyan;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        Haptics.tap();
        // BMI is Pro: free users land on the paywall instead of the
        // calculator — same rule as the AI meal plan. unlocksPro() also
        // admits the admin's lifetime grant, so the owner never sees the
        // paywall here.
        if (!await SubscriptionService.instance.unlocksPro()) {
          if (!context.mounted) return;
          await Navigator.push(
            context,
            habitFlowRoute(const SubscriptionScreen()),
          );
          return;
        }
        if (!context.mounted) return;
        await Navigator.push(context, habitFlowRoute(const BmiScreen()));
        await DietPlanService.instance.load();
        if (mounted) setState(() {});
      },
      child: _card(
        context,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.speed_rounded, size: 21, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'BMI',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      // ProBadge audit: Pro marks must all be ONE shared chip,
                      // not a screen-invented orange variant.
                      if (!_subscribed)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          child: const ProBadge(),
                        ),
                    ],
                  ),
                  Text(
                    category?.label ?? 'Add height & weight',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: category == null
                          ? MacroSnapTheme.textSecondary(context)
                          : accent,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              shownBmi == null ? '—' : shownBmi.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
                color: accent,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: MacroSnapTheme.textTertiary(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context, bool isDark) {
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'ACCOUNT', isDark),
          const SizedBox(height: 6),
          _detailRow(
            context,
            'Phone',
            _phone.isEmpty ? '—' : (_isGuest ? 'Guest (not linked)' : _phone),
          ),
          _detailRow(
            context,
            'Sign-in',
            _email.isNotEmpty ? 'Google' : (_isGuest ? 'Guest' : 'Phone'),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Haptics.tap();
              _openSubscription();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: 18,
                    color: _planColour,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isAdmin || _subscribed
                          ? 'Manage subscription'
                          : 'Upgrade to Pro',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
