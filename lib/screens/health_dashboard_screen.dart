import 'package:flutter/material.dart';
import 'dart:async';

import '../core/haptics.dart';
import '../core/theme.dart';
import '../services/health_service.dart';
import '../widgets/animations.dart';
import '../widgets/glass_card.dart';

/// The Health dashboard — steps and calories burned from Health Connect,
/// shown alongside the app's food-logging flow so a user can see intake and
/// activity in one place.
///
/// The screen has three states:
///   * disconnected — Health Connect is unavailable or not authorised; a CTA
///     offers to connect
///   * connected, no data — permissions granted but nothing read yet today
///   * connected with data — today's steps and calories displayed
///
/// Steps and calories are read fresh each time the screen is built (and again
/// when the user pulls to refresh). They are not stored locally by this screen
/// — the health platform is the source of truth.
class HealthDashboardScreen extends StatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  State<HealthDashboardScreen> createState() => _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends State<HealthDashboardScreen> {
  bool _initialized = false;
  bool _available = false;
  bool _hasReadPermission = false;
  int? _steps;
  double? _caloriesBurned;
  bool _loadFailed = false;

  bool get _connected => _hasReadPermission;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// One-time check: is Health Connect / HealthKit available on this device,
  /// and do we already have read permission?
  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() {
      _initialized = true;
    });

    final service = HealthService.instance;
    if (!service.isPlatformSupported) {
      setState(() {
        _available = false;
        _hasReadPermission = false;
      });
      return;
    }

    final ok = await service.isHealthAvailable;
    if (!mounted) return;
    setState(() {
      _available = ok;
      if (ok) {
        unawaited(_checkPermission());
      }
    });
  }

  Future<void> _checkPermission() async {
    final service = HealthService.instance;
    final has = await service.hasReadPermission;
    if (!mounted) return;
    setState(() {
      _hasReadPermission = has;
    });
    if (has) {
      unawaited(_loadToday());
    }
  }

  /// Connect / authorize: ask the user for read permission to steps and
  /// calories burned. On success, load today's data immediately.
  Future<void> _connect() async {
    unawaited(Haptics.light());
    final service = HealthService.instance;
    final granted = await service.requestReadPermissions();
    if (!mounted) return;
    setState(() {
      _hasReadPermission = granted;
      _loadFailed = false;
    });
    if (granted) {
      await _loadToday();
    }
  }

  /// Refresh today's steps and calories from the health platform.
  Future<void> _loadToday() async {
    final service = HealthService.instance;
    final steps = await service.todaySteps;
    final cals = await service.todayCaloriesBurned;
    if (!mounted) return;
    setState(() {
      _steps = steps;
      _caloriesBurned = cals;
      _loadFailed = false;
    });
  }

  Future<void> _refresh() async {
    if (!_connected) return;
    unawaited(Haptics.light());
    await _loadToday();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = const Text(
      'Health',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    );

    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        title: title,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_connected)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _initialized ? _refresh : null,
            ),
        ],
      ),
      body: _buildBody(context, isDark),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_available) {
      return _buildUnavailable(context, isDark);
    }

    if (!_connected) {
      return _buildConnectState(context, isDark);
    }

    return _buildDashboard(context, isDark);
  }

  /// Health Connect / HealthKit is not available on this device (too old, work
  /// profile, private space, etc.). Show a short explanation and hide the CTA.
  Widget _buildUnavailable(BuildContext context, bool isDark) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _buildIconCard(
              context,
              isDark,
              icon: Icons.fitness_center_rounded,
              iconColor: MacroSnapTheme.neonCyan,
              backgroundColor: MacroSnapTheme.neonCyan.withValues(alpha: 0.12),
              title: 'Health Connect unavailable',
              body: 'This phone or account does not support health data. '
                  'Try a different device to see your steps and calories here.',
            ),
            const SizedBox(height: 24),
            Text(
              'Steps and calories from your phone or watch appear here once '
              'you connect Health Connect.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: MacroSnapTheme.textTertiary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Health platform is available but the user has not granted read permission
  /// yet. Offer a one-tap connect flow.
  Widget _buildConnectState(BuildContext context, bool isDark) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            AnimatedEntrance(
              delayMs: 40,
              child: _buildIconCard(
                context,
                isDark,
                icon: Icons.fitness_center_rounded,
                iconColor: MacroSnapTheme.neonGreen,
                backgroundColor:
                    MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                title: 'Connect Health',
                body: 'Let MacroSnap read your steps and calories burned so '
                    'you can see activity alongside your food logs.',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.fitness_center_rounded, size: 20),
                label: const Text('Connect Health Connect'),
                style: FilledButton.styleFrom(
                  backgroundColor: MacroSnapTheme.neonGreen,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _connected ? null : () => _connect(),
              child: Text(
                'Allow read access to steps and calories',
                style: TextStyle(
                  fontSize: 13,
                  color: MacroSnapTheme.textSecondary(context),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Permissions granted and today's data is (or will be) shown.
  Widget _buildDashboard(BuildContext context, bool isDark) {
    final steps = _steps ?? 0;
    final cals = _caloriesBurned;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: MacroSnapTheme.neonGreen,
        backgroundColor: isDark
            ? MacroSnapTheme.cardDark
            : MacroSnapTheme.surfaceLight,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              AnimatedEntrance(
                delayMs: 30,
                child: _buildStatCard(
                  context,
                  isDark,
                  icon: Icons.directions_walk_rounded,
                  iconColor: MacroSnapTheme.neonGreen,
                  label: 'Steps today',
                  value: steps.toString(),
                  unit: 'steps',
                  color: MacroSnapTheme.neonGreen,
                ),
              ),
              const SizedBox(height: 14),
              AnimatedEntrance(
                delayMs: 90,
                child: _buildStatCard(
                  context,
                  isDark,
                  icon: Icons.local_fire_department_rounded,
                  iconColor: MacroSnapTheme.neonOrange,
                  label: 'Calories burned today',
                  value: cals == null ? '—' : cals.round().toString(),
                  unit: 'kcal',
                  color: MacroSnapTheme.neonOrange,
                ),
              ),
              if (_loadFailed) ...[
                const SizedBox(height: 14),
                Text(
                  'Could not read health data right now. Pull to retry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _buildNoteCard(
                      context,
                      isDark,
                      icon: Icons.arrow_back_rounded,
                      iconColor: MacroSnapTheme.textTertiary(context),
                      title: 'Food + activity',
                      body: 'Your meal logs and these steps appear together so '
                          'you can see the full picture of a day.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildNoteCard(
                      context,
                      isDark,
                      icon: Icons.data_usage_rounded,
                      iconColor: MacroSnapTheme.textTertiary(context),
                      title: 'One-time permission',
                      body: 'MacroSnap asks once to read steps and calories. '
                          'You can revoke access any time in Health Connect.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconCard(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required String title,
    required String body,
  }) {
    return GlassCard(
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: MacroSnapTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MacroSnapTheme.textTertiary(context),
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

  Widget _buildNoteCard(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: MacroSnapTheme.borderSubtle(context).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
    );
  }
}
