# Independent review: ASC review-screenshot fix (branch claude/asc-verify, commit 4cf0cf2)

Reviewed: tool/asc/upload_review_screenshot.py, .github/workflows/asc-verify.yml (job `review-screenshot`),
tool/asc/review-screenshot.png, the verify_asc.py territory change. Nothing was run against Apple and nothing
was committed.

## Verdict
GO for running the upload, with the caveats below. No blocking defects in the script or workflow. But the
commit message overclaims: the upload will very probably clear MISSING_METADATA, and Apple does not document
that it is what makes the product appear in TestFlight. The Paid Apps Agreement, banking and tax status is an
equally likely cause, and the API cannot show it. The owner must check it in App Store Connect > Business.

## 1. Does a missing screenshot explain MISSING_METADATA? What else is required?
- Apple's setup guide for auto-renewable subscriptions ("Offer auto-renewable subscriptions", App Store Connect
  Help) lists these items:
  - reference name, product ID and duration
  - a price, and availability (the countries it is sold in)
  - localized display name and description for the subscription and for the subscription group
  - Review Information: a screenshot upload and Review Notes.
  - Tax category and Family Sharing are explicitly "Optionally". Review notes are shown as an optional field.
- Everything else was found present, so the review screenshot is the only required item missing. That makes it
  the most likely reason for MISSING_METADATA (inference: Apple publishes no field-by-field list for this state).
- A price for every territory is not required. You need a price for each territory the subscription is sold in,
  and the read-only check shows those are set (US, CA, MX, ES).
- Sandbox and TestFlight do not need the subscription to be submitted. TN3186 (Troubleshooting In-App Purchases
  availability in the sandbox, 2025-04-29) says: "TestFlight also uses the sandbox ... Testing In-App Purchase in
  the Apple sandbox environment doesn't require you submit your In-App Purchases for review."
- TN3186's list of causes for products not loading includes all of these:
  - "You don't have a Paid Apps Agreement in effect". It must show Active, and Bank Accounts and Tax Forms must
    also show Active.
  - an inactive developer account, or an unsigned newer Program License Agreement
  - a bundle ID mismatch, or the IAP capability off or a wildcard App ID
  - incomplete product configuration or localization
  - edits take "up to 1 hour" to reach the sandbox.
- Apple does not say that Ready to Submit is required for sandbox; it only asks that products be configured and
  localized. Many teams can load MISSING_METADATA products in sandbox once the agreement is active (community
  experience, not an Apple statement). So this upload is necessary for submission, but it may not be enough to fix
  the paywall.
- The App Store release has a separate requirement. The first auto-renewable subscription and its group must be
  submitted together with a new app version. That is not needed for TestFlight.
- App-side checks look fine:
  - StoreService.productId is 'datewise_premium_monthly', which matches App Store Connect.
  - ios/Runner/DateWise.storekit only affects Xcode scheme runs, not archived TestFlight builds.

Sources:
- https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions
- https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox
- https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases
  (Paid Apps Agreement must be active; "In-App Purchases do not need prior approval from App Review to function in review")
- https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect

## 2. Upload script correctness (against "Uploading assets to App Store Connect")
- Reservation is correct: POST /v1/subscriptionAppStoreReviewScreenshots with:
  - attributes fileName and fileSize (the byte length of the exact bytes uploaded)
  - relationship `subscription` to {type: subscriptions, id}.
- Upload operations are handled correctly. For each one, the script:
  - uses its method (default PUT) and url
  - sends the slice `blob[offset:offset+length]`
  - sends exactly its requestHeaders (Content-Type comes from Apple, so urllib's default form type is overridden).
- The commit is correct: PATCH with uploaded=true and sourceFileChecksum = MD5 hex of the whole file. Apple says
  "the MD5 checksum of your original, entire asset file".
- Polling is correct: it checks assetDeliveryState until COMPLETE or FAILED, for 30 x 10 s.
- Idempotency is acceptable. GET /v1/subscriptions/{id}/appStoreReviewScreenshot stops if a screenshot is already
  COMPLETE. If one exists in any other state, it exits without deleting anything.
- JWT: ES256, kid, aud appstoreconnect-v1, exp = iat + 1200. That is at Apple's 20-minute ceiling, so 900 would
  be safer.
- Lookup is correct: the app is found by exact bundleId, and the subscription by productId through
  subscriptionGroups?include=subscriptions.

Non-blocking issues:
- a. If the polling loop ends without COMPLETE, the script still exits 0. It should `sys.exit` non-zero so the
  run shows as failed.
- b. An HTTPError or timeout on the blob PUT is not caught, so it raises a traceback. The traceback shows only
  "HTTP Error 4xx", not the URL. The reservation is then left in AWAITING_UPLOAD, and a re-run refuses to continue
  because of the "never delete" rule. Recovery is manual: delete the screenshot in the App Store Connect UI.
  Alternatively, the script could re-upload the parts and commit an existing AWAITING_UPLOAD reservation, which
  Apple allows within a week. That would mean saving its upload operations, so the simpler fix is to accept manual
  recovery.
- c. A non-JSON 2xx response body would raise in `call`. This is unlikely.

## 3. Security
- The token is sent only to api.appstoreconnect.apple.com. NoRedirect stops it from following redirects. The
  pre-signed blob URLs get only Apple's requestHeaders and no Authorization header, which follows Apple's guidance
  ("You don't need to supply a JWT; don't share the URLs").
- Neither the token nor the upload URL is printed. Logs show only state, counts and Apple error code/detail,
  truncated to 400 characters.
- Write operations are limited to one POST to subscriptionAppStoreReviewScreenshots and one PATCH of that same new
  resource. Nothing is deleted, and nothing touches prices, territories, offers, localizations or the subscription.
  verify_asc.py stays GET-only. Its only change adds `territory` to the requested fields.
- Gating: the job runs only on `push` with `[asc-screenshot]` in head_commit.message and `environment:
  app-store-connect-write`. The current commit 4cf0cf2 does not contain the marker, so it does not trigger the job.
- Unverified: I could not confirm through the proxy that app-store-connect-write has required reviewers. Without
  them, the environment gate does nothing. The owner should confirm this in Settings > Environments.
- Caveats:
  - `concurrency: cancel-in-progress: true`. A second push to claude/asc-verify while the write job is running
    could cancel it mid-upload, which leads to issue 2b. Do not push again until the run finishes.
  - The marker commit must change one of the files listed under `paths:`, or the workflow will not run at all.
  - Do not put `[asc-apply]` in the same commit message.
  - The job passes APPLE_TEAM_ID and EXPECTED_USD to the script although it does not need them for the upload.
    This is harmless.

## 4. Screenshot
- PNG, 1290x2796, 8-bit RGB with no alpha, 1.29 MB. That is iPhone 6.7"/6.9" portrait. It is above Apple's
  minimum for IAP review screenshots (640x920) and within the 10 MB limit the script enforces. It is used only by
  App Review and is never shown on the store.
- It shows the purchase UI:
  - product name "DateWise Premium", "Monthly · auto-renews"
  - price $19.99 per month and a "Subscribe for $19.99/month" button
  - Restore purchases, Terms of Use and Privacy links
  - the full auto-renewal disclosure.
- Nothing misleading. The edit that painted out "Review build: purchases are simulated" is clean, with no visible
  artifacts in the gap between the button and the links. The image matches what the TestFlight app shows once the
  product loads, so the edit is acceptable. The bottom fair-use paragraph is cut off, which is fine.
- Optional later: replace it with a real device capture once StoreKit returns the product. A capture that also
  shows the system purchase sheet is the strongest evidence for App Review.

## Recommended order
1. The owner confirms that Paid Apps Agreement, Bank Accounts and Tax Forms are all Active, and that the
   environment has required reviewers.
2. Push a marker commit with `[asc-screenshot]` and approve the run. Then do not push again until it finishes.
3. Wait up to 1 hour, then reopen the paywall on the TestFlight build. Delete and reinstall the app if needed,
   signed in with a sandbox or TestFlight account.
4. If it still says "not available", the cause is the agreement, tax or banking, or the bundle/capability, not
   metadata.
