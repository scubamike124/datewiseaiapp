# iPhone end-to-end demo: speak to a coach, real AI on staging, talking avatar

**Status: ready to run, BLOCKED on owner steps** (signing secrets, merge to `main`, staging deploy). Nothing here has run
on an iPhone yet.

**iPhone only: no Mac needed.** Every step below is done on the iPhone: Safari for github.com, appstoreconnect.apple.com
and dash.cloudflare.com, plus the TestFlight app. The signed build is made by GitHub Actions on GitHub's own macOS
runner, signed with **cloud-managed signing** (`signing: cloud`): only an App Store Connect API key is needed, made and
stored from Safari. Steps that truly need a computer are marked **[COMPUTER]**; none of them is on the cloud-signing
path.

Tip: if a page in Safari hides a menu, tap **aA** in the address bar, then **Request Desktop Website**.

One run proves the whole chain:

```
you speak ──> on-device speech recognition (speech_to_text, iOS Speech, onDevice: true)
          ──> DateWise app (TestFlight build, real StoreKit 2 entitlement JWS in X-DateWise-Entitlement)
          ──> staging Worker datewise-coach-staging (verifies the JWS against Apple Root CA - G3, Llama 3.3 on Workers AI)
          ──> reply streams back ──> coach voice (iOS voices, on device) + avatar mouth synchronized to the speech
```

The app talks to the isolated **staging** Worker (`[env.staging]` in `backend/wrangler.toml`; see
docs/launch/WORKER_DEPLOY_RUNBOOK.md section 9), never production. Nothing in Cloudflare security or Apple subscription
verification is bypassed. The staging Worker has the same security as production, and the build has no fake store and
no offline coach.

## 0. What is verified before the device run, and what only the device run proves

| Checked in CI or simulation (no iPhone) | Where |
|---|---|
| A release build with `COACH_BACKEND_URL` set to staging uses the real backend client at exactly that URL, never the offline demo coach | `test/staging_device_demo_test.dart` |
| A non-HTTPS backend URL is refused (release builds fail every reply instead) | `test/staging_device_demo_test.dart`, `test/backend_chat_test.dart` |
| Every chat request sends the StoreKit entitlement JWS (`X-DateWise-Entitlement`). Release iOS builds always use the real App Store (`DW_FAKE_STORE` and `DW_MOCK_AI` are ignored in release) | `test/staging_device_demo_test.dart` |
| The staging Worker refuses a request without a valid StoreKit JWS (403 `SUBSCRIPTION_REQUIRED` / `SUBSCRIPTION_INVALID`), checked again after every staging deploy | `backend/*.test.mjs`, deploy-worker.yml post-deploy checks |
| The full chat-v7 Worker code path with a scripted model (limits, streaming, report) | `tool/live/live_chat_test.mjs --mode local` (SIMULATED, not AI evidence) |
| The `iOS build` workflow: `coach_backend` is a fixed choice and the staging URL is a constant. The input reaches the shell only through `env:`, staging builds get the +50000 build-number range, and the compiled binary is checked for the right host | `test/workflows_test.dart`, actionlint |
| The app compiles for iOS (unsigned release build on macOS) | `iOS build` workflow, job "Unsigned release build" |
| Lip-sync timing on a host (word-anchored driver, audio-path envelope) | `test/avatar_lip_sync_test.dart`, `test/avatar_voice_audio_test.dart` |
| Staging cannot reach production data (static review, section 1) | `backend/wrangler.toml`, `backend/staging_env.test.mjs` |

| Proved **only** by this device run |
|---|
| On-device speech recognition of your voice (EN, and ES if you test a Spanish coach) and the permission prompts |
| A real TestFlight (Sandbox) StoreKit 2 JWS accepted by the staging Worker |
| A real Llama 3.3 reply from Workers AI, streamed to the app |
| Voice playback through the iPhone speaker or headphones |
| The avatar's mouth moving in time with the audio on real hardware |
| End-to-end latency on a real network |

## 1. Pre-live isolation check

**Shared deploy credential.** The staging deploy runs in the same `production-worker` GitHub environment with the
same `CLOUDFLARE_API_TOKEN`, which can also deploy production. Staging stays off production because the workflow
hardcodes the Worker name `datewise-coach-staging` for the `chat-v7-staging` target and checks the deployed URL, not
because the credentials are separate. The running Worker itself has no access to that token.

**What was verified statically** (main session, branch `claude/datewise-v2-app` at `310e94e`; no Cloudflare call):

- **Bindings.** `[env.staging]` in `backend/wrangler.toml` declares exactly three:
  - `AI`: account-level Workers AI. It is not separate from production: both Workers draw on the account's free
    10,000-neuron daily allowance.
  - `USAGE_GUARD`: the Durable Object class `UsageGuard`, with **no `script_name`**. It is a separate namespace owned
    by `datewise-coach-staging`, so staging has its own counters and budget and cannot see production's.
  - `RATE_LIMITER`: rate-limit namespace **`740221`**.
- **No other bindings.** There are no KV, D1, R2, service, queue or tail bindings.
- **No outbound calls.** `backend/*.js` makes no outbound `fetch`. The only `fetch` calls are the Worker's own
  handler and the Durable Object stub.
- **Environment names read.** `AI`, `ALLOW_SANDBOX`, `APPLE_BUNDLE_ID`, `APPLE_PRODUCT_ID`, `ASSN_ENABLED`,
  `FAILOPEN_LIMITER` (absent on staging), `ID_HASH_SALT` (staging's own random salt, never production's),
  `LEGACY_CLIENTS`, `RATE_LIMITER`, `REQUIRE_SUBSCRIPTION` and `USAGE_GUARD`. Also the numeric limit variables, read
  through `guardConfig()` in `backend/cost_guard.js`. None is a credential or a link to another service.
- **Rate-limit namespace IDs in repo configs:**
  - production: `740219`;
  - reserved: `740220` (commented out);
  - staging: `740221`.

  No other wrangler config in this repository or in `amberai` (which shares the Cloudflare account) declares a
  rate-limit namespace. Amber's redeploy tool only keeps the production Worker's existing bindings.

**What cannot be verified from the repositories:** Workers on the account that were created outside these repos. A
Worker that already uses namespace `740221` would share rate-limit counters with staging. Check it yourself. This is
read-only and works in Safari on the iPhone:

1. Open **dash.cloudflare.com** and sign in. Pick the account if asked.
2. Left menu (tap the menu icon on a phone): **Compute (Workers)**, then **Workers & Pages**. On older dashboards it
   is just **Workers & Pages**.
3. For **each** Worker in the list except `datewise-coach-staging`:
   1. Tap its name, then **Settings**, then **Bindings**.
   2. Look at any **Rate Limiting** binding and its **namespace ID**.
4. **PASS** if no Worker other than `datewise-coach-staging` shows `740221`. If one does, stop: staging's
   namespace must change in a reviewed PR first (ask an agent to open it).

**After the staging deploy** (section 2.5, step 6), open **Workers & Pages**, then **`datewise-coach-staging`**, then
**Settings**, then **Bindings**. **PASS** only if it lists exactly these three:

- **Workers AI** `AI`;
- **Durable Object** `USAGE_GUARD` (class `UsageGuard`, this Worker);
- **Rate Limiting** `RATE_LIMITER` with namespace `740221`.

Anything else (KV, D1, R2, a service binding, a queue, a tail consumer) is a FAIL: delete the staging Worker
(section 8) and report it.

## 2. Prerequisites (owner, once)

### 2.1 Signing: cloud-managed, iPhone only (App Store Connect and github.com in Safari)

The `iOS build` workflow has two signing modes, chosen with its **`signing`** input:

- **`cloud`** (use this from an iPhone): the archive is built without codesigning, then `xcodebuild -exportArchive`
  signs it with automatic signing (`-allowProvisioningUpdates` with the App Store Connect API key). Xcode uses the
  team's **cloud-managed Apple Distribution certificate** and creates the App Store profile for
  `com.datewise.datewiseAi` itself. No `.p12`, no profile file, no computer. It needs **four** secrets.
- `manual` (the default): the distribution certificate and profile from secrets, as before. Making those needs a
  computer; see the end of this section.

**Status: the cloud path is UNTESTED** until you run it (section 3): it can only run on GitHub's macOS runner with your
secrets. If the export step fails, the run log names Apple's reason; nothing is uploaded in that case.

#### a. Create the API key (appstoreconnect.apple.com in Safari)

You must be the **Account Holder** or an **Admin** of the team to make a team key.

1. Sign in, then tap **Users and Access**.
2. Tap **Integrations** (top tabs), then **App Store Connect API** in the sidebar, then the **Team Keys** tab. The
   first time, tap **Request Access** and accept the terms.
3. Tap **Generate API Key** (or **+**). **Name:** `GitHub cloud signing`. **Access:** **Admin**. Tap **Generate**.
   Admin is required: Xcode refuses cloud-managed distribution signing with a Developer or App Manager key
   ("Cloud signing permission error").
4. On the new row, note the **Key ID** (10 characters). Above the table, tap **Copy** next to the **Issuer ID** (a long
   id with dashes).
5. Tap **Download** on the new row. **The .p8 can be downloaded only once.** Safari asks to download
   `AuthKey_<Key ID>.p8`: tap **Download**. It is saved to **Files**, **Downloads** (Safari's download arrow, top right,
   shows it).
6. Team ID: developer.apple.com, **Account**, **Membership details**, **Team ID** (10 characters).

**Risk: an Admin API key is powerful.** Anyone who has the `.p8` can act as an admin of your App Store Connect team
(users, apps, builds, certificates) until the key is revoked. So:

- store it **only** as a GitHub secret (below). Do not email it, paste it into notes or chats, or keep it in iCloud
  Drive after the step;
- after the secret is saved, delete the `.p8` from Files (**Downloads**, long-press it, **Delete**, then empty
  **Recently Deleted** in Files);
- **Revoke** it after the demo if you like: Users and Access, Integrations, Team Keys, tap the key, **Revoke API Key**.
  A revoked key cannot be restored; make a new one for the next build and update the three secrets.

The workflow only writes the `.p8` to the runner's temporary folder, readable by the job's user only, never prints it,
and deletes it in a step that always runs.

#### b. Copy the .p8 text on the iPhone

1. Open the **Files** app, then **Downloads** (or **Recents**), then tap `AuthKey_<Key ID>.p8`. Quick Look shows it as
   text. If Quick Look shows only an icon: long-press the file, tap **Rename**, add `.txt` to the end
   (`AuthKey_<Key ID>.p8.txt`), tap **Done**, then open it.
2. Long-press the text, tap **Select All**, then **Copy**. It must include the `-----BEGIN PRIVATE KEY-----` and
   `-----END PRIVATE KEY-----` lines (the job checks this).

#### c. Add the four GitHub secrets (github.com in Safari)

Repo **Settings** (tap **aA**, **Request Desktop Website** if the tab is hidden), then **Secrets and variables**, then
**Actions**, then the **Secrets** tab, under **Repository secrets**. For each row: **New repository secret**, enter the
**Name**, paste the value into **Secret**, then **Add secret**.

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | the Team ID (step a6) |
| `APP_STORE_CONNECT_API_KEY_ID` | the Key ID (step a4) |
| `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID (step a4) |
| `APP_STORE_CONNECT_API_KEY_P8` | paste the copied `.p8` text (step b), BEGIN/END lines included |

Then delete the `.p8` from Files (see the risk note above). With `signing: cloud` the job fails visibly with "Signing
secrets missing" if any of the four is absent. Nothing is built or uploaded in that case.

#### API signing (`signing: api`, App Manager key, iPhone only, UNTESTED)

For a key whose access is **App Manager** (no Admin key needed, no new key). Same four secrets as above. The job makes
a fresh private key and certificate request on the runner, then through the App Store Connect API: creates an
**Apple Distribution** certificate, looks up the existing `com.datewise.datewiseAi` identifier (it fails if it is
missing; it never creates one), creates an **App Store** profile named `DateWise CI api <run>-<attempt>`, signs
manually, and uploads. A final step that always runs deletes that profile and, with **`revoke_api_cert`** ticked (the
default), revokes the certificate, after the upload.

Side effects on the Apple account, visible in Certificates, Identifiers & Profiles: one distribution certificate and
one profile exist during the run. Apple limits distribution certificates per team; if the team is at the limit the
create step fails with HTTP 409 and nothing is built. If a run is killed before cleanup, revoke the leftover
"DateWise CI api" certificate and profile by hand. Apple says revoking a distribution certificate does not affect apps
already on the App Store; it does not clearly say the same for builds still processing or in TestFlight. If a revoked
run's build misbehaves in TestFlight, run once with `revoke_api_cert` unticked and revoke that certificate later by
hand.

#### Manual signing (optional, needs a computer)

`signing: manual` needs all seven secrets: the four above (an App Manager key is enough for manual signing) plus:

| Secret | Where the value comes from | Computer? |
|---|---|---|
| `IOS_PROVISIONING_PROFILE_BASE64` | developer.apple.com, **Certificates, Identifiers & Profiles**, **Profiles**, the App Store profile for `com.datewise.datewiseAi`, **Download**, then base64 of the file | **[COMPUTER]** to base64-encode it (`base64 -i profile.mobileprovision`). Any computer works, Mac not required |
| `IOS_DIST_CERT_P12_BASE64` | an **Apple Distribution** certificate **with its private key** exported as `.p12`, then base64 | **[COMPUTER]**. The private key is created on the computer that made the certificate request (Keychain Access on a Mac, or `openssl` on any computer) |
| `IOS_DIST_CERT_PASSWORD` | the password chosen when exporting the `.p12` | with the above |

### 2.2 App Store Connect (appstoreconnect.apple.com in Safari)

1. **Agreement:** **Business** (or **Agreements, Tax, and Banking**). **Paid Applications** must be **Active**.
2. **Subscription:** **Apps**, then **DateWise AI - Dating Coach**, then **Monetization**, then **Subscriptions**,
   then the subscription group. **`datewise_premium_monthly`** must exist with price, localization and review
   information filled in. Its status must be at least **Ready to Submit** ("Missing Metadata" can stop StoreKit from
   returning it).
3. **Sandbox tester:** **Users and Access**, then **Sandbox** in the sidebar, then **Test Accounts** (or **Sandbox
   Testers**), then **+**. Enter the first and last name and an email address that has **never** been an Apple
   Account (for example a new `+sandbox` alias of your email). Then enter a password and the country or region
   (United States for USD pricing), and tap **Create**. Note the email and password.
4. **TestFlight group** (once): **Apps**, then **DateWise AI**, then **TestFlight**, then **Internal Testing**, then
   **+** (Create Group). Name it `iPhone demo` and add yourself as a tester (you must be a user on the team). The
   build is added to it in section 3.

### 2.3 Version and build numbers (decide before the merge)

App Store Connect can reject a lower build number after a higher one of the same version. A staging build is 50000+,
so once one is uploaded for a version, that version's App Store build (100 + run number) may be refused. Decide this before
the merge in 2.4, because `pubspec.yaml` on the v2 branch is `2.0.0+100`. Do one of these:

- upload the App Store build of a version before any 50000+ build of that version; or
- give the demo its own version (for example 2.0.1). The version comes from `version:` in `pubspec.yaml`, so this
  needs a `pubspec.yaml` change in a reviewed PR before the merge (ask an agent to open it).

### 2.4 Merge to `main` (github.com in Safari)

**Blocked until you decide to merge.** Today `main` has only the "Deploy to GitHub Pages" workflow. GitHub offers a
**Run workflow** button only for a workflow that is on the default branch, so **iOS build** and **Deploy coach
Worker** cannot be started until the v2 branch is merged (iOS build may be listed from earlier PR runs, without the
button), and the staging deploy only deploys commits on `main`. Sections 2.5 and 3 onward wait for this merge.

You can do these now: section 1 (namespace check), 2.1, 2.2, 2.3, 2.6, and
docs/launch/WORKER_DEPLOY_RUNBOOK.md sections 1b to 1f. Do 1f (**Protect `main`**, mandatory) **before** the merge
below: without it the deploy's "on `main`" check means nothing.

**Merging to `main` and every deploy are the owner's decision alone.** No agent or workflow merges or deploys on its
own; nothing in this runbook happens until you do it.

1. Merge `claude/datewise-v2-app` (which contains chat-v7 and PRs #34, #37, #38 and #39) into `main` through a
   reviewed PR (ask an agent to open it).
2. Merging does **not** publish the website: **Deploy to GitHub Pages** runs only when you start it by hand
   (Actions, Deploy to GitHub Pages, Run workflow, branch `main`), and only `main` is ever published.
3. To merge a PR: **Pull requests**, open the PR, then **Merge pull request**, then **Confirm merge**.

### 2.5 Deploy the staging Worker (github.com in Safari)

These are runbook section 9, owner steps 2 to 4.

0. If not done yet: docs/launch/WORKER_DEPLOY_RUNBOOK.md sections 1b to 1f (a Cloudflare API token; the
   `production-worker` environment with you as required reviewer and deployment branches and tags `main` and
   `worker-v*`; its secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`; the `worker-v*` tag ruleset; and the
   `main` branch ruleset). These must be **environment** secrets: the run fails on purpose
   if `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` or `ID_HASH_SALT` is a repository secret.
1. Run the **rate-limit namespace check** in section 1. It must PASS.
2. Repo **Actions** tab, then **Deploy coach Worker** in the workflow list, then **Run workflow**. Fill in the form:
   - **Use workflow from:** `main`;
   - **target:** `chat-v7-staging`;
   - **dry_run:** ticked.

   Tap the green **Run workflow** button.
3. Open the run when it finishes. The summary must say **STAGING** and show the commit.
4. Run it again with **dry_run unticked**. The deploy job waits for you: tap **Review deployments**, tick
   **production-worker**, then tap **Approve and deploy**. The gate is named `production-worker`, but this run deploys
   only `datewise-coach-staging`: check the job title says
   `chat-v7-staging` before approving. The GitHub mobile app can also approve it from the notification.
5. When the run is green, open
   **https://datewise-coach-staging.scubamike124.workers.dev/?version** in Safari. It must show
   `"version":"chat-v7-cost-guard"`. If the run summary shows a workers.dev subdomain other than `scubamike124`, stop:
   the build below has that host fixed and would not reach it. The constant in `ios-build.yml` must change in a reviewed
   PR first (ask an agent to open it).
6. Run the **post-deploy bindings check** in section 1. It must PASS.

### 2.6 The iPhone

- iOS 15 or later (iOS 18+ recommended for the Sandbox sign-in flow below).
- Install **TestFlight** from the App Store.
- **Sandbox account:** **Settings**, then **Apps**, then **App Store** (iOS 18 and later; on iOS 17 and earlier
  **Settings**, then **App Store**), then scroll to **Sandbox Account** (under Developer or near the bottom), then sign in with the tester from 2.2 step 3. On iOS 18 and later this section may only appear, or ask
  for the sign-in, at the first purchase in a test build. Then sign in there when the purchase sheet asks. Never sign
  in to the Sandbox account under **Settings, [your name]** (that is your real Apple Account).
- Recommended: a Premium or Enhanced voice: **Settings**, then **Accessibility**, then **Spoken Content**, then
  **Voices**, then English (and Spanish), then download one marked Premium or Enhanced.
- Screen recording in Control Center: **Settings**, then **Control Center**. Add **Screen Recording** if it is not
  already there (iOS 18 and later: open Control Center, tap **+**, then **Add a Control**, then **Screen Recording**).

## 3. Build the TestFlight staging build (github.com in Safari)

1. Repo **Actions** tab, then **iOS build**, then **Run workflow**. Set:

   | Field | Value |
   |---|---|
   | Use workflow from | `main` |
   | `signed_build` | ticked |
   | `upload_testflight` | ticked |
   | `coach_backend` | **`staging`** |
   | `signing` | **`cloud`** (section 2.1) |
   | `avatar_audio_path` | unticked for the first run (flutter_tts word-anchored mouth driver, the App Store default). Optional second run ticked, see section 6 |
   | `run_tests` | optional |

   `signing` defaults to `manual`. If you leave it there, the run fails with "Signing secrets missing"; pick `cloud`.
   Tap the green **Run workflow** button. The run takes about 20 to 40 minutes.
2. Open the run, then the job **Signed IPA / TestFlight (manual, needs secrets)**. ("manual" in that name means the
   job only runs when you start it by hand; it is not the `signing: manual` choice.) The summary must show
   **"STAGING COACH BUILD ... do NOT submit for App Store review"**, the build number, `Coach backend: staging`,
   `Coach host check passed (staging)`, `Signing: cloud` and `Cloud-managed signing: Apple Distribution, build <N>`.
   If the export step fails with a cloud signing permission error, check the key's access is **Admin** (2.1 a3).
3. App Store Connect: **Apps**, then **DateWise AI**, then **TestFlight**. Wait until the new build (50000+) finishes
   **Processing**, usually 5 to 30 minutes. Then open **Internal Testing**, then **iPhone demo**, then **Builds**, then
   **+**, select the 50000+ build and tap **Add**. Export compliance should not be asked (the Info.plist declares it).
   If it is, answer that the app uses only exempt encryption (HTTPS).

What `coach_backend: staging` does:

- **Backend URL.** The build gets
  `--dart-define=COACH_BACKEND_URL=https://datewise-coach-staging.scubamike124.workers.dev`. The URL is a constant in
  the workflow, never typed in. `production` (the default) passes no define and keeps the app's production URL.
- **Build number +50000.** The base is 100 + the run number. The audio path adds 5000, then staging adds 50000. For
  run 50:

  | Build | Number |
  |---|---|
  | production | 150 |
  | audio-path test | 5150 |
  | staging | **50150** |
  | staging with audio path | **55150** |

  The ranges stay apart while run numbers are below about 4,900 (the same limit the audio-path range already has).
- **Labels and checks.** The run summary carries the STAGING warning and the IPA artifact is named
  `datewise-ios-ipa-signed-STAGING`. The job fails if the compiled staging app lacks the staging host, or if a
  production build lacks the production host or contains the staging host.
- **Unsigned job.** It refuses `coach_backend: staging` or `signing: cloud` without `signed_build`.

**Never submit a 50000+ build for App Store review.** The workflow has no App Store submission flag (it only uploads
to TestFlight). Submission is a manual choice in App Store Connect, so this rule is yours to keep. Decide the version
question in section 2.3 before the first staging build.

## 4. Install, subscribe, allow voice (on the iPhone)

1. **Install.** Open **TestFlight**, then **DateWise AI**, then **Install** (or **Update**). Check that the build
   number shown is 50000+.
2. **Onboarding.** Open DateWise and finish onboarding and the 18+ gate.
3. **Confirm the backend.** Open the **You** tab and scroll to the bottom. Under the version line it must say
   **"Test build · coach server: datewise-coach-staging.scubamike124.workers.dev"**. Production builds never show
   this line. If it is missing, you installed the wrong build: stop.
4. **Subscribe.** Open the paywall and buy the monthly plan. The sheet must say **[Environment: Sandbox]** or say
   that you will not be charged. Sign in with the Sandbox tester if asked (on iOS 18+ this is where the sign-in
   happens). The paywall closes and the coaches unlock.
5. **Permissions.** Open a coach, switch to **Voice mode** ("Talk to <name>"), then press **Hold to talk**. Tap
   **Allow** on the **microphone** prompt and **OK** on the **speech recognition** prompt. If you denied one, the app
   offers **Open Settings**: under **Settings**, then **Apps**, then **DateWise AI** (iOS 18 and later; on iOS 17 and
   earlier **Settings**, then **DateWise AI**), turn on **Microphone** and **Speech Recognition**.

## 5. The demo

1. **Pick a coach.** Ava or Ethan for English; Sofía or Diego for Spanish.
2. **Start recording first.** Open Control Center, **long-press** Screen Recording, turn **Microphone On**, then tap
   **Start Recording**. This records your voice along with the coach's audio.
3. **Speak.** Hold **Hold to talk**, ask a specific question, then release. Suggested: *"I have a first date on Friday
   at a jazz bar. She loves hiking. What should I ask her?"*
4. **Expected:**
   - While you hold, the transcript appears. After you release, your words show as your message.
   - Within a few seconds the coach's reply starts streaming as text.
   - The coach speaks the reply. The avatar's mouth opens and closes with the words and stops when the speech stops.
5. **Continue.** Do 3 to 5 exchanges, including one follow-up that depends on the previous answer ("And if she asks
   what I do?").
6. **Optional: owner-side proof the request hit staging.** In Safari, open Cloudflare **Workers & Pages**, then
   **`datewise-coach-staging`**, then **Logs** (live or real-time logs; begin the log stream before you speak). Each
   reply prints a count-only `event: usage` line, with no message text. The same is possible from a computer with
   `cd backend && npx wrangler@4.158.0 tail --env staging --format=pretty` **[COMPUTER, optional]**.

### How to tell a real AI reply from the offline demo coach

- **No offline coach.** A TestFlight build is a release build: the offline demo coach is **not compiled in** and
  `DW_MOCK_AI` is ignored. In release, a reply is either from the Worker or an error notice ("Couldn't reach your
  coach...", "Coaching is temporarily unavailable..."). A "subscription required" or limit notice means the Worker
  answered but refused.
- **Specifics.** The reply uses your specifics (Friday, jazz bar, hiking) and the follow-up builds on the previous
  answer. The demo coach only matches a few keywords to fixed templates and gives the same text for the same question.
- **Repeat the question.** Ask the same question twice: a real reply is worded differently.
- **Logs.** The Cloudflare logs (step 6) show one usage event per reply.

## 6. Pass/fail checklist

Record each as PASS / FAIL with a note and the timestamp in the recording.

| # | Check | PASS when |
|---|---|---|
| 0 | Isolation | Section 1: namespace `740221` unused elsewhere; staging shows exactly the three bindings |
| 1 | Correct build | TestFlight build is 50000+; You tab shows the staging coach server line |
| 2 | Subscription | Sandbox purchase completes; coaches unlocked; no "subscription required" notice in chat |
| 3 | Permissions | Microphone and speech prompts appear with DateWise's text; allowing them enables Hold to talk |
| 4 | Speech recognised | The transcript matches what you said (minor wording differences are fine), on device, with no network error |
| 5 | Real AI reply | Specific to your question, consistent across a follow-up, different when repeated (section 5) |
| 6 | Voice playback | The whole reply is spoken in the coach's voice and language, not cut off at the end |
| 7 | Mouth sync | The mouth moves while the voice speaks, is closed in pauses and after the last word, and is not visibly ahead of or behind the sound (under about a tenth of a second by eye) |
| 8 | Latency | From releasing Hold to talk: first reply text within about 3 s, voice starting within about 2 s after that. Note the times; over 6 s in total is a FAIL to investigate |
| 9 | Stability | No crash, no stuck "Listening…" state, Hold to talk works again after each reply |

**Mouth sync has two drivers:**

- **Default** (`avatar_audio_path` unticked, what App Store builds use): flutter_tts speaks the reply and the mouth
  follows its word-range events (the word-anchored driver). Run this first.
- **Native audio path** (`avatar_audio_path` ticked, `--dart-define=DW_AVATAR_AUDIO_PATH=true`): `AVSpeechSynthesizer`
  renders the reply and the mouth follows the real audio loudness (and word markers on iOS 17+). This is an optional
  second build (build number 55000+) to compare. Also try:
  - headphones;
  - a call or Siri interruption;
  - backgrounding the app.

  See docs/avatar/TALKING_AVATARS.md and checklist items E4 and E7.

## 7. What to keep

- **The screen recording** with audio (microphone on) of the whole session. It should run from the You tab (the
  staging line) through at least three exchanges. It is saved to Photos.
- **The notes:**
  - the filled checklist above;
  - the build number;
  - the iPhone model and iOS version;
  - the voice used (default, Enhanced or Premium);
  - speaker or headphones.
- Keep recordings out of the repository if they show anything personal.

## 8. Teardown and cost

After the run (and after `docs/qa/LIVE_AI_TEST_PLAN.md` if you run it on the same staging deploy):

1. **Delete the staging Worker.** In Cloudflare in Safari: **Workers & Pages**, then **`datewise-coach-staging`**,
   then **Settings**, then scroll to the bottom and tap **Delete**. Type the name if asked, and check that it is
   `datewise-coach-staging`, never `datewise-photo-coach`. This deletes only the staging Worker, its Durable Object
   data and its salt. From a computer, `cd backend && npx wrangler@4.158.0 delete --env staging` does the same
   **[COMPUTER, optional]**.
2. **Check it is gone.** Open **https://datewise-coach-staging.scubamike124.workers.dev/?version**: it no longer shows
   `chat-v7-cost-guard`.
3. **Expire the build.** In App Store Connect: **TestFlight**, then the 50000+ build, then **Expire Build**, so testers
   do not keep a build that can no longer get replies.

**Cost: $0.**

- **Build:** GitHub-hosted macOS runners are free on this public repository.
- **Purchases:** TestFlight and Sandbox purchases are free.
- **Worker:** Workers Free covers the staging Worker, its Durable Object and the rate-limit binding.
- **AI:** a demo of a few replies uses a small part of the account's free **10,000-neuron daily allowance**, which the
  staging and production Workers **share**. Staging stops itself at `DAILY_NEURON_BUDGET` 4000, and Sandbox users at
  `SANDBOX_NEURON_BUDGET` 3300. On Workers Free, use past the allowance fails rather than bills.

No paid service or new account is needed.
