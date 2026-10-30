# MacroSnap → Firestore Migration Design

> Status: **In progress.** Phases 1–2 done (backend dual-write `backend/firestore.js`,
> `backfill_firestore.js`). **Phase 3 (app swap) implemented:** `MealSyncService` now reads/writes
> Firestore directly (`meals/{id}`, `habitData/{uid}`) keyed by Firebase Auth UID;
> `SubscriptionService.verifyServerSubscription` reads `users/{uid}.subscribed` with a
> backend fallback; `SyncStatusService.probeBackend` probes Firestore for signed-in users.
> Security rules live in `firestore.rules` (deploy via `firebase deploy --only firestore:rules`).
> This document remains the agreed design (collections, security rules, phased plan).

## 0. Why this migration

MacroSnap already uses **Firebase Authentication** for all sign-in methods
(phone OTP, Google, email/password). What lives on a third-party backend today
is the **user data layer**:

- `backend/server.js` — Node/Express on Railway
- **PostgreSQL** database (tables: `users`, `meals`, `habit_data`,
  `subscriptions`, `payments`)

The app syncs meals/habits to this backend via HTTP
(`MealSyncService`) and verifies subscriptions against
`/subscription/status`.

Moving the user-data layer to **Cloud Firestore** gives us:

- Data on Google's infrastructure — no more "Application not found"
  outages when the Railway deployment dies.
- Offline-first caching via the Firestore SDK (upgrade over
  SharedPreferences + best-effort HTTP sync).
- Fine-grained security rules equivalent to the Postgres RLS model.

### What must stay server-side (secrets can never ship in the APK)

| Stays on Node backend | Moves to Firestore |
|---|---|
| `POST /analyze` — Gemini AI analysis + free-scan-limit enforcement | `users`, `meals`, `habit_data` CRUD |
| `POST /generate-diet-plan` — Gemini | Subscription-status reads |
| `POST /payment/create-subscription`, `/payment/verify`, `/payment/webhook` — Razorpay HMAC + secrets | Referral code lookup |

### Known contract bugs this migration fixes

The app calls `/meals/remove` and `/meals/list/:phone`, but the server only
exposes `POST /meals/sync` and `GET /meals/:phone`. Meal deletion and meal
restore have been silently returning 404 — a contributing factor to flaky
reinstall restore. Firestore eliminates this class of client/server
contract mismatch.

## 1. Collection design

Maps 1:1 to the existing Postgres tables. Keys use the **Firebase Auth UID** —
phone auth yields the same UID for the same number on every install, so
reinstall restore works without extra bookkeeping.

### `users/{uid}` ← `users` table

```text
identifier:    string   // phone "+919876543210" OR email — the app's prefs 'phone' value
email:         string
name:          string
photoUrl:      string
subscribed:    bool
subscriptionId string   // Razorpay subscription id (set by webhook)
scanCount:     int      // free scans used this month
scanMonth:     int      // YYYY*12+M — monthly reset marker
referralCode:  string
referredBy:    string
createdAt:     timestamp
```

The owner account (`prabhasaaho213@gmail.com`) receives lifetime Pro,
enforced in security rules — never trusted from the client.

### `userIndex/{identifier}` ← new

Maps identifier → `{ uid, name }`. Doc ID = the identifier itself. Needed so a
fresh install can resolve "restore data for phone X" via the same identity the
app already persists (`prefs['phone']`).

### `meals/{mealId}` ← `meals` table

```text
uid:      string     // owner UID
date:     timestamp
name:     string
category: string
calories: int
protein:  number
carbs:    number
fats:     number
fiber:    number
serving:  string
createdAt timestamp
```

Query: `where('uid', ==, uid).orderBy('date', descending)` — replaces
`GET /meals/:phone`.

### `habitData/{uid}` ← `habit_data` table

One doc per user, mirroring the current single JSONB row so the app's JSON
round-trip stays byte-identical:

```text
habits:    array<map>        // Habit.toJson() list, as today
waterLog:  map<string, int>  // dateKey -> glasses
waterGoal: int
updatedAt: timestamp
```

### `subscriptions/{subId}` ← `subscriptions` table

`subId` = Razorpay subscription id. **Written only by the backend webhook via
the Admin SDK** (Admin SDK bypasses rules) — never by the client.

### `payments/{autoId}` ← `payments` table

Written only by `/payment/verify` + `/payment/webhook` (Admin SDK).
Read-only for the owning user.

### `referrals/{code}` ← new

Doc ID = the uppercase 6-char code. Doc-ID uniqueness replaces the Postgres
`UNIQUE INDEX idx_referral_code`. Contains `{ uid, identifier, createdAt }`.

**The reward transaction** (set `subscribed = true` on referrer + referee,
reject self-referral / duplicate use) must run in a Cloud Function or the Node
backend — client rules cannot do cross-doc transactions.

## 2. Firestore security rules

Replaces Postgres RLS with equivalent guarantees: authenticated access only,
users can only touch their own data, money/entitlement records are
server-write-only.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function isOwner(uid) { return request.auth.uid == uid; }
    function isAdmin() {
      return request.auth != null &&
        request.auth.token.email == 'prabhasaaho213@gmail.com';
    }

    match /users/{uid} {
      allow read, write: if signedIn() && isOwner(uid);
      // Support/admin: any authenticated admin may read any user.
      allow read: if isAdmin();
      // NOTE: scan-count increments stay gated server-side in /analyze.
    }

    match /userIndex/{identifier} {
      // Only the person who owns that identifier may read the mapping.
      allow read: if signedIn() && (
        request.auth.token.phone_number == identifier ||
        request.auth.token.email == identifier);
    }

    match /meals/{mealId} {
      allow create: if signedIn()
        && request.resource.data.uid == request.auth.uid;
      allow read, update, delete: if signedIn()
        && resource.data.uid == request.auth.uid;
    }

    match /habitData/{uid} {
      allow read, write: if signedIn() && isOwner(uid);
    }

    match /subscriptions/{subId} {
      allow read: if signedIn()
        && resource.data.uid == request.auth.uid;
      allow write: if false;   // webhook only (Admin SDK bypasses rules)
    }

    match /payments/{id} {
      allow read: if signedIn()
        && resource.data.uid == request.auth.uid;
      allow write: if false;
    }

    match /referrals/{code} {
      allow create: if signedIn()
        && request.resource.data.uid == request.auth.uid;
      allow read: if signedIn();
      allow update, delete: if false;   // Cloud Function / backend rewards
    }
  }
}
```

## 3. Phased implementation plan

Each phase is independently shippable; phases 1–2 are zero-risk.

### Phase 1 — Backend dual-write (reversible)

- Add `firebase-admin` to `backend/` (service-account credential via
  env var, e.g. `GOOGLE_APPLICATION_CREDENTIALS_JSON`).
- Every Postgres write also writes to Firestore with identical data:
  - `/register` → `users/{uid}` + `userIndex/{identifier}`
  - `/meals/sync` → `meals/*`
  - `/habits/sync` → `habitData/{uid}`
  - `/subscribe`, `/unsubscribe`, `/payment/verify`, `/payment/webhook` →
    `users/{uid}.subscribed`, `subscriptions/*`, `payments/*`
  - `/referral/*` → `referrals/{code}`, `users.*.referredBy`
- Postgres stays the source of truth during this phase. Firestore failures
  are logged, never fatal.

### Phase 2 — Data backfill

- One-time Node script: read all Postgres rows → write Firestore
  (`users`, `meals`, `habit_data`, `subscriptions`, `payments`, `referrals`,
  `userIndex`).
- Existing users keep their data after the switch.

### Phase 3 — App swap

- Add `firebase_cloud_firestore` to `pubspec.yaml`.
- Rewrite `MealSyncService` to read/write Firestore instead of `/meals/*` +
  `/habits/*`. Keep method signatures identical so `MealStore`, `HabitStore`,
  and `SyncStatusService` are untouched.
- Swap `SubscriptionService.verifyServerSubscription()` to a Firestore read of
  `users/{uid}.subscribed` (rules handle the admin override).
- Remove the `serverUrl` edit flow in Settings for data endpoints (kept for
  `/analyze` + payments).

### Phase 4 — Cutover

- Remove Postgres paths for user data: `/register`, `/meals/*`, `/habits/*`,
  `/subscribe`, `/unsubscribe`, `/subscription/status`.
- Keep `/analyze`, `/generate-diet-plan`, `/payment/*` — these now read/write
  Firestore via Admin SDK (including the webhook flipping `subscribed`).

### Phase 5 — Validation

- Widget tests: restore-after-reinstall, free-scan limit, admin lifetime Pro.
- Live rules tests: unauthenticated denied, cross-user denied, owner allowed,
  webhook write allowed.
- End-to-end: a Razorpay test subscription webhook still flips `subscribed`
  in Firestore.

### Phase 6 — Decommission

- Point Railway Postgres at a read-only snapshot.
- Delete Postgres-sync code from the app and backend.
- ⚠️ **Decision flagged:** this reverses the earlier explicit choice to use the
  500 MB Postgres database. The tradeoff: user data no longer depends on the
  Railway service staying alive.

## 4. Costs & tradeoffs

| Item | Note |
|---|---|
| Firestore free tier | 50k reads / 20k writes / 1 GiB/day — ample for a small user base; overage is pennies |
| No unique indexes / server transactions from clients | Referrals need the small Cloud Function or the existing Node backend (already server-side) |
| Offline support | Firestore SDK local cache is a strict upgrade over SharedPreferences + HTTP sync |
| Effort | ~2–3 focused sessions; Phase 1–2 zero-risk, Phase 3 the only real app surgery |
| Postgres retirement | The 500 MB DB becomes unused for user data after Phase 6 |

## 5. Decisions recorded

- **Key by UID, not phone** — deterministic per identifier, reinstall-safe,
  and rules check `request.auth.uid` (cannot be forged).
- **`habitData` stays one doc per user** — matches today's single JSONB row;
  avoids array-field subcollection complexity and keeps `Habit.toJson()`
  round-trips identical.
- **Money + entitlement docs are client-write-forbidden** — only the webhook /
  verify path (Admin SDK) may write `subscriptions` and `payments`.
- **Admin lifetime Pro lives in rules**, keyed on the owner email claim — the
  client can't grant itself or anyone else Pro.
