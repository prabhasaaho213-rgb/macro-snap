# Play Store listing — copy and Data Safety answers

Everything here matches what the current build actually does. If a number changes
in code, change it here too; the two must never disagree, because both are
read by the same person deciding whether to install.

## Short description (80 characters max)

```
Photo → calories, Indian food included. 3 free scans a day, then ₹49/month.
```

Alternates, if the above reads too price-led:

- `Snap a plate, get calories, protein and carbs. Built for Indian food.`
- `Calorie tracking by photo — idli, dal, biryani and packaged snacks too.`

## Full description

```
Snap a photo of your plate and MacroSnap estimates the calories and macros —
protein, carbs and fat — for what is actually in front of you.

BUILT FOR INDIAN FOOD, NOT JUST WESTERN DISHES
Most calorie apps know a bagel better than a thali. MacroSnap identifies roti,
dal, sabzi, idli, dosa, biryani, paneer dishes, street food, packaged Indian
snacks and restaurant plates, and names the portion it thinks it sees
("2 rotis", "1 small bowl of dal") instead of guessing a flat 100 g.

YOU ADJUST THE PORTION, NOT THE APP
Every scan opens with an editable serving — the weight the app estimated, which
you can change with the + / − control before saving. Because portions are the
biggest source of error in any photo estimate, the number that counts is the one
you confirm. Barcodes for packaged foods are read from the pack, and you can
type a barcode by hand when the camera cannot read it.

WHAT YOU GET
• Photo scan → calories, protein, carbs, fat, fibre and sugar
• A one-day Indian meal plan built around your goal, activity level and diet
  preference (fully vegetarian by default)
• Habits: water intake, daily streaks, and reminders that survive a reboot
• Weekly insights: your calorie-goal streak and how the week actually went
• A health score per plate, so "is this a good meal" is one glance
• BMI and weight tracking, with your own history

PRICING — NO SURPRISES
• Free: 3 photo scans per day, plus unlimited barcode scans and manual entry.
• Pro: ₹49/month. The first month costs ₹1.
• Cancel any time from the Play Store. If you cancel, Pro stays on until the
  end of the month you already paid for.

PRIVACY
• Your meals, habits, weight and plan are stored on your device and synced to
  your own account so a reinstall does not lose them.
• Meal photos are sent to our server only to be analysed, and are never shared
  with third parties.
• No ads, and no selling of data.
• Delete your account from Settings → Delete account. That removes your data;
  only a record that the account existed is kept so the same welcome offer
  cannot be claimed twice.
• Privacy policy: https://prabhasaaho213-rgb.github.io/macro-snap/

ABOUT ACCURACY
Nutrition values are estimates, not measurements. Portions are inferred from
the photo and confirmed by you; packaged-food values come from the pack's
printed nutrition panel. Treat MacroSnap as a consistent way to track, not as
medical or dietary advice — if you have a condition that depends on exact
intake, work with a doctor or dietitian.
```

Notes on the copy:

- The price and the free limit are stated in the first screenful on purpose.
  "Free scan limit not stated" is the most common reason people back out of a
  calorie-app listing.
- The accuracy paragraph is the honest version of "how was it tested": there is
  no lab validation, so the listing says what the numbers are derived from and
  that the user confirms the portion. Do not replace it with a claim like
  "clinically accurate".
- The privacy URL must be updated if the policy ever moves off GitHub Pages (see
  the last section).

## Data Safety answers

Play asks what the app *collects and transmits*, not what it can access. Answer
from this table and check the current build against it before submitting.

| Category | Collected? | Details |
|---|---|---|
| **Location** | **No** | The app has no location code and no location permission in the merged manifest. If the form still says Location, that is a mistake in the form — remove it. |
| Personal info → Name | Yes | The nickname you choose, shown in the app and stored with your account. |
| Personal info → Email address | Yes | From Google sign-in; used as the account identity. |
| Health and fitness → Fitness info | Yes | Height, weight, age, goal, activity level and the meals you log. Collected because the plan and targets are computed from them. |
| Photos and videos → Photos | Yes | The meal photo you choose or take. Sent to the server for analysis; not used for anything else. |
| Financial info → Purchase history | Yes | Subscription state from Razorpay/Play. Card details never reach the app or our server. |
| App activity → Other actions | Yes | Meals, habits, water and streak days you log. |
| Device or other IDs | Yes | Firebase installation ID, used to keep your session and sync working. |
| Contacts, SMS, Calendar, Microphone, Files | **No** | Not requested, not used. Microphone and NFC were removed from the merged manifest in 1.5.16 — the camera plugin declared the microphone for video recording, which this app never does. |

Data is encrypted in transit (HTTPS only; `usesCleartextTraffic="false"`), is not
sold, and is not shared with third parties beyond the processors listed in the
privacy policy (Firebase, Razorpay, the model provider that analyses the scan).
Users can request deletion in-app and by email.

### Why each permission appears

- **Camera** — scanning meals. Optional: manual entry and barcode typing work
  without it, and the app is installable on devices with no camera.
- **Notifications** — habit reminders. Requested at the moment the user sets a
  reminder, not at launch.
- **Receive boot completed / Vibrate** — re-scheduling reminders after a reboot.
- **Read basic phone state** — declared by the Razorpay payment SDK for device
  binding during checkout. It is not read by app code and nothing is stored.
- **Read external storage** — implied by the camera library; the app itself
  reads only files the user picked.

## Reviews

- Do **not** ask friends or family for 5-star reviews, and never offer anything
  in exchange for one. Play's policy treats that as fake engagement and it can
  cost the listing.
- The app currently ships no in-app review prompt. The honest version — ask
  after the user has saved three meals, using Play's in-app review flow so the
  rating sheet is Play's own UI — needs the `in_app_review` package and a gate in
  `result_screen.dart`'s save path. That is a feature, not a copy change.
- The one written review asks for better diet plans. That is a product signal:
  the plan is Pro-only, so a free user can only judge the scans. Worth answering
  that review publicly, since it is the only text on the page.

## Where the policy lives

The policy is served from GitHub Pages
(`https://prabhasaaho213-rgb.github.io/macro-snap/` — the same URL the app opens
from Settings). Play accepts
it, but a `github.io` address reads as a side project. The cheapest fix without
buying a domain is to serve the same HTML from the API host the app already
calls (`https://macro-snap-backend.vercel.app/privacy`), which keeps everything
on one origin and is still free. A real domain is the better long-term answer:
buy it, point it at the Pages site or the API host, and update the URL in
Play Console, the app's Settings screen, and `docs/index.html`.
