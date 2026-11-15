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
account, MacroSnap stores the identifier you signed up with (your email
address) in a `deletedAccounts` record so the same identity cannot be used to
claim the once-per-account ₹1 first-month offer a second time.

- It contains **only the identifier** — no meals, habits, name, photos, history
  or subscription state, and it is not linked to any active account.
- It is kept **indefinitely**, because a fingerprint with an expiry would let
  the offer be farmed again once the expiry passed.
- It is never shown to any other user, and it is not readable or writable by
  the app (server-only).

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
