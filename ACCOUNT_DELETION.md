# Account Deletion Request — MacroSnap

**Last updated: November 15, 2026**

## How to Delete Your Account and Data

### Option 1: In the app (immediate)

1. Open **Settings** (bottom tab bar → Settings).
2. Scroll to **Delete Account**.
3. Confirm the dialog.

The app then calls the backend to delete your account and everything attached
to it, wipes this device's copy of your data, signs you out and returns to the
sign-in screen. This is immediate and cannot be undone.

If the server cannot be reached, the app tells you so and **leaves your data
untouched** — nothing is deleted locally until the server confirms, so you can
retry or keep using the app. There is no separate "pending deletion" state.

### Option 2: Email request

Send an email to **macrosnap7@gmail.com** with the subject
**"Account Deletion Request"** and include the email address you used to sign
in (Google sign-in).

We will process your request within **7 business days**.

---

## What Data Is Deleted

| Data Type | Deleted? | Notes |
|-----------|:--------:|-------|
| Email address (Google account) | ✅ Yes | Removed from Firebase Authentication |
| User name / display name | ✅ Yes | |
| Meal history & logs | ✅ Yes | Including cloud-synced meals |
| Meal photos | ✅ Yes | Local copies and any Pro cloud backup |
| Nutrition records | ✅ Yes | |
| Streak data, badges | ✅ Yes | |
| Diet plan preferences | ✅ Yes | |
| Subscription status | ✅ Yes | The payment record itself is kept by Razorpay |
| Local data on this device | ✅ Yes | Only this account's data — other accounts on the same phone are untouched |

## What Data Is Retained

**One record is kept on purpose: a deletion tombstone.** When you delete your
account, MacroSnap stores a **one-way fingerprint** of the email address you
signed up with, and the date of deletion, so the same identity cannot be used to
claim the once-per-account ₹1 first-month offer a second time.

- The fingerprint is a keyed hash (HMAC) of the address, not the address. It
  cannot be turned back into your email without the secret key, which lives only
  in the server environment — not in the app, not in the code, not in this
  repository.
- It contains **only that fingerprint and the deletion date** — no meals,
  habits, name, phone, photos, history, trial data or subscription state, and it
  is not linked to any active account.
- It is kept for **at most 24 months**: after that it no longer counts for the
  offer, and the record is deleted at the next account deletion.
- It is never shown to any other user, and it is not readable or writable by
  the app (server-only).
- It can be **erased sooner on request** — email
  [macrosnap7@gmail.com](mailto:macrosnap7@gmail.com) from any address. The only
  consequence is that the ₹1 offer could then be claimed again with that email
  address.

Also retained, as described in the [privacy policy](PRIVACY_POLICY.md):

- **Crash reports** (technical data only, no meals or messages) — 90 days in
  Firebase Crashlytics.
- **Transaction records** held by Razorpay for tax/accounting purposes — 90
  days.

---

## Contact

For any questions about account deletion:

- **Email:** macrosnap7@gmail.com
- **Response time:** Within 7 business days
