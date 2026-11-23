# StoreKit Sandbox test plan (TestFlight + Sandbox testers)

**Status: every test is BLOCKED until the owner has Apple access.** That means an App Store Connect sign-in, the product
`datewise_premium_monthly` created (checklist step 12, after the existing-IAP check in
`docs/qa/SUBSCRIPTION_RESILIENCE.md` §5), a TestFlight build of v2, and chat-v7 deployed to the Worker.
Nothing in this plan charges real money: TestFlight and Sandbox purchases are free.

## 0. Setup (once)

1. **Sandbox tester:** App Store Connect → Users and Access → **Sandbox** → Test Accounts → **+**. Use a new email
   address that is not an Apple Account. Region: United States (price $19.99). Make a second tester for the new-device and restore tests.
2. **iPhone:** Settings → App Store → scroll to **Sandbox Account** → sign in with the tester. Leave your real Apple Account signed in
   for everything else.
3. **Renewal rate:** App Store Connect → Users and Access → Sandbox → select the tester → **Subscription Renewal Rate**
   → choose the fastest rate (for example "Every 3 minutes" for a 1-month plan). You can change it per tester. Interrupted purchases
   and billing-problem simulation are on the same page. The exact labels may differ by App Store Connect version.
   Without changes, Sandbox renews a monthly plan every 5 minutes, up to 12 renewals.
4. **Billing Grace Period** (for G1 only): App Store Connect → Monetization → Subscriptions → Billing Grace Period → On, 3 days, applies to
   Sandbox. Turn it **off** again afterwards (launch recommendation: off, `BILLING_GRACE_DAYS="0"`).
5. **Worker:** chat-v7 deployed, `ALLOW_SANDBOX="1"`, and `ASSN_ENABLED="1"` with **both** notification URLs set
   (`docs/appstore/ASSN_SETUP.md`). Run `wrangler tail --format=pretty` (owner) and keep it open. Logs carry counts only.
6. Install the v2 build from TestFlight. Delete any earlier DateWise install first.

Server log lines to look for (`event: usage`): `kind: chat` with `outcome: ok | SUBSCRIPTION_EXPIRED | SUBSCRIPTION_REVOKED | DAILY_LIMIT…`,
and `kind: assn` with `outcome: SUBSCRIBED | DID_RENEW | … | stale | ack | ignored`. Sandbox subscribers use the `sbx:` counter and
`SANDBOX_DAILY_LIMIT` (20 a day). For a long session, raise it in the dashboard; never raise the Production limits for this.

## 1. Tests

| ID | Test | Steps | Expected app | Expected server |
|---|---|---|---|---|
| P1 | Purchase | Fresh install → onboarding → paywall → **Subscribe** → confirm in the Sandbox sheet | The sheet shows **$19.99/month** and "[Environment: Sandbox]". The paywall closes and chat unlocks. Send a message and a reply streams | `assn SUBSCRIBED` (INITIAL_BUY); `chat ok` on an `sbx:` key; `X-DateWise-Remaining-Today: 19` |
| P2 | Purchase cancelled | Paywall → Subscribe → **Cancel** in the sheet | Paywall stays, no error text, nothing charged | No `assn`; no chat request |
| P3 | Ask to Buy / pending (optional, needs a Family child tester) | Subscribe as the child | "Purchase pending…" notice; unlocks after approval | `SUBSCRIBED` after approval |
| R1 | Restore, same device | Delete the app → reinstall from TestFlight → paywall → **Restore purchases** | Paywall closes, chat works. Counters continue (not reset) | `chat ok` on the **same** `sbx:` key as before (the counter continues) |
| R2 | Restore, new device | Second iPhone, same Sandbox tester → install → **Restore purchases** | Unlocks | Same `sbx:` key as R1 |
| R3 | Restore with nothing bought | Second tester (never bought) → Restore | "No active subscription for this Apple Account" | None |
| R4 | Restore while offline | Airplane mode → Restore | If StoreKit already holds the subscription: unlocks. Otherwise "Couldn't restore… try again" (never a crash or dead end) | None |
| N1 | Renewal (accelerated) | After P1, keep the app open through 2 renewals (rate from setup step 3), sending a message after each | Chat keeps working with no prompt. Just after a renewal, at most one invisible re-read and retry | `assn DID_RENEW` per renewal; no `SUBSCRIPTION_EXPIRED` visible to the user (if one is logged, the next line is `ok`) |
| N2 | Renewal while the app is closed | Close the app for 2 renewal periods → open → chat | Unlocked, chat works | `DID_RENEW` logged while closed; `chat ok` |
| E1 | Expiration (cancel then wait) | Settings → [name] → Subscriptions (Sandbox: Settings → App Store → Sandbox Account → Manage) → **Cancel** → wait past the period | Until the end: still works. After: on the next resume the paywall returns, and a message in an open chat shows "subscription isn't active" with **Try again** | `DID_CHANGE_RENEWAL_STATUS` (AUTO_RENEW_DISABLED, `ack`) then `EXPIRED` (VOLUNTARY); chat `SUBSCRIPTION_EXPIRED` after expiry + 60 min leeway |
| E2 | Sandbox auto-expiry | Leave a tester renewing until Sandbox stops (12 renewals) | As E1 | `EXPIRED` |
| C1 | Cancellation, then resubscribe | After E1 → paywall → Subscribe | Unlocks again. The counter is the same `sbx:` key (same original transaction) | `SUBSCRIBED` (RESUBSCRIBE) |
| F1 | Refund (TestFlight) | On the device: Settings → [name] → Media & Purchases → … or reportaproblem.apple.com → **Request a refund** for the Sandbox purchase. If Sandbox does not offer it, use Xcode StoreKit testing (Debug → StoreKit → Manage Transactions → Refund) as a local stand-in, and the server half stays BLOCKED | Next launch or resume: paywall. A message gets "This purchase was refunded or revoked" (no instant retry). Subscribe again works | `assn REFUND`; chat `SUBSCRIPTION_REVOKED`; replaying the pre-refund token is also refused |
| F2 | Refund reversed (only if Apple reverses one) | — | Unlocks again | `REFUND_REVERSED`; chat `ok` |
| B1 | Billing retry (no grace) | Sandbox tester → enable the billing-problem / "fail renewals" option (setup step 3) → wait for the next renewal | After the period ends: paywall on resume and "isn't active" in chat. When the option is turned off and Apple recovers: unlocks without buying again | `DID_FAIL_TO_RENEW` (no subtype); chat `SUBSCRIPTION_EXPIRED`; then `DID_RENEW` (BILLING_RECOVERY) and chat `ok`, **even before the device re-reads** |
| G1 | Billing grace period | Grace on (setup step 4) → billing problem on → wait for a renewal | Chat keeps working during grace. Apple shows its own "update payment" sheet. After grace without payment: locked | `DID_FAIL_TO_RENEW` (GRACE_PERIOD); chat `ok` while `now < gracePeriodExpiresDate` with `BILLING_GRACE_DAYS="0"`; `GRACE_PERIOD_EXPIRED` then `SUBSCRIPTION_EXPIRED` |
| X1 | StoreKit slow at launch | Weak network (Settings → Developer → Network Link Conditioner, "Very Bad Network") → cold launch | Subscriber sees chat (or at worst the paywall with "Could not reach the App Store" + Restore). Never a blank screen longer than 10 s | — |
| X2 | Purchases restricted | Settings → Screen Time → Content & Privacy → iTunes & App Store Purchases → In-app Purchases: **Don't Allow** → launch | An active subscriber keeps chat. Subscribe is disabled for a non-subscriber | — |
| X3 | Notification check | Optional: App Store Server API "Request a Test Notification" (needs an API key; do not create one just for this) | — | `assn ack` (TEST); nothing stored |
| X4 | Sandbox stays separate | After P1, check the Worker's Durable Objects (dashboard) | — | Only `sbx:` objects for Sandbox; Production `sub:` untouched |

## 2. Results (fill in)

Build: ______  Worker version (`GET /?version`): ______  Tester: ______  Date: ______

| ID | Result (PASS / FAIL / BLOCKED) | Device / iOS | Notes (log lines, screenshots) |
|---|---|---|---|
| P1 | BLOCKED | | |
| P2 | BLOCKED | | |
| P3 | BLOCKED | | |
| R1 | BLOCKED | | |
| R2 | BLOCKED | | |
| R3 | BLOCKED | | |
| R4 | BLOCKED | | |
| N1 | BLOCKED | | |
| N2 | BLOCKED | | |
| E1 | BLOCKED | | |
| E2 | BLOCKED | | |
| C1 | BLOCKED | | |
| F1 | BLOCKED | | |
| F2 | BLOCKED | | |
| B1 | BLOCKED | | |
| G1 | BLOCKED | | |
| X1 | BLOCKED | | |
| X2 | BLOCKED | | |
| X3 | BLOCKED | | |
| X4 | BLOCKED | | |

A FAIL in P1, R1, N1, E1, F1 or B1 blocks submission. Record the exact `wrangler tail` lines (they hold no personal data).
