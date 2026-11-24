# Owner-only premium access

For the owner's own phone only. Not a customer feature, not in App Store metadata, no new price or tier.

1. Pick a random secret of 16+ characters and set it on the Worker: `wrangler secret put OWNER_ACCESS_SECRET`.
2. Deploy the Worker. Without the secret the feature is off (the routes answer 404, tokens are ignored).
3. In the app, long-press the version line under You > About (or the plan card on the paywall), tap "Owner code", enter the secret.
4. The Worker returns a 30-day token bound to a random device id; the app renews it at launch when under 10 days remain.
5. The token goes in `X-DateWise-Owner`; the cost guard treats it as a Production subscriber with the normal daily/monthly and budget limits.
6. Revoke everything by rotating or deleting the secret. "Owner access: on" > "Turn off" removes it from the phone.
7. Wrong codes are limited to 5 attempts/hour per network and 30/hour overall (Durable Object counters, fail closed).
8. Codes and tokens are never logged. Apple verification, restore and synthetic-receipt rejection are unchanged.
