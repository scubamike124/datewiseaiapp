# DateWise AI 2.0.0: owner-only App Store checklist

Everything in this list needs the owner (Apple Developer account holder,
legal or banking access). Nothing here has been done by an agent; no build has
been uploaded and nothing has been submitted. Do the steps in order.

App: **DateWise AI - Dating Coach**, Apple ID `6780110141`, bundle id
`com.datewise.datewiseAi` (unchanged; v2 is an update, not a new app).
Version **2.0.0**, build **100** (`version: 2.0.0+100` in `pubspec.yaml`; CI
TestFlight builds are 101 and up, see step 19).

**Still open for the owner** (details in the numbered steps):
- Interim coach portraits: the current `assets/coaches/` images are interim;
  replace them with the final, licensed portraits and record them (step 10).
- iPad 13" screenshots (2064x2752) are generated in
  `docs/appstore/screenshots/{en,es}/ipad-13/`; review them and upload them
  with the iPhone sets (steps 11 and 24). Regenerate after replacing the
  portraits.
- Live legal and support URLs: deploy the website so
  `https://datewiseai.com/privacy-policy` and `/terms-of-service` show the v2
  pages (served by `web/_redirects` on Netlify or `web/.htaccess` on Apache),
  and choose a live Support URL (steps 6 and 7).
- Billing Grace Period stays OFF unless you also change the backend (step 12a).

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

10. Replace the placeholder **coach portraits** in `assets/coaches/` (same file
    names) with the final, licensed portraits. Keep a record of the licence /
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
    (1 month, USD 9.99, no introductory offer, EN + ES localizations).
13. Add the subscription **review screenshot** (paywall from a TestFlight or
    simulator build showing the real price).
12a. **Billing Grace Period: keep it OFF** (Monetization › Subscriptions ›
    Billing Grace Period). The coach backend matches it with
    `BILLING_GRACE_DAYS = "0"` in `backend/wrangler.toml`, so chat stops when a
    renewal fails (Apple keeps retrying the payment; chat resumes once it
    succeeds). If you turn grace on, set `BILLING_GRACE_DAYS` to the same
    number of days (3, 16 or 28) and redeploy the Worker before release, or
    subscribers in grace would be refused.
13a. **App Store Server Notifications (recommended):** App Information › App
    Store Server Notifications › Production and Sandbox Server URL =
    `https://<worker-host>/apple/notifications`, Version 2, then
    `ASSN_ENABLED = "1"` (`docs/appstore/ASSN_SETUP.md`). With it, refunds take
    effect at once and Apple's grace period is followed even if
    `BILLING_GRACE_DAYS` is not matched.
14. Status should become "Ready to Submit". It is submitted together with the
    2.0.0 version (step 26), not on its own.
15. Optional: create a **Sandbox Apple Account** (Users and Access › Sandbox)
    for your own testing.

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

22. Install from **TestFlight** on an iPhone. Check: onboarding and 18+ gate,
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
27. Choose release: manual release after approval is recommended.
28. **Submit for Review** (owner only).
29. After approval: release, then confirm a real purchase works in
    production and that the 1.0.2 users update cleanly.
