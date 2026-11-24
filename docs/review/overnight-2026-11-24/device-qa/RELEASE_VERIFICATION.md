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
