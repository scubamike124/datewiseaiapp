# DateWise AI v2: handoff for independent review

Status as of 2026-11-23. Read this before reviewing PR #27. Where this handoff and the release checklist at the top of `docs/appstore/checklist.md` differ, the checklist wins.

Only PASS results that were actually run are reported as PASS. Anything that needs a physical iPhone, Apple credentials, a signed build or the live backend is marked **BLOCKED**, because it has not been tested.

## 0. Final state (2026-11-23, end of the 8-hour completion session)

This section supersedes the older figures below; the earlier sections are kept as history.

| | |
|---|---|
| Release candidate | PR #27 `claude/datewise-v2-app`, head `7fed09c` (draft, not merged, nothing deployed). Price: $19.99/month (owner decision, 2026-11-23; was $9.99). |
| Merged in (squashed, each independently reviewed YES) | #31 subscription resilience (ASSN v2, opt-in bounded fail-open, lockout fixes, v1 forced-update reply); #32 protected wrangler deploy workflow; #33 on-device talking avatars; QA-sweep and regression fixes; the live AI test kit (`tool/live/`) |
| Open drafts | #30 Llama vs Gemma model comparison + Workers Paid evaluation (live run BLOCKED on credentials) |
| Tests (local, at 01754b7 + 7fed09c) | `flutter analyze lib test tool`: 0 issues. `flutter test`: 871 passed. `node --test backend/*.test.mjs tool/live/*.test.mjs`: 96 passed. |
| CI | Tests, Backend tests and the unsigned iOS release build (compiles the native avatar audio Swift) green on every pushed head, latest verified [01754b7](https://github.com/scubamike124/datewiseaiapp/actions/runs/45148929312) |
| Final reviews | Code/security/functional: YES (fba0f6a, then deltas to 01754b7). Design: YES 9/10 (1500269). Debug token export: YES (cannot ship in release; no leak via logs, crash paths or reports). Regression QA: 274 interactive checks, 116 screen captures, 144 layout cases; one HIGH defect found (Undo could restore data deleted by a bulk delete) and fixed, reviewed YES. |
| Talking avatars | On-device, $0, no provider sees conversations. App Store default = flutter_tts word-anchored lip sync (visual review 5/10 on interim portraits; acceptable as "animated coach" with final neutral-lip portraits). Native audio path (loudness-driven jaw, 6/10) is TestFlight-only behind `DW_AVATAR_AUDIO_PATH` until a device test passes. Neither meets "realistic"; that needs the paid provider bake-off (`docs/avatar/PAID_PROVIDER_BAKEOFF.md`, owner approval). No avatar claims in store copy until device-verified. |
| LIVE AI | **BLOCKED.** Production still serves chat-v5 (HTTP 502). The 36-request live kit has only run SIMULATED (`docs/qa/LIVE_AI_TEST_SIMULATED_SAMPLE.md`: 36 requests, 0 failing checks). A live run needs the isolated staging Worker `datewise-coach-staging` deployed through the protected workflow (checklist D8; no production changes) and an Apple Sandbox JWS, see `docs/qa/LIVE_AI_TEST_PLAN.md`. Estimated live cost about 2,497 neurons (free allowance). |
| Device tests | **BLOCKED** (TestFlight): purchases, restore, refunds, voice/STT EN and ES, avatar timing per voice tier, frame time and memory. |
| Owner actions | The single list is the release checklist at the top of `docs/appstore/checklist.md`. |

## 1. What to review

| | |
|---|---|
| Main PR | #27 `claude/datewise-v2-app`. Draft, not merged, nothing deployed. |
| Reviewed head | `b081c27` (only this file is newer) |
| Merged into it | the PR #29 cost guard (chat-v7-cost-guard); the QA test branches `claude/datewise-qa-ai` and `claude/datewise-qa-store` |
| Separate draft PR | #30 `claude/datewise-model-eval`: model comparison tool and the Workers Paid cost evaluation |
| CI on `b081c27` | [Tests](https://github.com/scubamike124/datewiseaiapp/actions/runs/45099774409) passed; [iOS build (unsigned release)](https://github.com/scubamike124/datewiseaiapp/actions/runs/45099774442) passed; [Backend tests](https://github.com/scubamike124/datewiseaiapp/actions/runs/45099774441) passed |
| Local results | `flutter analyze lib test`: 0 issues. `flutter test`: 556 passed. `node --test backend/*.test.mjs`: 46 passed. |

## 2. Independent reviews (separate reviewer agents, read-only)

| Review | Rounds | Final verdict |
|---|---|---|
| Code, security and functionality | 84bce04 (NO: 3 major, 12 minor), then 84d5e1e | **YES**: all findings fixed, no regressions. Its two follow-ups are fixed in `b081c27`. |
| Design and App Store screenshots | 84bce04 (NO: 3 major at large text, 8/10), then 84d5e1e | **YES**, 9/10 |
| Cost guard (PR #29) security | f4327ec, then a1125da, then 94ae69f | **YES**: the JWS chain, notifications, atomic counting, budget breaker and privacy were all reviewed |
| Earlier rounds | code review M1–M2 and design M1–M4, then the localization, AI/voice and subscription/privacy audits | all fixed |

## 3. Issues found and fixed

### Product and business rules
- **One plan only:** $19.99 a month (`datewise_premium_monthly`). There is no free plan, trial, annual or lifetime plan. The paywall shows only the price StoreKit returns.
- **No unlimited-use claims.** Every "unlimited" / "ilimitado" was removed. Fair-use limits are now disclosed on the paywall, in the Terms, in the App Store description and in the review notes:
  - 150 replies a day, 1,500 a month, 12 a minute, 2 at a time;
  - voice messages count the same as typed ones.

  All of these come from `lib/config/fair_use.dart`, and a test checks them against `backend/wrangler.toml`.
- **No animated or lip-sync avatar claims.** The portraits are still images with spoken replies, and a test enforces that the copy says so.

### Security and privacy
- **Subscriptions are enforced on the server**, not only in the app:
  - The Worker checks the StoreKit 2 JWS: the x5c chain up to the pinned Apple Root CA G3, Apple's marker OIDs, basicConstraints, the bundle and product IDs, expiry, revocation and the environment.
  - A v2 request without a valid token gets `SUBSCRIPTION_REQUIRED`.
- **Cost protection:**
  - per-subscriber limits per day, month and minute, plus a limit on replies at once;
  - a separate daily budget for anonymous and legacy traffic, with IPv6 addresses grouped by /64;
  - a rate-limit binding;
  - a global daily neuron budget that fails closed.
- **No prompt hijacking:** the coach prompts are built on the server, and any system messages sent by the client are dropped.
- **Privacy:**
  - Usage logs hold counts only.
  - Identifiers are salted hashes; no conversation content or raw IDs are stored, and a test checks this.
  - The privacy policy (EN/ES), `PrivacyInfo.xcprivacy` and the App Privacy answers all describe this.
- **Old v1 data:** the v1 profile fields are removed and never sent, and a stock photo was removed.
- **Workflows:** signing secrets are scoped per step and cleaned up afterwards; actions are pinned to commit SHAs; Flutter is pinned to 3.47.9.

### Reliability
- **Chat stream:** at most 2 HTTP requests per reply. A stream that ends without `[DONE]` is treated as truncated. Error and limit codes are kept with the message, and only the last 24 turns are sent.
- **StoreKit:**
  - On iOS the app re-reads the current entitlements on every purchase event.
  - If that re-read fails, it keeps the last known state; for a purchase the user just started, it shows "pending".
  - On Android, restore waits for the purchases to settle.
- **Voice:** the reply language is detected, and the matching voice of the same gender is used. Microphone locales fall back es-MX → es-US → es-ES and en-US → en-GB. The recognizer is always cancelled after a stop.
- **Coach memory:** off by default. Turning it off asks for confirmation and deletes the note. Delete-all clears every `dw_` key.

### English and Spanish
- About 35 wording corrections, including:
  - "coach de autoconfianza" replaces the mistranslated "coach de confianza";
  - "Cuenta de Apple" / "Apple Account";
  - "presionado" and "Configuración" as the Latin American terms;
  - "con IA" used consistently.
- Pluralization is fixed, and there are no hard-coded user-facing strings.

### Visual and accessibility
- **Earlier fixes:** opaque chat header, no empty-chat gap, Coaches footer no longer clipped, App Store screenshots taken only after a reply finishes, no widows.
- **At Dynamic Type 2.0:**
  - dialogs scroll and starter chips wrap;
  - coach cards and progress tiles stack, so no word breaks mid-word;
  - coach replies follow the system text size.

## 4. Screenshots
- **After (current):** `docs/appstore/screenshots/{en,es}/{6.9,6.5,ipad-13}/01-coaches … 05-privacy.png`. The 20 iPhone shots were regenerated at `84d5e1e` and checked by the design reviewer; the 10 iPad 13" shots and the new chat and 04 captions ("Example chat", "From an AI dating coach, not a person") were added in the release polish. Sizes are 1320×2868 (6.9"), 1284×2778 (6.5") and 2064×2752 (iPad 13").
- **Before:** the same paths at commit `7c3306c`, which predates the design fixes, viewable with `git show 7c3306c:docs/appstore/screenshots/...`.
- **The chats in the screenshots are examples from the review build** (`DW_MOCK_AI`, which works only in web and debug builds). They are not live AI output.

## 5. Test evidence, by area

| Area | Result |
|---|---|
| EN/ES UI, at text scale 1.0 and 2.0 | PASS: widget tests plus 112 captured screens (web review build) |
| Coach personas, prompt sync between server and app | PASS (unit tests) |
| Chat client: streaming, retry, timeout, truncation, error and limit codes | PASS: real socket against a local fake server; **no live AI** |
| Live AI replies for Ava, Ethan, Sofía and Diego (EN, ES, language switching) | **BLOCKED.** Production is still chat-v5, whose model was retired on 2026-11-20 (HTTP 502). chat-v6 (`f5b0401`) is approved but not yet deployed (release checklist D0). |
| Voice: mapping, locale fallback, permission states | PASS (unit tests) |
| Voice on a real device: sound, recognition, permission prompts | **BLOCKED** (needs a physical iPhone) |
| StoreKit logic: purchase, restore, expiry, refund, no-spoof | PASS (fakes injected through the plugin's test API) |
| Real sandbox or TestFlight purchase, renewal, refund | **BLOCKED** (needs Apple credentials and a signed build) |
| Backend cost guard, JWS check, limits, concurrency, bypass attempts | PASS (46 node tests, plus a Miniflare run using Apple's sample notification) |
| Unsigned iOS release build | PASS (CI on macOS) |
| Signed IPA and TestFlight upload (`altool --upload-package`) | **BLOCKED** (needs the 7 signing secrets) |

## 6. AI model comparison and costs
- **Tool ready, live run BLOCKED.** PR #30 compares Llama 3.3 70B fp8-fast (current) against Gemma 4 26B (`@cf/google/gemma-4-26b-a4b-it`). It covers 9 scenarios per language for each coach, cross-language cases and a 10-request parallel test, with automatic checks and blind A/B pairs.
  - The live run is blocked because the repo has no Cloudflare secrets.
  - A full run costs about 4,800 neurons, split over two UTC days to stay inside the free 10,000 per day.
- **Cloudflare prices (MEASURED):**
  - Workers AI: $0.011 per 1,000 neurons, with 10,000 neurons a day free.
  - Llama 3.3: $0.293 per million input tokens and $2.253 per million output tokens. Gemma: $0.10 and $0.30.
  - Workers Paid costs $5 a month.
  - There is **no hard spending cap** on Workers AI, so the cost guard's own budget breaker is required.
- **Projections at the configured $19.99**, after 30% commission, 3% refunds (an ASSUMPTION) and infrastructure:
  - 1,000 typical subscribers: about $13.2k a month on Llama or $13.5k on Gemma (97–99% margin).
  - Heavy use: 83% margin on Llama, 96% on Gemma.
  - Full tables are in `docs/business/WORKERS_PAID_EVALUATION.md` (PR #30) and `AI_COST_MODEL.md`. Usage levels are assumptions until real usage is measured.
- **Pricing research:** `PRICING_EVALUATION.md` (owner scratchpad). It recommends $19.99 if the server-side check ships (it now has) and Mexico and Spain prices are set by hand. Competitors are all at $9–20 a month, and all have a free tier, which DateWise does not.

## 7. Known items that are not code defects
- **The portraits are interim placeholders.** They are landscape, about 1.2 MP, the hero and avatar files are identical, and Ava and Sofía look alike. The owner will supply 8 final portraits, to be checked with `portrait_intake.py`. Provenance is recorded in `docs/legal/ASSET_PROVENANCE.md`.
- **The global AI budget is still 10,000 neurons a day (owner decision).** That is about 80–120 messages a day across the whole service. Before App Review, the owner should approve Workers Paid with a higher `DAILY_NEURON_BUDGET`, or approve Gemma after the comparison.
- **Small large-text cosmetic issues:** the support email wraps at the dot, and the chat header subtitle wraps onto two lines.

## 8. Owner-only actions
1. **v1 stop-gap:** deploy chat-v6 (`f5b0401`) to the old Worker, with an owner-internal redeploy tool outside this repo or with `.github/workflows/deploy-worker.yml` (target `chat-v6`), per `docs/launch/WORKER_DEPLOY_RUNBOOK.md` §7 (release checklist D0). That fixes the production HTTP 502. Then rerun the live coach tests.
2. **Model comparison:** add the repo secrets `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_AI_TOKEN` (your existing token, which needs Workers AI Read and Edit). Then approve the model and the `DAILY_NEURON_BUDGET`, and Workers Paid if you want it.
3. **Pricing:** decided, $19.99/month (2026-11-23). Set USD 19.99 in App Store Connect, check Mexico and Spain prices by hand, and join the Apple Small Business Program for 15% commission.
4. **App Store Connect:**
   - sign the Paid Apps Agreement and complete tax and banking;
   - create `datewise_premium_monthly`, and first check whether any older in-app products exist;
   - keep Billing Grace Period off;
   - set the App Store Server Notifications URL (optional);
   - add the 7 signing secrets;
   - review Users and Access.
5. **Assets:** the 8 final portraits, and the date and account the reference images were generated with; then regenerate all screenshots (iPhone and iPad 13").
6. **Hosting:** confirm you control datewiseai.com, the legal and support URLs, and support@datewiseai.com.
7. **Cost-guard deploy (later, needs approval):**
   - deploy chat-v7 **only** through the reviewed workflow `.github/workflows/deploy-worker.yml`, approved in the `production-worker` environment (`docs/launch/WORKER_DEPLOY_RUNBOOK.md`; release checklist D1–D4). An owner-internal redeploy tool outside this repo cannot deploy it;
   - set the `ID_HASH_SALT` secret;
   - check that the rate-limit namespace is unique;
   - decide on the capacity of the legacy 1.0.2 client.
8. **Device testing:** TestFlight install, sandbox purchase, restore and refund, voice in EN and ES, and the permission prompts.
