# DateWise AI v2: subscription and privacy QA report

Branch under test: `claude/datewise-v2-app` at `b36b0eb` (PR #27).
QA branch: `claude/datewise-qa-store` (only new test files and this report).
Date: 2026-11-22. Nothing was bought, deployed or signed.

New tests:

- `test/qa_subscription_store_test.dart`: AppStoreService with a scripted
  `InAppPurchase` and a fake StoreKit 2 host API (`currentEntitlements`).
- `test/qa_privacy_test.dart`: Delete my data, Coach memory consent, the 18+
  block, the privacy disclosures, the backend, the paywall price and the voice gate.

Tests marked `skip: 'DEFECT Dn'` describe the correct behavior. They are
skipped because the current code fails them. Run them with
`flutter test --run-skipped`; each one has been checked to fail today.

## Test results

`flutter test` (whole suite, Flutter 3.47.9, Linux): **331 passed, 4 skipped,
0 failed**. `flutter analyze` on the new files: no issues.

`flutter test --run-skipped test/qa_*.dart`: the 4 defect tests fail as
expected (D1, D2, D3, D5).

Latest GitHub Actions runs for the branch, all at head `b36b0eb`:

- Tests #19: success.
- iOS build #7 (unsigned `flutter build ios --release --no-codesign`): success.
- The signed TestFlight job has never run.

## Verdict per check

| Check | Result |
|--|--|
| One paid plan, $19.99/month | PASS in the app, StoreKit file and metadata. Stale docs mention other plans (D9). |
| StoreKit file | PASS: one auto-renewable `datewise_premium_monthly`, P1M, 19.99, `introductoryOffer: null`, no other products or offers, Family Sharing off. |
| Paywall price | PASS: it shows only `ProductDetails.price` (tested with `19,99 €`). Without a price, Subscribe is disabled and no price is invented. |
| Auto-renew disclosure, Terms, Privacy, Restore | PASS. The copy says "Apple ID"; Apple now calls it "Apple Account" (D14). |
| Purchase success / pending / error / cancel | PASS. `completePurchase` is called for every transaction of our product. |
| Restore with or without a prior purchase | PASS on iOS. Android has a race (D3). |
| Expiration and lapsed entitlement | iOS: PASS on launch and resume through `Transaction.currentEntitlements`. Live `Transaction.updates` events are trusted blindly (D1). Android never clears the entitlement (D2). |
| Entitlement cached or spoofable on device | PASS: it is kept in memory only and never written to SharedPreferences. Forged `dw_tier`/premium keys do not unlock chat. |
| Chat and voice gated for non-subscribers | PASS: `sendMessage` and `retryLastReply` refuse, nothing reaches the backend, and voice from Home opens the paywall without asking for the microphone. |
| Backend enforcement | NONE: the Worker does not check any subscription for chat (D6). Reported for the cost-guard agent. |
| Delete my data | PASS: every `dw_` key is removed (chats, profile, plan, memory, stats, legacy tier and photo caches). The app writes no files. The 18+ block survives. |
| Memory consent | PARTIAL: memory is off by default and sent only while on, and the app never writes it by itself. Turning it off does **not** delete the note (D5). |
| 18+ gate | PASS: the existing tests in privacy_store_test.dart cover it, and a new test checks the block survives Delete my data. |
| Privacy text vs manifest vs nutrition label | CONSISTENT. Other User Content and Purchase History, not linked, no tracking, App Functionality only. UserDefaults uses CA92.1. No analytics or ads SDKs. Purchase History is declared but never actually sent (D11, harmless). |
| Backend stores no content | PASS: no `console.*` logging, no KV/D1/R2/Queues bindings, no outbound fetch, and no observability or logpush in wrangler.toml. |
| Release workflow | The secrets check works without error, but there is no build-number bump (D4). The workflow is not on `main`, so "Run workflow" is not available (D7). |

## Defects

Severity: High = can lose money or fail App Review; Medium = wrong behavior
users can hit; Low = edge case, docs or copy.

### D1 (Medium): iOS trusts every `purchased`/`restored` event

- **Where:** `lib/services/store_service.dart:259-263`.
- **Problem:** The StoreKit 2 plugin forwards each `Transaction.updates` event
  with status `purchased`. That includes unfinished renewals for a period
  that has already ended, and refunded or revoked transactions (the plugin
  does not look at `revocationDate`). These events can arrive at launch
  *after* `currentEntitlements` returned nothing. Chat then unlocks until the
  next resume.
- **Fix:** on iOS, re-read the entitlement instead of setting it to true:

  ```dart
  case PurchaseStatus.purchased:
  case PurchaseStatus.restored:
    if (_isIOS) {
      try { await _refreshEntitlement(); } catch (_) { _entitled = true; }
    } else {
      _entitled = true;
    }
    _error = null;
    _finishPending(_entitled ? PurchaseResult.purchased : PurchaseResult.failed);
  ```

  Then remove the `skip:` from the test "a Transaction.updates event is
  re-checked against currentEntitlements".

### D2 (Low; Android only, not shipping now): a lapsed Play subscription stays unlocked for the session

- **Where:** `lib/services/store_service.dart:249-252`.
- **Problem:** `_refreshEntitlement` only calls `restorePurchases()`. Nothing
  ever sets `_entitled = false` (memory only, so a relaunch fixes it).
- **Fix:** in the Android branch, set `_entitled = false` before
  `restorePurchases()`. Then wait for the stream to settle, for example with a
  `Completer` that completes on the first `restored` batch or after about 2
  seconds. Alternatively, use
  `InAppPurchaseAndroidPlatformAddition.queryPastPurchases()` and set
  `_entitled` from its result.

### D3 (Low; Android only): `restore()` returns before Play re-delivers the purchase

- **Where:** `lib/services/store_service.dart:309-321`.
- **Problem:** The paywall can say "No active subscription found" and then
  unlock a moment later.
- **Fix:** the same settle-wait as D2 inside `restore()` before returning
  `_entitled`, or use `queryPastPurchases()`.

### D4 (Medium; release): the TestFlight job never bumps the build number

- **Where:** `.github/workflows/ios-build.yml:222`. The version comes from
  `pubspec.yaml:19` (`2.0.0+4`).
- **Problem:** A second upload with the same `CFBundleVersion` is rejected by
  App Store Connect.
- **Fix:** derive the build number from the run:

  ```yaml
  flutter build ipa --release --build-number=$((100 + GITHUB_RUN_NUMBER)) \
    --export-options-plist="$RUNNER_TEMP/ExportOptions.plist"
  ```

  The +100 offset keeps it above 4 and above any earlier uploads. Print the
  number to `$GITHUB_STEP_SUMMARY`.

### D5 (Medium; privacy expectation): turning Coach memory off keeps the note

- **Where:** `lib/state/app_state.dart:136-140`. The copy is in
  `lib/l10n/app_en.arb:438` and `app_es.arb`.
- **Problem:** The note is not sent while memory is off, which is correct.
  But it stays on the device until the user clears it.
- **Fix:**

  ```dart
  Future<void> setMemoryEnabled(bool on) async {
    _memoryEnabled = on;
    await _storage.setMemoryEnabled(on);
    if (!on) await clearMemory();
    notifyListeners();
  }
  ```

  Then update `memoryOff` to "Off: your note is deleted and coaches only see
  the current conversation." (and the same in ES). Add a confirm dialog if
  the toggle should warn first. The other agent owns the ARB files.

### D6 (High, cost; current state only, owned by the cost-guard agent): the backend enforces no subscription

- **Where:** `backend/worker.js:617-619`.
- **Problem:** Any POST with `messages` is streamed through Workers AI. There
  is no transaction check, no rate limit and no Origin requirement for
  non-browser clients. The caller supplies its own `system` message, so the
  Worker is a free general-purpose LLM proxy. `tier` is client-sent and is
  only used for the photo path (`:621-623`).
- **Fix direction:** the app sends the StoreKit 2 JWS
  (`PurchaseDetails.verificationData.serverVerificationData`) with each
  request. The Worker verifies the JWS signature chain against Apple's root,
  checks `productId`, `bundleId` and `expiresDate`, and builds the system
  prompt itself from `coachId`. Add per-IP and per-`originalTransactionId`
  rate limits.

### D7 (Medium; release): `ios-build.yml` is not on the default branch

- **Where:** `main` has only `.github/workflows/deploy.yml`.
- **Problem:** The `workflow_dispatch` button (and so the signed TestFlight
  job) is unavailable until PR #27 merges. GitHub only offers it for
  workflows on the default branch.
- **Fix:** merge PR #27, or cherry-pick `.github/workflows/ios-build.yml`
  alone to `main`. Then run it on the branch with
  `gh workflow run ios-build.yml --ref claude/datewise-v2-app -f signed_build=true -f upload_testflight=true`.

### D8 (Low; release): a requested build can end "green" with nothing built

- **Where:** `.github/workflows/ios-build.yml:153-158`.
- **Problem:** When secrets are missing the job only adds a notice, and
  `upload_testflight` without `signed_build` silently does nothing.
- **Fix:** after the notice, add `exit 1` when `inputs.signed_build` is
  true, so a requested signed build fails visibly. Also add
  `if: inputs.upload_testflight && !inputs.signed_build` to a step that
  prints "tick signed_build too".

### D9 (Low; docs): stale docs describe other plans and prices

- **Where:**
  - `Project.PRD.txt:23-26` and `:137`: weekly Spark $4.99, Flame $7.99,
    Magnet $13.99, and a "free trial of Flame".
  - `backend/supabase_schema.sql:47-48`: spark/flame/magnet tiers.
  - `backend/README.md:28-48`: Magnet photo coach and "free tier".
  - `docs/launch/LAUNCH_READINESS.md:33` and
    `docs/qa/APP_STORE_1_0_2_RELEASE.md:34`: `freeLaunch`.
  - `docs/research/DATEWISE_AVATAR_AND_MODEL_RESEARCH.md:117,142`: "free
    tier" gating suggestions.
- **Problem:** None of these ship in the app, but they contradict "one plan,
  no free tier, no trial" and can mislead agents and reviewers.
- **Fix:** add a one-line "Superseded by v2: one plan,
  `datewise_premium_monthly`, $19.99/month, no free tier or trial" banner at
  the top of each file, or move them to `docs/archive/`.

### D10 (Low): transactions for other product IDs are never finished

- **Where:** `lib/services/store_service.dart:257`.
- **Problem:** `continue` skips `completePurchase`. A stray transaction (for
  example from sandbox testing of a removed product) is redelivered on every
  launch.
- **Fix:**

  ```dart
  if (p.productID != StoreConfig.productId) {
    if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    continue;
  }
  ```

### D11 (Info): Purchase History is declared but the app sends no purchase data

- **Where:** `ios/Runner/PrivacyInfo.xcprivacy`, and the comment at lines
  13-14.
- **Problem:** The app always sends `tier: "magnet"` (`AppState.aiTier`,
  `lib/state/app_state.dart:43`), not the purchase result. Over-declaring is
  allowed and safe.
- **Fix:** keep the declaration, because D6 will send the transaction JWS.
  Fix the manifest comment to say "the app will send the StoreKit
  transaction for server-side verification".

### D12 (Info): `DateWise.storekit` is not attached to the Run scheme

- **Where:** `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`.
- **Problem:** There is no `StoreKitConfigurationFileReference`. Step 23 of
  the checklist documents the manual step, and archives are unaffected.

### D13 (Low, cost; owned by the cost-guard agent): the v1 photo coach is still live on the Worker

- **Where:** `backend/worker.js:621-640`.
- **Problem:** The endpoint is gated only by a client-sent `tier`, while v2
  has no photo features.
- **Fix:** return 410 for `imageBase64`/`images` requests once v1 (1.0.x)
  adoption is gone.

### D14 (Low; copy, owned by the screens/ARB agent): "Apple ID" is now "Apple Account"

- **Where:** `lib/l10n/app_en.arb:363,376,460`, the ES equivalents, and
  `lib/content/legal_text.dart:49,87,141,180`.
- **Problem:** Since iOS 18, the path is Settings › [your name] ›
  Subscriptions, and Apple calls it "Apple Account".
- **Fix:** "Payment is charged to your Apple Account…" and "Cancel any time
  in Settings › [your name] › Subscriptions." Then regenerate `web/*.html`
  with `dart run tool/legal_pages.dart`.

### D15 (Low; docs): the macOS-minutes note does not apply

- **Where:** `.github/workflows/ios-build.yml:3-6` and
  `docs/appstore/checklist.md:92`.
- **Problem:** Both say macOS minutes count 10x against the allowance. The
  repo is **public**, so standard GitHub-hosted runners, macOS included, are
  free with no minute limit.
- **Fix:** reword to "free on this public repository".

## BLOCKED (not verified; needs Apple credentials, a signed build, a sandbox tester or an iPhone)

- A real StoreKit purchase, pending (Ask to Buy), cancel and error on a
  device with a Sandbox Apple Account.
- Restore on a second device or after a reinstall with a real Apple Account.
- Renewal, expiration, refund and revocation timing (sandbox accelerated
  renewals or the Xcode StoreKit test session). The unit tests use fakes
  only.
- That `ProductDetails.price` shows the localized App Store price in
  non-US storefronts.
- The paywall and its disclosures on a real iPhone. Screenshots for App
  Review need a TestFlight or simulator build.
- The signed IPA build, upload to App Store Connect, TestFlight processing
  and installation.
- That the App Store Connect product `datewise_premium_monthly` exists with
  $19.99, 1 month and no intro offer (needs App Store Connect access).
- That the App Privacy answers in App Store Connect match §3 of
  `docs/appstore/metadata.md`.
- Microphone and speech permission prompts in EN and ES on a device.
- Cloudflare dashboard settings (Workers Logs and Logpush off) for the
  production Worker. Only the repo config was checked.

## Shipping to TestFlight without a Mac

Everything below happens in a browser and in GitHub Actions on a
GitHub-hosted `macos-latest` runner, which is free on this public
repository. No paid service is needed beyond the Apple Developer Program
membership the owner already has.

### 1. App Store Connect API key (.p8)

1. App Store Connect › Users and Access › Integrations › App Store Connect
   API › Team Keys › **Generate API Key**.
2. Name it "DateWise CI" and give it the **App Manager** role.
3. Download `AuthKey_XXXXXXXXXX.p8`. It can be downloaded only once.
4. Note the **Key ID** and the **Issuer ID** shown on that page.

### 2. Distribution certificate, made on any OS with openssl

```sh
openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr \
  -subj "/CN=DateWise Distribution/C=US"
```

1. developer.apple.com › Certificates › **+** › **Apple Distribution**.
2. Upload `dist.csr` and download `distribution.cer`.
3. Convert it to a .p12:

   ```sh
   openssl x509 -inform DER -in distribution.cer -out dist.pem
   openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12 -passout pass:CHOOSE_A_PASSWORD
   base64 -w0 dist.p12 > dist.p12.b64   # macOS/BSD: base64 -i dist.p12
   ```

`-legacy` keeps the .p12 importable by the runner's `security import`.
Keep `dist.key` and `dist.p12` private and never commit them.

### 3. App Store provisioning profile

1. developer.apple.com › Profiles › **+** › **App Store Connect**.
2. Choose App ID `com.datewise.datewiseAi` and the certificate from step 2.
3. Name it "DateWise AppStore" and download it.
4. Encode it: `base64 -w0 DateWise_AppStore.mobileprovision`.

The App ID must have the In-App Purchase capability, which is on by default.

### 4. Add the 7 repository secrets

GitHub › Settings › Secrets and variables › Actions › New repository secret.

| Secret name | Value |
|--|--|
| `IOS_DIST_CERT_P12_BASE64` | Contents of `dist.p12.b64` |
| `IOS_DIST_CERT_PASSWORD` | The .p12 password from step 2 |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64 of the .mobileprovision file |
| `APPLE_TEAM_ID` | 10-character Team ID (developer.apple.com › Membership details) |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from step 1 |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from step 1 |
| `APP_STORE_CONNECT_API_KEY_P8` | Full text of `AuthKey_XXXXXXXXXX.p8`, including the BEGIN/END lines |

If any secret is missing, the job prints a notice naming the missing ones
and builds nothing (see D8 to make it fail visibly instead).

### 5. Make the workflow runnable and bump the build number

1. Get `ios-build.yml` onto `main` by merging PR #27 (D7).
2. Raise the build number for each upload: `version: 2.0.0+5`, `+6` and so
   on in `pubspec.yaml`. Alternatively, apply the D4 fix so CI sets it.

### 6. Run it

Actions › **iOS build** › Run workflow › branch `main` (or the release
branch), tick **signed_build** and **upload_testflight**.

The same from a terminal:

```sh
gh workflow run ios-build.yml --ref main -f signed_build=true -f upload_testflight=true
```

The job then:

1. installs the certificate into a temporary keychain;
2. switches the Runner target to manual signing in the CI checkout only;
3. runs `flutter build ipa` with an `app-store-connect` ExportOptions.plist;
4. keeps the IPA as an artifact for 7 days;
5. uploads it with `xcrun altool --upload-app --apiKey/--apiIssuer`.

### 7. In App Store Connect

1. Wait for the build to finish processing (about 10–30 minutes). Export
   compliance is answered by `ITSAppUsesNonExemptEncryption = NO`.
2. Go to TestFlight › Internal Testing, add the owner, and install with the
   TestFlight app on an iPhone.
3. Test purchases with a Sandbox Apple Account: Users and Access › Sandbox
   › Testers.

### Alternatives

- **API key only, with automatic signing.** This needs no certificate or
  profile: Xcode cloud-managed signing creates them. Replace the manual
  signing steps with
  `flutter build ipa --export-method app-store-connect` followed by
  `xcodebuild -exportArchive ... -allowProvisioningUpdates -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8 -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID`,
  with `DEVELOPMENT_TEAM` set. That needs 4 secrets: `APPLE_TEAM_ID` plus
  the three `APP_STORE_CONNECT_*` secrets. The key then needs the **Admin**
  role to create cloud-managed certificates. This is a workflow change; the
  current workflow uses manual signing.
- **fastlane match.** This stores certificates in a private git repository
  and needs extra secrets (`MATCH_PASSWORD` and repository access). It is
  not recommended here because it adds a second system for what the current
  7-secret job already does.

Reuse check: the new tests reuse `test/helpers.dart`, `FakeStoreService`,
`BackendAIService.buildPayload`, `NoSpeechService`, and the plugin's own
`setInAppPurchaseHostApis` test hook. No new dependencies were added.
