# iPhone end-to-end demo: speak to a coach, real AI on staging, talking avatar

**Status: ready to run, BLOCKED on owner steps** (signing secrets, merge to `main`, staging deploy). Nothing here has run
on an iPhone yet.

One run on a real iPhone proves the whole chain:

```
you speak ──> on-device speech recognition (speech_to_text, iOS Speech, onDevice: true)
          ──> DateWise app (TestFlight build, real StoreKit 2 entitlement JWS in X-DateWise-Entitlement)
          ──> staging Worker datewise-coach-staging (verifies the JWS against Apple Root CA - G3, Llama 3.3 on Workers AI)
          ──> reply streams back ──> coach voice (iOS voices, on device) + avatar mouth synchronized to the speech
```

The app talks to the isolated **staging** Worker (`[env.staging]` in `backend/wrangler.toml`, runbook section 9), never
production. Nothing in Cloudflare security or Apple subscription verification is bypassed: the staging Worker has the
same security as production, and the build has no fake store and no offline coach.

## 0. What is verified before the device run, and what only the device run proves

| Checked in CI or simulation (no iPhone) | Where |
|---|---|
| A release build with `COACH_BACKEND_URL` set to staging uses the real backend client at exactly that URL, never the offline demo coach | `test/staging_device_demo_test.dart` |
| A non-HTTPS backend URL is refused (release builds fail every reply instead) | `test/staging_device_demo_test.dart`, `test/backend_chat_test.dart` |
| Every chat request sends the StoreKit entitlement JWS (`X-DateWise-Entitlement`); release iOS builds always use the real App Store (`DW_FAKE_STORE` and `DW_MOCK_AI` are ignored in release) | `test/staging_device_demo_test.dart` |
| The staging Worker refuses a request without a valid StoreKit JWS (403 `SUBSCRIPTION_REQUIRED` / `SUBSCRIPTION_INVALID`), checked again after every staging deploy | `backend/*.test.mjs`, deploy-worker.yml post-deploy checks |
| The full chat-v7 Worker code path with a scripted model (limits, streaming, report) | `tool/live/live_chat_test.mjs --mode local` (SIMULATED, not AI evidence) |
| The `iOS build` workflow: `coach_backend` is a fixed choice, the staging URL is a constant, the input reaches the shell only through `env:`, staging builds get the +50000 build-number range, and the compiled binary is checked for the right host | `test/workflows_test.dart`, actionlint |
| The app compiles for iOS (unsigned release build on macOS) | `iOS build` workflow, job "Unsigned release build" |
| Lip-sync timing on a host (word-anchored driver, audio-path envelope) | `test/avatar_lip_sync_test.dart`, `test/avatar_voice_audio_test.dart` |

| Proved **only** by this device run |
|---|
| On-device speech recognition of your voice (EN, and ES if you test a Spanish coach) and the permission prompts |
| A real TestFlight (Sandbox) StoreKit 2 JWS accepted by the staging Worker |
| A real Llama 3.3 reply from Workers AI, streamed to the app |
| Voice playback through the iPhone speaker or headphones |
| The avatar's mouth moving in time with the audio on real hardware |
| End-to-end latency on a real network |

## 1. Prerequisites (owner, once)

1. **Signing secrets** for the `iOS build` workflow's `signed-testflight` job, all seven (docs/appstore/checklist.md,
   Details section 6): `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`,
   `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`.
   The job fails visibly if any is missing.
2. **App Store Connect**: the auto-renewable subscription **`datewise_premium_monthly`** exists for the app (checklist
   Details section 4) with status at least "Ready to Submit", and the Paid Applications agreement is active.
   TestFlight purchases are free and run in Apple's **Sandbox** environment.
3. **A tester account.** In TestFlight, purchases use the Apple Account signed in to the App Store on the iPhone and are
   not charged. Also create a **Sandbox Apple Account** (App Store Connect, Users and Access, Sandbox, Test Accounts)
   as a fallback: if TestFlight asks for one, or you test a development build, sign in to it on the iPhone under
   Settings, App Store, Sandbox Account. Either way the token the Worker receives says `environment: Sandbox`, which
   staging accepts (`ALLOW_SANDBOX = "1"`, `SANDBOX_DAILY_LIMIT` 40).
4. **Merge to `main`** through a reviewed PR: chat-v7, the staging config (PR #34), and this PR (the `coach_backend`
   input). "Run workflow" only lists inputs that are in `ios-build.yml` on the branch you run from, and the staging
   deploy only deploys commits on `main`.
5. **Deploy the staging Worker** (docs/launch/WORKER_DEPLOY_RUNBOOK.md section 9, owner steps 2 to 4):
   1. Confirm rate-limit namespace `740221` is not used by another Worker on the account.
   2. Actions, *Deploy coach Worker*, Run workflow from `main`: target **`chat-v7-staging`**, `dry_run` on. The summary
      must say **STAGING**.
   3. Run again with `dry_run` off and approve the `production-worker` environment.
   4. Check: `curl -s https://datewise-coach-staging.scubamike124.workers.dev/?version` returns
      `"version":"chat-v7-cost-guard"`. If the summary shows a different workers.dev subdomain than `scubamike124`,
      stop: the build below has the host fixed and would not reach it (change the constant in `ios-build.yml` in a
      reviewed PR first).
6. An iPhone with iOS 15 or later, the TestFlight app, and (recommended) a Premium or Enhanced voice downloaded
   (Settings, Accessibility, Spoken Content, Voices).

## 2. Build the TestFlight staging build

Actions, **iOS build**, Run workflow from `main`:

| Input | Value |
|---|---|
| `signed_build` | ticked |
| `upload_testflight` | ticked |
| `coach_backend` | **`staging`** |
| `avatar_audio_path` | off for the first run (flutter_tts word-anchored mouth driver, the App Store default). Optional second run ticked, see section 5 |
| `run_tests` | optional |

What the workflow does with `coach_backend: staging`:

- Builds with `--dart-define=COACH_BACKEND_URL=https://datewise-coach-staging.scubamike124.workers.dev`. The URL is a
  constant in the workflow, never typed in; `production` (the default) passes no define and keeps the app's
  production URL.
- **Build number +50000**: 100 + run number, +5000 with `avatar_audio_path`, then +50000 for staging. Example run 50:
  production 150, audio-path test 5150, staging **50150**, staging with audio path **55150**. The ranges stay apart
  while run numbers are below about 4,900 (the same limit the audio-path range already has).
- The run summary says **"STAGING COACH BUILD ... do NOT submit for App Store review"**, the IPA artifact is named
  `datewise-ios-ipa-signed-STAGING`, and the job fails if the compiled app does not contain the staging host (or a
  production build does).
- The unsigned job refuses `coach_backend: staging` without `signed_build`.

**Never submit a 50000+ build for App Store review.** There is no App Store submission flag in the workflow (it only
uploads to TestFlight); submission is a manual choice in App Store Connect, so this rule is yours to keep. Because App
Store Connect can reject a lower build number after a higher one of the same version, upload the App Store build of a
version before any 50000+ build of that version, or give the demo its own version (for example 2.0.1).

Wait for processing in App Store Connect (TestFlight tab), then add the build to an internal testing group that
includes you. Answer nothing for export compliance (the Info.plist already declares it).

## 3. Install, subscribe, allow voice

1. Install the build from the TestFlight app. Check the build number in TestFlight is 50000+.
2. Open DateWise, finish onboarding and the 18+ gate.
3. **Confirm the backend:** You tab, scroll to the bottom. Under the version line it must say
   **"Test build · coach server: datewise-coach-staging.scubamike124.workers.dev"**. (Production builds never show
   this line.) If it is missing, you installed the wrong build: stop.
4. **Subscribe:** open the paywall and buy the monthly plan. TestFlight shows a sheet saying you will not be charged;
   confirm with your Apple Account (or the Sandbox account if asked). The paywall closes and the coaches unlock.
5. **Permissions:** open a coach, switch to **Voice mode** ("Talk to <name>"), press **Hold to talk**. Allow the
   **microphone** prompt and the **speech recognition** prompt. If you denied one, the app offers Open Settings.

## 4. The demo

1. Pick a coach (Ava or Ethan for English; Sofía or Diego for Spanish).
2. **Start the screen recording first** (Control Centre, Screen Recording, long-press and turn **Microphone on** so your
   voice is recorded along with the coach's audio).
3. Hold **Hold to talk**, say a specific question, release. Suggested: *"I have a first date on Friday at a jazz bar.
   She loves hiking. What should I ask her?"*
4. Expected:
   - While you hold, the transcript appears; after release your words show as your message.
   - Within a few seconds the coach's reply starts streaming as text.
   - The coach speaks the reply; the avatar's mouth opens and closes with the words and stops when the speech stops.
5. Do 3 to 5 exchanges, including one follow-up that depends on the previous answer ("And if she asks what I do?").
6. Optional, owner-side proof the request hit staging: with Wrangler signed in,
   `cd backend && npx wrangler@4.158.0 tail --env staging --format=pretty` prints a count-only `event: usage` line per
   reply (no message text).

### How to tell a real AI reply from the offline demo coach

- A TestFlight build is a release build: the offline demo coach is **not compiled in** and `DW_MOCK_AI` is ignored. In
  release, a reply is either from the Worker or an error notice ("Couldn't reach your coach...", "Coaching is
  temporarily unavailable..."). A "subscription required" or limit notice means the Worker answered but refused.
- The reply uses your specifics (Friday, jazz bar, hiking) and the follow-up builds on the previous answer. The demo
  coach only matches a few keywords to fixed templates and gives the same text for the same question.
- Ask the same question twice: a real reply is worded differently.
- `wrangler tail` (above) shows one usage event per reply.

## 5. Pass/fail checklist

Record each as PASS / FAIL with a note and the timestamp in the recording.

| # | Check | PASS when |
|---|---|---|
| 1 | Correct build | TestFlight build is 50000+; You tab shows the staging coach server line |
| 2 | Subscription | Sandbox purchase completes; coaches unlocked; no "subscription required" notice in chat |
| 3 | Permissions | Microphone and speech prompts appear with DateWise's text; allowing them enables Hold to talk |
| 4 | Speech recognised | The transcript matches what you said (minor wording differences are fine), on device, with no network error |
| 5 | Real AI reply | Specific to your question, consistent across a follow-up, different when repeated (section 4) |
| 6 | Voice playback | The whole reply is spoken in the coach's voice and language, not cut off at the end |
| 7 | Mouth sync | The mouth moves while the voice speaks, is closed in pauses and after the last word, and is not visibly ahead of or behind the sound (lip-sync offset under about a tenth of a second by eye) |
| 8 | Latency | From releasing Hold to talk: first reply text within about 3 s, voice starting within about 2 s after that. Note the times; over 6 s total is a FAIL to investigate |
| 9 | Stability | No crash, no stuck "listening" state, Hold to talk works again after each reply |

**Mouth sync, two drivers:**

- **Default** (`avatar_audio_path` off, what App Store builds use): the voice is spoken by flutter_tts and the mouth
  follows its word-range events (word-anchored driver). Run this first.
- **Native audio path** (`avatar_audio_path` ticked, `--dart-define=DW_AVATAR_AUDIO_PATH=true`): the reply is rendered
  through `AVSpeechSynthesizer` and the mouth follows the real audio loudness (and word markers on iOS 17+). Optional
  second build (build number 55000+) to compare; also try headphones, a call or Siri interruption and backgrounding
  (docs/avatar/TALKING_AVATARS.md, checklist E4/E7).

## 6. What to keep

- The **screen recording with audio** (microphone on) of the whole session, from opening the You tab (staging line)
  through at least three exchanges.
- The filled checklist above, the build number, iPhone model and iOS version, voice used (default, Enhanced or
  Premium), speaker or headphones.
- Keep recordings out of the repository if they show anything personal.

## 7. Teardown and cost

After the run (and after `docs/qa/LIVE_AI_TEST_PLAN.md` if you run it on the same staging deploy):

```bash
cd backend && npx wrangler@4.158.0 delete --env staging   # deletes Worker datewise-coach-staging only
```

Check that Wrangler names `datewise-coach-staging` before confirming (or use the dashboard: Workers,
`datewise-coach-staging`, Settings, Delete). Once it is gone, the staging TestFlight build can no longer get replies;
expire it in App Store Connect (TestFlight, the build, Expire Build) so testers do not keep using it.

**Cost: $0.** GitHub-hosted macOS runners are free on this public repository; TestFlight and Sandbox purchases are
free; the staging Worker, its Durable Object and rate-limit binding are covered by Workers Free. A demo of a few
replies uses a small part of the account's free **10,000-neuron daily allowance**, which the staging and production
Workers **share** (staging stops itself at `DAILY_NEURON_BUDGET` 4000 and Sandbox users at `SANDBOX_NEURON_BUDGET`
3000). On Workers Free, use past the allowance fails rather than bills. No paid service or new account is needed.
