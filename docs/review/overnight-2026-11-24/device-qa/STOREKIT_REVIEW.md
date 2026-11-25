# Independent review: StoreKit paywall fix (5ea0646, e8860b5)

Branch `claude/overnight-2026-11-24`, DateWise AI. This was a read-only review: nothing was edited, committed or pushed.
I checked the plugin source against `in_app_purchase_storekit 0.4.17` in the pub cache.

## Verdict

**GO for a new TestFlight build.** I found no critical or major issues. The minor issues below can wait.
A TestFlight build is still not proof of a working purchase. The owner has to confirm on the device that the product loads, and Apple will not serve it until the Paid Applications Agreement is active.

## Results

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | 1,051 passed, 0 failed, 0 skipped |
| `node --test backend/*.test.mjs tool/live/*.test.mjs` | 130 passed, 0 failed, 0 skipped |

## 1. No bypass: OK

- `_entitled` is set in only two places:
  - On iOS, `_applyEntitlement` runs from `_readEntitlement`, which reads `SK2Transaction.currentEntitlements` filtered to `datewise_premium_monthly`.
  - On Android, the Play purchase stream sets it. That code is unchanged.
- None of the new code writes the entitlement:
  - `retryProduct`, `_queryProduct`, `_ensureAvailable` and the diagnostics only touch `_product`, `_error`, `_available` and `_diag`.
  - Restore still decides from `_refreshEntitlement()`. A failed `AppStore.sync` cannot unlock anything; it only allows the local read.
  - The diagnostics sheet's "Query again" calls `retryProduct` and nothing else.
- iOS purchase events still re-read `currentEntitlements`. A "purchased" event that StoreKit does not confirm does not unlock, and a test covers it.
- Debug-only flags cannot reach a release build:
  - `createStoreService` returns `FakeStoreService` only when `useFakeStore && (kIsWeb || kDebugMode)`. A release iOS build always gets `AppStoreService`.
  - `DW_MOCK_AI` is honored only when `kIsWeb || !kReleaseMode`.
  - `ReviewMode._active` requires `kIsWeb`.
  - The iOS workflow passes no `DW_FAKE_STORE` or `DW_MOCK_AI` defines.
- One thing to know about, not new in this change: `AppState.canChat` returns `true` when no store is attached. `main.dart` always attaches one.

## 2. Subscribe gating and price: OK

- Subscribe stays disabled unless `store.canPurchase && price != null`. `canPurchase` requires `_available && _product != null`.
- The only product accepted is one whose id is `StoreConfig.productId`. A test shows another id does not enable Subscribe.
- The price shown is only `_product.price` from StoreKit. Without it, the paywall shows the localized `priceFromAppStore` text.
- There is still one monthly plan.

## 3. Retry logic: OK, with two minor issues

- **No request storms.** `_productLoad ??=` makes launch, resume, paywall open and Try again share one query that is already running. `retryProduct` returns early while `_loadingProduct` is true, before launch has finished, or once the product is loaded. The Try again and "Query again" buttons are disabled while a query runs. In practice the app sends at most one query per user action or resume.
- **No listener leak.** `_sub ??=` is used in `_ensureAvailable`, and `dispose` cancels it. A test counts the listens.
- **Resume** (`refresh`) re-checks availability and loads the product while it is missing.
- **The product arriving after an earlier failure** is handled: `_product` is set and `productUnavailable` is cleared. Tests cover this.
- **minor-1: a late result does not redraw the paywall.** `_queryProduct` never calls `notifyListeners()`. Suppose a query is still running when the 10 s timeout in `retryProduct` or `refresh` fires. Those methods notify immediately, and when the query later finishes and sets `_product`, nothing notifies again. The paywall then keeps Subscribe disabled until another rebuild. Tapping Try again does recover it, because `_retryProduct` calls `setState`. Fix: call `notifyListeners()` at the end of `_queryProduct`.
- **minor-2: the `diagnostics` getter writes to `_diag`** (entitled, ready, price and so on) every time it is read. It is harmless, but a getter with side effects is surprising.
- **Purchase stream:** I checked against the plugin.
  - With StoreKit 2, `SK2PurchaseDetails.pendingCompletePurchase` is true only for `purchased`.
  - So `completePurchase` runs for purchased events. It does not run for pending, canceled, error or restored events, which carry no transaction or are already finished.
  - Tests cover pending, then approved; canceled; purchased; and revoked.

## 4. `AppStore.sync()` on Restore: OK, one minor issue

- The API use is correct. `AppStore().sync()` calls `hostApi2.sync()`, and the plugin's Swift code runs `try await AppStore.sync()`.
- The engineer's finding is right: the plugin's StoreKit 2 `restorePurchases` only goes through `Transaction.currentEntitlements` and does not sync.
- `sync` is called only from Restore, which the user starts. That matches Apple's guidance.
- What happens if the user cancels the Apple ID prompt:
  - `sync` throws, and the plugin reports the code `storekit2_failed_to_sync_to_app_store`.
  - If StoreKit already holds a subscription, Restore still succeeds.
  - Otherwise the user sees "Could not restore purchases."
- **minor-3: a cancelled prompt reads as a failure.** "Could not restore purchases." is acceptable but not ideal when the user simply cancelled. The plugin uses one error code for every sync failure, so telling a cancel apart means parsing `details` (`userCancelled`). This is optional.
- A Restore that finds nothing keeps `productUnavailable`. The message the user sees is still "No active DateWise Premium subscription was found for this Apple Account", because `_message` takes precedence.

## 5. Diagnostics sheet: acceptable, one minor issue

- **Contents.** It shows:
  - the product id, the query count and time, and the returned ids
  - `notFoundIDs`
  - the plugin error code and message, cut to 300 characters
  - `canMakePayments`, the storefront country and the StoreKit 2 flag
  - the price, the subscribed state, the ready state and the error name

  It shows no JWS, receipt, transaction id or token. A test checks that the JWS is absent. The Copy button copies the same text.
- **The `debugPrint` line** carries the same non-secret fields. The restore log prints only the exception's type.
- **Access.** It opens only on a long-press of the paywall plan card or of the You › About version line. A plain tap does nothing, and a test checks that.
- **App Review.** I think it is low risk for App Review. It is a read-only support readout, it unlocks nothing and it changes no behaviour.
- **minor-4: English only.** The brief asked for EN and ES; the engineer chose not to localize it ("technical readout"). Ordinary users can still reach it by long-pressing, and a Spanish-speaking user would then see an English sheet. Either localize the roughly 15 labels and the title and buttons, or show the long-press only in TestFlight or test builds (for example when `AIConfig.testBuildHost()` is set). This does not block TestFlight.

## 6. Tests: meaningful

- `test/storekit_product_retry_test.dart` (31 tests) runs the real `AppStoreService` against a fake `InAppPurchase` and a fake StoreKit 2 host API, set up through the plugin's `setInAppPurchaseHostApis`, with the plugin's real `SK2PurchaseDetails` event shapes. The tests check service and UI state, not just that the mocks were called:
  - Subscribe stays disabled.
  - No price is shown.
  - Nothing unlocks.
  - Only one query runs when several callers overlap.
  - The listen count stays at one.
  - The token is cleared after a revoke.
- The widget tests cover the paywall in EN and ES, Try again loading the real price, and long-press versus plain tap.
- `test/age_confirmation_explicit_test.dart` (3 tests, EN and ES) checks that the 18+ box starts unselected, that Continue stays disabled until it is ticked, and that the box can be unticked. These are tests only; the app code is unchanged.
- Gaps:
  - No test covers a query that times out and then succeeds (minor-1).
  - Nothing here exercises real StoreKit, as the engineer notes. A sandbox purchase, Ask to Buy, the Restore sign-in prompt and a refund still need a device check.

## Before and after the build

1. App Store Connect: confirm the Paid Applications Agreement and the tax and banking details are active. Without them, StoreKit will still return no product.
2. On the device: long-press the plan card. Expect "Products returned: 1", an empty notFoundIDs and the StoreKit price, then try a sandbox purchase and a Restore.
3. Optional follow-ups: fix minor-1 with one line, and handle minor-4 by localizing the sheet or gating it to test builds.
