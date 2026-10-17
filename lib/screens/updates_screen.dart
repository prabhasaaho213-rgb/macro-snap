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

/// "What's New" page — shows the installed version, recent release notes and a
/// button that jumps straight to the Play Store listing to check for or
/// install the newest build. Changelog entries are maintained here.
///
/// This used to be the fourth bottom-nav tab. It now lives behind Settings,
/// because it is read-once content that does not deserve permanent navigation
/// space. Settings puts a dot on its "What's New" row until the user has
/// opened this page for the newest release.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  /// The newest release listed below. Settings compares this with the version
  /// the user has already seen and puts a dot on the "What's New" row when the
  /// two differ — so a new release announces itself instead of waiting to be
  /// found.
  static const String latestVersion = '1.4.94';

  /// SharedPreferences key holding the latest version the user has seen.
  static const String seenVersionKey = 'updates_seen_version';

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  static const List<_UpdateEntry> _changelog = [
    _UpdateEntry(
      version: UpdatesScreen.latestVersion,
      date: 'Latest',
      isLatest: true,
      notes: [
        'Scans now open at the weight of the food in the photo, so calories and protein match the portion',
        'Brighter orange progress rings',
        'Habit actions are colour-coded: green completes, red undoes',
        'Guru offers a few openers when the chat is empty',
        'Polish: lighter Pro header, stronger Settings banner, calmer scan button',
      ],
    ),
    _UpdateEntry(
      version: '1.4.93',
      date: 'Earlier',
      notes: [
        'Pro now turns off when the server says it is over - cancelled subscriptions and expired referral rewards no longer show the Pro look',
        'Settings shows when your Pro window ends',
      ],
    ),
    _UpdateEntry(
      version: '1.4.92',
      date: 'Earlier',
      notes: ['Habit icons now have brighter accent tiles and borders'],
    ),
    _UpdateEntry(
      version: '1.4.91',
      date: 'Earlier',
      notes: [
        'Guru (Ask Guru) is now part of Pro \u2014 the chat button opens with your plan',
        'The AI meal plan is now part of Pro too \u2014 free users see the plans screen',
        'The Pro list now matches what Pro actually unlocks',
        'Photos the AI can\u2019t identify no longer use one of your free scans',
        'Fixed the scan counter showing the wrong number of scans left',
        'Sign-in email must now be verified before it unlocks Pro',
      ],
    ),
    _UpdateEntry(
      version: '1.4.90',
      date: 'Earlier',
      notes: [
        'Food-name background now fits the text instead of stretching full width',
        'Serving-gram controls removed — nutrition always calculates at 100 g',
        'Rate Us now always opens the Google Play Store',
        'Every change now saves to the cloud automatically — no backup step',
        'Meet Guru \u2014 your in-app nutrition assistant',
        'Long food names in Results wrap onto a second line instead of cutting off',
      ],
    ),
    _UpdateEntry(
      version: '1.4.85',
      date: 'Earlier',
      notes: [
        'Veg Plan — a full vegetarian day plan sized to your calorie target',
        'All Veg Suggestions — every veg food in the app, tap to log it',
        'Food Preference is now a Veg / Non-Veg toggle',
        'Faster home screen — fixed clipped action tiles and calorie ring',
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
        'Release notes — see what\u2019s new right in the app',
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
      // Version display is best-effort — never break the page over it.
    }
    // Opening this page counts as having seen the newest release notes.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UpdatesScreen.seenVersionKey,
        UpdatesScreen.latestVersion,
      );
    } catch (_) {
      // Best-effort - a failed write only means the dot appears once more.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? MacroSnapTheme.surfaceDark
          : MacroSnapTheme.surfaceLight,
      appBar: AppBar(
        title: Text(
          "What's New",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
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
                    // Must match the pill's accent: neonPill is a tinted
                    // background, so black text here would vanish on a dark
                    // theme.
                    color: entry.isLatest
                        ? MacroSnapTheme.greenText(context)
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
                    color: MacroSnapTheme.macroFiber,
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
