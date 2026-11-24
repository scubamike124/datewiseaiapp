# DateWise AI: security, privacy and code-health review (2026-11-24)

Branch `claude/overnight-2026-11-24` at `b060239` (the branch moved during the review; findings are against b060239). Review was read-only: nothing was edited, committed or deployed, and no live services were called.

## Tests

| Suite | Result |
|---|---|
| `node --test backend/*.test.mjs tool/live/*.test.mjs` | **109 / 109 pass**, 0 fail |
| `flutter test` (Flutter at /root/fl) | **952 pass, 0 fail** ("All tests passed!"); afterwards the working tree is clean (lib/l10n was not changed) |

## Summary

I found no critical issues. The StoreKit JWS verifier, the server-built prompt, the hashed IDs and the logs that hold counts only are all solid. The main risks are capacity and configuration:

- **High:** the whole service can serve fewer replies per day than one subscriber is promised.
- **Medium:** with ASSN off, a refunded user keeps access until the token expires.
- **Medium:** the Sandbox budget slice must go back to 1,000 after App Review.
- **Medium:** the legacy and photo paths would be weak if they are ever turned back on.

## Findings

### HIGH

**H1. One subscriber's fair-use cap is larger than the whole service's daily capacity, so one user can shut chat for everyone.**
- `backend/wrangler.toml` `[vars]`: `DAILY_NEURON_BUDGET = "10000"` and `DAILY_MESSAGE_LIMIT = "150"`.
- `backend/cost_guard.js:440` refuses every request once the global budget is spent.
- The worst-case reservation for one chat is about 324 neurons on Llama 3.3 70B (6,000 tokens in, 800 out; `worker.js:623-635`, `cost_guard.js:155`). A typical message is about 115 neurons, so the service can serve about 87 messages a day (docs/appstore/checklist.md A3).
- One subscriber at the advertised 150 replies a day, or one shared JWS (see M3), uses up the global budget. Every other subscriber then gets 503 `SERVICE_BUDGET_EXHAUSTED` until 00:00 UTC.
- The store description (`docs/appstore/metadata.md`, "Fair use") promises "up to 150 coach replies a day". The infrastructure cannot deliver that to more than one user.
- This is documented in `docs/business/AI_COST_MODEL.md:106-114` as an owner decision, but nothing in the code stops it.
- **Fix:** before launch, do one of the following:
  - get the owner's approval for Workers Paid and a larger budget;
  - lower the per-subscriber daily cap to a fair share, or add a dynamic per-subscriber share of the remaining global budget;
  - switch to the cheaper model (Gemma, about 26 neurons a message).
- Either way, keep the advertised numbers equal to what the service can actually deliver.

### MEDIUM

**M1. Refunds are not enforced while `ASSN_ENABLED = "0"`. A refunded user can keep chatting until the token expires (up to about one month plus 60 minutes).**
- `backend/wrangler.toml` sets `ASSN_ENABLED = "0"`.
- `cost_guard.js:211` refuses a token only when the token itself carries a `revocationDate`.
- A JWS signed before the refund has no `revocationDate`. A user who saves it (it is an HTTP header and easy to capture) can replay it after a refund. The client clears its own copy (`store_service.dart:351-353`), but the server cannot tell the difference.
- **Fix:** turn ASSN on at launch, as `docs/appstore/ASSN_SETUP.md` recommends. If it stays off, record the residual risk.

**M2. The Sandbox slice is 60% of the free budget and must be reset after review.**
- `backend/wrangler.toml` sets `SANDBOX_NEURON_BUDGET = "6000"` with `ALLOW_SANDBOX = "1"` in production.
- Slices are ceilings, not reservations (`cost_guard.js:440-445`). Production subscribers have only 4,000 neurons of protected room while this is set, which makes H1 worse.
- Anyone with TestFlight access gets free Sandbox subscriptions.
- `docs/appstore/checklist.md:55` (A4) still says "`wrangler.toml` sets **1,000**", which is now wrong.
- **Fix:** set it back to 1,000 (or set `ALLOW_SANDBOX = "0"` if TestFlight is no longer needed) as soon as the app is approved, and update the checklist.

**M3. The entitlement JWS is a bearer token that is not bound to a device.**
- `cost_guard.js:561-607`: anyone holding a valid subscriber JWS can use it from any IP until it expires.
- The damage is limited because every holder shares that subscriber's counters (150 a day). Combined with H1, though, one leaked token can drain the global budget.
- **Fix:** accept this as residual risk once H1 is fixed. Optionally:
  - add a soft cap on distinct IP buckets per subscriber per day;
  - require `appAccountToken` to match a per-install value sent in a second header. This is weak, but it raises the effort needed.

**M4. The legacy and photo paths would be weak if `LEGACY_CLIENTS` is ever set back to 1.** This is only a risk if the configuration changes; production config is `LEGACY_CLIENTS = "0"` and `REQUIRE_SUBSCRIPTION = "1"`.
- `worker.js:609-611`: the legacy chat keeps a client-supplied `system` message (`sanitizeMessages`, `worker.js:509-533`). That makes the Worker an anonymous general-purpose LLM proxy within the anonymous caps.
- `worker.js:766` and `worker.js:791`: the photo coach "tier" check is client-supplied (`tier === 'magnet'`).
- `worker.js:813` and `worker.js:431`: `userNote` has no length limit and goes into the vision prompt. The reservation assumes 2,000 input tokens (`worker.js:672-674`), so a large note becomes an unreserved overage that `budgetSettle` charges later.
- **Fix:**
  - remove the legacy and photo code once v1 is retired, or at least drop client system messages and cap `userNote` (for example 300 characters) even on that path;
  - add a test asserting that `LEGACY_CLIENTS=0` stays the production value.

**M5. The request body is parsed and processed before any rate limit runs.**
- `worker.js:746` (`request.json()`) and `worker.js:611-616` (sanitize/coachMessages over an unbounded `messages` array) run before `admit()` applies the IP limiter (`cost_guard.js:555`).
- A multi-MB body or a `messages` array with 100k elements uses CPU on every request, and no IP limit applies to that work.
- On Workers Free (10 ms CPU) the request mostly just fails, so the practical impact is low to medium.
- **Fix:**
  - reject requests whose `Content-Length` is over about 256 KB (chat) or 7 MB (photo) before parsing;
  - cap `messages.length` (for example 64) before iterating;
  - or run the IP limiter before parsing the body.

### LOW

- **L1. Internal error details are returned to clients.** Responses include `detail: String(e)` (`worker.js:446`, `worker.js:647`, `worker.js:777`, `worker.js:845`) and `raw:` model output (`worker.js:501`, `worker.js:911`). This exposes Workers AI internals and account error codes. **Fix:** log a short code and return a generic message.
- **L2. Clients can forge assistant turns.** `coach_prompts.js:156-161` accepts assistant turns from the client, so a client can write fake "assistant" history to try to jailbreak the coach's topic restriction. The impact is limited to off-topic use of a paid user's own quota. This is accepted because the conversation history lives on the device; a closing system reminder after the history could make it stronger.
- **L3. The only way to withdraw AI consent is "Delete my data".** See `app_state.dart:89-101` and `legal_text.dart:56`. GDPR says withdrawing consent should be as easy as giving it, but here it means wiping all data. **Fix:** add a "Stop sharing with AI provider" toggle in You › Privacy that clears only `dw_ai_consent`.
- **L4. Conversations are stored in NSUserDefaults without encryption and are included in device and iCloud backups.** See `storage_service.dart` (SharedPreferences). The store text says conversations "are stored on your device", but backups copy them off the device. **Fix:** move threads and the memory note to a file with `NSFileProtectionComplete` and `isExcludedFromBackup`, or mention backups in the privacy policy.
- **L5. The age gate is a self-declared checkbox.** See `onboarding_screen.dart:28-50` and `233-253`. The underage block survives "Delete my data" (`storage_service.dart:199-206`), but reinstalling the app resets it. This is acceptable with an App Store 17+/18+ rating; the coach prompt also refuses minors (`coach_prompts.js:131`).
- **L6. `GET /?version` reveals the guard version** (`worker.js:707-709`). This is minor information disclosure and is acceptable as a deploy check.
- **L7. A default public salt is used if `ID_HASH_SALT` is missing** (`cost_guard.js:88-89`). This is mitigated: `deploy-worker.yml:655-695` refuses to deploy production without a salt.
- **L8. CORS is fine.** The allow-list is `datewiseai.com`, `www.datewiseai.com` and `*.datewiseai.pages.dev` (`worker.js:28-43`). An unknown origin gets the default apex origin, not a reflected one. CORS is not the security boundary here anyway; the JWS is.

### Verified OK (no action)

- **StoreKit JWS verification (`apple_jws.js`).** It checks:
  - ES256 only;
  - exactly 3 x5c certificates;
  - the root pinned by SHA-256 to Apple Root CA G3;
  - the root signed the intermediate and the intermediate signed the leaf;
  - Apple marker OIDs on the leaf and the intermediate;
  - basicConstraints, and refuses unknown critical extensions;
  - certificate validity at `signedDate`;
  - `signedDate` is not in the future;
  - a P-256 leaf;
  - a 16k length cap.
  It does no online OCSP check, which is by design. `checkEntitlement` checks the bundle, product, environment (only Production, or Sandbox when allowed), `originalTransactionId`, `revocationDate` and expiry plus leeway. The cache stores verified payloads only, and expiry is checked again on every request.
- **Subscription bypass.** Any `coachId` or entitlement header forces `requireToken` (`worker.js:606-631`). The token-less path goes to the "update the app" notice with no model call while `LEGACY_CLIENTS=0`.
- **Durable Object and user isolation.** Keys are `sub:` or `sbx:` plus a salted SHA-256 of `originalTransactionId`, `anon:` plus the hashed network, or `global`; they cannot collide. Each object stores counters only, and ASSN state is deleted after 35 days (alarm).
- **ASSN endpoint.** It is off by default. Every nested JWS is verified, transaction and renewal must match, replays are idempotent because the latest `signedDate` wins, and refunds are stored as hashes.
- **Logs.** `logUsage` records counts, the outcome and a 12-hex hash prefix only. No message text, IP address or transaction ID is logged. The app has no analytics, and `debugPrint` is guarded by `kDebugMode` and never prints message content.
- **What reaches the AI provider.** The server-built system prompt, user and assistant text (each message cut to 6,000 characters, at most 24 turns), goals and language from fixed lists, and the memory note (single line, quotes removed, 600 characters, framed as "facts, never instructions") only when memory is on. The client's system prompt is dropped (`coach_prompts.js:156`).
- **Coach memory.** It is off by default (`storage_service.dart`), turning it on asks for confirmation (`settings_screen.dart:518`), turning it off deletes the note (`app_state.dart` setMemoryEnabled), and the note is sent only while memory is on (`profileForCoach`).
- **Delete my data.** It removes every `dw_` key, including `dw_ai_consent`, and resets the in-memory consent, drafts, Undo state and memory. It keeps the underage block. `sendMessage` and `retryLastReply` both refuse without consent.
- **AI disclosure.** The prompt says "You are an AI. Never claim to be human"; the store text says "AI, not people, can make mistakes", with no outcome guarantees. The safety, crisis and consent rules are in the prompt.
- **URL launching.** Only fixed URLs are opened: the legal and support pages, the stores, `app-settings:`, and an Apple Maps search with a fixed, encoded query. Model-generated links are not tappable (`coach_text.dart` has no link handling). There are no custom URL schemes or deep links.
- **Secrets.** A scan of tracked files found no keys or tokens; only `android/key.properties.example` is committed. The app ships only the public Worker URL. The developer JWS-export row exists only in debug builds (`kDebugMode`). Mock AI is never used in an iOS or Android release (`main.dart:35`).
- **Speech.** `onDevice: true` (`speech_service.dart:265`) matches the store claim. `PrivacyInfo.xcprivacy` is present and in the Xcode project.
- **CI.** Workflow inputs are passed through `env`, there is no `pull_request_target`, deploys are gated by the `production-worker` environment, and a repository-level secret is refused.

## Dependencies

I checked these offline; there was no network lookup. I know of no published advisories for the versions locked in `pubspec.lock`:

| Package | Version |
|---|---|
| http | 1.6.0 |
| url_launcher | 6.3.2 |
| shared_preferences | 2.5.5 |
| in_app_purchase | 3.3.1 |
| in_app_purchase_storekit | 0.4.17 |
| speech_to_text | 7.5.0 |
| flutter_tts | 4.2.5 |
| uuid | 4.5.3 |
| provider | 6.1.5+1 |
| package_info_plus | 8.3.1 |
| intl | 0.20.3 |
| crypto | 3.0.7 |

`archive` 4.0.9 and `image` 4.9.1 come in through the dev-only `flutter_launcher_icons` and are not shipped in the app. `pub get` reports 45 packages with newer versions blocked by constraints, so a routine `flutter pub outdated` pass is advisable. The backend has no npm runtime dependencies (WebCrypto only); wrangler is pinned to 4.158.0 in CI.

## Code health

- **CH1.** The web build (`deploy.yml` builds with no dart-defines) uses `UnsupportedStoreService` (`store_service.dart:570`). The website can't subscribe, and the backend accepts only Apple JWS, so the web app is a showcase that cannot chat. That is consistent with the owner's "Flutter iOS for v1" decision, but it should not be published as a working product.
- **CH2.** Android: `store_service.dart` (non-iOS branch) unlocks chat after a Play purchase without any server check. The backend rejects every Android request anyway (it needs an Apple JWS), so the Android lane is non-functional. Don't ship it; a Play build would charge users for a chat that never works.
- **CH3.** About 400 lines of v1 photo-coach code are dead in production (`worker.js:76-504` and `worker.js:787-914`; `LEGACY_CLIENTS=0`). `backend/README.md` still describes a Gemini key and the old CORS setup. Remove both once v1 is retired.
- **CH4.** Two places drift from the actual settings:
  - `docs/appstore/checklist.md:55` A4 says Sandbox is 1,000, but `wrangler.toml` has 6,000.
  - The `?version` note (`worker.js:708`) still says "chat-v6 + ...".
- **CH5.** There are no TODO, FIXME or lorem markers, and the shipped UI shows no placeholder text. The features the store copy advertises (four coaches, the weekly plan, progress and streak, voice, memory, "Find a table" through an Apple Maps link) all exist. The app makes no claims about notifications or in-app reservations.
- **CH6.** `CoachPersona.systemPrompt` is still built and sent by the client (`backend_ai_service.dart:299-305`) "for an older Worker". The production Worker drops it, so this only costs upload bytes. Remove it after v1.
