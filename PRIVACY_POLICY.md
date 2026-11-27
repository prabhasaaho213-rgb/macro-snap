# Privacy Policy for MacroSnap

**Last updated: November 15, 2026**

## Data Collection
MacroSnap collects only the data needed to run the app:

- **Account information** — the email address of the Google account you sign in with, and the display name you choose, used to identify your account via Firebase Authentication. Sign-in in the app is Google only, and there is no guest mode. An account is identified by its Firebase user ID; a verified phone number is also accepted as an account identifier for accounts created that way.
- **Meal, habit and diet data** — meals, nutrition targets, habit trackers, streak days, water logs and diet preferences. Stored on your device and **backed up to the cloud automatically** (Cloud Firestore) whenever you are signed in, so your data survives reinstalls and device changes. The cloud copy is a backup, not a live two-way merge: meals you add or delete reach your other devices, but an edit made to an existing meal on one device is not merged into the copy on another, and habits and the water log are stored as a single document per account, so the most recent save wins.
- **Leaderboard (optional)** — if you join the Weekly Leaderboard, your chosen display name, your area (state and district) and your weekly points are visible to other signed-in users in the same area. Your meals, weight, photos and habits are never shown there. Points are derived from activity you already log (meals, habits, water, weigh-ins and your step totals) and are stored per week.
- **Health and fitness data (optional)** — only if you grant the permission, the app reads step counts and active-calorie totals from Health Connect on Android (or Apple Health on iOS) to show your movement and count it towards habits and leaderboard points. The raw health records stay on your device; only per-day step totals are uploaded to your account so a reinstall can restore them. You can revoke the permission at any time in system settings, and the app keeps working without it. The phone's own step sensor is also used and needs no health permission.
- **AI assistant messages** — messages you send to Guru, the in-app nutrition assistant, are forwarded to Google Gemini AI to generate a reply. Along with the last few messages, a summary of your own logged data (today's meals and macro totals, nutrition targets, habit progress, water intake and your display name) is included so Guru can answer questions about your day. Your phone number and email are never sent.
- **Subscription status** — handled by Razorpay; we store only your subscription status and start date. No card, UPI or banking details are ever stored on our servers.
- **App usage counters** — anonymous interaction counts (for example, how often each tab is opened) stored against your account, used only to decide which interface layout works better. They contain no content and no location.
- **Crash reports** — if the app crashes, a technical report (stack trace, device model, app version) is sent to Google Firebase Crashlytics so the bug can be fixed. Release builds only; it never contains your meals, photos or messages.
- **Invite links and install attribution** — when you open a Friends League invite link, or install the app from one, we record the invite code, which step it was (link opened, install, league joined) and the time, so invites can be counted and the league found. On first launch the app reads Google Play's Install Referrer once for this purpose; it carries only the referral data Play attaches to the install, not your Google account, contacts or advertising ID. These records contain no account identifier, and a league you join is visible to the other members of that league.

## Camera & Photos

The app uses your camera and your photo gallery only to analyse the food you are logging. A photo you take or pick is sent through our backend to Google Gemini AI for analysis; the analysis result is what we keep, not the photo.

A copy of a logged meal's photo is then kept **on your device only**, so the meal card can show what you ate. For how long depends on your setting in Settings → Meal Photos:

- **24 hours** (default) — the photo is deleted automatically
- **7 days** or **30 days**
- **Forever** — available on Pro

**Optional cloud backup (Pro, off by default).** If you turn on Settings → Sync Meal Photos, photos of meals you log are also uploaded to our servers and stored in Cloud Firestore, so they can reappear on a new phone or after a reinstall. You can turn this off at any time; turning it off stops new uploads. Deleting a meal deletes its cloud photo, and deleting your account deletes all of them.

We never read your photos for any purpose other than the analysis you asked for, we never use them for advertising or to train models, and we never share them with anyone except the analysis provider named above.

## Third-Party Services
MacroSnap uses:
- **Google Firebase** – Authentication and cloud data storage (Firestore)
- **Google Gemini AI** – Food recognition, diet plans and the nutrition assistant
- **Razorpay** – Subscription payments (UPI, cards and other supported methods)

## How long we keep things

- Meals, habits, weight and diet data: until you delete them, or delete your account.
- Guru conversations: kept on your device, and used only to build the context for your next question.
- Meal photos: the local window you choose (24 hours by default); cloud copies only while you keep the backup setting on.
- Crash reports: retained by Firebase Crashlytics for 90 days.
- Invite events (invite code, step, time): kept while the invite campaign is in use; they carry no account identifier.
- **Deletion record: a one-way fingerprint, kept at most 24 months.** When you delete your account we keep one record: a keyed hash (HMAC) of the email address you signed up with, plus the date of deletion. It is not your email address — it cannot be turned back into one without a secret key that exists only in our server environment — and it holds no meals, habits, name, phone, photos, history, trial data or subscription state. No user and no other part of the app can read it. Its only purpose is to answer "has this identity already had the ₹1 offer?". After 24 months it stops counting for that purpose, and the record itself is deleted at the next account deletion. You can also ask us to erase it sooner (see Your Rights); the only consequence is that the ₹1 offer could then be claimed again with that address.

## Your Rights

You can delete your account and all associated data at any time from **Settings → Delete Account** in the app. That removes your cloud data, your photos, your subscription record and your local data on this device, and it cannot be undone. The only thing kept is the fingerprint-only deletion record described under "How long we keep things" — and that is erasable on request too. You can also email us to ask what we hold about you, or to have it corrected or erased; we answer within 30 days.

## Contact
For questions, contact: macrosnap7@gmail.com
