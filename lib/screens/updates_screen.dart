import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_version.dart';
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
  /// `test/release_version_test.dart` fails when this drifts from the
  /// version in `pubspec.yaml`, so a release bump cannot forget it.
  static const String latestVersion = kAppVersion;

  /// SharedPreferences key holding the latest version the user has seen.
  static const String seenVersionKey = 'updates_seen_version';

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  static const List<_UpdateEntry> _changelog = [
    _UpdateEntry(
      version: UpdatesScreen.latestVersion,
      date: '2026-11-27',
      isLatest: true,
      notes: [
        'Your meal history is written safely now: a crash or a full disk can no longer leave you with an empty history',
        'Restoring after a reinstall brings back your newest meals first instead of an arbitrary slice of older ones',
        'A meal logged on a bad connection can no longer fall out of the upload retry queue',
      ],
    ),
    _UpdateEntry(
      version: '1.5.29',
      date: '2026-11-27',
      notes: [
        'Your avatar now survives logging out and back in, and it is saved to your account instead of only this phone',
        'Without Health Connect, calories burned are estimated from the steps your phone counted and the weight on your profile',
        'With Health Connect connected, steps AND calories both come from it — the phone sensor is never added on top',
        'Steps and calories start fresh at midnight instead of showing yesterday\'s numbers first thing',
        'The welcome screen is a proper card with the app icon, and setup shows "Step 3 of 9" with an animated progress bar',
        'The BMI and Macronutrients cards on Home no longer overflow at large system text',
      ],
    ),
    _UpdateEntry(
      version: '1.5.28',
      date: '2026-11-27',
      notes: [
        'Your picture shows on the Settings account card now, instead of the first letter of your name',
        'The avatar picker fills the sheet evenly — four columns, no empty strip on one side',
        'Six avatars were re-cut, so no illustration has a pale border along one edge',
      ],
    ),
    _UpdateEntry(
      version: '1.5.27',
      date: '2026-11-27',
      notes: [
        'Pick a cartoon avatar on your profile — the same face now shows on the Rank card, the top-100 board and your friends league',
        'Habit icons are drawn in full colour again instead of washed-out outlines',
        'The bottom navigation is visible on phones in light mode, and so are the system buttons below it',
        'A league invite opens MacroSnap straight away instead of the browser and then the Play Store',
        'Changing your name or picture updates just that, without re-scoring your whole week',
        'The Recent Foods card no longer overlaps its own text on a narrow screen',
        'The analysis page counts the steps you actually have and shows your carb target, with a colour per section',
      ],
    ),
    _UpdateEntry(
      version: '1.5.26',
      date: '2026-11-26',
      notes: [
        'League invite links work again — a shared invite opens the league instead of a missing page',
        'Rate Us opens Google Play every time instead of sometimes doing nothing',
        'The Macronutrients card lines each macro\'s grams up with the card edge',
        'A logged meal can be deleted from its own detail page, not only from the list',
        'Going back from Settings and Profile animates the whole way out instead of stopping halfway',
        'Profile no longer flickers or re-loads its details every time it opens',
        'Steps you had already walked come back after reinstalling the app',
        'Signing in on a fresh install no longer plays the first-log or goal celebration on its own',
      ],
    ),
    _UpdateEntry(
      version: '1.5.25',
      date: '2026-11-25',
      notes: [
        'Friends League: start a league, share an invite link, and see everyone\'s week on one board',
        'Invite links open straight to the league — including for someone who has not installed the app yet',
        'The photo scan sweeps like a viewfinder now: one smooth pass, a gently drifting photo, and dish names that land one by one',
        'The barcode scanner uses the same motion, with a green catch the moment a code is read',
        'Streak, Pro and scan-limit values no longer flash a placeholder before the real number appears',
      ],
    ),
    _UpdateEntry(
      version: '1.5.23',
      date: '2026-11-24',
      notes: [
        'Deleting your account now also cancels the Razorpay subscription, removes every meal and cloud photo, and deletes the sign-in itself',
        'If a deletion step fails, the app says so and lets you retry instead of claiming everything was removed',
        'Sync Meal Photos actually uploads and restores photos now — the backup route the app called did not exist on the server',
        'Photo backup still requires Pro, and the check happens on the server, not just in the app',
      ],
    ),
    _UpdateEntry(
      version: '1.5.21',
      date: '2026-11-22',
      notes: [
        'The Rank page shows the top 5 and a View more button, which opens the full top-100 board on its own page',
        'Opening a page no longer blends two screens: Profile, Subscription and every other page slide in fully opaque instead of cross-fading',
        'Launching the app shows one logo, not the launcher icon fading out over the splash',
        'Joining the leaderboard: Country, State and District labels no longer print on top of their values',
      ],
    ),
    _UpdateEntry(
      version: '1.5.20',
      date: '2026-11-22',
      notes: [
        'The leaderboard is the first card on the Fitness Points page now, on the same violet gradient as the rest of the app',
        'Joining is a search: type a couple of letters to pick your country, state or district instead of scrolling a long menu',
        'Every state\'s districts are listed by name, so "Pune", "pune" and "Poona" no longer split into three half-empty boards — and Other still lets you type a place the list does not carry',
        'Quick Actions keeps all four tiles on one row on narrow phones, where Rank used to drop onto a line of its own',
        'Changing district still moves your row, and leaving still removes you from all three boards',
      ],
    ),
    _UpdateEntry(
      version: '1.5.19',
      date: '2026-11-22',
      notes: [
        'New: a live leaderboard on the Fitness Points page — District, State and India boards, still opened from Home\'s Quick Actions',
        'Pick your state and district to join; only your name and weekly points are shared, never your meals, health data or contact details',
        'The board updates by itself when anyone\'s score changes, with no refresh needed',
        'You can look at your district before joining, and your points stay private on your phone until you do',
        'Changing district moves your row to the new board, and leaving removes it',
      ],
    ),
    _UpdateEntry(
      version: '1.5.18',
      date: '2026-11-22',
      notes: [
        'Health stays connected between launches: steps and calories are read separately, so a phone that never grants one of them no longer blanks the whole dashboard',
        'Steps and burned calories refresh every 5 seconds and catch up the moment you come back to the app',
        'Set your daily step target from the Health tab in 5,000-step steps, and keep a streak for every day you hit it',
        'Logged meals keep their photo: the picture is saved as the result opens, so the phone clearing its cache no longer leaves a bare icon',
        'The serving-size keypad works — clear and backspace actually clear, the first digit replaces the old value, and an invalid weight says so',
        'Profile opens from Settings as its own page, without the Settings screen showing through it',
        'New: Fitness Points, opened from Home\'s Quick Actions — points for meals, habits, water, weigh-ins, your calorie goal and your step goal, with daily caps so nothing pays twice',
      ],
    ),
    _UpdateEntry(
      version: '1.5.17',
      date: '2026-11-21',
      notes: [
        'Skipping setup no longer makes up numbers for you — until you enter your height, weight and age, the app does not pretend to know your targets',
        'Your calorie streak belongs to your account now: a second account on the same phone no longer inherits it, and a reinstall restores it instead of starting from zero',
        'Pro is tied to the account that paid for it, so signing in as someone else on a shared phone no longer leaves them with your subscription',
        'The BMI band always matches the score on screen, and weight loss is blocked only below the healthy range',
        'Switching between cm and inches now saves the height you can actually see, and the age dial saves what it shows',
        'Your water goal is editable instead of fixed at 8 glasses, and habit streaks count calendar days across daylight-saving changes',
        'Barcodes reject impossible nutrition values and fill in missing calories from the macros, and a scan that times out says so instead of blaming the connection',
        'The app no longer asks for microphone or NFC access, which it never used',
        'A rating is suggested once, through Google Play\'s own review card, after you have saved three meals — and you choose the stars, not us',
        'The Pro screen lists only what Pro actually unlocks, so nothing you already get for free is sold back to you',
      ],
    ),
    _UpdateEntry(
      version: '1.5.16',
      date: '2026-11-10',
      notes: [
        'Meals you log offline upload by themselves once the connection is back, and a meal deleted on another phone no longer comes back here',
        'Long-press a meal to edit its name, calories, macros or time instead of deleting it and scanning again',
        'Reminders may arrive a few minutes late, but updates are no longer held up by Android exact-alarm rules',
        'The intro animation plays once after install instead of every time you open the app',
        'The rating prompt waits until you have logged five meals and opened the app three times',
        'A failed scan says what to try next instead of showing a raw error',
        'Two accounts with similar emails on one phone no longer see each other\'s history',
      ],
    ),
    _UpdateEntry(
      version: '1.5.15',
      date: '2026-11-09',
      notes: [
        'Habit reminders fire at the exact minute you chose; if Android refuses exact alarms, the reminder still arrives a little late instead of never',
        'Pro now shows the date it ends when the grant has one - a referral month or the days left after a cancel read as a date, not a plain Subscribed tick',
        'Logging in from the paywall or answering the notification prompt no longer crashes if you leave the screen while it works',
        'Running out of free scans no longer offers TRY AGAIN, which could never succeed - manual entry carries you until tomorrow',
        'Connection errors say the server could not be reached instead of telling you to check your WiFi and start the backend',
        'Barcode calories with a decimal are rounded instead of logged as zero, and editing one macro now scales every dish on the plate',
        'A corrupt saved meal no longer hides the rest of your history, the heatmap stops at your first month, and Refer a Friend applies a code once',
      ],
    ),
    _UpdateEntry(
      version: '1.5.13',
      date: '2026-11-08',
      notes: [
        'Deleting an account now leaves every other account on the same phone untouched — habits, water, weight history and badges included',
        'Choosing pounds or inches in onboarding now saves the weight and height you picked instead of converting them twice',
        'Diet Plan: the clear button empties the form and leaves your saved plan alone, and a deficit is never saved below a healthy BMI',
        'Habits: Delete and Reset Streak ask before wiping your history, and an account that lapsed from Pro keeps syncing',
        'Barcode scanning still works without a camera — type the label numbers or the grams you actually ate',
        'Recent Foods tags show the right empty message, and the paywall no longer lists meal history the app does not have',
      ],
    ),
    _UpdateEntry(
      version: '1.5.12',
      date: '2026-11-01',
      notes: [
        'Home and Habits finally sit on one grid: the same 24dp side margin, the same 20dp card padding, 16sp card titles and 12dp between cards',
        'The streak flame appears on the calorie card only once you have hit your calorie goal — before that the card tells you what is left',
        'Refer a Friend shows your code the instant you open it instead of spinning while it asks the server',
      ],
    ),
    _UpdateEntry(
      version: '1.5.11',
      date: '2026-10-31',
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
