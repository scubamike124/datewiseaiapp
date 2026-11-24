# Hosted live avatar pilot: owner runbook

Status: the pilot harness is built and tested against a fake vendor. **Nothing here has run against a real vendor or on a real iPhone**, because no vendor keys exist yet. This runbook is what you do once you have free-tier keys. Costs: $0 (free tiers only; stop if any step asks for a card).

Why a pilot: the existing frame-based avatar failed the independent premium review. The hosted avatar replaces the avatar engine only (Flutter app, Cloudflare Worker, StoreKit 2 verification, coach identities and customer interface are unchanged). The frame avatar stays as the automatic fallback.

Background: `docs/research/avatar-decision-2026-11-24/` (decision brief, integration plan, costs) on the research branch.

## 0. What was built (so you know what you are testing)

| Piece | Where | Default |
|---|---|---|
| Worker endpoints `POST /v1/avatar/session`, `/heartbeat`, `/end` | `backend/avatar.js`, wired in `backend/worker.js` | **Off.** `AVATAR_PROVIDER` unset or `off` = "avatar unavailable" |
| Per-subscriber monthly minutes + global daily cap | `UsageGuard` Durable Object (`backend/cost_guard.js`) | 60 min per month, staging 30 min per day for everyone |
| Vendor adapters (Simli first, Anam second) | `backend/avatar.js` (token call), `assets/avatar_pilot/adapter_*.js` (browser side) | Simli |
| App engine switch, WebView page, bridge | `lib/avatar/hosted/`, `assets/avatar_pilot/` | **Off.** `AVATAR_HOSTED` not set |
| Second AI-sharing consent naming the vendor | `avatarConsent*` strings (EN/ES), `AvatarConsent` | **Never shown** until `AVATAR_CONSENT_COPY_APPROVED` |
| Pilot screen (state, latency, mic, minutes) | You > Avatar pilot (test builds only) | Hidden |
| Fallback to the frame avatar | `HostedAvatarController` | Always on |

Production Worker: `AVATAR_PROVIDER` is not set, so avatar is off. The production `wrangler.toml` values are unchanged. The production bundle does change because `worker.js` changed; deploying it is a separate step that needs your approval (see section 8).

## 1. Which keys you need, and what they cost

Do Simli first. Anam second, only if Simli fails the rubric.

| Vendor | You create | You copy | Free tier (check on the vendor's pricing page today; it moves) |
|---|---|---|---|
| Simli (https://www.simli.com) | A free account | 1. **API key** (dashboard, API keys). 2. A **face ID** for each coach you will test (stock faces are in the dashboard; uploading our own portraits may need a paid plan: do not pay, test a stock face first) | Free minutes per month; the plan page states them |
| Anam (https://anam.ai) | A free account | 1. **API key** (lab.anam.ai, API keys). 2. An **avatar ID** (our own image avatar is available on the free plan per the research; sessions are short) | Free plan; sessions are about 3 minutes |

Questions to put to the vendor in writing before uploading any coach portrait (from the integration plan): do they train on or retain portraits, audio-in or video and for how long; where is it processed and by whom; is a dating-coaching app with fictional AI faces within acceptable use; minimum user age; DPA; deleting a custom avatar.

## 2. Where the keys go

**Never in the app, never in GitHub files, never in chat.**

1. The API key is a **Worker secret** on the staging Worker `datewise-coach-staging`:
   - Cloudflare dashboard: Workers and Pages, `datewise-coach-staging`, Settings, Variables and Secrets, Add. Type **Secret**. Name `SIMLI_API_KEY` (or `ANAM_API_KEY`). Paste the key. Save.
   - or on a computer with Wrangler: `npx wrangler@4.158.0 secret put SIMLI_API_KEY --env staging` and paste when asked.
   Secrets survive later deploys. The deploy workflow does not touch them.
2. The face IDs are not secret. They go in `backend/wrangler.toml`, `[env.staging.vars]`, as one JSON string, in a reviewed commit:
   `AVATAR_FACE_IDS = '{"ava":"<face id>","sofia":"<face id>"}'`
   (coach ids: `ava`, `ethan`, `sofia`, `diego`; a coach with no id falls back to the frame avatar). For Anam these are Anam avatar ids and you also set `AVATAR_PROVIDER = "anam"` and the `ANAM_API_KEY` secret.
3. Do **not** put keys in `[env.staging.vars]`. A test fails the build if a var name contains `API_KEY`.

## 3. Switching the staging Worker on

The staging section ships with `AVATAR_PROVIDER = "simli"`. It does nothing until both the secret (step 2.1) and a face id (step 2.2) exist: without them the endpoint answers "avatar unavailable" and the app keeps the frame avatar. Other staging variables: `AVATAR_MONTHLY_MINUTES = "60"` per subscriber, `AVATAR_DAILY_MINUTES = "30"` for all testers per day, `AVATAR_SESSION_MAX_SECONDS = "600"` (hard ceiling 10 minutes), `AVATAR_IDLE_SECONDS = "60"`.

To switch off: set `AVATAR_PROVIDER = "off"` and redeploy staging, or delete the secret in the dashboard (immediate; every request then answers "unavailable").

Deploy: GitHub Actions, **Deploy coach Worker**, target `chat-v7-staging` (section 9 of `docs/launch/WORKER_DEPLOY_RUNBOOK.md`). That workflow only deploys code that is already on `main`, and every run needs your approval click. So the pilot branch must be merged to `main` first (your call; merging does not deploy production). Check after deploy: open `<staging worker url>/?version`, then run the unauthenticated check in section 6, step 1.

## 4. Building the iPhone test build

GitHub Actions, **iOS build**, Run workflow, with: `signed_build` on, `upload_testflight` on, `coach_backend` = `staging`, **`avatar_pilot` on**, and your usual `signing` choice. The workflow refuses `avatar_pilot` with a production backend. The build number is in the +50000 range and must never go to App Review. It compiles in `AVATAR_HOSTED=true` and `AVATAR_CONSENT_COPY_APPROVED=true` (so the draft consent text shows to you and internal testers only).

Install it from TestFlight. You need an active sandbox subscription in the app (the Worker refuses the avatar without a valid StoreKit entitlement, same as chat).

## 5. Tap-by-tap iPhone test

Setup once: Wi-Fi on, volume up, silent switch off, Low Power Mode off, a charged phone near 100 percent, a second phone or a screen recorder ready.

1. Open the TestFlight build. Settings (You tab). Scroll to **Avatar pilot** and tap **Avatar pilot (test builds)**. If you do not see the row, the build was not made with `avatar_pilot` or it points at production.
2. Note the screen: Vendor, Connection `idle`, Fallback reason `none`.
3. Tap **Start session**. A dialog asks "Show your coach as a live video face?" and names the vendor. Read it; tap **Allow live video**. (Tap **Keep the usual picture** once to test the decline path: the reason becomes `noConsent`, nothing is sent, the frame avatar shows. Then start again.)
4. Start a stopwatch when you tap Start. Watch the box: it shows the frame avatar and "Connecting your coach...", then the live face. Read **Time to first frame** on screen, and compare with your stopwatch.
5. Tap **Speak test phrase**. Phase A (today): a short tone burst. The face should move its mouth as it plays. This proves connection, audio-in, state changes and minute counting, not lip-sync quality. Phase B (needs the neural voice endpoint `/tts` from the voice branch, not built here): real speech in English with Ava and Spanish (es-MX) with Sofia.
6. While it is speaking, tap **Interrupt**. Speech and mouth should stop within a moment and the state should return to `listening`.
7. Tap the small camera-off button on the video: the frame avatar returns at once and **Minutes used** stops growing. Tap the camera button to resume.
8. Network drop: with a session live, turn on Airplane Mode. Within about a minute the Fallback reason becomes `offline` or `poorNetwork` and the frame avatar shows, with no error dialog. Turn Airplane Mode off and tap Start again.
9. Backgrounding: with a session live, press Home for 10 seconds, return. The reason is `backgrounded`; start again.
10. Microphone: the Microphone permission row says "Not needed" or `prompt`/`denied`. The live face must never trigger the iOS microphone prompt. Then go to a chat and use the talk button: on-device speech recognition must still work exactly as before, after a live session and after a fallback.
11. Allowance: note **Minutes used** at the start and end of the test. Compare with the vendor dashboard's minutes.
12. Leave it open on Start with no speech for 90 seconds: the session should close on its own (idle) and the reason becomes `sessionEnded`.
13. Battery and heat: run one continuous 10-minute session (it ends itself at 10 minutes). Note battery percent before and after and how warm the phone feels.

## 6. What to measure, and how

1. Unauthenticated check (Mac or Linux terminal, no key needed): `curl -s -X POST <staging url>/v1/avatar/session -H 'content-type: application/json' -d '{"coachId":"ava"}'` must answer 403 `SUBSCRIPTION_REQUIRED` (or 503 `AVATAR_UNAVAILABLE` while the pilot is off). Never a token.
2. Measure on the real phone:

| Measure | How | Record |
|---|---|---|
| Time to first frame | On-screen value and stopwatch, 10 starts, Wi-Fi and LTE | p50, p95 |
| Lip-sync | Screen-record a speech clip, step through frames; 5 bilabial words (m, b, p) in EN and ES | Lag in ms; lips closing on m/b/p yes or no |
| es-MX | A native speaker watches Sofia (Phase B) | Any English-looking mouth shapes, yes or no |
| Interruption | Tap Interrupt mid-sentence, 10 times | Time to stop (ms), leftover audio yes or no |
| Mic permission | Step 10 | Prompt shown yes or no; chat dictation still works yes or no |
| Network drop | Step 8, 5 times | Seconds to fallback; error dialog yes or no |
| Battery and heat | Step 13 | Percent per 10 minutes; warm, hot |
| Minutes counted | Step 11 | App value vs Worker vs vendor dashboard, within 10 percent |
| Identity | Compare the live face with the approved portrait; run `tool/avatar/verify.py` on 10 captured frames if available | Same person, brown eyes, yes or no |
| Fallback | Allowance reached (set `AVATAR_MONTHLY_MINUTES = "1"` temporarily), kill switch (delete secret), vendor 5xx | Frame avatar within 3 s, no dialog |

## 7. Acceptance rubric (to reach 9 out of 10)

Gates first. **Any gate failed = the pilot fails, whatever the score.**

| Gate | Pass |
|---|---|
| G1 Entitlement | No token, expired token, wrong environment: 403 every time, and the vendor dashboard shows no session |
| G2 Key safety | The vendor key appears nowhere in the app, the responses, the Worker logs (`wrangler tail`) or the repository |
| G3 Consent | No session starts, and nothing is sent, before the consent dialog is agreed; declining shows the frame avatar |
| G4 Fallback | Every failure in section 6 lands on the frame avatar within 3 s with no error dialog, and the reply text is always visible |
| G5 Mic | The live face never asks for the microphone; dictation works after it |
| G6 Cost | Counted minutes within 10 percent of the vendor's; monthly and daily caps stop new sessions |
| G7 Privacy | The vendor's written answers: no training on our content, retention 30 days or less (or zero), acceptable use confirmed |

Score (each 0 to 10; the pilot reaches **9/10** only if every gate passes and the weighted average is 9.0 or more):

| Criterion | Weight | 10 means |
|---|---|---|
| Visual quality vs the current avatar (blind, 8 matched clips) | 25 | Vendor clearly preferred in 7 of 8 or more; no uncanny artifacts |
| Lip-sync | 20 | Lag within +/-80 ms, lips close on m/b/p |
| Time to first frame | 10 | p50 up to 2.0 s, p95 up to 3.5 s |
| es-MX | 10 | A native speaker sees no English mouth shapes |
| Identity and eye colour | 10 | Same face as the approved portrait, brown eyes |
| Interruption and responsiveness | 10 | Stops within 500 ms, clean |
| Reliability (20 consecutive turns, no manual retry) | 10 | 20 of 20 |
| Battery, heat, data | 5 | Under 8 percent per 10 minutes, not hot |

Scores for sub-ranges: score linearly between the pass line (7) and the target (10); a measurement at half the pass line or worse scores 0.

Phase A (tone) can score connection, interruption, reliability, minutes and battery only. The full 9/10 needs Phase B (real speech through the neural voice).

## 8. After the pilot

- Pass: tell the owner's reviewer; the next steps are the voice endpoint, the consent text approval (replace the draft in `avatarConsentBody`, then set `AVATAR_CONSENT_COPY_APPROVED` for a release build), the Privacy Policy and App Privacy label updates, and your approval to deploy the Worker change to production (production stays `off` until then). None of that is done here.
- Fail or stop: set `AVATAR_PROVIDER = "off"`, delete the `SIMLI_API_KEY` or `ANAM_API_KEY` secret, delete the custom faces at the vendor, cancel the free account if you wish, and tear down staging with `npx wrangler@4.158.0 delete --env staging`. The app needs no release: the flag is off by default.

## 9. Known limits and what is unverified

- **Unverified on a device:** WKWebView video and audio autoplay with `playsinline`, the page loading from the app's asset folder (file URL, local scripts under the Content-Security-Policy in `assets/avatar_pilot/index.html`), WebRTC (the Simli SDK uses LiveKit) inside WKWebView on your iPhone model, and audio-session coexistence with on-device speech recognition and `AVSpeechSynthesizer`. The pilot exists to find these out.
- **Unverified against real vendors:** the exact token request bodies were taken from the vendors' documentation (cited in `backend/avatar.js`, `assets/avatar_pilot/adapter_*.js`); free-tier limits, whether a free plan allows the face you choose, Simli's `speaking`/`silent` events timing, Anam's text mode (`talk`) on an audio-passthrough persona.
- **The neural voice does not exist yet:** `WorkerTtsAudioSource` calls `POST /tts` (voice plan), which the Worker does not have. Until then the pilot screen uses a tone, and a real reply cannot be spoken by the live face (the stage keeps the system voice and the frame avatar).
- The vendor SDK bundles (`assets/avatar_pilot/vendor/`, about 760 KB, MIT) ship inside every build, inert when the flag is off. Rebuild with `tool/avatar_pilot/build_vendor.sh` (pinned versions).
- Minutes: a session's whole grant (at most 10 minutes) is reserved when it opens and the unused part is refunded when the app reports the end. An app that crashes is charged by its last heartbeat plus 90 seconds, or the whole grant if it never sent one. A modified client that stops reporting can get at most 12 sessions of up to 10 minutes per hour (the per-subscriber open limit), all bounded by the daily cap for all testers.
- Not touched by this branch (another branch changes them): `lib/screens/chat_screen.dart`, `lib/avatar/coach_stage_avatar.dart`, `lib/services/voice_service.dart`. To put the live face on the stage later: embed `HostedAvatarView` (or `HostedAvatarEngine.build`) in the stage, and on each finished reply call `if (!await engine.speakReply(text)) voice.speak(text)`.

## 10. Commands

Worker tests: `node --test backend/*.test.mjs`. App: `flutter analyze` and `flutter test --concurrency=2`. Vendor bundles: `tool/avatar_pilot/build_vendor.sh`.
