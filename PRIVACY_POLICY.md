# Privacy Policy for MacroSnap

**Last updated: November 15, 2026**

## Data Collection
MacroSnap collects only the data needed to run the app:

- **Account information** — the email address of the Google account you sign in with, and the display name you choose, used to identify your account via Firebase Authentication. Google sign-in is the only sign-in method; there is no guest or phone-number account.
- **Meal, habit and diet data** — meals, nutrition targets, habit trackers, streak days, water logs and diet preferences. Stored on your device and **saved to the cloud automatically** (Cloud Firestore) whenever you are signed in, so your data survives reinstalls and device changes.
- **AI assistant messages** — messages you send to Guru, the in-app nutrition assistant, are forwarded to Google Gemini AI to generate a reply. Along with the last few messages, a summary of your own logged data (today's meals and macro totals, nutrition targets, habit progress, water intake and your display name) is included so Guru can answer questions about your day. Your phone number and email are never sent.
- **Subscription status** — handled by Razorpay; we store only your subscription status and start date. No card, UPI or banking details are ever stored on our servers.
- **App usage counters** — anonymous interaction counts (for example, how often each tab is opened) stored against your account, used only to decide which interface layout works better. They contain no content and no location.
- **Crash reports** — if the app crashes, a technical report (stack trace, device model, app version) is sent to Google Firebase Crashlytics so the bug can be fixed. Release builds only; it never contains your meals, photos or messages.

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
- **Deletion record: a one-way fingerprint, kept at most 24 months.** When you delete your account we keep one record: a keyed hash (HMAC) of the email address you signed up with, plus the date of deletion. It is not your email address — it cannot be turned back into one without a secret key that exists only in our server environment — and it holds no meals, habits, name, phone, photos, history, trial data or subscription state. No user and no other part of the app can read it. Its only purpose is to answer "has this identity already had the ₹1 offer?". After 24 months it stops counting for that purpose, and the record itself is deleted at the next account deletion. You can also ask us to erase it sooner (see Your Rights); the only consequence is that the ₹1 offer could then be claimed again with that address.

## Your Rights

You can delete your account and all associated data at any time from **Settings → Delete Account** in the app. That removes your cloud data, your photos, your subscription record and your local data on this device, and it cannot be undone. The only thing kept is the fingerprint-only deletion record described under "How long we keep things" — and that is erasable on request too. You can also email us to ask what we hold about you, or to have it corrected or erased; we answer within 30 days.

## Contact
For questions, contact: macrosnap7@gmail.com
