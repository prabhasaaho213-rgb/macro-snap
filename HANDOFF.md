# MacroSnap — project handoff

Last updated: 30 Oct 2026 · version `1.5.9+110`

This file used to contain machine-specific paths, a personal email address and
the filename of a service-account key. All of that has been removed: nothing
here identifies a person, a laptop or a credential.

## Stack

- Flutter (Dart 3) app, Android-first; iOS/macOS/Linux folders are present but
  Android is the shipping target.
- Firebase Auth (Google + phone) and Cloud Firestore for data; Razorpay for the
  ₹49/month Pro subscription.
- A separate Node backend (own repository) owns payments, trials and the
  authoritative scan allowance.

## Layout

```
lib/
  core/        theme, navigation, haptics, shared limits
  models/      MealRecord, Habit, DietProfile, BMI
  screens/     Home, Scan, Result, Habits, BMI, Profile, Settings, Subscription…
  services/    stores (meal/habit/weight/recent), Gemini, Razorpay,
               SubscriptionService, ScanGate, BadgeService, ShareService,
               notification + reminder registry
  widgets/     animation primitives, cards, gauge, charts, splash, badge board
test/          widget + unit tests (run all of them before a release)
android/       Gradle config, manifest, signing (key.properties + keystore)
firestore.rules  data-access rules; deploy with `firebase deploy --only firestore:rules`
```

### The three big screens are split by feature

`home_screen.dart`, `result_screen.dart` and `habits_tab.dart` used to be
1,600–2,000-line files. Each is now a thin screen plus `part` files, grouped by
what the widgets are for:

```
home_screen.dart (360)   + home_screen_header / _calories / _week / _meals
result_screen.dart (381) + result_screen_states / _results / _dish / _dialogs
habits_tab.dart (451)    + habits_tab_cards / _mission / _sheets
```

The parts stay in the same library (they are `part of` the screen), so the
builders keep access to the screen's private state without threading a dozen
parameters through. `_rebuild()` exists only because `setState` is `@protected`
and an extension is not a `State` subclass — it is not a second state machine.

Truly self-contained pieces were lifted out as real widgets in `lib/widgets/`:
`MacroBar`, `NutrientRow`, `SwipeActionBackground`. They rebuild independently
of the screen, and `SwipeActionBackground` has its own shape test.

When adding UI to one of these screens, put it in the part file that matches its
feature; a new 400-line screen method is how these files got to 2,000 lines.

## Build and release

```bash
flutter pub get
flutter analyze          # must be clean
flutter test             # must be green
flutter build appbundle --release
flutter build apk --release
```

Release signing uses `android/key.properties` + `android/upload-keystore.jks`.
Both are deliberately kept out of source archives and out of git. The keystore
must be the **same** one registered in Firebase (Google Sign-In) and in Play
Console — a new key breaks sign-in and in-place updates.

Release checklist: analyze, tests, `aapt dump badging` for versionCode/name,
`apksigner verify --print-certs` to confirm the certificate matches the
previous release, then a real payment on a release build.

## Repository and folder names

- Local folder: `MACROSNAP/app` — version-less on purpose. It was
  `macro-snap-source-1.4.5`, which stopped matching the app at 1.4.96.
- GitHub: `prabhasaaho213-rgb/macro-snap`, renamed from
  `macro-snap-source-1.4.5`. Raw/API links to the old name still redirect.
- `prabhasaaho213-rgb/macro-snap-source-1.4.5` is deliberately kept as a tiny
  **redirect-only** repository. Builds already on phones open their Privacy
  Policy from that Pages address, which does not redirect on its own; the repo
  serves a meta-refresh to the new site. Do not delete it while 1.4.x builds
  are in the wild.
- Pages site: `https://prabhasaaho213-rgb.github.io/macro-snap/`, published from
  `docs/` by `.github/workflows/pages.yml`. The workflow used to upload
  `macro-snap-source-1.4.5/docs`, a path that never existed in the repo.
- Note: `prabhasaaho213-rgb/macro-snap-source` is an unrelated stale v1.4.5
  dump (last push July). It is not this project.

## Environment / credentials

- `android/app/google-services.json` — Firebase project config; required.
- Keystore + `key.properties` — machine-only, never committed.
- No API keys live in the app: scans and payments go through the backend, and
  the client authenticates with a Firebase ID token.
- CI (`.github/workflows`, `codemagic.yaml`) expects the signing material as
  secrets, not files in the repo.

## Crash reporting

Release builds report to **Firebase Crashlytics** (`lib/services/crash_reporting.dart`).
Collection starts after `Firebase.initializeApp()` and is release-only: debug
and profile builds stay local so the dashboard is not polluted. Uncaught
framework/platform/zone errors are recorded as fatal; caught errors go through
`logError('<Class.method>', e, st)` as non-fatal, which is why the old generic
`debugPrint("Error: $e")` calls no longer exist. Reporting is best-effort and
never throws — a failure to report can never break startup.

## Owner / admin access

The owner's free Pro and the admin exemptions are a Firebase **custom claim**
(`admin: true`), never an email address. The app reads the claim from its ID
token (`SubscriptionService.isAdmin`), `firestore.rules` checks
`request.auth.token.admin == true`, and the backend does the same in
`isAdminUser()`.

The claim is minted by the backend at boot from `ADMIN_EMAIL` (comma-separated
if more than one) using the Admin SDK — that env var is the only place the
address lives. Until the claim has been set once, the owner has no admin
privileges: run the backend with `ADMIN_EMAIL` set, or set the claim manually.
The client refreshes its ID token on sign-in, so a newly granted claim takes
effect at the next sign-in/restart.

## Release build gotcha

`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` is
repo-ignored and regenerated by the tool. A stale copy left by `flutter test`
registers the dev-only `integration_test` plugin, and the next
`flutter build apk --release` then dies in `compileReleaseJavaWithJavac` with
`package dev.flutter.plugins.integration_test does not exist`. Delete the file
and rebuild; the build writes a release-clean one (no dev-only plugins).

## Known gaps

- A real payment has not been tested on a release build. R8 keep rules for
  Razorpay exist, but only a paid checkout on a real phone proves them.
- Reminders use inexact alarms, so they can arrive late while the phone is in
  battery saver.
- `firestore.rules` must be deployed; editing the file alone changes nothing.
