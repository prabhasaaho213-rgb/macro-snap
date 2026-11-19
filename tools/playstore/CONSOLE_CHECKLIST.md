# What only you can do

Everything in this file needs a console login, a payment dashboard or a phone.
Code changes are done; these are the switches. Each item says what to click and
how to know it worked.

## 1. Ship the backend (10 min)

The webhook replay fix, the referral/payment rate limits and the failed-charge
grace period are committed on `fix/diet-plan-validation` and **not deployed**.

1. Merge that branch into whatever Vercel deploys (Project → Settings → Git →
   *Production Branch* tells you which).
2. Wait for the deployment, then open
   `https://macro-snap-backend.vercel.app/` — it must answer `OK`.
3. In Vercel → Deployments, confirm the new deployment's commit matches.

Why it matters: until this is live, a retried Razorpay webhook can re-activate a
cancelled subscription, and a single failed renewal switches Pro off for a
customer who is still being charged.

## 2. Fix the Data Safety form (10 min)

Play Console → *App content* → *Data safety*.

- **Remove Location.** The app has no location code and no location permission in
  the merged manifest. Declaring it is both wrong and the first thing a cautious
  user sees.
- Check the rest against the table in `tools/playstore/listing.md`: Name, Email,
  Health & fitness, Photos, Purchase history, App activity, Device IDs. Nothing
  else.
- Confirm "Data is encrypted in transit" and "Users can request data deletion".

Verification: the summary line on the listing no longer includes Location.

## 3. Paste the listing copy (10 min)

Play Console → *Grow* → *Store presence* → *Main store listing*. Copy the short
and full description from `tools/playstore/listing.md`.

Verification: the description states **3 free scans a day** and **₹49/month,
first month ₹1**.

## 4. Publish the Firestore rules (10 min) — security

Firebase Console → *Firestore Database* → *Rules*.

1. Paste the contents of `app/firestore.rules`.
2. *Rules Playground*: simulate `get` on `meals/<your meal id>` as your uid
   (allow) and as another uid (deny). Same for `userPreferences/<uid>`.
3. *Publish*.

Verification: the playground denies a cross-user read. Until this is published,
the client-side rules are whatever the last console paste left there.

## 5. App Check — register now, enforce later (15 min)

Firebase Console → *App Check* → Apps → your Android app → *Play Integrity*.

- The app already calls `FirebaseAppCheck.instance.activate(...)` on startup
  (release: Play Integrity, debug: debug provider). Nothing to code.
- **Do not enable enforcement yet.** Watch *App Check → Metrics* for a few days.
  Enforce Firestore/Auth only when verified traffic is ~100%, or installs that
  predate the release lose access.
- For debug builds, add the debug token printed in logcat under *App Check →
  Manage debug tokens*.

## 6. Restrict the Android API key (15 min)

Google Cloud Console → *APIs & Services* → *Credentials* → the Android key.

- Application restrictions → Android.
- Package: `com.macrosnap.macro_snap`.
- Add **two** SHA-1s: your upload key's **and** the Play App Signing certificate
  (Play Console → *Test and release* → *Setup* → *App signing*). Restricting to
  the upload key alone breaks the Play-installed app, because Play re-signs it.

Verification: install from Play (internal testing) and complete a Google sign-in
and one scan. If sign-in fails with `DEVELOPER_ERROR`, a SHA-1 is missing.

## 7. Use the build on a phone (half a day)

Install `releases/1.5.17/MacroSnap-1.5.17.apk` (or the AAB through internal
testing). Walk these and note anything odd:

- [ ] Onboarding → **Skip** → Home must not show invented targets
- [ ] Camera scan → adjust grams → save
- [ ] Gallery scan
- [ ] Barcode scan (packaged item) and typed barcode
- [ ] A habit with a reminder → force-stop the app → wait for the reminder
- [ ] Weekly share card → the image opens and shares
- [ ] Settings → *Delete account* on a throwaway account
- [ ] One real **₹1 checkout**, then cancel it in the Razorpay dashboard and
      refund it. Pro must stay on until the paid month ends.

That last one is the only way to see the new grace logic and the cancellation
window working.

## 8. Read the barcode packs (ongoing)

`tools/barcode_audit/BARCODE_CHECKLIST.md` is 54 rows with the stored values and
blank columns for the printed panel. Fill a row, fix `lib/services/barcode_db.dart`
or delete the entry, then rebuild. For a single barcode:

```
node tools/barcode_audit/check_off.js 8901063030037
```

Two entries are already corrected against official labels in 1.5.17 (Parle-G and
Maggi 2-Minute Masala). The rest are still unchecked.

## 9. Answer the review (5 min)

One written review, asking for better diet plans. Suggested public reply:

> Thanks for trying it — and sorry the plans felt thin. The photo scans are the
> free tier; the detailed meal planner is the Pro feature, which is why you may
> not have seen it. If you tell me which meals you want covered (South Indian
> breakfasts? high-protein veg?), I'll make sure the planner gets those right.

## 10. Things not to do

- **Don't enable App Check enforcement** before the metrics look clean.
- **Don't ask friends for 5-star reviews.** Play treats it as fake engagement.
- **Don't upload 1.5.17 to Play without the AAB** (`releases/1.5.17/*.aab`) — the
  APK is for sideloading.
- **Don't skip the version bump** on the next release: `pubspec.yaml`,
  `lib/core/app_version.dart` and the changelog entry in
  `lib/screens/updates_screen.dart` are checked against each other by
  `test/release_version_test.dart`.
