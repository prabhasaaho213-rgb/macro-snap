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

- **Delete the Location category** — both *Approximate* and *Precise* row. There
  is no location permission in the merged manifest, no location plugin in
  `pubspec.yaml`, and no location call in `lib/`. The only thing that looked
  location-adjacent is `lib/services/currency_service.dart`, which reads the
  device **timezone and locale** to label prices in the user's currency — not
  location data, and nothing about it is transmitted.
- Check the rest against the table in `tools/playstore/listing.md`: Name, Email,
  Health & fitness, Photos, Purchase history, App activity, Device IDs. Nothing
  else. Microphone, Contacts, SMS, Calendar and Files are all *No*.
- Confirm "Data is encrypted in transit" and "Users can request data deletion".

Verification: the *Data safety* summary on the store listing lists six
categories and Location is not one of them. Over-declaring is not the safe
direction — it makes the app look more invasive than it is and it is the first
thing a cautious user reads.

## 3. Paste the listing copy (10 min)

Play Console → *Grow* → *Store presence* → *Main store listing*. Copy the short
and full description from `tools/playstore/listing.md` — replace the text, do
not edit around the old one, because the live copy still sells Pro benefits the
app does not gate.

**3a. The Pro lines to delete.** The live description names *Complete Meal
History* and *Cloud Backup* under Pro. Neither exists as a paywalled feature:
`/meals/sync` and `/habits/sync` accept any signed-in user, and no screen lists
past meals by date. The app removed both from its own paywall in 1.5.17 for the
same reason, and the replacement copy lists only the three things the server
refuses with `403 pro_required` or `ScanGate` enforces: unlimited scans, the AI
meal plan, and Guru.

**3b. Pricing must be on the page.** Free = 3 photo scans a day (barcode and
manual entry unlimited); Pro = ₹49/month with the first month at ₹1. Both are in
the description's PRICING block. A user who discovers the scan limit *after*
installing rates that discovery, not the app.

**3c. `TOMBSTONE_SECRET` must exist in Vercel production** (Project → Settings →
Environment Variables), or the function refuses to boot — by design, since a
constant fallback in the source would let anyone hash a guessed email and test
the tombstone table. Generate once with `openssl rand -hex 32` and never change
it: HMAC is one-way, so re-keying makes every account deleted before the change
eligible for the ₹1 month again.

**3d. Three fields outside the description.** They are easy to miss because the
description looks finished without them:

| Field | Where | Value |
|---|---|---|
| Privacy policy | *Main store listing* → Privacy policy | `https://prabhasaaho213-rgb.github.io/macro-snap/` |
| Subscription benefit | *Monetise* → *Products* → *Subscriptions* → plan → Benefit | the three Pro bullets |
| Base plan price | *Monetise* → *Subscriptions* → base plan | ₹49/month + ₹1 intro on the same base plan |

On the privacy URL: the console currently points at
`.../macro-snap-source-1.4.5/`, an old repo name kept alive by a redirect. It
resolves today, which is exactly why it survives reviews — and why it is one
rename away from taking the listing out of compliance. The correct address is
the one the app opens from Settings and the one printed in the description.

Verification: open the store page in a private browser window and check, in one
pass, that (1) the privacy link opens the current policy, (2) the price under
the install button reads ₹49/month with the ₹1 offer, (3) the description says
"3 a day" and does not contain "Complete Meal History", "Cloud Backup", "Streak
Tracking" or "Weekly Auto-Insights".

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
- [ ] Referral screen → the code copies, and "Share on WhatsApp" opens the
      share sheet with the code in the text (that is the only sharing flow in
      the app; there is no weekly share card, despite older notes)
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

## 10. Publish the updated policy, and check the Gemini tier once

**Order of operations for the tombstone key.** The function throws at load when
`TOMBSTONE_SECRET` is missing in production, so a deploy without the variable
takes down scans, payments and sign-in — not just deletion. The safe order is:

1. set `TOMBSTONE_SECRET` in Vercel (done: added as **Config** so the migration
   can pull it with `vercel env pull`; a Secret is unreadable, even by you);
2. run the migration below with that same value;
3. deploy.

A key that differs between step 1 and step 2 is the quiet failure: the migration
succeeds and writes fingerprints that the server will never match, so everyone
who deleted before still gets ₹1. The script reports `key confirmed` when some
legacy address's fingerprint already exists — a positive signal. If it says
`NOT confirmed`, stop and check the value before `--apply`.

The privacy policy and the deletion page changed on 19 Nov 2026. Both make two
promises that must be true in the running system, not just in the HTML:

1. **The billed Gemini tier.** The policy says Google logs images for abuse
   monitoring for a limited period (up to 55 days) and does not use them to
   improve its products. That second half is only true for a Cloud project with
   **billing enabled** — on the free tier Google's terms let it use the content
   to improve its services and to have reviewers read it. Open Google Cloud →
   *Billing* and confirm the project holding `GEMINI_API_KEY` has an active
   billing account. If it does not, either enable it or change the policy text,
   because as written it would be wrong.
2. **The 24-month deletion record.** The tombstone holds an HMAC fingerprint
   instead of an email. Two separate things enforce the window, because they
   fail differently:
   - the **offer check** ignores any fingerprint whose `deleted_at` is older
     than 24 months, so an expired record stops withholding the ₹1 month the
     moment it expires — no cleanup needed;
   - **expired documents are deleted** on the next account deletion, in
     Firestore *and* in Postgres (production runs Firestore-only: `DATABASE_URL`
     is unset and the function prints "running without Postgres" on cold start).
     There is no scheduled job, so the bytes may outlive the window by weeks;
     that is why the policy says the record "stops counting after 24 months" and
     is deleted "at the next account deletion" rather than claiming a daily job.

Publish `app/docs/index.html` and `app/docs/delete-account.html` wherever the
GitHub Pages site is served from, then load both URLs in a private window and
confirm the new paragraphs are visible. A policy that says something the server
does not do is worse than the vaguer text it replaced.

**One-time migration (do this before pointing 1.5.17 at users).** Tombstones
written by earlier builds sit at `deletedAccounts/<email>`, and the offer check
now only looks up fingerprints — so everyone who deleted before this build can
claim the ₹1 month again. Do **not** delete those documents by hand: the address
is the only evidence left. Convert them instead:

```
cd backend
TOMBSTONE_SECRET=<production key> FIREBASE_SERVICE_ACCOUNT_JSON=<json> \
  node tools/migrate_tombstones.js          # dry run: prints counts only
TOMBSTONE_SECRET=<production key> FIREBASE_SERVICE_ACCOUNT_JSON=<json> \
  node tools/migrate_tombstones.js --apply  # writes fingerprints, deletes old docs
```

The script never prints an address, preserves each record's original
`deleted_at`, is idempotent (fingerprint ids are skipped), and merges two legacy
documents that normalise to the same address into one fingerprint — keeping the
**later** deletion date, since that is the one that says "this identity has
deleted". It commits in chunks of 200 records (400 operations), because a
Firestore commit allows 500 and the old single-batch version would have failed
on a collection of more than ~250 records. Run it with the **same**
`TOMBSTONE_SECRET` the server uses, or the documents it writes will never match.

A failed purge is now logged as `tombstone purge failed (Firestore|Postgres): …`
in the function logs rather than swallowed, so Search the logs for that string if
you ever need to prove the cleanup ran.

## 11. Things not to do

- **Don't enable App Check enforcement** before the metrics look clean.
- **Don't ask friends for 5-star reviews.** Play treats it as fake engagement.
- **Don't upload 1.5.17 to Play without the AAB** (`releases/1.5.17/*.aab`) — the
  APK is for sideloading.
- **Don't describe a photo as "not retained" by anyone.** We retain nothing; Google
  keeps abuse-monitoring logs for a limited period. Say that.
- **Don't let a paid feature reach the store page without a `403 pro_required`
  or a `ScanGate` branch behind it.**
- **Don't skip the version bump** on the next release: `pubspec.yaml`,
  `lib/core/app_version.dart` and the changelog entry in
  `lib/screens/updates_screen.dart` are checked against each other by
  `test/release_version_test.dart`.
