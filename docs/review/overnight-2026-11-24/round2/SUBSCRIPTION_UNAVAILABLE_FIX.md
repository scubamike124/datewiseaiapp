# Subscription unavailable on iPhone (TestFlight build 196): diagnosis and fix, 2026-11-24

Symptom (owner's physical iPhone): paywall says "DateWise Premium is not available in the store yet",
Subscribe disabled, no price.

Diagnosis (read-only App Store Connect API, asc-verify runs 12-14):
- Product id matches: app `datewise_premium_monthly` (lib/services/store_service.dart) = App Store Connect.
- Bundle id com.datewise.datewiseAi; the app is sold in USA, CAN, MEX, ESP; build 196 IN_BETA_TESTING in the
  internal group "Owner" (1 tester).
- Subscription was MISSING_METADATA: en-US name and description present, prices set (US 19.99, CA 24.99,
  MX 399, ES 22.99), availability CAN/ESP/MEX/USA, no offers, family sharing off, but **no App Store review
  screenshot**.
- Owner's App Store Connect Business page: banking update processing (up to 24 h), **W-9 tax form missing**,
  Digital Services Act compliance in review. Per Apple TN3186, products do not load in sandbox/TestFlight until
  the Paid Applications Agreement is in effect (banking and tax active). This is very likely the main cause.

Fix done (2026-11-24 14:38 UTC, asc-verify run 45416207362, independently reviewed: GO):
- Uploaded the paywall screenshot (tool/asc/review-screenshot.png, 1290x2796) as the subscription's review
  screenshot. Subscription state is now **READY_TO_SUBMIT**. Nothing else changed.

Still required before the owner retests:
- Owner: finish the W-9 and wait for banking to finish processing until the Paid Applications Agreement shows
  Active. Then reopen the paywall on build 196 (or a newer build).
- Note: the `app-store-connect-write` GitHub environment ran without waiting for approval, so it has no
  required reviewer. Owner: add yourself as a required reviewer (Settings › Environments) if you want that gate.

Not yet verified on a device: product load, purchase, restore, expiry and entitlement in the sandbox.
