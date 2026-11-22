# DateWise AI

An AI dating coach for iPhone, built in Flutter. Four AI coaches, chat and
voice practice, one monthly subscription, and no accounts: everything the user
does stays on the device.

## DateWise v2 (iPhone app)

Dark "Evening" design, four AI coaches (Ava and Ethan in English, Sofía and
Diego in Spanish), five tabs: Home, Coaches, Chat, Progress, You.

- **Chat** streams real replies from the secure backend (`BackendAIService`,
  SSE) and saves conversations on the device, per coach. Reply chips appear
  only when the model ends a reply with an `OPTIONS:` line.
- **Voice mode** (iOS/Android only): hold to talk with on-device speech
  recognition (`speech_to_text`), replies read aloud with the system voices
  (`flutter_tts`). Hidden on web and when permission is denied.
- **Subscription**: one auto-renewable product, `datewise_premium_monthly`
  ($9.99/month, price read from StoreKit). No free plan, no trial. Chat needs
  an active subscription. **The owner must create this product in App Store
  Connect** (auto-renewable, 1 month) before real purchases work.
- **No accounts**: everything is stored on the device. You › Delete my data
  wipes it.
- **Coach portraits**: `assets/coaches/{ava,ethan,sofia,diego}-{hero,avatar}.jpg`.
  Replace the files with the final portraits (same names); focal points are
  `Coach.heroFocus` / `Coach.avatarFocus` in `lib/models/coach.dart`.

Review build for the web (fake store, offline coach, `?screen=` to open a
screen with sample data):

```bash
flutter run -d chrome --dart-define=DW_FAKE_STORE=true --dart-define=DW_MOCK_AI=true
# e.g. http://localhost:PORT/?screen=chat  (welcome, home, coaches, chat, progress, settings, paywall)
```

A web build without `DW_FAKE_STORE` has no purchase path ("Subscribe in the
iPhone app"), so it cannot chat.

Hosted legal pages (`web/privacy.html`, `web/terms.html` and the Spanish
`-es.html` versions) are generated from `lib/content/legal_text.dart`:

```bash
dart run tool/legal_pages.dart
```

## Architecture

```
lib/
  main.dart              bootstrap: storage, coach backend, store, voice
  app.dart               root gate: welcome/onboarding → paywall → tabs
  content/legal_text.dart  Privacy Policy and Terms (EN + ES)
  l10n/                  English and Spanish UI strings (gen-l10n)
  models/                coaches, profile (goals + language), threads, plan
  services/
    ai_service.dart      AIService abstraction + factory
    backend_ai_service.dart  secure coach backend client (HTTPS, SSE)
    mock_ai_service.dart offline demo coach (tests, review builds)
    persona.dart         coach system prompts
    storage_service.dart on-device persistence (+ v1 → v2 migration)
    store_service.dart   the one StoreKit subscription
    speech_service.dart / voice_service.dart  on-device speech and voices
  state/app_state.dart   ChangeNotifier orchestrating everything
  screens/, widgets/     UI
```

## AI backend

Replies come from a Cloudflare Worker (`backend/worker.js`); the model and any
keys stay server-side and the app ships **no API keys**. The app only knows
the Worker's HTTPS URL (`lib/services/ai_config.dart`), overridable with
`--dart-define=COACH_BACKEND_URL=https://…`. Without a backend URL (and in
tests) the offline demo coach runs.

## Run

```bash
flutter pub get
flutter run -d chrome      # web
flutter run                # pick a device (Android emulator, etc.)
flutter test               # unit + widget tests
```

> iOS builds require macOS + Xcode (CI builds them on GitHub Actions).
