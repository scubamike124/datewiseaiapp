# App Store Server Notifications v2: recommendation and setup

Status: code ready and tested offline (`backend/subscription_resilience.test.mjs`).
Turning it on is **BLOCKED** until the owner has App Store Connect access and
deploys the Worker. Nothing here spends money: notifications are free, and the
endpoint runs on the same Worker and Durable Object.

## Recommendation: turn it ON for the v2 launch

The app works without notifications, and chat is never blocked by them. The
StoreKit 2 token the device sends is verified **offline** (JWS checked against
the pinned Apple Root CA - G3, no call to Apple). An Apple outage or a late
notification therefore never stops a subscriber from chatting.

But the token alone cannot know about some events, and notifications close those gaps:

| Event | Token only (`ASSN_ENABLED=0`) | With notifications (`ASSN_ENABLED=1`) |
|---|---|---|
| Refund / revocation (`REFUND`, `REVOKE`) | An older saved copy of the refunded transaction keeps working until its `expiresDate` (at most one month plus the 60-minute leeway). The leak stops sooner only if the device happens to send the revoked copy | Refused from the moment Apple sends the notification |
| Refund reversed (`REFUND_REVERSED`) | Not seen | Reinstated |
| Renewal not yet on the device (`DID_RENEW`, `SUBSCRIBED`) | The old token is refused after the leeway. The app re-reads StoreKit once and retries. If StoreKit cannot answer, the subscriber sees "subscription isn't active" plus Try again | The old token keeps working, because Apple confirmed the renewal for the same `originalTransactionId` (if that renewal is not refunded) |
| Billing Grace Period (`DID_FAIL_TO_RENEW` / `GRACE_PERIOD`) | Works only if `BILLING_GRACE_DAYS` exactly equals the App Store Connect setting. A mismatch locks out subscribers in grace | Follows Apple's own `gracePeriodExpiresDate`, whatever `BILLING_GRACE_DAYS` says (capped at 28 days) |
| Billing retry without grace, expiration (`DID_FAIL_TO_RENEW`, `EXPIRED`, `GRACE_PERIOD_EXPIRED`) | The token's `expiresDate` already ends access | Same, and any recorded renewal or grace is cleared |
| Auto-renew turned off (`DID_CHANGE_RENEWAL_STATUS`) | Access continues until `expiresDate` (correct) | Acknowledged; no change (correct) |

So notifications are **required for reliable refunds and revocations**, and for
grace handling that cannot drift out of sync. They also remove the most likely
lockout, a renewal that has not reached the device yet. They are **not required
for chat to work**.

Every notification is idempotent. The latest Apple `signedDate` wins per
subscriber (renewal and grace) and per transaction (revocation), so duplicates,
retries and out-of-order deliveries change nothing. A notification for another
product id (for example an IAP from before v2) is acknowledged and ignored.

## What `ASSN_ENABLED` does

- `"0"` (default in `backend/wrangler.toml`): `POST /apple/notifications` returns 404. The guard uses only the device token.
- `"1"`: the endpoint verifies each `signedPayload`, then its `signedTransactionInfo` and `signedRenewalInfo`, all offline. It stores only salted hashes and dates in the subscriber's Durable Object. The guard also checks that object when a token has expired, to apply a confirmed renewal or grace period.
  - 200: handled, or deliberately ignored (another environment or product, `TEST`, informational types). Apple stops retrying.
  - 400: not a valid notification for this app (forged, wrong bundle, mismatched inner transaction).
  - 503: the Durable Object was unreachable. Apple retries later, on its own schedule.
- `ALLOW_SANDBOX` applies here too. With `"0"`, Sandbox notifications are acknowledged and ignored.

## Owner steps (BLOCKED: needs App Store Connect and a Worker deploy)

1. Deploy chat-v7 (this branch, once approved) to the Worker. Note its URL, for example
   `https://datewise-photo-coach.scubamike124.workers.dev`. The notification URL is that URL plus `/apple/notifications`.
2. In `backend/wrangler.toml`, set `ASSN_ENABLED = "1"` (or set it in the Cloudflare dashboard under Workers › datewise-photo-coach › Settings › Variables), then deploy.
3. Sign in at https://appstoreconnect.apple.com → **Apps** → *DateWise AI - Dating Coach* (Apple ID 6780110141).
4. Open **App Information** (under *General* in the left sidebar), then scroll to **App Store Server Notifications**.
5. Next to **Production Server URL**, click **Set up URL** (or *Edit*). Enter `https://<worker-host>/apple/notifications`, choose **Version 2 Notifications**, and **Save**.
6. Next to **Sandbox Server URL**, click **Set up URL**. Enter the **same** URL and choose **Version 2 Notifications**. Sandbox state is kept apart (`sbx:` objects), so one Worker serves both. **Save**.
7. Check: make a Sandbox purchase on TestFlight (docs/qa/STOREKIT_SANDBOX_TEST_PLAN.md, test P1). The Worker log (`wrangler tail`, owner only) should show `{"event":"usage","kind":"assn","outcome":"SUBSCRIBED"}`. You can also call the App Store Server API *Request a Test Notification* endpoint. It needs an App Store Connect API key, so it is optional and you should not create one only for this. The Worker answers `TEST` with 200 and stores nothing.
8. If the field already holds a URL from before (see V1_PAYMENT_INVESTIGATION section 7), note who controls that host before you replace it.

Turning it off again: set `ASSN_ENABLED = "0"`. The App Store Connect URL can stay. Apple then gets 404 and retries for a while, and nothing else changes.
