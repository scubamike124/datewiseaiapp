# Subscription resilience and enforcement (chat-v7)

Date: 2026-11-23. Scope: `lib/services/store_service.dart`, `backend_ai_service.dart`, `coach_usage.dart`,
`backend/cost_guard.js`, `apple_jws.js`, `worker.js`, `wrangler.toml`. Tests: `backend/subscription_resilience.test.mjs`
(server) and `test/subscription_resilience_test.dart` (device). Nothing is deployed. One plan,
$19.99/month (owner decision, 2026-11-23; previously $9.99).

## 1. The only plan is $19.99/month

Verified by tests, not only by reading:

- `ios/Runner/DateWise.storekit`: one subscription group with one subscription, `datewise_premium_monthly`, `P1M`, 19.99,
  no introductory, ad-hoc, code or win-back offers, `familyShareable: false`, and no other products
  (`subscription_resilience.test.mjs` test 1; `qa_subscription_store_test.dart`).
- `backend/wrangler.toml` `APPLE_PRODUCT_ID`, the `cost_guard.js` default, `StoreConfig.productId` and
  `docs/appstore/metadata.md` all name only `datewise_premium_monthly`.
- ARB and legal text never hard-code a price. They take the StoreKit price string (`privacy_store_test.dart`,
  `qa_subscription_store_test.dart`, `l10n_test.dart`). The disclosure says monthly, and there is no free plan, trial or annual plan.
- The only other id in the repo, `datewise_premium_yearly`, appears in one test, which checks that a stray
  product is finished and never unlocks chat.

## 2. Server-side enforcement: audit

| Attack | Result | Test |
|---|---|---|
| Forged JWS (another chain, re-signed or swapped payload, `alg: none`) | 403 `SUBSCRIPTION_INVALID` before any model call | `forged tokens…` |
| Other-app JWS (bundle, product, a notification or renewal-info JWS used as a token) | 403 `SUBSCRIPTION_INVALID` | `other-app tokens…` |
| Replay / sharing one token from 30 networks at once | One counter keyed on `originalTransactionId`: exactly `DAILY_MESSAGE_LIMIT` succeed | `replay: one token shared…` |
| Replay of a previous period | `SUBSCRIPTION_EXPIRED` (unless Apple confirmed a renewal through notifications) | `replay of a previous period…` |
| Expired transaction | Refused after `EXPIRY_LEEWAY_MINUTES` (59 min accepted, 61 min refused); missing or non-numeric `expiresDate` refused | `expired transaction…` |
| Sandbox token on the production Worker | `ALLOW_SANDBOX=0`: refused. `=1` (needed for TestFlight and App Review): own `sbx:` counter, `SANDBOX_DAILY_LIMIT`, and **new** its own budget slice `SANDBOX_NEURON_BUDGET` (10%), so TestFlight cannot drain the subscribers' budget and v1 traffic cannot starve App Review. `Xcode`, `LocalTesting`, empty and wrong-case environments are refused | `sandbox token in production…` |
| Missing, empty or whitespace header on a v2 request | 403 `SUBSCRIPTION_REQUIRED` whatever `REQUIRE_SUBSCRIPTION` says | `missing or empty header…` |
| Legacy spoofing (a v2 client posing as v1) | See below | `legacy spoofing…` |
| Header injection: two headers (joined by `, `), suffixes, `Bearer` prefix, JSON, 70 kB | `SUBSCRIPTION_INVALID`. CR/LF cannot be put into a Fetch header at all. `X-Forwarded-For`, `X-Real-IP`, `True-Client-IP` and `Forwarded` are ignored, because only Cloudflare's `CF-Connecting-IP` picks the anonymous bucket. Prototype keys as `coachId` get 400. The token is never echoed | `header injection…` |
| Concurrency | Counters are atomic per Durable Object (exact counts under 30 parallel requests). The same notification 10 times in parallel is applied once. **Fixed:** the Worker kept the CORS origin in a module variable, so two interleaved requests in one isolate could get each other's `Access-Control-Allow-Origin`. The origin is now set per response | `concurrency: …` (2 tests) |

### Legacy spoofing: what posing as v1 gains

A request with no `coachId` and no token is treated as the v1 build (1.0.2), and anyone can send one. While
`LEGACY_CLIENTS=1` it gets:

- the per-network anonymous bucket: `ANON_DAILY_LIMIT` 60 a day and `ANON_MONTHLY_LIMIT` 600 a month per IPv4
  address or IPv6 /64;
- a share of **one global slice**, `ANON_NEURON_BUDGET` = 2,000 neurons a day, which it shares with every real v1 user;
- its own system prompt (v1 builds its persona on the device). That makes it a small general-purpose model proxy.

Quantified, at Workers AI prices (Llama 3.3 70B: 26,668 / 204,805 neurons per million input / output tokens; $0.011 per
1,000 neurons above the free 10,000 a day):

| | Before | Now (new legacy caps 3,000 in / 500 out) |
|---|---|---|
| Worst-case reservation per message | 324 neurons (6,000 in, 800 out) | 183 neurons |
| Typical message (2,000 in, 300 out) | about 115 neurons | about 115 neurons |
| What all spoofers together can take per day | 2,000 neurons, roughly 6 maximum-size or 17 typical messages | the same 2,000 neurons, roughly 10 maximum-size or 17 typical messages, with shorter context and replies |
| Money | $0 on Workers Free (inside the free allowance); at most $0.022 a day ($0.66 a month) if the same 2,000 neurons were billed on Workers Paid | same |
| Subscribers' budget | untouched (the other 80%) | untouched |
| Subscriber counters | never touched | never touched |

So the gain is small and capped. The real harm is that spoofers can use up the slice that real v1 users share.

**Safest default, implemented:**
1. `LEGACY_MAX_INPUT_TOKENS=3000` and `LEGACY_MAX_OUTPUT_TOKENS=500`, for the token-less path only (v2 subscribers keep 6,000 / 800).
2. A forced update that v1 can display. v1 has no update mechanism, and it shows its generic outage text for any non-200
   response, so a 426 would look like an outage. With `LEGACY_CLIENTS=0`, a v1 chat request now gets **HTTP 200** with
   a single SSE event in v1's own format (`data: {"response": …}` then `data: [DONE]`). The text is "DateWise has a new version. Please update the app in the App Store to keep chatting with your coach."
   It is in Spanish when the request looks Spanish: an explicit `language`/`locale` field first, then `Accept-Language`, then the last user message. v1 sends no
   language field, so the last message is usually what decides. No model call, no counter and no budget are used. The v1 photo coach gets 426 with a
   `message`, which v1 prints in its error text.
3. **Rollout:** keep `LEGACY_CLIENTS=1` for **60 to 90 days after v2 ships**, then set it to `"0"`. Note from
   `V1_PAYMENT_INVESTIGATION.md`: the live App Store 1.0 calls a different Worker host (`kaowserprobd.workers.dev`), and it
   is unknown whether 1.0.2 (which calls this Worker) ever shipped. If App Store Connect version history shows that 1.0.2 never
   went live, no real client uses this path, and `LEGACY_CLIENTS=0` can be set at v2 launch.
   `REQUIRE_SUBSCRIPTION=1` would also refuse v1, but with a 403 that v1 cannot display, so `LEGACY_CLIENTS=0` is the better switch.

## 3. App Store Server Notifications v2

Recommendation: **on for the v2 launch.** Notifications are needed for refunds and revocations to take effect at once, for grace
that cannot drift out of sync, and to keep a token whose renewal has not reached the device yet working. Chat works without them: every check is offline JWS, so an Apple
outage blocks nothing. Setup, what `ASSN_ENABLED` does, and the exact App Store Connect steps are in `docs/appstore/ASSN_SETUP.md`.

Handled idempotently (the latest `signedDate` wins), with tests for each:
`SUBSCRIBED` (INITIAL_BUY, RESUBSCRIBE), `DID_RENEW` (and BILLING_RECOVERY), `DID_FAIL_TO_RENEW` with and without
`GRACE_PERIOD`, `GRACE_PERIOD_EXPIRED`, `EXPIRED` (VOLUNTARY, BILLING_RETRY, PRICE_INCREASE, PRODUCT_NOT_FOR_SALE),
`REFUND`, `REFUND_REVERSED`, `REVOKE`, `DID_CHANGE_RENEWAL_STATUS` (both subtypes), `TEST`, plus informational types,
an unknown product id, out-of-order delivery, a refunded renewal, Sandbox isolation, forged or mismatched payloads (400)
and storage outages (503, so Apple retries).

## 4. Lockout map: every way a paying user could be refused

| # | Path | Before | Fix / behaviour now | Test |
|---|---|---|---|---|
| L1 | StoreKit `currentEntitlements` fails or hangs at launch | One read. The product query ran first and shared the 10 s launch limit. A failure meant a subscriber saw the paywall | The entitlement is read **before** the product query, with a 4 s timeout per read and a **second read** after 1 s. If both fail, the paywall says "Could not reach the App Store" and offers **Restore purchases**, and the next resume reads again | `launch: …` (4 tests) |
| L2 | Purchases unavailable on iOS (Screen Time "In-App Purchases: Don't Allow", a StoreKit hiccup, `isAvailable()` throwing) | Entitlement **never read**, so an active subscriber was locked out | The iOS entitlement is read anyway (it is local). Restore and resume also read it. A lapsed subscription still locks chat | `purchases unavailable on iOS…` |
| L3 | Restore on a new device when `AppStore.sync` fails (offline, sign-in cancelled) | `restoreFailed` without reading the local entitlement | The local entitlement is still read. Restored if StoreKit holds it, otherwise `restoreFailed` ("try again") | `restore on a new device` (3 tests) |
| L4 | Token renewed mid-session | The client re-reads StoreKit once and retries once (existing) | Unchanged and now tested end to end with the real `AppStoreService.refresh`. With notifications on, the server also accepts the previous-period token once Apple confirms the renewal | Dart `a token that renewed mid-session…`; server `ASSN SUBSCRIBED and DID_RENEW…` |
| L5 | Clock skew | n/a | Only Cloudflare's clock is used. Device time and `Date` headers are ignored. Apple's `signedDate` may be up to 5 min ahead | `clock skew…` |
| L6 | Durable Object unavailable (`GUARD_UNAVAILABLE`) | Fail closed for everyone | **Still fail closed by default** (`Retry-After: 30`, the chat says "busy" and offers Try again). An **opt-in**, multiply bounded fail-open exists for verified Production subscribers (below). A missing binding always fails closed | `fail-open is off by default…`, `missing USAGE_GUARD binding…`, `opt-in fail-open…` (5 tests) |
| L7 | `expiresDate` passes just before the renewal reaches the device | 60-min leeway | Unchanged (`EXPIRY_LEEWAY_MINUTES`), boundary-tested. Notifications extend it with the confirmed renewal | `expired transaction…` |
| L8 | Billing retry | No access until Apple recovers the payment (correct: the user has not paid) | Unchanged. With notifications, `DID_RENEW`/`BILLING_RECOVERY` reopens chat at once, even with the old token | `ASSN DID_FAIL_TO_RENEW without grace…` |
| L9 | Billing Grace Period on in App Store Connect but `BILLING_GRACE_DAYS` not matched | Subscribers in grace refused | With notifications, Apple's `gracePeriodExpiresDate` is followed. Without them, `BILLING_GRACE_DAYS` must match (checklist step 12a) | `ASSN DID_FAIL_TO_RENEW with GRACE_PERIOD…`, `billing grace without ASSN…` |
| L10 | Family Sharing | Off (`familyShareable: false`), so Apple issues no family transactions | An Apple-signed `FAMILY_SHARED` transaction is accepted if Family Sharing is ever turned on (doing that cannot be undone in App Store Connect). Whether family members share a counter is unverified: **BLOCKED** (Sandbox) | `restore on a new device / family sharing…` |
| L11 | Unknown product id (an IAP created before v2) | Finished on the purchase stream, never unlocks chat (existing) | Also: never sent as the token. The latest-expiring entitlement of our product is sent. Notifications for it get 200 and are ignored | Dart `unknown product ids` (3 tests); server `ASSN: unknown product id…` |

**Fail-open decision (L6): off by default, opt-in.** Cost risk against customer harm: a Durable Object outage is rare and usually
short, but failing closed shows every paying subscriber "Coaching is busy" for as long as it lasts. Failing open removes the budget breaker,
and an attacker could try to cause it by overloading the hot `global` object. Per-isolate caps alone do not bound the total, because
the total is that cap times the number of isolates. So the default stays **fail closed** (`FAIL_OPEN_PER_SUBSCRIBER = FAIL_OPEN_PER_ISOLATE = "0"`
in the code and in `wrangler.toml`). The owner can opt in. Every one of these bounds must hold:

1. Only when a Durable Object call **throws**. A missing `USAGE_GUARD` binding is a configuration error and always gets 503.
2. Only a **Production** token that verifies offline (Apple-signed, this app and product, not expired, not revoked in the token). Sandbox, v1/anonymous,
   expired, revoked and forged requests fail closed.
3. Per isolate and clock hour: `FAIL_OPEN_PER_SUBSCRIBER` per subscriber and `FAIL_OPEN_PER_ISOLATE` in total.
4. Per isolate and outage: at most `FAIL_OPEN_MAX_MINUTES` (15). An outage ends only after 10 quiet minutes with no Durable Object call
   throwing. A single successful call does not end it, so a flapping Durable Object cannot restart the 15-minute bound.
5. Across isolates: the dedicated `FAILOPEN_LIMITER` rate-limit binding must allow both `failopen:<subscriber>` and `failopen:all`.
   It is required: the existing `RATE_LIMITER` is never used as a fallback, so with no `FAILOPEN_LIMITER`, or a failing one, the request
   fails closed even if the two variables are set. The Workers rate limit counts **per Cloudflare location**, so this bound is per colo
   (each location has its own `failopen:all` counter), not global.
6. Each fail-open request gets the legacy per-request caps (3,000 tokens in, 500 out), which is at most 183 neurons. It carries `X-DateWise-Degraded: 1`.

**Recommended values if the owner opts in:** 3 per subscriber and 10 per isolate. Exposure math, at most 183 neurons per message and $0.011 per 1,000
neurons above the free allowance on Workers Paid (on Workers Free, Workers AI stops at the free 10,000 a day, so $0):
- Per isolate: at most 10 messages per outage (the 15-minute bound sits inside an hour, or straddles two hours for at most 20), so about 1,830 to 3,660 neurons.
- Across isolates, with the required `FAILOPEN_LIMITER` binding (commented out in `wrangler.toml`, 10 a minute per key): `failopen:all`
  allows at most 10 × 15 = 150 messages **per Cloudflare location** per outage, about 27,000 neurons, or $0.30 per location on Workers Paid.
  The total is that times the number of locations that receive fail-open traffic during the outage, because the counter is per colo.
- During an outage the revoked list cannot be read, so a refunded user holding an old token could get those few messages.

Recommendation: leave it off until the count-only logs show that Durable Object outages actually happen. If you turn it on, use the values above and uncomment `FAILOPEN_LIMITER` (with a namespace_id unique in the account); without that binding fail-open stays closed.

**Always an action, never a dead end.** Paywall: Subscribe, **Restore purchases**, Close, and a message for each store error.
Chat refusals: `SUBSCRIPTION_EXPIRED`/`REQUIRED` say "isn't active", and `SUBSCRIPTION_INVALID` says "Tap Restore purchases", both
with **Try again**. `GUARD_UNAVAILABLE`/`SERVICE_BUDGET_EXHAUSTED` say "busy" with Try again. `RATE_LIMITED` says "slow down" with Try again.
`DAILY_LIMIT`/`MONTHLY_LIMIT` give the reset time and no instant retry. The subscription notices also open the paywall (Subscribe,
**Restore purchases**) from the chat bubble itself: `SUBSCRIPTION_REVOKED`, `SUBSCRIPTION_EXPIRED` and `SUBSCRIPTION_REQUIRED` show
**See DateWise Premium**, and `SUBSCRIPTION_INVALID` shows **Restore purchases** (`CoachLimitCode.paywallAction`; tests in
`test/coach_limit_ui_test.dart`, EN and ES). The paywall is also reachable from Settings › Subscription.

## 5. Existing subscriptions (v1)

v1 sold nothing in the app (no billing SDK, `MockPurchaseService`, `freeLaunch=true`; see
`V1_PAYMENT_INVESTIGATION.md`). Before creating `datewise_premium_monthly` (checklist step 12) the owner must check
**App Store Connect → Apps → DateWise AI (6780110141) → Monetization → Subscriptions and In-App Purchases** and list
every existing product id and its status. **BLOCKED** (owner sign-in).

- **None:** create `datewise_premium_monthly` as planned.
- **Some exist but were never approved or sold** (Missing Metadata, Ready to Submit, Developer Removed): leave them alone or
  remove them from sale. Do not reuse their ids (Apple never allows reuse). Put `datewise_premium_monthly` in its own group, DateWise Premium.
- **One was approved and sold** (check Sales and Trends › Subscriptions): its subscribers stay on that product, and a new id does
  not migrate them. Options: (a) keep it on sale until its subscribers lapse, and create `datewise_premium_monthly` in the **same**
  subscription group so they can crossgrade; (b) tell the developer agent before release, because the app and the Worker accept only
  `datewise_premium_monthly`. Supporting a second id means adding it to `StoreConfig` and `APPLE_PRODUCT_ID` (a code change that needs review).
  Until then the code fails safe: an unknown product's transaction is finished (completed) on the device so it is not re-delivered, it
  never unlocks chat or becomes the token, the Worker refuses it (`SUBSCRIPTION_INVALID`), and its notifications get 200 and are ignored.

## 6. BLOCKED (needs Apple access)

Everything in `docs/qa/STOREKIT_SANDBOX_TEST_PLAN.md`; the App Store Connect product check (section 5); setting the
notification URLs (`docs/appstore/ASSN_SETUP.md`); confirming that StoreKit's `currentEntitlements` includes a
subscription in Billing Grace Period and in billing retry on a real device; confirming the Family Sharing counter behaviour; and
measuring real Durable Object outage frequency before tuning the fail-open numbers.
