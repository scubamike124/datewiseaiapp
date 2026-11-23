# Agent instructions for DateWise AI

These are the owner's standing rules for every coding agent working in this repository.

## Reuse first, build last

Before writing new code, use what already exists, in this order: capabilities already in DateWise or the owner's other
repositories (Amber, White Glove), connected APIs and services, then free, secure, maintained open source with a
commercial-friendly licence. Build only what is missing. No duplicate systems, no paid services or new accounts without
the owner's authorization, and reuse never skips security, compatibility or acceptance tests. Every PR includes a
"Reuse check" line.

## App delivery: website first, White Glove wraps it (decided 2026-11-23)

The owner's standard for all products:

1. Build and finish the website / web app first: features, AI, avatars, subscriptions, security, testing.
2. Package it for iOS and Android with the owner's White Glove app-wrapping software (in the `amberai` repository,
   `src/lib/api-v1/ios-build`, `android-build`; docs in `docs/white-glove-treatment/`). White Glove is a Capacitor
   shell that loads the live site and can include an app's own Capacitor plugins (its existing-project lane).
3. Do not build separate Flutter, Swift, Kotlin or React Native apps. Native code is allowed only for a feature White
   Glove cannot provide, and it should become a reusable White Glove plugin, not app-only code.
4. Check White Glove's capabilities in its code before adding native functionality.

### DateWise's current position (owner decisions, 2026-11-23)

A code review of White Glove on 2026-11-23 found it does **not** yet provide three things DateWise depends on:
Apple In-App Purchase (StoreKit 2 with the signed transaction for `backend/apple_jws.js`), speech recognition, and
speech playback with timing for the avatar's mouth. It had also not yet run a real signed build or TestFlight upload,
and its live Android lane is not built.

The owner chose: **ship DateWise v1 with the existing Flutter iOS build, and extend White Glove later.**

- **DateWise is not wrapped with White Glove until the owner has personally verified that DateWise works.** Do not
  start White Glove packaging or White Glove plugin work for DateWise before then. The priority is getting DateWise
  into a state the owner can test and verify.
- The Flutter iOS app (`ios/`, `.github/workflows/ios-build.yml`, `lib/services/store_service.dart`,
  `lib/services/voice_service.dart`, `ios/Runner/AppDelegate.swift`) is kept and maintained for v1. Do not delete it or
  its pipeline until DateWise is verified working through White Glove.
- Add no new native-only features to it. Bug fixes, security fixes and App Store requirements only.
- New product work goes into the shared web/app code and the backend, which both delivery paths use.
- Afterwards, the native pieces (StoreKit 2 subscription and entitlement JWS, speech recognition, AVSpeechSynthesizer
  audio with word markers and levels) are ported into reusable White Glove Capacitor plugins, and DateWise moves to
  White Glove once those plugins and a real White Glove build are verified on a device.

## Standing limits

- Spending stays at $0 unless the owner approves otherwise. Never print or expose secrets.
- Do not merge to `main`, deploy production, or submit to Apple or Google without the owner's approval.
- Do not weaken security, subscription verification or tests. Do not report simulated results as live ones.
- Avatar portraits: keep the approved faces and original brown eye colour; do not loosen the identity or iris gates.
