# StoreKit E2E debugging report (PR #54, storekit-e2e.yml)

Nothing was pushed and no repo file was edited. Labels: UNIT-TEST (simulated), SIMULATOR (StoreKit Test, still simulated), DEVICE (genuine Apple sandbox purchase).
**Nothing here is a genuine Apple purchase. The owner's TestFlight sandbox purchase on build 203 remains the only DEVICE verification.**

Evidence is in `logs/`: `run8_artifact_xcodebuild.log`, `run8_artifact_simulator.log`, `run6_xcresult_failure_messages.txt`, job logs for both runs, `flutter_tests.log`, `backend_tests.log`.

## 1. Failure signatures by attempt

| Run | Head | Runtime (from log) | What happened | Layer |
|---|---|---|---|---|
| 45448116009 (job 138644915040) | dd3eac5 | iOS 26.5, parallel clone | catalog passed; all 7 purchase-dependent scenarios timed out at 30 s: `waiting for: premium after purchase` (and `purchase returned` for Ask to Buy) with `transactions: []`, 7 x ~45 s = 320 s. Total step 671 s. Dart output is invisible in the job log (clone), recovered from the zstd-compressed xcresult in the artifact. | Infrastructure: simulator/OS. Product.purchase never produced a StoreKit transaction (the known iOS 26.3-26.5 `disableDialogs` bug, matches the author's note). Not the app, not the test. |
| 45454802455 (job 138669442151) | 4aee293 | iOS 26.2 (`OS:26.2` in destination list), serial | catalog passed. Purchase now went through (about 5 s) and then: `Null check operator used on a null value` at `in_app_purchase_storekit_platform.dart:228:65` from `AppStoreService._onPurchases (store_service.dart:693)`. All 7 later scenarios died instantly with `!inTest` / `!_expectingFrame` assertions and never ran their bodies. | App defect (robustness, low device impact) plus test-harness cascade. |
| runs 4, 7 | | | cancelled by the old concurrency group, no signal. Runs 1, 2, 3, 5 cancelled. | n/a |
| 45460961016 (run 9) | 4fcdcac (has the store fix) | | in progress when I finished | pending |

Run 6 runtime selection fix worked: moving to iOS 26.2 got past the hang. Runtime choice alone is not proven for 26.6+ (not seen on the macos-latest image yet).

## 2. Root cause of run 8 (the live blocker)

Layer: **app code, store_service.dart** (plus StoreKit Test quirk).
- `ios` plugin `sk2_transaction_wrapper.dart:174`: `purchaseID: id > 0 ? id.toString() : null`.
- First transaction in a fresh StoreKit Test session has id 0, so `purchaseID` is null, and `InAppPurchaseStoreKitPlatform.completePurchase` does `int.parse(purchase.purchaseID!)` (line 228) which throws.
- At 4aee293 `_onPurchases` called `await _iap.completePurchase(p)` unguarded (line 693). The exception escaped the stream listener, aborted the rest of the batch and the closing `notifyListeners()`, and flutter_test treated it as an uncaught error.
- On a real App Store transaction ids are large positive numbers, so this path is very unlikely on a device. But the same unguarded call would also abort a batch if `SK2Transaction.finish` ever threw (for example an already finished transaction), so containing it is a legitimate hardening, not a test accommodation.
- The author's commit 4fcdcac (already pushed, not mine) wraps it in `_complete()` with a log line and adds a unit test. I re-ran it: store tests pass (139 Flutter tests in the store/paywall/subscription files, 0 failures; patch 0001 is a copy of that commit for reference). Note the commit message says "id 0"; precisely the id is 0 and the plugin maps it to a null `purchaseID`.
- Remaining small point: finishing is skipped for such transactions in StoreKit Test, so they stay unfinished and are re-delivered at the next launch. The re-delivery is handled (entitlement comes from `currentEntitlements`). Acceptable.

### Why 6 of the 7 failures are not evidence about those features
After the uncaught async error flutter_test ends the test immediately while the scenario body keeps running its `_until`/`pump` loop. `LiveTestWidgetsFlutterBinding.postTest` then asserts `!_expectingFrame`, and every later `testWidgets` hits `!inTest`. Log: scenarios 3 to 8 print `[E]` within 20 ms of each other at 18:27:32. The Swift side then reports `did not finish` because `_results[name]` was only set to the real error in the catch path that never ran. So renewal, expiry, cancel with accelerated time, restore, refund and Ask to Buy have **never executed** in CI. Expect new findings in run 9 once the purchase scenario passes. Review of their code found no obvious defect, but that is unproven.
Proposed hardening, patch 0002 (UNTESTED on a simulator, `dart format` clean): capture `FlutterError.onError` reports during a scenario and make `_until` throw them, so the body stops and the next scenario starts clean. It does not weaken any assertion.

## 3. Other layers checked

| Layer | Finding |
|---|---|
| (1) Test | Assertions are sound; no await misuse found in the code that ran. Cascade described above. Accelerated-time scenario guard is conditional (`expiresMs != null && now < expiresMs - 3000`) so it cannot false-fail on date scaling. Per-scenario 30 s `_until` and 6 min test timeout are fine. |
| (2) Simulator config | `-scheme Runner -destination id=...` works; RunnerTests finds `DateWise.storekit` (catalog scenario passes, product found, price $19.99). Runtime hang on 26.3-26.5 confirmed by xcresult (no transaction). `-parallel-testing-enabled NO` is now set. No signing problem (`CODE_SIGNING_ALLOWED=NO`). Not a timeout in the step itself (run 8 ended after 14 s of test). The 15 min wall time of run 6 was build (about 3 min) plus clone plus the 7 x 45 s timeouts plus xcresult export. |
| (3) .storekit | One group, one product `datewise_premium_monthly`, P1M, 19.99, `introductoryOffer: null`, no code/ad hoc/winback offers, no other products, EN and ES localizations. Matches docs/review RELEASE_VERIFICATION (ASC READY_TO_SUBMIT, 19.99 USD). I could not query App Store Connect (no credentials), so the ASC state is as documented, not re-verified. |
| (4) App code | Product query, purchase, restore and entitlement logic read correctly (see requirements). The only defect found is the unguarded `completePurchase`, fixed in 4fcdcac. |

## 4. Requirements a to f

| Req | Result | Label | Evidence and notes |
|---|---|---|---|
| a. One product, $19.99/month, no trial/intro/annual anywhere | **PASS** | UNIT-TEST + static review | `.storekit`: 1 product, P1M, 19.99, `introductoryOffer null`. `StoreConfig.productId` single; backend `APPLE_PRODUCT_ID` default and wrangler.toml; `subscription_resilience.test.mjs` "one product: ..." (line 66) and "other-app tokens" (yearly id refused); `qa_subscription_store_test.dart` "DateWise.storekit has exactly one auto-renewable product", "paywall shows only the StoreKit price", "metadata states one monthly plan". Repo grep for annual/yearly/lifetime/trial/intro found only "none" statements and one negative test id. E2E catalog scenario passed in CI: SIMULATOR (queried 8 plausible other ids, only the monthly one returned). |
| b. Purchase unlocks premium, reflected in chat gating | **PASS (unit); simulator end to end not yet green** | UNIT-TEST. SIMULATOR pending | `AppState.canChat => store.isEntitled` (app_state.dart:55), paywall shown when `!isEntitled` (app.dart:85). Tests: "success: entitled, purchased...", "purchased: entitled from currentEntitlements". The E2E purchase scenario is exactly the failing one; run 9 decides. |
| c. Restore Purchases | **PASS** | UNIT-TEST | `restore()` = `AppStore.sync` then plugin `restorePurchases` then `currentEntitlements`. Tests: "Restore calls AppStore.sync, then reads the entitlement", "sync fails but StoreKit holds it: restored", "sync fails and nothing held: restoreFailed", "no purchase on this Apple ID: false, no error", cancelled Apple ID prompt, EN/ES "nothing to restore" widget tests (qa_sweep_restore_test). Simulator scenario "restore after reinstall" has not run yet. |
| d. Expiry, cancellation, grace | **PASS with two notes** | UNIT-TEST (app and backend) | App: entitlement is only `Transaction.currentEntitlements` filtered to the product id; unverified results are dropped (fail closed, plugin Swift). Auto-renew off is not read, so cancel keeps premium until StoreKit drops the transaction at expiry. Tests: "expired while the app was in the background: refresh() locks chat" and now proposed patch 0004 (cancel-but-active). Backend: expiresDate plus 60 min leeway (`EXPIRY_LEEWAY_MINUTES`), `BILLING_GRACE_DAYS=0`; tests "expired subscription refused; renewal lag within leeway allowed", "boundaries 59/61 min", "ASSN DID_CHANGE_RENEWAL_STATUS ... cancelling auto-renew keeps access until expiresDate", "DID_FAIL_TO_RENEW with/without grace", "billing grace without ASSN". Notes: (1) backend allows up to 60 min after expiry while the app ends exactly at expiry (deliberate clock-skew/renewal-lag leeway). (2) Grace is OFF in ASC by owner decision (docs checklist B15), so billing retry means no access in app and backend: consistent with the documented policy. Whether `currentEntitlements` keeps a subscriber during Apple's grace period if the owner later turns grace on is Apple behaviour I did not verify here; with ASSN off the backend would need `BILLING_GRACE_DAYS` set to match. Cancel with accelerated time scenario: SIMULATOR, not yet executed. |
| e. Failed, cancelled, pending, interrupted purchases | **PASS (one minor gap)** | UNIT-TEST | Tests: "error: failed, purchaseFailed shown, not entitled", "cancel: canceled, no error, not entitled", "pending (Ask to Buy): not entitled yet; unlocks when approval arrives", "the plugin throwing on buy: failed, not busy", "a purchased event StoreKit does not confirm does not unlock", "both re-reads fail: pending not failed", new "completePurchase failure is contained". `buy()` always clears `_busy`, so retry is possible. Gap: the 5-minute `buy()` timeout path (returns failed, leaves `_pending` set) has no test; harmless since a late event just completes a stale completer, but a unit test would pin it. Simulator Ask to Buy scenario not yet executed. |
| f. Receipt/entitlement validation | **PASS, two gaps (config)** | UNIT-TEST (backend, 116/116 pass) | App sends the JWS from `currentEntitlements` (`receiptData`) as X-DateWise-Entitlement; chosen latest-expiring; cleared when not entitled or refunded. Backend rules and covering tests below. |

### f. Backend rule to test map (backend/*.test.mjs)
| Rule | Code | Tests |
|---|---|---|
| Chain to Apple Root CA G3 (pinned SHA-256), x5c shape, ES256, marker OIDs, CA flags, critical extensions, cert validity at signedDate | apple_jws.js | cost_guard: "pinned Apple Root CA - G3 fingerprint", "correctly chained JWS verifies; production trusts only G3", "forged JWS variants rejected", "certificate rules: CA flags and unknown critical extensions", "Apple's own sample notification verifies"; security_attacks: "JWS key confusion"; subscription_resilience "forged tokens" |
| Bundle id, product id | cost_guard.js:250 | "forged, wrong-app and wrong-product tokens refused"; resilience "other-app tokens"; security "subscription state from the token" (bundle, product with trailing space) |
| Environment (Production; Sandbox only if ALLOW_SANDBOX; Xcode/LocalTesting/lowercase/missing refused) | :231,253 | cost_guard "environment: Production and Sandbox only"; security_attacks case table; resilience "sandbox token in production" |
| Expiry (+60 min leeway), missing/garbage expiresDate | :259 | cost_guard "expired subscription refused..."; resilience "expired transaction boundaries"; security table |
| Revocation (revocationDate) incl. replay of an older pre-refund copy | :258, reserve() | cost_guard "refunded / revoked: refused, and an older saved copy ... refused too"; ASSN REFUND tests; "REFUND_REVERSED reinstates"; resilience "REFUND, REVOKE, REFUND_REVERSED ... latest signed state wins"; "a refunded renewal is not used to accept an older token" |
| Upgrade-superseded transaction | :257 | security "an upgraded (superseded) transaction" |
| Fail closed (DO down, no binding, no token) | admit() | cost_guard "fails closed"; resilience "fail-open is off by default", "missing USAGE_GUARD binding", "missing or empty header" |
| Not-from-the-future signedDate | apple_jws.js | covered in forged variants (verify with `grep` if needed; not separately named) |

Refund isolation (the coordinator's point 2): revocation is keyed per hashed transactionId (`txHash`), not per subscriber, and `subStatus` only zeroes `renewedUntil` when the specific `renewedTx` is revoked. So a refund of transaction A does not revoke a renewal B. The code is correct. The existing test only proves it on the token path (`t-1` revoked, `t-2` works) and for the renewedTx case; **gap**: no test that an ASSN REFUND of A leaves an active renewal B working and that both a pre-refund copy of A and a later refund of B are refused. Proposed and run: patch 0003 (passes against current code, 2 tests; my scratch copy lacked `.github/`, one unrelated deploy-health test failed there only for that reason, the real repo run is 116/116).

Gaps (config and process, not code defects):
1. `ASSN_ENABLED = "0"` in wrangler.toml (both envs). With it off, a refunded transaction is only refused if a revoked copy actually reaches the backend. A user who refunds and replays the saved pre-refund JWS keeps access until its `expiresDate` (up to a month plus 60 min). The app itself clears the token after a refund. Turning ASSN on is already the owner's checklist item A5/B16; I recommend treating it as a launch blocker for refund enforcement. Do not report refunds as enforced server side until it is on and tested against Apple's real notifications (DEVICE/sandbox).
2. Backend leeway of 60 minutes after expiry (described above), by design.
3. No OCSP/online revocation check of the certificate chain (documented as offline by design).
4. StoreKit Test JWS is signed by a local test certificate, so the backend would (correctly) refuse it. CI E2E therefore proves app-side StoreKit behaviour only, never the backend acceptance. Backend acceptance of a genuine Apple-signed token is proven only by the unit tests with a throwaway PKI plus Apple's sample chain.

## 5. Proposed patches (patches/)
- `0001-store-contain-completePurchase-failure.patch`: copy of the author's commit 4fcdcac (verified: store tests pass).
- `0002-e2e-harness-stop-body-on-async-error.patch`: stops the cascade; UNTESTED on a simulator, formatted/parsed only. Optional.
- `0003-backend-tests-refund-isolation-and-cancel-until-expiry.patch`: 2 new backend tests, both pass.
- `0004-app-test-canceled-but-active-until-expiry.patch`: 1 new app unit test, passes in a scratch copy of the repo.

## 6. Next step
Wait for run 9 (4fcdcac). If purchase passes, scenarios 3 to 8 run for the first time; any failure there is then a real finding (read `[storekit-e2e]` lines and the xcresult). If run 9 fails with `Timed out ... transactions: []` the runtime picked was 26.3 to 26.5 again; check the `Pick and boot` step output. I did not alter assertions or skip anything.
