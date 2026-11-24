# Release verification after the owner's W-9 and bank approval (2026-11-24)

Source: read-only App Store Connect API check, workflow `asc-verify.yml`, run 45440171206 (job 138608776741,
16:42 UTC). Nothing was written to App Store Connect by this run.

| Check | Result | How verified |
|---|---|---|
| Subscription `datewise_premium_monthly` exists | PASS | ASC API |
| Only one subscription (no annual, no other plan) | PASS, 1 subscription in 1 group | ASC API |
| Period one month | PASS, ONE_MONTH | ASC API |
| State | READY_TO_SUBMIT (was MISSING_METADATA before the review screenshot) | ASC API |
| Review screenshot processed | PASS, delivery COMPLETE | ASC API |
| US price $19.99 | PASS (CA 24.99, MX 399, ES 22.99) | ASC API |
| No free trial or introductory offer | PASS, 0 offers | ASC API |
| Territories | USA, CAN, MEX, ESP | ASC API |
| Localizations | en-US only; es-MX / es-ES planned (plan hash 4c18b2c8…, not applied) | ASC API |
| TestFlight build 2.0.0 (203) | VALID, internal IN_BETA_TESTING, group "Owner" | ASC API |
| Paid Applications Agreement active | PASS: ACTIVE, effective 2026-11-23 through 2027-06-01; Free Apps Agreement also ACTIVE; bank approved; W-9 uploaded | owner, verified in App Store Connect (the API cannot read it) |
| Product loads, price shows, Subscribe enabled on a device | NOT YET TESTED on a physical iPhone | needs owner |
| Sandbox purchase, restore, premium unlock | NOT YET TESTED on a physical iPhone | needs owner |
| Cancellation / expiration handling | Covered in unit tests and the StoreKit Test simulator run (see storekit-e2e); not on device | simulated |

Status: every App Store Connect setting the app depends on is correct, and the agreement blocker is cleared (owner
verification, 2026-11-24). The subscription is not marked as passing
until it loads and completes a sandbox purchase on the owner's iPhone with build 203.

## Live AI coach backend (checked 2026-11-24 16:50 UTC)

| Check | Result |
|---|---|
| Live Worker version (`?version`) | `chat-v5`, the retired model; live coach chat still fails |
| chat-v7 deploy rehearsal on `main` (run 45441299151, dry run, no upload, no credentials) | PASS: offline Worker tests, wrangler.toml checks, bundle, guard bindings, expected `?version` |
| Last real deploy attempt (run 45310505107, 02:11 UTC) | FAILED at the first step: `CLOUDFLARE_API_TOKEN` (and `CLOUDFLARE_ACCOUNT_ID`) are empty in the `production-worker` environment |

Remaining owner step: add `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` and `ID_HASH_SALT` as secrets of the
`production-worker` environment (Settings → Environments), then run Actions → Deploy coach Worker on `main`, target
`chat-v7-cost-guard`, with "Dry run" unticked. After that: real EN/ES coach conversations on the device are tested.

## Reusing the existing Cloudflare credentials (investigated 2026-11-24, no secret values read)

- DateWise repository: the Worker deploy workflow refuses repository and organization secrets on purpose; the three
  values must be secrets of the `production-worker` environment. Run 45310505107 proved that environment's
  `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` were empty at 02:11 UTC.
- Amber already holds the Cloudflare token and account ID for the account that runs
  `datewise-photo-coach.scubamike124.workers.dev` (Amber docs: token verified, Workers OK).
- Amber has an owner-only, already-merged mechanism to reuse them without exposing them: amberai #1709 (`ac290329`,
  on `main` since 2026-11-24 03:04 UTC), `src/lib/app-store-connect/worker-secret-sync.ts` behind the Vault page button
  "Send App Store Connect key to GitHub (DateWise)" (Infrastructure section). It verifies the Cloudflare token
  read-only, makes sure `production-worker` has the owner as required reviewer and is limited to `main`, derives
  `ID_HASH_SALT` server-side, and writes the three values sealed to GitHub. Values never reach a browser, log or agent.
  The earlier failed deploy (02:11 UTC) predates this change.
- Agents cannot press it: it needs the owner's Amber sign-in (HQ owner, same-origin). Reading Amber's vault any other
  way would be credential extraction and is not done.
- Not recommended: Amber's `/dashboard/deployments/worker` single-file redeploy. It can only push chat-v6, which has no
  subscription check, no per-user limit and no AI budget; build 203 needs chat-v7.
- If the sync reports that the Cloudflare token cannot edit Workers scripts, a new token is genuinely needed
  (runbook §1b: Account > Workers Scripts > Edit, DateWise account only).
- Budget note: the account's free Workers AI allowance (10,000 neurons a day) is shared with Amber. chat-v7 keeps
  `DAILY_NEURON_BUDGET = 10000` with a 6,000 sandbox slice, so the Worker's own guard stops spending at the free
  allowance; Amber's own Workers AI use on the same account could make DateWise hit the cap earlier. No paid usage
  is enabled by this deploy.

## Production deploy of chat-v7 (2026-11-24, run 7 at fd928f0, owner-approved)

Evidence from the run's own log and from direct requests made afterwards. Automated checks only; no genuine AI reply has
been verified yet (that needs an Apple Sandbox receipt from a TestFlight purchase).

| Check | Result |
|---|---|
| Live version before | chat-v5 (every chat returned 502: retired model) |
| ID_HASH_SALT | Missing on the Worker and in the environment, so the new salt step generated 32 random bytes (never printed) and uploaded it with the deploy; the deploy output lists `env.ID_HASH_SALT ("(hidden)")`. The Cloudflare token and account ID were only read. |
| Deploy | Success: version c04127ff-0e19-478f-9b51-c9fed21afcc7; rollback point 476d5cc9-bd29-433b-9cd0-fa9d43b76ab7 |
| Bindings listed by the deploy | Durable Object USAGE_GUARD, AI, rate limiter 60/60 s, production limits (SANDBOX_DAILY_LIMIT 20, SANDBOX_NEURON_BUDGET 6000, REQUIRE_SUBSCRIPTION 1, LEGACY_CLIENTS 0, ASSN_ENABLED 0, FAIL_OPEN 0) |
| `GET /?version` | `chat-v7-cost-guard` |
| Chat request with no receipt | 403 SUBSCRIPTION_REQUIRED, 8 of 8 repeated requests (no AI call) |
| Forged receipt | 403 SUBSCRIPTION_INVALID |
| Apple's public sample notification used as a receipt | 403 SUBSCRIPTION_INVALID |
| Old-app style request (v1) | 426 APP_UPDATE_REQUIRED |
| Oversized body with no receipt | 403 (refused by the subscription gate before the body is processed) |
| GET / | 405 |
| Deploy job status | Red: the job's own health check got one 502 within about a second of the upload (start-up race) and has no retry; every later request returned the correct 403. No rollback needed. Follow-up: retry the health check. |
| 502 error on chat | Resolved for unauthenticated traffic; the chat-v5 model failure no longer applies (new model llama-3.3-70b). A genuine AI reply still needs a Sandbox receipt. |

## Physical iPhone test of TestFlight build 2.0.0 (203), owner report, 2026-11-24 (PRELIMINARY DEVICE EVIDENCE)

Source: the owner's own hands-on test. Not a complete subscription or backend certification.

Worked on the device:
- The subscription allowed the owner to reach the chat screen, and Ava responded (first genuine device evidence that
  chat-v7 answers a subscriber; production was chat-v7 at the time, see the deploy section above).

Failed the owner's quality expectations (all confirmed on a physical iPhone):
- The voice sounds robotic and the coach speaks much too quickly.
- The lips move excessively fast.
- Most of the avatar's face is cut off; the eyes and full face are not visible.
- The avatar and captions occupy too much screen space; conversation text is clipped.
- Replies appear duplicated.
- The experience does not look or sound like a premium $19.99 monthly app.

Not yet device-verified: purchase and restore flows, renewal, cancellation and expiry, refund, Spanish chat, follow-up
continuity, latency, safety replies. Build 203 predates the framing, keyboard, listening and thinking changes.

## Subscription testing status (2026-11-24, PR #54 head 45390c9)

Labels: UNIT = unit/widget tests (simulated); SIMULATOR = Apple StoreKit Test on an iOS simulator in CI (still simulated,
the test receipt is signed locally so it proves app-side behaviour only, never backend acceptance); DEVICE = a genuine Apple
sandbox or production purchase on a physical iPhone. Nothing below is DEVICE except the owner's report above.

| Requirement | Evidence | Label |
|---|---|---|
| One $19.99 monthly plan, no trial/intro/annual/free plan | catalog scenario; store-metadata tests; App Store Connect read-only check (READY_TO_SUBMIT, 19.99, 0 offers) | SIMULATOR + UNIT + ASC API |
| Purchase unlocks premium; survives relaunch | scenario passed (run 45473085509, iOS 26.2) | SIMULATOR |
| Renewal keeps premium | scenario passed | SIMULATOR |
| Cancel auto-renew: premium until the period ends, then removed | scenario passed (accelerated time); unit tests | SIMULATOR + UNIT |
| Expiry removes premium and shows the paywall | scenario passed after the lapse fix (96b0ff4) | SIMULATOR |
| Restore after reinstall (active restored, expired not) | scenario passed | SIMULATOR |
| Refund/revocation removes premium (and only that transaction) | scenario passed; backend refund-isolation tests | SIMULATOR + UNIT |
| Ask to Buy pending is not premium until approved | scenario passed | SIMULATOR |
| Failed / cancelled / interrupted purchases | unit tests (5-minute buy() timeout path has no test) | UNIT |
| Receipt validation and backend authorization | backend tests (chain to Apple Root CA G3, bundle, product, environment, expiry, revocation, fail closed); live production refuses no-receipt and forged receipts | UNIT + production probes |
| Genuine Apple sandbox purchase, restore, renewal, cancellation | NOT YET VERIFIED on a device (owner's report: reached chat and Ava replied) | DEVICE pending |

Defect found and fixed by this testing: after a purchase made on the root paywall, an expiry, refund or end of a cancelled
period while the app was open removed premium but never showed the paywall (the purchase had set paywallDismissed).
Fixed in 96b0ff4, independently reviewed: APPROVE (no bypass, startup safe, rewritten test equal or stronger).
Known gaps: App Store Server Notifications are off (ASSN_ENABLED=0), so the backend does not learn of refunds until the
signed token expires; grace period is off by policy; two small test-coverage gaps noted by the reviewer.
