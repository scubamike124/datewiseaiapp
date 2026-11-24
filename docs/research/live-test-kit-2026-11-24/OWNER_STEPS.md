# Owner steps: get a Sandbox JWS and run the live battery

Nothing here has been run. An agent cannot create the token: it is an Apple-signed StoreKit 2 transaction from a
Sandbox purchase on a device. Production (`datewise-photo-coach`) is still chat-v5 and is **not** a target. The target
is the staging Worker `datewise-coach-staging`, deployed after PR #55 merges (docs/qa/LIVE_AI_TEST_PLAN.md section 1).
Every command below was prepared offline; the kit refuses the production Worker and a Production token.

## 0. One-time prerequisites (owner)

1. PR #55 merged to `main`; deploy staging: GitHub, Actions, **Deploy coach Worker**, Run workflow from `main`,
   target `chat-v7-staging`, `dry_run` off, approve the `production-worker` environment. Check
   `https://datewise-coach-staging.<subdomain>.workers.dev/?version` says `chat-v7-cost-guard`.
2. App Store Connect has the subscription `datewise_premium_monthly` and a TestFlight build of v2 (existing checklist).
3. A Sandbox tester: appstoreconnect.apple.com, **Users and Access**, **Sandbox**, **Test Accounts**, **+** (new email,
   any password; it never needs real money). Optional second tester for option C below.

## 1. What to buy

The only product: **`datewise_premium_monthly`**. In a Sandbox purchase the sheet shows `$19.99/month` and
`[Environment: Sandbox]`, and it is **free**. Do not use a real Apple Account for the purchase. A Sandbox monthly plan
renews about every 5 minutes (12 times), so each token's `expiresDate` is close; the Worker accepts a token for 60
minutes after it. Export a fresh token right before every run.

## 2. Getting the JWS: a TestFlight build cannot hand it out (intended)

TestFlight and App Store builds are release builds. They have no export of the token, and none may be added to release
code (docs/qa/LIVE_AI_TEST_PLAN.md section 2). The token comes from a **debug build on your iPhone**, which buys in the
same Sandbox environment, so the token is the same kind Apple gives TestFlight.

### Path A (needs a Mac with Xcode once per run day): automatic LIVE battery

1. iPhone: **Settings**, **Developer**, **Sandbox Apple Account** (older iOS: **Settings**, **App Store**, scroll to
   **Sandbox Account**), **Sign In** with the Sandbox tester.
2. Mac, Xcode: open `ios/Runner.xcworkspace`, **Product**, **Scheme**, **Edit Scheme**, **Run**, **Options**,
   **StoreKit Configuration: None** (with `DateWise.storekit` the token is environment `Xcode` and the Worker refuses it).
3. Mac, Terminal: `flutter run --debug -d <your iPhone> --dart-define=DW_DEV_TOOLS=true`
4. iPhone, in the app: finish onboarding. Paywall: tap **Subscribe**, then **Subscribe** in the Apple sheet, enter the
   tester password. (Already bought: **Restore purchases**.)
5. Tap the **You** tab, scroll to the bottom, tap **Developer: copy entitlement token**. The dialog must say
   `Sandbox · datewise_premium_monthly · expires ...`. Tap **Copy**.
6. Mac (Universal Clipboard), Terminal, in the repository folder:
   ```bash
   read -rs DW_TEST_JWS && export DW_TEST_JWS    # paste, press Enter; nothing is shown
   ```
   Then copy any other text on both devices to clear the clipboard. Never paste the token into chat, an issue or a PR.
7. Preview (sends nothing): `node tool/live/live_chat_test.mjs --list-battery`
8. Run day A, the 17 must-run scenarios (about 4 minutes, about 1,800 neurons):
   ```bash
   node tool/live/live_chat_test.mjs --mode live --confirm-live \
     --base-url https://datewise-coach-staging.<subdomain>.workers.dev --battery --tier 1
   ```
   Exit 0 = no failing check, 1 = a failing check or an early stop (for example `DAILY_LIMIT`), 2 = refused to start.
9. The report `build/live_ai/live_chat_LIVE_<time>.md` and `<same name>.grader.json` are the evidence. Hand the `.grader.json`
   to the independent grader with `docs/qa/LIVE_AI_GRADER_RUBRIC.md`. Keep both out of the repository.
10. Later days: repeat steps 5 to 6 (fresh token), then
    `... --battery --min-tier 2 --day 1`, then `--day 2`, and so on (section 3).

### Path B (iPhone only, no token export): the normal chat in the TestFlight build

No automatic checks and no `.grader.json`; you read the replies and rate them with the rubric by eye.

1. Build the TestFlight app against staging: GitHub in Safari, Actions, **iOS build**, Run workflow, tick
   **signed_build**, `coach_backend` = **staging**, `signing` = **cloud** (docs/qa/IPHONE_E2E_DEMO.md section 3).
2. TestFlight on the iPhone: install it, sign in to **Settings**, **App Store**, **Sandbox Account** with the tester,
   open DateWise, finish onboarding, **Subscribe** (free, Sandbox).
3. Open `owner-prompt-sheet.md` (89 scenarios that are one typed message; 15 of them are tier 1). Pick the coach named
   in the row, paste the message into the chat, send. Tick the box, note the reply.
4. Crisis scenarios need the right region: **Settings**, **General**, **Language & Region**, **Region** = United States,
   Canada, Mexico or Spain, then reopen the app (the app sends the country from the phone's region; the prompt then holds
   that country's numbers). I did not verify the region switch on a device.
5. Cannot be done this way: fake assistant history, the hidden-character and 6,500-character messages, the 300 KB body,
   and the exact profile (memory, country override). Those need Path A.

## 3. How many scenarios per day, and neurons

Numbers from `node tool/live/live_chat_test.mjs --list-battery` (the kit's own estimator: the Worker's token estimate
and Llama 3.3 70B prices, 300 output tokens a reply; real replies are often shorter, so the real spend is lower):

| | |
|---|---|
| Battery | **106 scenarios**: 105 reach the model, 1 (the 300 KB body) is refused before any model call. Plus the 21 base-plan scenarios if you also want them (30 admitted) |
| Per request | about **105 to 112 neurons** (about 1,600 to 1,900 input tokens, 300 output); worst case about 211 |
| Production Sandbox limit | **20 requests per day per Sandbox subscriber**, counted in UTC days; every admitted request counts, cancelled ones too. The preflight, a 403 or a 413 do not |
| Sandbox neuron slice | 6,000 a day (about 55 replies at 109; the config comment says about 42 with worst-case reservations) |
| Free allowance | 10,000 neurons a day for the whole account: staging and production share it |
| Tier 1 (must run) | 17 requests, about 1,810 neurons: **one day** |
| Tiers 1 and 2 | 77 scenarios, about 8,270 neurons |
| Everything | 105 requests, about **11,430 neurons** (worst case 22,200): more than one free day even without the request limit |

The kit splits by `--per-day 18` (20 minus two spare for a re-run): **18 scenarios a day**, about 1,950 neurons a day
(20% of the free allowance, a third of the slice). Day A is tier 1; the rest is 5 more days (90 and 15 requests).

## 4. Plans (options only; this change set alters no setting)

| Option | Days | What you do | Settings touched |
|---|---|---|---|
| **A. One tester, production limits** | **6 days** (tier 1 on day 1, then `--min-tier 2 --day 1..5`) | Fresh JWS each day | None |
| **B. Tier 1 and 2 only** | 5 days (or 1 + 4) | Skip tier 3 (`--tier 2`): 77 scenarios | None |
| **C. Two Sandbox testers, same UTC day** | **3 days** (36 a day, about 3,900 neurons, inside the 6,000 slice) | A second tester (own counter: the key is a hash of that subscription's originalTransactionId). Run `--day 1` with tester 1's JWS, then `--day 2` with tester 2's, and so on | None; use `--per-day 18` and two tokens a day. Do not use three: 54 requests is about 5,900 neurons, too close to the slice |
| **D. Larger limits on the staging Worker only** | **2 to 3 days** | A reviewed PR that changes **only** `[env.staging.vars]` in `backend/wrangler.toml`, for example `SANDBOX_DAILY_LIMIT` 40 (already), `SANDBOX_NEURON_BUDGET` 5000, `DAILY_NEURON_BUDGET` 5000, then `--per-day 38`: 38 + 35 + 32 requests, about 4,100 / 3,900 / 3,400 neurons, using at most half the free allowance. Delete staging afterwards (`wrangler delete --env staging`) | Staging only; the production `[vars]` block (limit 20, slice 6,000) stays as it is. `backend/staging_env.test.mjs` already pins the production values, so a PR that touched them would fail CI |
| E. Pay for Workers | not recommended | Needs your authorization (spending stays $0) | Account plan |

With the staging vars as they are today (limit 40, slice 3,000, daily 4,000) a day holds about 25 requests
(`--per-day 25`: 5 days), because the 3,000 slice is the first thing to run out. Option D with a bigger slice is what
shortens it. Whatever you pick, keep production's `SANDBOX_DAILY_LIMIT` and `SANDBOX_NEURON_BUDGET` as they are; the
Sandbox slice of 6,000 is documented as a temporary App Review window setting (set back to 1,000 after review), so check
that nothing else is using the Sandbox slice on the same day (App Review).

## 5. Still only the owner can do

Merge PR #55 and deploy staging; the Sandbox tester and the purchase; a Mac and iPhone for the debug build (Path A) or
the TestFlight build for Path B; setting `DW_TEST_JWS`; deciding between the options in section 4; the independent
grader's rating of the LIVE packet; teardown of the staging Worker.
