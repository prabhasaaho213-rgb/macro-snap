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
  static const String latestVersion = '1.5.11';

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
        'The calorie card now shows your streak flame where the calories-left figure used to sit',
        'Changing your details from Profile finally sticks — the editor saves when you leave it instead of dropping the edit',
        'PRO badges are for free accounts only: they disappear the moment you subscribe',
        'The reminder time is picked on smooth wheels that tick once per step, not a clock dial that buzzes as you drag',
        'Home and Habits cards share one gutter and one gap, so the BMI card is no longer tighter or wider than its neighbours',
      ],
    ),
    _UpdateEntry(
      version: '1.5.10',
      date: '2026-10-31',
      notes: [
        'Settings is down to the rows that change how the app works: meal-photo retention, price market, photo sync and Send Feedback are gone',
        'Profile no longer carries the quick-action tiles',
        'Changing weight or height in the BMI calculator now saves the moment you tap Save in the dialog',
        'Home drops the calorie trend card, the This Week strip and the scan-your-first-meal button',
        'The footer line under Settings is gone',
        'Bottom tabs sit in equal slots, so the selected pill no longer shifts the others',
      ],
    ),
    _UpdateEntry(
      version: '1.5.9',
      date: '2026-10-30',
      notes: [
        'Prices are quoted in the right currency — the India check reads your phone\'s timezone by name now, so a +5:30 clock outside India (Sri Lanka) is no longer shown rupees',
        'The orange-and-green M icon is on your home screen at last — the old green circle is gone',
        'Barcode scanning works on real products: anything the built-in list misses is looked up online, and when nothing has it you type the label values on a full form instead of a cramped popup that would not take input',
        'Home leads with your calorie ring; the meal streak card is gone',
        'Cloud backup no longer stops partway through a long history: meals sync in batches, and one unusually long food name can no longer break the rest',
        'The owner account never sees the subscribe popup',
      ],
    ),
    _UpdateEntry(
      version: '1.5.8',
      date: 'Earlier',
      notes: [
        'The Pro price now shows in your own currency — rupees, dollars, euros, dirhams and more',
        'Profile moved out of Settings and became its own tab, right after Habits',
        'Bottom navigation got a new look: the page you are on is a pill, the rest are round icons — Home, Cam, Habits, Profile',
        'Your scanned meal photo stays for 24 hours, so today\'s meals show the picture they were logged from',
        'Every Pro feature now carries a PRO badge, so it is obvious what comes with the plan',
        'The camera page has one pill for every way in — AI Camera, barcode and gallery — plus a flash toggle',
      ],
    ),
    _UpdateEntry(
      version: '1.5.7',
      date: 'Earlier',
      notes: [
        'Subscribe and Go Pro buttons now show the full price on every screen — long labels shrink to fit instead of being cut off',
      ],
    ),
    _UpdateEntry(
      version: '1.5.6',
      date: 'Earlier',
      notes: [
        'Every shared card now carries a scannable QR code — scan it straight to the Play Store',
        'Refer a Friend is back in Settings: share your code and you both get 30 days of Pro free',
        'After redeeming a code, the exact date Pro runs until is shown instead of a vague "activated"',
      ],
    ),
    _UpdateEntry(
      version: '1.5.5',
      date: 'Earlier',
      notes: [
        'BMI calculator is now part of Pro',
        'Badges got a fresh look — animated progress bar, glowing trophies and a bouncier unlock toast',
        'Guru gives short, to-the-point answers in bullets and remembers your recent chat',
        'Log out now starts onboarding from the welcome step again',
        'Longer ingredient names wrap instead of getting cut, and “Total Serving” always shows in full',
        'Habits celebration confetti no longer freezes the screen — you can keep tapping while it plays',
        'Ask for your name only once: the onboarding name sticks through login',
        'The Reset button is gone from the Habits header',
        'Already rated MacroSnap? We no longer ask again',
      ],
    ),
    _UpdateEntry(
      version: '1.5.3',
      date: 'Earlier',
      notes: [
        'Pricing is simpler: Pro is ₹49/month, and the first month is ₹0 — approve the small monthly autopay at checkout and your first charge is 30 days away',
        'The old 30-day free trial is gone for everyone — existing markers are cleared automatically and an old countdown no longer shows Pro',
        'Subscribed accounts cannot start a second subscription by mistake — the paywall says "already subscribed" instead of double-billing',
      ],
    ),
    _UpdateEntry(
      version: '1.5.2',
      date: 'Earlier',
      notes: [
        'MacroSnap is dark-only now — light mode is gone, along with the theme toggle in Settings',
        'Switching Vegetarian / Non-Veg now switches what your plan follows, without saving half-typed numbers',
        'Leftover recipe data is deleted — from the device at launch, and from your account when you delete it',
      ],
    ),
    _UpdateEntry(
      version: '1.5.1',
      date: 'Earlier',
      notes: [
        'Recipes and separate Veg Plan removed — veg food data now lives as the diet preference toggle in the Diet Plan; no more recipe screen or service',
      ],
    ),
    _UpdateEntry(
      version: '1.5.0',
      date: 'Earlier',
      notes: [
        'The health score understands simple food: water is no longer 1/5, milk is not junk, and lean chicken is not punished for having no fibre',
        'A scan that could not be identified shows no score at all, instead of claiming 5/5 Excellent for a dish with no data',
        'Opening the BMI calculator no longer earns First Weigh-In - the badge is for recording a weight, not for tapping a card, on this launch or the next',
        'The owner account picks up free Pro on the next launch instead of needing a sign-out',
        'Achievements you already earned by logging show up on a new phone, and they are cleared with the account when you delete it',
        'Two badges earned together are both celebrated instead of only the last one',
        'A failed scan can no longer cost you one of your free scans',
        'Payments: a subscription cannot be started twice, and Pro only confirms once it is actually saved',
      ],
    ),
    _UpdateEntry(
      version: '1.4.97',
      date: 'Earlier',
      notes: [
        'The scan result is a proper report card: a health score out of 5, the ingredients with their weights and scores, and your tastiness verdict',
        'Achievements: First Bite, Ten Plates, First Weigh-In, Week Warrior and Fortnight Flame - earned by logging, never by the number on the scale',
        'Share your week: a summary card with your average calories, the days you hit your protein goal and your streak',
        'A short animated logo introduces the launch while the app loads behind it',
        'Your details from onboarding are editable in Settings > Profile, along with your achievements',
      ],
    ),
    _UpdateEntry(
      version: '1.4.96',
      date: 'Earlier',
      notes: [
        'Launching is instant - the app draws its splash right away instead of sitting on a black screen',
        'The notification permission is now asked inside the app, not on top of a loading screen',
        'Startup work runs in parallel, so the first screen arrives sooner',
        'Subscriptions are paid inside the app - no more being sent to a browser, and Pro confirms with a celebration',
        'New BMI calculator on Home - pre-filled with your height and weight, with your BMR, TDEE and calorie target alongside',
        'Weight history is kept so Home can draw a trend line and show which way you are moving',
      ],
    ),
    _UpdateEntry(
      version: '1.4.95',
      date: 'Earlier',
      notes: [
        'No more black pause when switching tabs - Home, Scan and Habits stay loaded',
        'The streak flame is brighter, with a live glow',
        'Headlines are upright again (they no longer lean)',
        'Haptic feedback on tab switches and Settings rows',
        'One damaged saved item no longer wipes your meal history or habits',
      ],
    ),
    _UpdateEntry(
      version: '1.4.94',
      date: 'Earlier',
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
      notes: ['Release notes — see what\u2019s new right in the app'],
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
        'Rate Us now always opens the Google Play Store',
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
          // Only the few newest releases are shown — the full history is
          // noise that no one scrolls to the bottom of.
          for (final entry in _changelog.take(3)) _entryCard(context, entry),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF334155),
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
