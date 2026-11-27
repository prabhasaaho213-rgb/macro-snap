# MacroSnap

A Flutter (Android) calorie-tracking app: photograph or search a meal, get its
nutrition, and keep a history, habits and streaks that survive a reinstall.

Sign-in is **Google only** — there is no guest or anonymous mode, because every
account needs a cloud backup and a subscription identity.

## What's in it

- **Scan** — photo → Gemini vision → per-dish macros, with editable grams and a
  manually entered barcode/weight fallback that needs no camera.
- **History** — one document per meal in Cloud Firestore (`meals/{mealId}`),
  mirrored on device so the app works offline. Failed writes queue locally and
  replay on the next launch/resume (`lib/services/pending_sync_queue.dart`).
  The cloud copy is a **backup**, not a live merge: meals added or deleted on
  one device reach the others, but an edit to an existing meal stays local.
- **Habits & water** — habit list, streaks and a daily water log, backed up as
  one `habitData/{uid}` document; reminders are re-armed after reboot.
- **Guru** — an in-app nutrition assistant whose context is built from the
  user's own logged day, sent to Gemini.
- **Pro** — Razorpay subscriptions with a ₹1 intro month; entitlements
  (`subscribed`, `pro_until_at`, `scanCount`) are server-written only.

## Layout

```
lib/
  core/        theme, haptics, shared formatting
  models/      MealRecord, DietProfile, habit models
  screens/     one file per screen (home, scan, habits, settings, …)
  services/    Firestore backup, auth, Gemini, Razorpay, notifications, crash reporting
  widgets/     reusable cards, sheets, animations
android/       Gradle config, manifest, signing (key.properties is NOT in git)
docs/          privacy policy + account deletion pages served by GitHub Pages
test/          unit + widget tests (`flutter test`)
integration_test/
firestore.rules  database security rules (deploy separately, see below)
```

## Running it

Toolchain: Flutter 3.47.2 (pinned in CI and `codemagic.yaml`), Java 17, Android
SDK 36, NDK 27.

```bash
flutter pub get
flutter run --release      # a device/emulator with Play Services (Google Sign-In)
```

`flutter run` on a debug build works too, but Google Sign-In needs a real
certificate SHA-1 registered in Firebase, so release builds are the normal
test path.

## Checks

```bash
flutter analyze            # must stay clean; CI fails the build otherwise
flutter test               # 400+ unit/widget tests
```

CI runs both before it builds anything: `.github/workflows/release-apk.yml` on a
`v*` tag, and `codemagic.yaml` for the same on Codemagic.

## Building a release

Signing comes from `android/key.properties` (git-ignored) plus
`android/upload-keystore.jks`. Its SHA-1 is registered in Firebase — changing
the keystore breaks Google Sign-In and makes the update un-installable over the
published app. CI restores both from secrets.

```bash
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release  # build/app/outputs/bundle/release/app-release.aab
```

Version lives in `pubspec.yaml` (`version: <name>+<code>`); bump both the name
and the code, and the `latestVersion` in `lib/screens/updates_screen.dart`
(a test fails if the two disagree).

## Backend

The app talks to a Firebase project plus a small HTTP backend
(`https://macro-snap-backend.vercel.app`, `GeminiService.serverUrl`) for things
Firebase cannot decide alone: scan limits, payments and account deletion. Every
request carries a Firebase ID token (`lib/services/auth_http.dart`); the
backend never trusts a uid from the body or URL.

## Firestore rules

`firestore.rules` is the real access control: users can only touch their own
documents, entitlement records are server-write-only, and payload sizes are
bounded. Deploy after any change:

```bash
firebase deploy --only firestore:rules   # project macrosnap-cfde3
```

## Documents

- [Privacy Policy](PRIVACY_POLICY.md) — also served at
  https://prabhasaaho213-rgb.github.io/macro-snap/
- [Account Deletion](ACCOUNT_DELETION.md) — also served at
  https://prabhasaaho213-rgb.github.io/macro-snap/delete-account.html
- [Handoff notes](HANDOFF.md) — architecture, decisions and the traps in this
  codebase; read it before changing sync, auth or notifications.
- [Signing](docs/SIGNING.md)
