# DateWise AI 2.0.0: App Store release checklist

App: **DateWise AI - Dating Coach**, Apple ID `6780110141`, bundle id
`com.datewise.datewiseAi` (unchanged; v2 is an update, not a new app).
Version **2.0.0**, build **100** (`version: 2.0.0+100` in `pubspec.yaml`; CI
TestFlight builds are 101 and up, see Details step 19). Minimum iOS 15.

## Release checklist (single source of truth)

The short, ordered owner path to submission, with every App Store Connect
answer filled in, is [SUBMISSION_READY.md](SUBMISSION_READY.md). This list
keeps the full detail.

Status 2026-11-23: nothing is deployed, no build has been uploaded and nothing
has been submitted. Work through the groups in order (A, B and C can run in
parallel; D needs A and B; E needs D and a TestFlight build; F needs E).

Who does it:
- **Owner-only**: needs the owner's decision, approval, sign-in or spending
  authorization. No agent can do it.
- **Done in code**: already in this branch and covered by tests; nothing to
  do unless the owner changes the decision.
- **Agent, after owner**: an agent prepares it (PR or script run) once the
  owner step it depends on is done; the owner approves the result.

Numbers below are copied from `backend/wrangler.toml` and the linked docs.
Where two docs disagree, this list names the one that wins. Docs marked
"(PR #30)" are on branch `claude/datewise-model-eval` until that PR is merged.

[runbook]: ../launch/WORKER_DEPLOY_RUNBOOK.md
[cfsep]: ../launch/CLOUDFLARE_ACCOUNT_SEPARATION_PLAN.md
[v1]: ../launch/V1_TRANSITION_SUMMARY.md
[cost]: ../business/AI_COST_MODEL.md
[paid]: https://github.com/scubamike124/datewiseaiapp/blob/claude/datewise-model-eval/docs/business/WORKERS_PAID_EVALUATION.md
[models]: https://github.com/scubamike124/datewiseaiapp/blob/claude/datewise-model-eval/docs/business/MODEL_COMPARISON.md
[resil]: ../qa/SUBSCRIPTION_RESILIENCE.md
[sandbox]: ../qa/STOREKIT_SANDBOX_TEST_PLAN.md
[assn]: ASSN_SETUP.md
[meta]: metadata.md
[prov]: ../legal/ASSET_PROVENANCE.md
[handoff]: ../review/FINAL_REVIEW_HANDOFF.md
[avatar]: ../avatar/TALKING_AVATARS.md
[avtool]: ../../tool/avatar/README.md
[bakeoff]: ../avatar/PAID_PROVIDER_BAKEOFF.md
[live]: ../qa/LIVE_AI_TEST_PLAN.md
[demo]: ../qa/IPHONE_E2E_DEMO.md

### A. Owner decisions

| # | Decision | Who | Why | Detail |
|---|---|---|---|---|
| A1 | **Final price.** Configured: one plan, `datewise_premium_monthly`, **$9.99/month** (StoreKit file, metadata, sandbox plan). Proposed: **$19.99/month** (configured nowhere). If $19.99 is chosen, set it in App Store Connect and update `ios/Runner/DateWise.storekit`, [metadata.md][meta] §5 and the expected price in [sandbox test][sandbox] P1 in one reviewed PR; set Mexico and Spain prices by hand. The app and legal text show StoreKit's price string, so no other text changes | Owner-only | The price fixes the margin and the fair-use allowance the business can carry | [cost] §5–6, [paid] §4 (PR #30), [resil] §1 |
| A2 | **Chat model:** Llama 3.3 70B fp8-fast (current) or Gemma 4 26B, chosen after the live comparison (needs B5). Change the model, `DAILY_NEURON_BUDGET` and `SANDBOX_NEURON_BUDGET` in the same deploy | Owner-only | Budgets are in neurons: a typical message is about 115 neurons on Llama and about 26 on Gemma, so a budget sized for one model is wrong for the other | [models] §7 (PR #30) |
| A3 | **Workers Paid and `DAILY_NEURON_BUDGET`.** Today: Workers Free, `DAILY_NEURON_BUDGET = "10000"` ($0), about 87 typical Llama messages a day for the whole service (about 378 on Gemma). Workers Paid is **$5 a month** plus $0.011 per 1,000 neurons above the free 10,000 a day, with **no hard spending cap**, so the budget is the cap. Suggested start on Paid while v1 is still served: **Llama 285,000 / Gemma 70,000** at 100 subscribers (1,245,000 / 290,000 at 500; 2,440,000 / 565,000 at 1,000; 12,020,000 / 2,765,000 at 5,000), ASSUMPTION derived from MEASURED prices. Then `MONTHLY_NEURON_BUDGET` at about 30 x the average day | Owner-only (spending) | 10,000 neurons a day is too little for App Review plus launch traffic; the handoff asks for this decision before App Review | [paid] §2–5 (PR #30; [cfsep] §6.2 and [cost] §7 use the same figures) |
| A4 | **`SANDBOX_NEURON_BUDGET` for App Review.** `wrangler.toml` sets **1,000** (10% of 10,000). On Workers Paid: at least **35,000** on Llama or **10,000** on Gemma. On Workers Free, 1,000 fits only about 7 typical Llama Sandbox messages a day (about 37 on Gemma), fewer than one reviewer's `SANDBOX_DAILY_LIMIT` of 20. **Recommendation on Workers Free (pre-launch):** set `SANDBOX_NEURON_BUDGET = "6000"` for the App Review window (about 50 typical Llama replies a day, 6,000 / 115, and at least 18 even at the worst-case request size; about 230 on Gemma), then lower it back to **1,000** after approval. Before launch there are no v2 Production subscribers, so Sandbox can take most of the 10,000. How the slices combine (`backend/cost_guard.js`, `budget()`): every request counts against `DAILY_NEURON_BUDGET`; Sandbox requests are also capped by `SANDBOX_NEURON_BUDGET` and token-less v1 requests by `ANON_NEURON_BUDGET` (2,000). The slices are ceilings, not reservations, so 6,000 + 2,000 = 8,000 leaves at least 2,000 of the 10,000 that only Production subscribers can use, and v1 traffic cannot eat into the Sandbox slice. Production traffic has no cap of its own and could still use the Sandbox's room, which is why the large slice is only for the pre-launch window. This is an owner deploy-time setting: `wrangler.toml` keeps 1,000 until the owner changes it in the D1 PR | Owner-only | A refused reply during App Review reads as a broken app; the slice also keeps TestFlight from draining subscribers' budget | [paid] §5 (PR #30), [cost] §7, `backend/wrangler.toml`, `backend/cost_guard.js` |
| A5 | **App Store Server Notifications on.** Code done and tested; `ASSN_ENABLED = "0"` until the URLs are set (B16), then `"1"` in a reviewed PR and a redeploy (D5) | Owner-only | Refunds and revocations take effect at once, Apple's grace period is followed, and a renewal that has not reached the device does not lock a subscriber out. Chat works without it | [assn], [resil] §3 |
| A6 | **Fail-open stays off.** `FAIL_OPEN_PER_SUBSCRIBER = FAIL_OPEN_PER_ISOLATE = "0"` and `FAILOPEN_LIMITER` commented out. If the owner ever opts in: 3 / 10 and the `FAILOPEN_LIMITER` binding with its own namespace_id | Done in code | Failing open removes the budget breaker; leave it off until logs show Durable Object outages actually happen | [resil] §4 (L6) |
| A7 | **`LEGACY_CLIENTS` timeline** (now `"0"` in `wrangler.toml` production, with `REQUIRE_SUBSCRIPTION = "1"` and no anonymous budget: the owner chose full enforcement on 2026-11-23 because the live chat-v5 Worker had no subscription check; takes effect at the next approved production deploy). Before that decision: Separate account (B6): the new v2-only Worker sets `LEGACY_CLIENTS = "0"` and `ANON_NEURON_BUDGET = "0"` from day one; the old Worker keeps chat-v6 for v1 until R+90 days (then a no-AI "please update" responder) and is deleted at R+180. Same account: keep `"1"` for **60 to 90 days** after v2 ships, then `"0"`. If App Store Connect version history shows 1.0.2 never shipped, `"0"` at launch | Owner-only | Anyone can pose as v1, so the token-less path is an anonymous allowance (`ANON_NEURON_BUDGET` 2,000 a day); retiring it stops that and cuts the budget needed by about 20% | [resil] §2, [v1], [cfsep] §3.3 |
| A8 | **Paid avatar provider bake-off** (Simli and Anam free tiers; LiveAvatar and Tavus optional). Approve or decline: free accounts (no card), uploading the four approved portraits, then vendor, plan and privacy changes | Owner-only | Not needed for 2.0: the on-device avatar costs $0 and sends nothing out. A paid vendor costs per minute and receives the coach's reply audio | [bakeoff] |
| A9 | **Minimum iOS stays 15.** iOS 12–14 users keep the last v1 build their device supports (see B20) | Done in code | Xcode 26 (required for uploads since 2026-04-28) and Flutter 3.47 both set iOS 15 as the floor, and StoreKit 2 (the subscription check) needs iOS 15. Every iPhone that runs iOS 13/14 can install iOS 15 (to be checked against Apple's list before public text) | [v1] |

### B. Owner accounts and settings

**GitHub**

| # | Item | Who | Why | Detail |
|---|---|---|---|---|
| B1 | **Protect `main`**: branch ruleset "protect main" (no deletions, no force pushes, PR with 1 approving review, stale approvals dismissed; optional Backend tests check) | Owner-only | The deploy workflow trusts "on `main`" as "reviewed"; without this the check means nothing | [runbook] 1f |
| B2 | **Tag ruleset** "worker deploy tags" for `worker-v*` (restrict creation, update, deletion; bypass: admin only) | Owner-only | A tag push runs the workflow file at the tagged commit | [runbook] 1e |
| B3 | **Environment `production-worker`**: required reviewer = you; deployment branches and tags = `main` and `worker-v*` only | Owner-only | Every real deploy then waits for your click | [runbook] 1c |
| B4 | **Environment secrets** (in `production-worker` only, never repository level): `CLOUDFLARE_API_TOKEN` (B7), `CLOUDFLARE_ACCOUNT_ID`, `ID_HASH_SALT` (B8). Optional repository variable `WORKER_URL` | Owner-only | Repository secrets reach every job; the workflow's first step fails if any of the three exists at repository level | [runbook] 1d |
| B5 | **Model-eval repository secrets** `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_AI_TOKEN` (Workers AI Read and Edit), then start part 1 and part 2 on different UTC days (`[run-eval part=1]` commit). **Delete both repository secrets after the eval and before any deploy run (D2)**: a repository-level `CLOUDFLARE_ACCOUNT_ID` makes the deploy workflow fail | Owner-only | A2 needs real results; a full run is about 4,800 neurons, so splitting it keeps each day inside the free 10,000 | [models] §4–5 (PR #30), [runbook] 1d |

**Cloudflare**

| # | Item | Who | Why | Detail |
|---|---|---|---|---|
| B6 | **Separate DateWise account** (free plan) and register its workers.dev subdomain before the first deploy. Then the app's backend URL must change (D7) | Owner-only | The Workers AI allowance and bill are per account; today other projects can use up DateWise's 10,000 neurons and cause HTTP 502s | [cfsep] §1–3, [runbook] 1a |
| B7 | **API token**: Account > Workers Scripts > Edit, scoped to the DateWise account only, no zone permissions, with an expiry date | Owner-only | Least privilege for the one deploy path | [runbook] 1b, [cfsep] §4.1 |
| B8 | **`ID_HASH_SALT`**: `openssl rand -hex 32`, kept in your password manager; as the environment secret for the first deploy on a new account, or set on the Worker in the dashboard | Owner-only | Counters and the revoked list are keyed by salted hashes; without it a public default salt is used. Rotating it resets every counter | [runbook] 1d |
| B9 | **Unique rate-limit namespace**: `RATE_LIMITER` uses `namespace_id = "740219"`. On a fresh account it is unique; on the shared account check no other Worker uses it | Owner-only | Bindings that share a namespace share counters across Workers | `backend/wrangler.toml`, [runbook] 1a |
| B10 | **`AMBER_CF_MAX_SHARE` on Amber** while DateWise still shares the account: a fraction from 0 to 1 of the account's free daily neurons that Amber may use (unset = no cap; below about 0.22 Amber has no room for a coding run). Not needed once B6 is done | Owner-only | DateWise's `DAILY_NEURON_BUDGET` cannot see other projects' use of the same allowance | Amber's own repository; [cfsep] §1 |

**Apple (App Store Connect and developer.apple.com)**

| # | Item | Who | Why | Detail |
|---|---|---|---|---|
| B11 | **Paid Apps Agreement** accepted | Owner-only | A subscription cannot be approved or sold without it | Details step 2 |
| B12 | **Tax forms and banking** complete, all showing Active / Clear | Owner-only | Same | Details steps 3–5 |
| B13 | **Check existing IAPs**: list every product id and status before creating anything | Owner-only | Ids can never be reused, and a sold product's subscribers do not move to a new id | [resil] §5, Details step 11a |
| B14 | **Create `datewise_premium_monthly`** in group DateWise Premium (1 month, the A1 price, no introductory offer, EN + ES), plus its review screenshot | Owner-only | The app and the Worker accept only this product id | [meta] §5, Details steps 12–14 |
| B15 | **Billing Grace Period OFF** | Owner-only | Matches `BILLING_GRACE_DAYS = "0"` (done in code); a mismatch locks out subscribers in grace unless ASSN is on | Details step 12a |
| B16 | **ASSN URLs**: Production and Sandbox both `https://<worker-host>/apple/notifications`, Version 2, at the chat-v7 host (the new account's host after B6), set after D3 | Owner-only | Needed for A5; never point them at the old Worker | [assn] steps 1–8 |
| B17 | **Small Business Program** enrolment | Owner-only | 15% commission instead of 30% in a subscriber's first year | [cost] §2 |
| B18 | **The 7 signing secrets** for the `signed-testflight` job (`IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`), with the distribution certificate and profile. Not needed if you upload from a Mac | Owner-only | CI cannot sign or upload without them | Details §5–6 |
| B19 | **Users and Access review**: remove people who should not have access (including any former developer); create two Sandbox testers (US region) | Owner-only | The app record and its payment settings must be controlled by the owner; the sandbox plan needs two testers | [sandbox] §0, [handoff] §8 |
| B20 | **Last-Compatible Version Settings** (Pricing and Availability): choose which v1 build stays downloadable for iOS 12–14; if 1.0.2 is live, consider unticking 1.0 | Owner-only | Old-iOS users get the last compatible build; 1.0 calls a backend the owner does not operate | [v1] |

**Domain**

| # | Item | Who | Why | Detail |
|---|---|---|---|---|
| B21 | **Confirm ownership of `datewiseai.com`**: GoDaddy DNS and Microsoft 365 mail. Decide the API host: option A (new workers.dev URL, default for 2.0) or B (move DNS to Cloudflare and use `api.datewiseai.com`, copying every MX, autodiscover, SPF, DMARC and DKIM record first) | Owner-only | A stable host avoids an app update at the next move; a DNS move done wrong breaks support mail | [cfsep] §3.2 |
| B22 | **Legal and support URLs live**: legal approval of the v2 Privacy Policy and Terms, published at `https://datewiseai.com/privacy-policy` and `/terms-of-service` (via `web/.htaccess` on the `datewiseai.com` host or `web/_redirects` on Netlify; the GitHub Pages workflow cannot serve these clean URLs, see [meta] §1); a Support URL; `support@datewiseai.com` receives mail | Owner-only | The app opens these URLs, and Apple requires working privacy, EULA and support links for subscriptions | Details steps 6–9 |

### C. Assets

| # | Item | Who | Why | Detail |
|---|---|---|---|---|
| C1 | **The 8 final portraits**: `{ava,ethan,sofia,diego}-{hero,avatar}.jpg`, hero portrait at least 1024×1400, avatar at least 1024 on the short side, and each meeting the portrait requirements below | Owner-only | The current eight are interim (landscape, hero = avatar, Ava and Sofía look alike) and fail the size rules | [prov] |
| C2 | **Provenance**: generation date(s), the account used, the original files, and your approval date | Owner-only | Apple can ask; the record must show the faces are illustrations, not real people | [prov] |
| C3 | **Run `portrait_intake`** (identity, size and pair-distance check; kept outside the repository), then re-check `heroFocus` / `avatarFocus` in `lib/models/coach.dart` | Agent, after owner | Catches swapped or too-similar faces before anything is generated from them | [prov] |
| C4 | **Run `tool/avatar/regenerate.sh`** (all four coaches), then `flutter test test/avatar_widget_test.dart`, and review the sheets in `build/avatar-review/` | Agent, after owner | Avatar frames are cut from the portrait; a new portrait without new frames falls back to a still image (a same-size replacement is not detected) | [avtool] |
| C5 | **Regenerate the screenshots** (`tool/appstore_screenshots/generate.sh`): iPhone 6.9" and 6.5" and iPad 13" (2064x2752), EN and ES; the owner reviews every image | Agent, after owner | The store images must show the final faces; the iPad set is required because the app supports iPad | Details step 11, [meta] §7 |

**Portrait requirements** (each of the 8 files):
- relaxed face, lips closed or slightly parted, **no teeth showing**;
- facing the camera within **10°**, head level;
- nothing near the mouth or chin (no hand, collar, hair or microphone);
- at least **1024 px across the face**, with sharp lips;
- a plain background;
- deliberately different looks within each same-language pair, **Ava vs Sofía** and **Ethan vs Diego** (hair, wardrobe, accessories, background; cross-coach similarity below 0.5 in the intake check).

### D. Deploy sequence (chat-v7)

chat-v7 is deployed **only** through the reviewed workflow
(`.github/workflows/deploy-worker.yml`, see [runbook]). A single-file
redeploy tool, such as an owner-internal redeploy tool outside this repo,
cannot deploy it ([handoff] §8 and [cost] §9 say the same).

| # | Step | Who | Why | Detail |
|---|---|---|---|---|
| D0 | **v1 stop-gap**: deploy chat-v6 (`f5b0401`) to the old Worker on the shared account | Owner-only | Fixes 1.0.2's HTTP 502 (production runs chat-v5 on a retired model) | [runbook] §7, [v1] |
| D1 | **`wrangler.toml` values PR** for the decisions in A2–A7 (and the new account per [cfsep] §4.3), then **merge v2 to `main` through a reviewed PR** (#27) | Owner-only (approve and merge) | The workflow deploys only code that is on a protected `main` (B1) | [runbook] "Consequences" |
| D2 | **Dry run**: tag `worker-v7-<date>` or dispatch with `dry_run` on. Check the SHA in the summary, tests pass, and the binding list shows `AI`, `USAGE_GUARD (UsageGuard)`, `RATE_LIMITER` | Owner-only | Proves the bundle and bindings before anything changes | [runbook] §2–3 |
| D3 | **Deploy with approval**: tag `worker-v7-<date>-deploy` or `dry_run` off, then approve in `production-worker`. Note the "Previous version id". On a new account, open `https://<worker-url>/?agree=1` once (Llama licence) | Owner-only | The approval gate is the last human check | [runbook] §4, 1a |
| D4 | **Post-deploy checks**: `?version` = `chat-v7-cost-guard`; a token-less `POST /` returns 403 `SUBSCRIPTION_REQUIRED`; then one real v2 chat from TestFlight returns `x-datewise-*` headers (the first real use of the Durable Object) | Owner-only | The 403 check does not prove the Durable Object; only a real chat does | [runbook] §4 step 7, §5 |
| D5 | **Turn on ASSN**: B16, then `ASSN_ENABLED = "1"` (reviewed PR, redeploy); a Sandbox purchase logs `kind: assn` `SUBSCRIBED` | Owner-only | A5 | [assn] |
| D6 | **Rollback if needed**: `npx wrangler@4.158.0 rollback <version-id>` or the dashboard; secrets survive | Owner-only | Return to the previous version in minutes | [runbook] §6 |
| D8 | **Staging Worker for the live AI test** (after D1, independent of D2–D7): confirm rate-limit namespace `740221` is unused on the account, then dispatch target `chat-v7-staging` (dry run, then `dry_run` off) and approve in `production-worker`. It deploys only `datewise-coach-staging` (`wrangler deploy --env staging`) and checks `?version` and 403 `SUBSCRIPTION_REQUIRED`. Same security as production (verified StoreKit JWS, Sandbox allowed, v1 and ASSN off), test-sized limits (`SANDBOX_DAILY_LIMIT` 40, `SANDBOX_NEURON_BUDGET` 3000, `DAILY_NEURON_BUDGET` 4000). **No production variable changes, nothing to restore.** Tear down after E6: `cd backend && npx wrangler@4.158.0 delete --env staging`. Cost $0 (free allowance) | Owner-only | The 36-request live test needs more Sandbox room than production's 20 a day / 1,000 neurons, without touching production | [runbook] §9, [live] §1 |
| D7 | **App backend URL PR** to the new Worker (`lib/services/ai_config.dart` `productionUrl`, `test/backend_chat_test.dart`, `scripts/production-e2e-probe.mjs`) before the build used for submission | Agent, after owner | The URL is compiled into the app; until then use `--dart-define=COACH_BACKEND_URL=…` on test builds | [cfsep] §3.1 |

### E. Device testing (BLOCKED until TestFlight)

Nothing here has run: it needs a signed build on TestFlight (Details steps
19–21) and chat-v7 live (D3). The scripted live AI test (E6, first part) needs
only the staging Worker (D8) and a Sandbox token from a debug build.

| # | Test | Who | Why | Detail |
|---|---|---|---|---|
| E1 | **StoreKit Sandbox test plan** P1–X4 (purchase, restore, renewal, expiry, refund, billing retry, grace). A FAIL in P1, R1, N1, E1, F1 or B1 blocks submission | Owner-only | Subscription bugs are the most likely rejection and the most costly lockout | [sandbox] |
| E2 | **Voice and speech-to-text in EN and ES** (hold to talk, timeout, a transcript during a streaming reply) | Owner-only | On-device recognition cannot be tested in CI | Details step 22 |
| E3 | **Permission prompts** for microphone and speech recognition, EN and ES; the denied path offers Open Settings | Owner-only | App Review checks the purpose strings and the denied path | Details step 22 |
| E4 | **Avatar word timing per voice tier**: default, Enhanced and Premium voices; native audio path on iOS 15/16 (loudness only) and iOS 17+ (word markers), and the fallback; tune A/V sync | Owner-only | Lip sync was measured only on a host, never on an iPhone | [avatar] "Blocked / to do" |
| E5 | **Frame time and memory** in a profile build on the voice stage | Owner-only | Must not drop frames or grow memory on older iPhones | [avatar](../avatar/TALKING_AVATARS.md) |
| E7 | **Avatar native audio path** (only if it should ship): run `iOS build` by hand with `signed_build`, `upload_testflight` and `avatar_audio_path` ticked. That build is marked "AVATAR AUDIO-PATH TEST BUILD" in the run summary and gets a build number 5000 higher (e.g. 5150 instead of 150): **never submit a 5000+ build for review**. Upload the App Store build of a version before any 5000+ test build of that same version (or give test builds their own version, e.g. 2.0.1), because App Store Connect can reject a lower build number after a higher one; the ranges would also overlap once run numbers pass about 4,900. Test playback, ducking and release, a call/Siri interruption, unplugging headphones, backgrounding, and the fallback. Release builds keep the flag off (flutter_tts path) until this passes | Owner-only | The native path cannot be tested off-device | [avatar](../avatar/TALKING_AVATARS.md) |
| E8 | **iPhone end-to-end demo** (after D8): run `iOS build` by hand with `signed_build`, `upload_testflight` and `coach_backend` = **`staging`**; speak to a coach, the staging Worker's real AI replies, the avatar speaks it back. The build points at `https://datewise-coach-staging.scubamike124.workers.dev`, is marked "STAGING COACH BUILD" and gets a build number 50000 higher (e.g. 50150): **never submit a 50000+ build for review**. Pass/fail checklist, recording and teardown in [demo] | Owner-only | First proof of the whole chain (speech, StoreKit JWS, live AI, voice, mouth sync) on hardware | [demo] |
| E6 | **Live AI tests for the four coaches** (Ava, Ethan, Sofía, Diego) in EN and ES. (a) The scripted 36-request test (`tool/live/live_chat_test.mjs --mode live`) against the **staging Worker** URL from D8 (`https://datewise-coach-staging.<subdomain>.workers.dev`), with a Sandbox token in `DW_TEST_JWS`: replies, language, limits, streaming, usage headers. No production var changes; the kit refuses the production URL. Then tear down staging (D8). (b) On a TestFlight build against production (after D3): onboarding and the 18+ gate, limit notices, Delete my data, and the iPad layout | Owner-only | The model has not been called from a v2 build yet | [live], Details step 22, [models] (PR #30) |

### F. Submission

| # | Item | Who | Why | Detail |
|---|---|---|---|---|
| F1 | **Metadata** EN + ES (name, subtitle, promotional text, keywords, description with the Terms link), category Lifestyle, age rating 18+ | Owner-only | Must match the build and the subscription | [meta] §1–2, Details steps 24–25 |
| F2 | **Screenshots** per language: iPhone 6.9" (6.5" optional) and **iPad 13"** (from C5); the subscription review screenshot of the paywall with the real price | Owner-only | The iPad set is required; the IAP needs its own screenshot | [meta] §5, §7 |
| F3 | **App Privacy answers** exactly as in [meta] §3 (including the ASSN renewal/grace state) and matching the published privacy policy | Owner-only | A mismatch is a rejection reason | [meta] §3 |
| F4 | **Review notes** from [SUBMISSION_READY.md](SUBMISSION_READY.md) step 14: no sign-in, test with a Sandbox Apple Account; fair use **150 replies a day, 1,500 a month, 12 a minute, 2 at a time; Sandbox 20 a day**; contact details. Update them if A1 or the limits change | Owner-only | The reviewer needs to reach chat, and the limits must be disclosed | [meta] §4, `backend/wrangler.toml` |
| F5 | **What's New** (EN + ES) asking users to update to keep using the coach | Owner-only | v1 users are moved to v2 | [meta] §1, [v1] |
| F6 | **Select the build, attach `datewise_premium_monthly`, manual release with a 7-day phased release, Submit for Review** | Owner-only | The subscription is submitted together with 2.0.0 | Details steps 26–28 |
| F7 | **After approval**: release, a real production purchase, 1.0.2 users update cleanly; check App Analytics at R+30 | Owner-only | Confirms production before the phased release widens | Details step 29, [v1] |

**Count:** 54 Owner-only items, 2 Done in code (A6, A9), 4 Agent, after owner (C3, C4, C5, D7).

---

## Details (step-by-step)

The numbered steps below are the step-by-step instructions the table links
to. Where they differ from the table above, the table wins.

## 1. Accounts and agreements (once)

1. Apple Developer Program membership is active (annual fee already paid for
   the live app; no new spending in this plan).
2. App Store Connect › Business: accept the latest **Paid Apps Agreement**.
   Subscriptions cannot be sold, or even approved, until it is active.
3. Business › **Tax forms** (W-9 for a U.S. entity, or W-8BEN/-E) completed.
4. Business › **Banking**: bank account added and verified.
5. Wait until all three show "Active" / "Clear".

## 2. Legal approval

6. Have the v2 **Privacy Policy** and **Terms of Use** reviewed and approved,
   and publish them at the URLs the app opens (`lib/app_links.dart`):
   `https://datewiseai.com/privacy-policy`, `https://datewiseai.com/terms-of-service`.
   The privacy policy must match the App Privacy answers in `metadata.md` §3.
7. Choose the **Support URL** (a live page with a way to contact you, e.g.
   showing support@datewiseai.com) and confirm the support mailbox works.
8. Confirm the copyright holder name for the store listing.
9. Confirm the Terms of Use link is in the App Store description (Apple
   requires a functional EULA link for subscriptions; the standard Apple EULA
   is acceptable if you prefer it: then link
   `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`).

## 3. Final content

10. Replace the interim **coach portraits** in `assets/coaches/` (same file
    names) with the 8 finals that meet the portrait requirements (table C1),
    then run the intake check and `tool/avatar/regenerate.sh` (C3, C4). Keep a record of the licence /
    consent for each face (Apple can ask; the portraits must not be real
    people presented as the coaches without consent). The record lives in
    `docs/legal/ASSET_PROVENANCE.md`; update it with the finals.
11. Regenerate the screenshots (one command, needs Flutter, Python 3, Node):
    ```bash
    (cd tool/appstore_screenshots && npm install && npx playwright install chromium)
    tool/appstore_screenshots/generate.sh   # builds web, writes every set to docs/appstore/screenshots/
    tool/appstore_screenshots/generate.sh --skip-build --sizes ipad-13   # only the iPad 13" set
    ```
    It writes iPhone 6.9" (1320x2868), iPhone 6.5" (1284x2778) and iPad 13"
    (2064x2752) sets in English and Spanish. Review every image. Apple
    requires the iPad set because the app supports iPad
    (`TARGETED_DEVICE_FAMILY = 1,2`; removing iPad support from an app that
    already shipped on iPad is not allowed).

## 4. App Store Connect: subscription product

11a. **Before creating anything:** Monetization › Subscriptions and In-App
    Purchases. Write down every existing product id and its status. If one was
    ever approved and sold, stop and follow `docs/qa/SUBSCRIPTION_RESILIENCE.md`
    §5 (its subscribers do not move to a new id). Product ids can never be reused.
12. Monetization › Subscriptions › create group **DateWise Premium**, then the
    subscription `datewise_premium_monthly` exactly as in `metadata.md` §5
    (1 month, the price chosen in A1 (configured: USD 9.99), no introductory
    offer, EN + ES localizations).
13. Add the subscription **review screenshot** (paywall from a TestFlight or
    simulator build showing the real price).
12a. **Billing Grace Period: keep it OFF** (Monetization › Subscriptions ›
    Billing Grace Period). The coach backend matches it with
    `BILLING_GRACE_DAYS = "0"` in `backend/wrangler.toml`, so chat stops when a
    renewal fails (Apple keeps retrying the payment; chat resumes once it
    succeeds). If you turn grace on, set `BILLING_GRACE_DAYS` to the same
    number of days (3, 16 or 28) and redeploy the Worker before release, or
    subscribers in grace would be refused.
13a. **App Store Server Notifications (on for launch, decision A5):** App Information › App
    Store Server Notifications › Production and Sandbox Server URL =
    `https://<worker-host>/apple/notifications`, Version 2, then
    `ASSN_ENABLED = "1"` (`docs/appstore/ASSN_SETUP.md`). With it, refunds take
    effect at once and Apple's grace period is followed even if
    `BILLING_GRACE_DAYS` is not matched.
14. Status should become "Ready to Submit". It is submitted together with the
    2.0.0 version (step 26), not on its own.
15. Create two **Sandbox Apple Accounts** (Users and Access › Sandbox, region
    United States); the sandbox test plan (E1) needs both.

## 5. Certificates, identifiers and profiles (developer.apple.com)

16. Identifiers › `com.datewise.datewiseAi`: no extra capabilities are needed
    (In-App Purchase is enabled by default; no Push, no Sign in with Apple,
    no App Groups).
17. Certificates › an **Apple Distribution** certificate (reuse the one used
    for 1.0.2 if it is still valid).
18. Profiles › an **App Store Connect** distribution provisioning profile for
    `com.datewise.datewiseAi` with that certificate.

## 6. Optional: CI signing secrets (only for the TestFlight job)

The `iOS build` workflow's default job needs no secrets. The manual
`signed-testflight` job does nothing until **all** of these repository secrets
exist (GitHub › Settings › Secrets and variables › Actions):

| Secret | What to put in it |
|--|--|
| `IOS_DIST_CERT_P12_BASE64` | Apple Distribution certificate + private key exported from Keychain as .p12, then `base64 -i dist.p12` |
| `IOS_DIST_CERT_PASSWORD` | The password chosen when exporting the .p12 |
| `IOS_PROVISIONING_PROFILE_BASE64` | The App Store provisioning profile: `base64 -i DateWise_AppStore.mobileprovision` |
| `APPLE_TEAM_ID` | The 10-character Team ID (Membership details) |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID of an App Store Connect API key (Users and Access › Integrations › App Store Connect API; role App Manager is enough) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID shown on the same page |
| `APP_STORE_CONNECT_API_KEY_P8` | Full text of the downloaded `AuthKey_XXXX.p8` file |

**No computer? Use `signing: cloud`.** With the workflow's `signing` input
set to `cloud`, only the last four secrets are needed (`APPLE_TEAM_ID` and the
three `APP_STORE_CONNECT_*`), and the API key must have the **Admin** role.
Xcode then signs with a cloud-managed distribution certificate; no `.p12` or
profile is made. iPhone-only steps: docs/qa/IPHONE_E2E_DEMO.md section 2.1.
`manual` (the default) still needs all seven.

Then: Actions › iOS build › Run workflow › tick **signed_build** (and
**upload_testflight** to upload). Note: "Run workflow" only appears once
`ios-build.yml` is on the default branch. GitHub-hosted runners, macOS
included, are free on this public repository; no paid service is used. The
job fails visibly if a signing secret is missing, and sets the build number
to 100 + the run number so each upload is unique.

## 7. Build and upload (pick one)

19. Build numbers: `pubspec.yaml` is `version: 2.0.0+100`, and the CI
    TestFlight job uses 100 + the run number (101, 102, ...), so a manual
    upload of the pubspec build (100) never collides with a CI build. For a
    second manual upload, pass a number above the highest build already in
    App Store Connect: `flutter build ipa --build-number=<N>`. App Store
    Connect rejects a repeated number; it never overwrites a build.
20. **On a Mac:** `flutter pub get && flutter build ipa --release`, then
    upload `build/ios/ipa/*.ipa` with the Transporter app or Xcode Organizer.
    **Or CI:** run the signed-testflight job (step 6). It uploads with
    `xcrun altool --upload-package` and the App Store Connect API key
    (the older `--upload-app` command is deprecated). **BLOCKED (not verified
    here):** this upload step has never run; it needs a Mac runner with the
    secrets. On the first run, check that the build appears in TestFlight; if
    altool fails, upload the job's IPA artifact with Transporter instead.
21. Wait for processing; answer nothing for export compliance (the Info.plist
    already declares HTTPS-only encryption).

## 8. Test before submitting

22. Install from **TestFlight** on an iPhone (table group E). Check: onboarding and 18+ gate,
    sandbox purchase, restore, chat replies from the live backend (the coach
    backend must be up: see `docs/launch/LAUNCH_READINESS.md`), voice
    permission prompts in English and Spanish, Delete my data.
23. Local StoreKit testing in Xcode (no sandbox account needed): open
    `ios/Runner.xcworkspace`, Product › Scheme › Edit Scheme › Run › Options ›
    **StoreKit Configuration** › choose `DateWise.storekit`. Run on a
    simulator; purchases use the local file (USD 9.99, monthly). Set it back
    to "None" before archiving if you prefer (it does not affect archives).
    This covers the **purchase UI only** (paywall, buy, restore, locked and
    unlocked states). Chat does not work with it: local StoreKit
    transactions have the environment "Xcode" and are not signed by Apple, so
    the coach backend refuses them (403 `SUBSCRIPTION_INVALID`). Test chat
    with a **Sandbox** Apple Account on a device or through **TestFlight**
    (step 22); Sandbox purchases get 20 replies a day.

## 9. Store listing and submit

24. Version 2.0.0 page: paste metadata (EN + ES) from `metadata.md` §1,
    upload screenshots for each language: `6.9` (iPhone 6.9"), optionally
    `6.5`, and `ipad-13` (iPad 13" display).
25. App Information: category Lifestyle, age rating questionnaire (§2, target
    18+), App Privacy answers (§3), privacy policy URL.
26. Version page: select build 2.0.0 (100, or the CI build you tested in
    TestFlight); under "In-App Purchases and
    Subscriptions" add `datewise_premium_monthly`; App Review Information:
    contact details and the review notes (§4); sign-in not required.
27. Choose release: manual release after approval, with a 7-day phased
    release.
28. **Submit for Review** (owner only).
29. After approval: release, then confirm a real purchase works in
    production and that the 1.0.2 users update cleanly.
