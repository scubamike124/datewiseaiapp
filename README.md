# DateWise AI 💗

An AI-powered dating coach built in Flutter (web · Android · iOS), implementing
the **Lumière** PRD: a premium, blush-toned coaching experience with a
three-tier subscription model, threaded AI chat, and a Magnet-tier photo coach.

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

The sections below describe the previous (v1) app and are kept for history.

## Features

- **Landing & conversion funnel** — hero, feature highlights, how-it-works,
  pricing comparison, testimonials, and CTA (PRD §5.1).
- **Tiered coaching** — Spark / Flame / Magnet, each unlocking deeper
  capabilities exactly per the PRD pricing matrix (PRD §4).
- **Threaded AI chat** — create, rename, delete conversations; persistent
  sidebar on desktop, drawer on mobile; real-time streamed replies in Lumière's
  voice (PRD §5.2, §5.4, §8).
- **AI Photo Coach (Magnet)** — upload a photo, get a 1-10 score, a
  KEEP / RESHOOT / DELETE verdict, per-dimension critique (lighting, expression,
  outfit, framing, vibe), and a predicted match-rate lift (PRD §5.3).
- **Private by design** — tier and chat history persist locally via
  `shared_preferences` (localStorage on web). No server-side storage (PRD §9).

## Architecture

```
lib/
  main.dart              app bootstrap (storage + AI + provider)
  app.dart               routing: returning users → chat, new → landing
  theme/                 Romantic Blush design system
  models/                tier (capability matrix), thread, message, photo analysis
  services/
    ai_service.dart      AIService abstraction + factory
    mock_ai_service.dart offline coach — app works with zero setup
    gemini_ai_service.dart  real Google Gemini client (used when a key is set)
    persona.dart         Lumière system prompt + tier-gated greetings
    storage_service.dart local persistence
  state/app_state.dart   provider ChangeNotifier orchestrating everything
  screens/               landing_screen, chat_screen
  widgets/               brand, pricing card, message bubble, photo card, input, sidebar
```

## AI backend

DateWise AI ships with a fully-working **offline mock coach**, so it runs
end-to-end with no API key. To use a real model (Google Gemini, per PRD §6.2),
pass a key at run time — the factory wires the real client automatically:

```bash
flutter run -d chrome --dart-define=GEMINI_API_KEY=your_key_here
```

See [lib/services/ai_config.dart](lib/services/ai_config.dart). No key is ever
committed.

## Run

```bash
flutter pub get
flutter run -d chrome      # web
flutter run                # pick a device (Android emulator, etc.)
flutter test               # unit + widget tests
```

> iOS builds require macOS + Xcode; the iOS target is scaffolded but cannot be
> built from Windows.
