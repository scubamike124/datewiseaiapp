# StoreKit paywall fix ("DateWise Premium is not available in the store yet")

Branch `claude/overnight-2026-11-24` (draft PR #54). Nothing merged, deployed or submitted.

## Diagnosis (app side, build 196)

- Product id: `StoreConfig.productId = 'datewise_premium_monthly'` (lib/services/store_service.dart). It is the only id queried, and it matches App Store Connect and `ios/Runner/DateWise.storekit`.
- Plugin: `in_app_purchase 3.3.1` with `in_app_purchase_storekit 0.4.17`. StoreKit 2 is on by default (`_useStoreKit2 = true`), and the app never calls `enableStoreKit1`. So the app uses StoreKit 2 for products, purchases, entitlements and restore. There is no StoreKit 1/2 mismatch.
- With StoreKit 2, `queryProductDetails` calls `Product.products([...])`. When Apple serves nothing, the plugin returns an **empty list, `notFoundIDs = [id]` and `error = null`**. It sets `error` only when StoreKit throws (for example a network error).
- Old app handling: an empty list or a throw set `StoreError.productUnavailable`, which is the exact text the owner saw. `canPurchase` stayed false and Subscribe stayed disabled. `notFoundIDs` and the error were thrown away (nothing was logged), and the price showed "Price shown by the App Store".
- Retries: the old app retried **only on app resume** (`refresh()` → `_loadProduct()` when `_product == null`). It did **not** retry when the paywall opened, and there was no Try again button. A user who never leaves the app was stuck until relaunch.
- Things ruled out as causes:
  - Storefront or territory filter: none in the app.
  - Cached failure: none. The failure is not persisted, and every launch queries again.
  - `.storekit` file: it is only a file reference in the Xcode project. It is not in a scheme (`StoreKitConfigurationFileReference`) and not in the bundle, so TestFlight talks to the real sandbox.
  - Startup race: the entitlement is read first, then the product. Both run inside the 10 s init timeout. A slow product query that outlived the timeout still applied its result later, but nothing re-rendered it except the next store notification. The shared-query and retry logic now covers this.
- Conclusion: the app behaved as coded. The empty product list comes from App Store Connect (`MISSING_METADATA`: Apple does not serve products in that state to the sandbox or TestFlight). The app made it hard to diagnose and gave no way to recover without leaving the app.
- Other findings from re-reading the real plugin:
  - Restore: the plugin's StoreKit 2 `restorePurchases()` does **not** call `AppStore.sync()`. It only re-reads `Transaction.currentEntitlements`. The app's comments assumed it synced. Fixed (see below).
  - `res.productDetails.first` was used without checking the id. It now uses only `datewise_premium_monthly`.
  - The StoreKit 2 pending and cancelled events carry no transaction (`purchaseID == null`), and `SK2PurchaseDetails.pendingCompletePurchase` is true only for purchased. The app already calls `completePurchase` only when `pendingCompletePurchase` is true, which is correct. A test now covers it so it cannot regress (finishing a null id would crash the plugin's `int.parse`).
  - Revoked and refunded transactions are excluded from `Transaction.currentEntitlements`. The app already re-reads `currentEntitlements` for every `Transaction.updates` event, so a revocation locks chat and clears the JWS token. Tests now cover this with the real plugin's event shape.

## Changes

Commits (pushed to origin/claude/overnight-2026-11-24):

- `5ea0646`: paywall retry, Try again, Store status readout, Restore syncs, and their tests.
- `e8860b5`: tests for the explicit 18+ choice (EN and ES).

1. **Retries without a bypass** (`lib/services/store_service.dart`, `lib/screens/paywall_screen.dart`)
   - New `StoreService.retryProduct()` and `loadingProduct`. `AppStoreService` re-checks `canMakePayments` if needed, listens to the purchase stream once, and runs the product query.
   - Launch, resume (`refresh`), paywall open and Try again share one query that is already running (`_productLoad`), so they never double up.
   - When it opens, the paywall calls `retryProduct()` if the product or price is missing.
   - New **"Try again" / "Reintentar"** button (`paywall-retry`, existing `retry` string) shows whenever the product or price is missing, with a busy state.
   - Subscribe stays disabled until StoreKit returns the product and its price. There is no hard-coded price, no unlock without a verified StoreKit entitlement, and still exactly one monthly plan.
   - A Restore that finds nothing no longer clears `productUnavailable`. The "not available" message and Try again stay, and the restore message still says "No active subscription found".
2. **Store status readout and logging**
   - New `StoreDiagnostics` class (no secrets: no transaction, receipt or JWS). It records:
     - the product id queried
     - number of queries and the time of the last one
     - number of products returned and their ids
     - `notFoundIDs`
     - the plugin's error code and message, or the exception type
     - `canMakePayments`
     - the storefront country (`InAppPurchase.countryCode()`, which with StoreKit 2 is `Storefront.current.countryCode`; no native code needed)
     - whether StoreKit 2 is on
     - the loaded price, subscribed state, ready state and paywall error
   - Every query writes a `debugPrint('[DW store] product query #n: ...')` line with the same fields.
   - `lib/widgets/store_status_sheet.dart` is a hidden bottom sheet with Copy and "Query again". It opens on a **long-press on the paywall's plan card** or a **long-press on the version line under You › About**. It is English only (a technical readout).
3. **Restore**: on iOS, Restore now calls StoreKit 2 `AppStore.sync()` (injectable `appStoreSync`), then the plugin's `restorePurchases()`, then reads `currentEntitlements`. Only Restore calls sync, because it may ask the user to sign in. If sync fails but StoreKit holds the subscription, the restore succeeds. If sync fails and nothing is held, the paywall shows `restoreFailed`.
4. **Age confirmation**: it was already explicit. `_adult = false` on the 18+ step, so "I am 18 or older" starts unselected, Continue is disabled until the user taps it, tapping it again unselects it, and `AppState.completeOnboarding` refuses `adultConfirmed: false`. I did not change the code and added tests in EN and ES.

## Tests

- New `test/storekit_product_retry_test.dart` (31 tests):
  - Empty product list, plugin error, throwing query, failed storefront read and a wrong product id, with the diagnostics for each.
  - `retryProduct`: success, no query once loaded, no query before launch finishes, shared query, retry on resume, unavailable then available (stream listened to once), failed retry, and Restore keeping `productUnavailable`.
  - iOS with real StoreKit 2 event shapes: purchased (finished), pending (not finished, later approved), cancelled (not finished), unconfirmed "purchased" event (no unlock, no token), revoked while running (locks chat, clears the token), expired on resume, Restore calls sync, sync fails but held, sync fails with nothing held, a subscriber keeps chat without the product, and no JWS in the diagnostics.
  - Paywall in EN and ES: the message, Subscribe disabled, no price, a query on open, Try again loading the real price and enabling Subscribe without an unlock.
  - No Try again when the product is loaded or on web. Long-press opens Store status and a plain tap does not. The You › About long-press opens it too.
- New `test/age_confirmation_explicit_test.dart` (3 tests): EN and ES unselected start, Continue disabled, toggling, and `completeOnboarding` refused without the confirmation.
- The existing StoreKit 2 host-API fakes gained `sync()` (counted; it fails on request). No test was skipped or weakened.
- Results: `flutter analyze` reports no issues. `flutter test` passes 1,051 tests (the previous 1,017 plus 34 new) with none skipped. `node --test backend/*.test.mjs tool/live/*.test.mjs` passes 130 with 0 failures and 0 skipped.

## Still needs App Store Connect or the device

- App Store Connect: move `datewise_premium_monthly` out of MISSING_METADATA. It needs localization (display name and description), price, a review screenshot and review notes, and availability in the tester's storefront. Check the Paid Apps agreement and tax/banking are active, otherwise products are not served. A fully filled-in subscription for a first-version app shows "Ready to Submit", which the sandbox does serve.
- Device: install a new TestFlight build with these commits. On the paywall, long-press the plan card. Expect "Products returned: 1", an empty notFoundIDs and the $19.99 price. If it still shows 0 or the id is in notFoundIDs, note the "Storefront" and "Error code" values and compare the storefront with the subscription's availability.
- Not verified here: real StoreKit on a device. All tests use fakes of the plugin's host API and the plugin's own event shapes. A sandbox purchase, Ask to Buy, Restore (sync sign-in prompt) and a refund still need a device check.
