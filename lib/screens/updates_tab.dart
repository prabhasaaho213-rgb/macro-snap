import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../services/rate_us_service.dart';

/// One release entry in the in-app changelog.
class _UpdateEntry {
  const _UpdateEntry({
    required this.version,
    required this.date,
    required this.notes,
    this.isLatest = false,
  });

  final String version;
  final String date;
  final List<String> notes;
  final bool isLatest;
}

/// "Updates" tab — shows the installed version, recent release notes and a
/// button that jumps straight to the Play Store listing to check for or
/// install the newest build. Changelog entries are maintained here.
class UpdatesTab extends StatefulWidget {
  const UpdatesTab({super.key});

  /// The newest release listed below. MainShell compares this with the version
  /// the user has already opened and puts a dot on the Updates tab when the
  /// two differ — so a new release announces itself instead of waiting to be
  /// found behind a tab.
  static const String latestVersion = '1.4.85';

  /// SharedPreferences key holding the latest version the user has seen.
  static const String seenVersionKey = 'updates_seen_version';

  @override
  State<UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<UpdatesTab> {
  static const List<_UpdateEntry> _changelog = [
    _UpdateEntry(
      version: UpdatesTab.latestVersion,
      date: 'Latest',
      isLatest: true,
      notes: [
        'Veg Plan — a full vegetarian day plan sized to your calorie target',
        'All Veg Suggestions — every veg food in the app, tap to log it',
      ],
    ),
    _UpdateEntry(
      version: '1.4.84',
      date: 'Earlier',
      notes: [
        'Non-veg diet plan — pick Vegetarian or Non-Vegetarian in Diet Plan',
        'Rating button right after your first login, straight to the Play Store',
        'Keyboard closes the moment you leave the name step',
      ],
    ),
    _UpdateEntry(
      version: '1.4.83',
      date: 'Earlier',
      notes: [
        'New Updates tab — see what\u2019s new right in the app',
      ],
    ),
    _UpdateEntry(
      version: '1.4.5',
      date: 'Earlier',
      notes: [
        'Habit streaks, consistency map and smart reminders',
        'Cloud backup for meals and habits',
      ],
    ),
    _UpdateEntry(
      version: '1.4.0',
      date: 'Earlier',
      notes: [
        'Faster AI food scans with Google Gemini',
        'Custom recipes and barcode lookup',
      ],
    ),
  ];

  String _installedVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _installedVersion = info.version);
    } catch (_) {
      // Version display is best-effort — never break the tab over it.
    }
    // Opening this tab counts as having seen the newest release notes.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UpdatesTab.seenVersionKey,
        UpdatesTab.latestVersion,
      );
    } catch (_) {
      // Best-effort - a failed write only means the dot appears once more.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MacroSnapTheme.neonGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.new_releases_rounded,
                  color: MacroSnapTheme.neonGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Updates',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Check for updates card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: MacroSnapTheme.habitlyHeroCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You\u2019re on version $_installedVersion',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'New updates bring faster scans, new features and fixes. '
                  'Check the Play Store for the newest build.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: MacroSnapTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => RateUsService.openPlayStore(),
                    icon: const Icon(Icons.system_update_alt_rounded, size: 20),
                    label: const Text('Check for updates'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Release notes
          Text(
            'What\u2019s new',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in _changelog) _entryCard(context, entry),
        ],
      ),
    );
  }

  Widget _entryCard(BuildContext context, _UpdateEntry entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: MacroSnapTheme.habitlyCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: entry.isLatest
                    ? MacroSnapTheme.neonPill(MacroSnapTheme.neonGreen)
                    : BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(24),
                      ),
                child: Text(
                  'v${entry.version}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: entry.isLatest
                        ? Colors.black
                        : MacroSnapTheme.textSecondary(context),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                entry.date,
                style: TextStyle(
                  fontSize: 12,
                  color: MacroSnapTheme.textTertiary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final note in entry.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 15,
                    color: MacroSnapTheme.neonGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
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