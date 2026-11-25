# DateWise AI: independent QA report (web review build)

Date: 2026-11-24. Tester: independent QA agent (did not write the app).
Source: `/home/user/datewiseaiapp`, branch `claude/overnight-2026-11-24` (copied to `qa/src`; repository not modified).

## How it was tested

- **Build A (mock):** `flutter build web --release --no-web-resources-cdn --dart-define=DW_FAKE_STORE=true --dart-define=DW_MOCK_AI=true` → `qa/web`, served on 127.0.0.1:8765. Used for every screen and flow.
- **Build B (live backend client):** the same without `DW_MOCK_AI` → `qa/web-live`, served on :8766. It was used only for network-failure tests. Playwright intercepted **every** request to the coach backend (`*.workers.dev`) and answered it locally with 502, 429, an abort or a hang, so no request reached the real server and nothing was spent.
- Playwright Chromium with an iPhone Safari user agent (`isMobile`, `hasTouch`), deviceScaleFactor 1, at 375x667 (SE), 393x852 (15) and 430x932 (15 Pro Max), in English (`en-US`) and Spanish (`es-ES`). The tests turned on Flutter semantics and drove the app by accessible role and name.
- Scripts: `qa/scripts/*.js`. Raw results: `qa/screens.json`, `qa/flow-*.json`, `qa/extra-*.json`, `qa/net-*.json`, `qa/hang.json`. Screenshots: `qa/shots/` (an earlier pass with a desktop Linux user agent is in `qa/shots-linuxUA/`).
- **Simulated, not live:** purchases use `FakeStoreService`, and replies come from the offline `MockAIService`. No result in this report is a live StoreKit or live AI result.

## Summary

- 257 matrix rows: 256 PASS, 1 BLOCKED (a test-harness problem; the same step passes on the other devices). No crash and no Flutter page error on any screen. The only runtime error was the clipboard error in m-1.
- **Critical: none. Major: 1** (M-1, which may be an intended product decision). **Minor: 6. Info: 3.**

## Accounts

The app has **no accounts**: no sign-up, login, logout or account deletion. `lib/content/legal_text.dart:41` says: "DateWise AI has no sign-in and no account". `pubspec.yaml` has no auth or Firebase packages, and nothing in `lib/` has login code. All data is in on-device SharedPreferences (`dw_*` keys, `lib/services/storage_service.dart`). The test therefore covered **Delete my data** (You › Delete my data › Delete everything) in both languages on all 3 sizes:
- the app returns to the Welcome screen;
- the `dw_*` keys left in localStorage = `[]`;
- after a reload the app still opens on Welcome;
- the AI-consent flag, memory, plan and conversations are gone.

The under-18 block stays after Delete my data, by design (`storage_service.dart` `clearAll`). Under-18 → "adults only" screen, which stays after a reload and offers no way forward: PASS.

## Defects

### Critical
None found.

### Major
**M-1. When the subscription has lapsed, the user cannot read their own saved conversations.**
Repro (build A): onboard, subscribe, chat (send "Give me a strong opener"), then reload the page. The fake entitlement is not persisted, which is the same state as an expired or refunded subscription. Close the paywall and open the Chat tab. The whole message list is replaced by the "Chat with Ava is part of DateWise Premium" card, and the conversation menu (history, delete one conversation) is disabled. The data is still on the device: localStorage `dw_threads` still holds both messages, and Progress shows "1 conversation".
Evidence: `shots/i15-en-flow-20.png` (locked) and `shots/i15-en-flow-10.png` (before).
Suspect: `lib/screens/chat_screen.dart:687-695` (`entitled ? _MessageList(...) : _Locked(...)`) and `:654` (`onMenu: entitled ? _openMenu : null`).
Locking the composer is correct. Hiding the user's own on-device history, and blocking deletion of a single conversation, may not be intended. The only remaining option is "Delete all conversations". The owner should confirm whether this is intended. If it is, reclassify it as Info.

### Minor
**m-1. The "Copy reply" chip always says "Copied", even when the copy fails. Its snackbar also covers the composer.**
Repro: open `?screen=chat&lang=en` and tap the "Playful" option card. On the web the clipboard write fails with an uncaught page error ("PAGEERROR Error" in `flow-*-en.log`), but the snackbar still says "Copied. Paste it into your dating app." The snackbar is not floating and sits over the message field and the Send button (`shots/i15-en-flow-12.png`). Other chat snackbars use `_aboveDock()`.
Suspect: `lib/screens/chat_screen.dart:1140-1141`. `Clipboard.setData` is not awaited or caught, and the `SnackBar` has no floating behaviour or margin. On iOS the copy will usually succeed; the overlap applies on iOS too.

**m-2. A settings row title breaks in the middle of a word at large text.**
Repro: iPhone SE, English, text scale 200% → You tab. "Language" shows as "Languag / e" next to the value "English" (`shots/scale200-se-en-settings.png`).
Suspect: `lib/screens/settings_screen.dart:363` (a plain `Text` title) next to the value, which is capped at `maxWidth: 150` (`:388`). The app already has `WholeWordsText` in `lib/widgets/dw.dart:31` for this case. Spanish "Idioma" is not affected.

**m-3. Paywall Restore / Terms / Privacy links measure 36 px tall (the 44 pt minimum is not met in the web build).**
The semantics bounds are 123x36, 91x36 and 55x36 on every device and language (`screens.json`, `shots/*-paywall*.png`). This happened even with the iOS user agent, although `_LinkButton` sets `minimumSize: Size(44, 44)`.
Suspect: `lib/screens/paywall_screen.dart:325-333`. Check on an iPhone with Accessibility Inspector before fixing. Every other control measured at least 44 px; smaller readings came only from nodes clipped at the viewport edge.

**m-4. "Chat with Ava" at the end of onboarding opens Home, not Chat.**
Repro: onboarding step 4 → "Chat with Ava" → paywall → Subscribe. The app lands on the Home tab (`shots/i15-en-flow-09.png`), so the button label promises a chat that does not open.
Suspect: `lib/app.dart` `RootGate` (`HomeShell(initialTab: … initialTab)` with the default `AppTab.home`).

**m-5. (Web build only) White blank page while the app loads, and pinch-zoom is disabled.**
With Slow-3G emulation (400 ms RTT, 500 kbps), the page is pure white (255,255,255) for about 170 s before the first frame. About 10.5 MB is transferred. There is no dark background and no loading indicator (`shots/net-en-slow3g-t*.png`).
`web/index.html:20` sets `maximum-scale=1.0, user-scalable=no`, which blocks browser zoom (WCAG 1.4.4).
This does not affect the Flutter iOS app, which bundles its assets. It does affect the review site, and it will matter once White Glove wraps the live site.

**m-6. (Web build only) Keyboard Tab order gets stuck.**
Tab traversal never reaches the tab bar or the composer from Home or Chat: focus cycles between "Talk to Ava" and the root on Home, and between the header and "Conversation options" on Chat (output of `scripts/focus.js`). Paywall, Settings and Onboarding traverse in a logical order. The DOM semantics order is the visual order on every screen. iOS VoiceOver order must be checked on a device.

### Info / test limitations
- **i-1.** In the review build the fake purchase is in memory only (`lib/services/store_service.dart:96-160`). Every reload shows the paywall again, and Restore after a reload finds nothing. Persistence of chat history therefore cannot be shown on screen in the review build (see M-1). It was verified through storage and the Progress count instead.
- **i-2.** "Find a table" is **hidden on the web by design** (`lib/widgets/find_table_link.dart:24-25`, `!kIsWeb && iOS/macOS`). The first-date flow ran ("Prepare for a date" quick action → the mock date-plan reply, in both languages) and the link was correctly absent. Opening the link (Apple Maps search) is a device-only test.
- **i-3.** The Spanish UI keeps "Coaches" and "coaching" untranslated. This is probably intentional branding.
- Contrast: every theme text token measures at least 4.92:1 on every surface (`faint` on `surface2` is the lowest; `text` on `background` is 16.9:1). Pixel samples of text over photos (the welcome chip, the chat intro caption) give a median contrast of 6.8–16.9:1. PASS.
- Text scaling: at a 200% root font size (Flutter web follows it) on the SE, all 11 screens in both languages scroll, and no text is cut off except m-2.

## Device-only tests (cannot be done in a browser, so no device results are claimed)

Code reviewed: `lib/services/voice_service.dart`, `lib/services/speech_service.dart`, `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist`, `ios/Runner/{en,es}.lproj/InfoPlist.strings`.

1. **Microphone and speech-recognition permission prompts (EN and ES).** `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are present and localized in en and es. Check: the prompts appear only on the first hold of the talk button; Deny → snackbar with "Open Settings" (`canOpenSettings` is iOS-only); come back after allowing → the voice button returns (`recheckPermission` on resume).
2. **On-device recognition.** `speech_service.dart:262-269` uses `onDevice: true`, `listenFor: 60 s` and `pauseFor: 6 s`, which matches the "on your device" wording in the usage string. Test: hold-to-talk; release early, and release while recognition is still starting; silence (expect "I didn't catch that"); the es-MX → es-US → es-ES fallback; Siri & Dictation turned off (expect "recognition unavailable"); VoiceOver tap-to-toggle mode.
3. **Speech playback.** Default path: flutter_tts with an AVAudioSession of `.playback` / `.spokenAudio` / `mixWithOthers + duckOthers + allowBluetoothA2DP`, set before each utterance (`voice_service.dart:460-475`). The native PCM path with mouth levels (`AppDelegate.swift`, `SpeechAudioChannel`) is used only when the build sets `DW_AVATAR_AUDIO_PATH=true` (TestFlight only). Test both paths: lip-sync timing, coach voice selection per coach, and the fallback to flutter_tts after 2 start timeouts.
4. **Interruptions.** `AppDelegate.swift:79-120` observes `interruptionNotification` (on `.began` only), route changes and backgrounding, and sends "done". Test: an incoming call, Siri, an alarm, unplugging headphones or a Bluetooth disconnect, and backgrounding mid-utterance. Also check that other audio (music) is ducked and then resumes. There is no handler for `.ended`, so check that playback does not try to resume on its own.
5. **Real StoreKit 2.** Purchase, restore, cancellation, refund/revoke (and the server's `subscriptionRevoked` code → re-check of the entitlement), expiry while the app is in the background (`AppLifecycleListener.onResume` → `refresh`), and the signed JWS reaching `backend/apple_jws.js`. Also check the localized price string on the paywall (the review build shows a fixed "$19.99" in Spanish too).
6. **Safe areas.** The notch / Dynamic Island and the home indicator on the SE, 15 and 15 Pro Max. The browser has no insets, so the tab bar's bottom padding and the `paddingOf(context).top` headers can only be checked on a device.
7. **Real AI backend over cellular.** Streaming, 30 s connect and idle timeouts, the offline → online retry, and the daily/monthly limit notices with real server codes.
8. **VoiceOver:** reading order, the hold-to-talk alternative, and announcements of streamed replies. **Dynamic Type** at the largest accessibility sizes.
9. **"Find a table"**: opens an Apple Maps restaurant search outside the app; no location prompt from DateWise itself.
10. **Clipboard** copy of reply options on iOS (see m-1), battery or thermal use during long voice sessions, and the keyboard covering the composer.

## Test matrix
| # | Test | Lang | Device | Result | Evidence | Notes |
|---|---|---|---|---|---|---|
| 1 | Screen renders, labelled controls: welcome | en | iPhone SE 375x667 | PASS | shots/se-en-welcome.png, shots/se-en-welcome-bottom.png |  |
| 2 | Screen renders, labelled controls: onboarding-1 | en | iPhone SE 375x667 | PASS | shots/se-en-onboarding-1.png, shots/se-en-onboarding-1-bottom.png |  |
| 3 | Screen renders, labelled controls: onboarding-2 | en | iPhone SE 375x667 | PASS | shots/se-en-onboarding-2.png, shots/se-en-onboarding-2-bottom.png |  |
| 4 | Screen renders, labelled controls: onboarding-3 | en | iPhone SE 375x667 | PASS | shots/se-en-onboarding-3.png, shots/se-en-onboarding-3-bottom.png |  |
| 5 | Screen renders, labelled controls: onboarding-4 | en | iPhone SE 375x667 | PASS | shots/se-en-onboarding-4.png, shots/se-en-onboarding-4-bottom.png |  |
| 6 | Screen renders, labelled controls: paywall | en | iPhone SE 375x667 | PASS | shots/se-en-paywall.png, shots/se-en-paywall-bottom.png |  |
| 7 | Screen renders, labelled controls: home | en | iPhone SE 375x667 | PASS | shots/se-en-home.png, shots/se-en-home-bottom.png |  |
| 8 | Screen renders, labelled controls: coaches | en | iPhone SE 375x667 | PASS | shots/se-en-coaches.png, shots/se-en-coaches-bottom.png |  |
| 9 | Screen renders, labelled controls: chat | en | iPhone SE 375x667 | PASS | shots/se-en-chat.png, shots/se-en-chat-bottom.png |  |
| 10 | Screen renders, labelled controls: chat-error | en | iPhone SE 375x667 | PASS | shots/se-en-chat-error.png, shots/se-en-chat-error-bottom.png |  |
| 11 | Screen renders, labelled controls: chat-limit | en | iPhone SE 375x667 | PASS | shots/se-en-chat-limit.png, shots/se-en-chat-limit-bottom.png |  |
| 12 | Screen renders, labelled controls: progress | en | iPhone SE 375x667 | PASS | shots/se-en-progress.png, shots/se-en-progress-bottom.png |  |
| 13 | Screen renders, labelled controls: settings | en | iPhone SE 375x667 | PASS | shots/se-en-settings.png, shots/se-en-settings-bottom.png |  |
| 14 | Screen renders, labelled controls: welcome | es | iPhone SE 375x667 | PASS | shots/se-es-welcome.png, shots/se-es-welcome-bottom.png |  |
| 15 | Screen renders, labelled controls: onboarding-1 | es | iPhone SE 375x667 | PASS | shots/se-es-onboarding-1.png, shots/se-es-onboarding-1-bottom.png |  |
| 16 | Screen renders, labelled controls: onboarding-2 | es | iPhone SE 375x667 | PASS | shots/se-es-onboarding-2.png, shots/se-es-onboarding-2-bottom.png |  |
| 17 | Screen renders, labelled controls: onboarding-3 | es | iPhone SE 375x667 | PASS | shots/se-es-onboarding-3.png, shots/se-es-onboarding-3-bottom.png |  |
| 18 | Screen renders, labelled controls: onboarding-4 | es | iPhone SE 375x667 | PASS | shots/se-es-onboarding-4.png, shots/se-es-onboarding-4-bottom.png |  |
| 19 | Screen renders, labelled controls: paywall | es | iPhone SE 375x667 | PASS | shots/se-es-paywall.png, shots/se-es-paywall-bottom.png |  |
| 20 | Screen renders, labelled controls: home | es | iPhone SE 375x667 | PASS | shots/se-es-home.png, shots/se-es-home-bottom.png |  |
| 21 | Screen renders, labelled controls: coaches | es | iPhone SE 375x667 | PASS | shots/se-es-coaches.png, shots/se-es-coaches-bottom.png |  |
| 22 | Screen renders, labelled controls: chat | es | iPhone SE 375x667 | PASS | shots/se-es-chat.png, shots/se-es-chat-bottom.png |  |
| 23 | Screen renders, labelled controls: chat-error | es | iPhone SE 375x667 | PASS | shots/se-es-chat-error.png, shots/se-es-chat-error-bottom.png |  |
| 24 | Screen renders, labelled controls: chat-limit | es | iPhone SE 375x667 | PASS | shots/se-es-chat-limit.png, shots/se-es-chat-limit-bottom.png |  |
| 25 | Screen renders, labelled controls: progress | es | iPhone SE 375x667 | PASS | shots/se-es-progress.png, shots/se-es-progress-bottom.png |  |
| 26 | Screen renders, labelled controls: settings | es | iPhone SE 375x667 | PASS | shots/se-es-settings.png, shots/se-es-settings-bottom.png |  |
| 27 | Screen renders, labelled controls: welcome | en | iPhone 15 393x852 | PASS | shots/i15-en-welcome.png, shots/i15-en-welcome-bottom.png |  |
| 28 | Screen renders, labelled controls: onboarding-1 | en | iPhone 15 393x852 | PASS | shots/i15-en-onboarding-1.png, shots/i15-en-onboarding-1-bottom.png |  |
| 29 | Screen renders, labelled controls: onboarding-2 | en | iPhone 15 393x852 | PASS | shots/i15-en-onboarding-2.png, shots/i15-en-onboarding-2-bottom.png |  |
| 30 | Screen renders, labelled controls: onboarding-3 | en | iPhone 15 393x852 | PASS | shots/i15-en-onboarding-3.png, shots/i15-en-onboarding-3-bottom.png |  |
| 31 | Screen renders, labelled controls: onboarding-4 | en | iPhone 15 393x852 | PASS | shots/i15-en-onboarding-4.png, shots/i15-en-onboarding-4-bottom.png |  |
| 32 | Screen renders, labelled controls: paywall | en | iPhone 15 393x852 | PASS | shots/i15-en-paywall.png, shots/i15-en-paywall-bottom.png |  |
| 33 | Screen renders, labelled controls: home | en | iPhone 15 393x852 | PASS | shots/i15-en-home.png, shots/i15-en-home-bottom.png |  |
| 34 | Screen renders, labelled controls: coaches | en | iPhone 15 393x852 | PASS | shots/i15-en-coaches.png, shots/i15-en-coaches-bottom.png |  |
| 35 | Screen renders, labelled controls: chat | en | iPhone 15 393x852 | PASS | shots/i15-en-chat.png, shots/i15-en-chat-bottom.png |  |
| 36 | Screen renders, labelled controls: chat-error | en | iPhone 15 393x852 | PASS | shots/i15-en-chat-error.png, shots/i15-en-chat-error-bottom.png |  |
| 37 | Screen renders, labelled controls: chat-limit | en | iPhone 15 393x852 | PASS | shots/i15-en-chat-limit.png, shots/i15-en-chat-limit-bottom.png |  |
| 38 | Screen renders, labelled controls: progress | en | iPhone 15 393x852 | PASS | shots/i15-en-progress.png, shots/i15-en-progress-bottom.png |  |
| 39 | Screen renders, labelled controls: settings | en | iPhone 15 393x852 | PASS | shots/i15-en-settings.png, shots/i15-en-settings-bottom.png |  |
| 40 | Screen renders, labelled controls: welcome | es | iPhone 15 393x852 | PASS | shots/i15-es-welcome.png, shots/i15-es-welcome-bottom.png |  |
| 41 | Screen renders, labelled controls: onboarding-1 | es | iPhone 15 393x852 | PASS | shots/i15-es-onboarding-1.png, shots/i15-es-onboarding-1-bottom.png |  |
| 42 | Screen renders, labelled controls: onboarding-2 | es | iPhone 15 393x852 | PASS | shots/i15-es-onboarding-2.png, shots/i15-es-onboarding-2-bottom.png |  |
| 43 | Screen renders, labelled controls: onboarding-3 | es | iPhone 15 393x852 | PASS | shots/i15-es-onboarding-3.png, shots/i15-es-onboarding-3-bottom.png |  |
| 44 | Screen renders, labelled controls: onboarding-4 | es | iPhone 15 393x852 | PASS | shots/i15-es-onboarding-4.png, shots/i15-es-onboarding-4-bottom.png |  |
| 45 | Screen renders, labelled controls: paywall | es | iPhone 15 393x852 | PASS | shots/i15-es-paywall.png, shots/i15-es-paywall-bottom.png |  |
| 46 | Screen renders, labelled controls: home | es | iPhone 15 393x852 | PASS | shots/i15-es-home.png, shots/i15-es-home-bottom.png |  |
| 47 | Screen renders, labelled controls: coaches | es | iPhone 15 393x852 | PASS | shots/i15-es-coaches.png, shots/i15-es-coaches-bottom.png |  |
| 48 | Screen renders, labelled controls: chat | es | iPhone 15 393x852 | PASS | shots/i15-es-chat.png, shots/i15-es-chat-bottom.png |  |
| 49 | Screen renders, labelled controls: chat-error | es | iPhone 15 393x852 | PASS | shots/i15-es-chat-error.png, shots/i15-es-chat-error-bottom.png |  |
| 50 | Screen renders, labelled controls: chat-limit | es | iPhone 15 393x852 | PASS | shots/i15-es-chat-limit.png, shots/i15-es-chat-limit-bottom.png |  |
| 51 | Screen renders, labelled controls: progress | es | iPhone 15 393x852 | PASS | shots/i15-es-progress.png, shots/i15-es-progress-bottom.png |  |
| 52 | Screen renders, labelled controls: settings | es | iPhone 15 393x852 | PASS | shots/i15-es-settings.png, shots/i15-es-settings-bottom.png |  |
| 53 | Screen renders, labelled controls: welcome | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-welcome.png, shots/max-en-welcome-bottom.png |  |
| 54 | Screen renders, labelled controls: onboarding-1 | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-onboarding-1.png, shots/max-en-onboarding-1-bottom.png |  |
| 55 | Screen renders, labelled controls: onboarding-2 | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-onboarding-2.png, shots/max-en-onboarding-2-bottom.png |  |
| 56 | Screen renders, labelled controls: onboarding-3 | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-onboarding-3.png, shots/max-en-onboarding-3-bottom.png |  |
| 57 | Screen renders, labelled controls: onboarding-4 | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-onboarding-4.png, shots/max-en-onboarding-4-bottom.png |  |
| 58 | Screen renders, labelled controls: paywall | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-paywall.png, shots/max-en-paywall-bottom.png |  |
| 59 | Screen renders, labelled controls: home | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-home.png, shots/max-en-home-bottom.png |  |
| 60 | Screen renders, labelled controls: coaches | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-coaches.png, shots/max-en-coaches-bottom.png |  |
| 61 | Screen renders, labelled controls: chat | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-chat.png, shots/max-en-chat-bottom.png |  |
| 62 | Screen renders, labelled controls: chat-error | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-chat-error.png, shots/max-en-chat-error-bottom.png |  |
| 63 | Screen renders, labelled controls: chat-limit | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-chat-limit.png, shots/max-en-chat-limit-bottom.png |  |
| 64 | Screen renders, labelled controls: progress | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-progress.png, shots/max-en-progress-bottom.png |  |
| 65 | Screen renders, labelled controls: settings | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-settings.png, shots/max-en-settings-bottom.png |  |
| 66 | Screen renders, labelled controls: welcome | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-welcome.png, shots/max-es-welcome-bottom.png |  |
| 67 | Screen renders, labelled controls: onboarding-1 | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-onboarding-1.png, shots/max-es-onboarding-1-bottom.png |  |
| 68 | Screen renders, labelled controls: onboarding-2 | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-onboarding-2.png, shots/max-es-onboarding-2-bottom.png |  |
| 69 | Screen renders, labelled controls: onboarding-3 | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-onboarding-3.png, shots/max-es-onboarding-3-bottom.png |  |
| 70 | Screen renders, labelled controls: onboarding-4 | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-onboarding-4.png, shots/max-es-onboarding-4-bottom.png |  |
| 71 | Screen renders, labelled controls: paywall | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-paywall.png, shots/max-es-paywall-bottom.png |  |
| 72 | Screen renders, labelled controls: home | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-home.png, shots/max-es-home-bottom.png |  |
| 73 | Screen renders, labelled controls: coaches | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-coaches.png, shots/max-es-coaches-bottom.png |  |
| 74 | Screen renders, labelled controls: chat | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-chat.png, shots/max-es-chat-bottom.png |  |
| 75 | Screen renders, labelled controls: chat-error | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-chat-error.png, shots/max-es-chat-error-bottom.png |  |
| 76 | Screen renders, labelled controls: chat-limit | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-chat-limit.png, shots/max-es-chat-limit-bottom.png |  |
| 77 | Screen renders, labelled controls: progress | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-progress.png, shots/max-es-progress-bottom.png |  |
| 78 | Screen renders, labelled controls: settings | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-settings.png, shots/max-es-settings-bottom.png |  |
| 79 | Welcome renders in device language | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-01.png |  |
| 80 | Get started -> onboarding step 1; Back returns to welcome | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-02.png |  |
| 81 | Onboarding step 1: Continue disabled until a goal is picked | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-03.png | continue aria-disabled before pick=true |
| 82 | Onboarding step 2: language | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-04.png |  |
| 83 | Onboarding step 3: 18+ required | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-05.png | continue aria-disabled before 18+=true |
| 84 | Onboarding step 4: choose coach -> paywall | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-06.png |  |
| 85 | Paywall: Terms opens legal page and Back returns | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-07.png | legal: Back Terms of Use Last updated: November 23, 2026 By using DateWise AI you agree to these terms. DateWise AI is for adul // Back Term |
| 86 | Paywall: Restore with no purchase shows message | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-08.png | No active DateWise Premium subscription was found for this Apple Account.  |
| 87 | Paywall: Subscribe (fake store) -> app shell | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-09.png | tab after subscribe: ? |
| 88 | Chat: send asks AI consent; Not now keeps text | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-10.png | see screenshot: composer text kept |
| 89 | Chat: Agree sends and mock reply streams | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-11.png | Skip “hey”. A strong opener mentions one specific thing from their profile and is ea |
| 90 | Chat: reply chip copies | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-12.png | Copied. Paste it into your dating app.  |
| 91 | Chat: Stop mid-stream then Try again | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-13.png | retry visible after stop; reply after retry: Tell me a bit more: where are you at (profile, a conversat |
| 92 | Chat menu: New conversation / Past conversations sheet | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-14.png | Dismiss Conversations with Ava Delete conversation // Dismiss Conversations with Ava Delete conversation // Dismiss Conversations with Ava D |
| 93 | Home: plan item toggles | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-15.png | false->true |
| 94 | Home: "Prepare for a date" quick prompt opens chat and sends (Find a table hidden on web) | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-16.png | find-table visible=false; reply=Keep a first date simple and in a public place: coffee or a one-hou |
| 95 | Progress tab | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-17.png | Progress Counted on this device from what you actually did. 1 conversation 1 day in a row 1 day with a coach 1/3 plan st // Progress Counted |
| 96 | Settings: memory note save asks to turn on | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-18.png | memory switch: true |
| 97 | Settings: memory persists across reload (fake store lost -> paywall, close) | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-19.png | paywall shown after reload=true |
| 98 | History persists across reload (storage + Progress); Chat tab locked without subscription | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-20.png | stored messages kept=true; progress="1 conversation"; history visible in Chat=false; locked card=true |
| 99 | Settings: Restore purchases after reload (fake store) | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-21.png | DateWise Premium Not subscribed  |
| 100 | Settings: memory off with note asks to delete | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-22.png |  |
| 101 | Settings: privacy policy page + back | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-23.png | Back Privacy Policy Last updated: November 24, 2026 DateWise AI ("DateWise AI", "we", "us") provides an AI dating-coachi |
| 102 | Settings: language switch changes UI | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-24.png | after switch has Spanish tab=true English tab=false |
| 103 | Settings: Delete my data -> welcome, storage wiped | en | iPhone 15 393x852 | PASS | shots/i15-en-flow-25.png | dw_ keys left=[] welcome after reload=true |
| 104 | Welcome renders in device language | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-01.png |  |
| 105 | Get started -> onboarding step 1; Back returns to welcome | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-02.png |  |
| 106 | Onboarding step 1: Continue disabled until a goal is picked | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-03.png | continue aria-disabled before pick=true |
| 107 | Onboarding step 2: language | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-04.png |  |
| 108 | Onboarding step 3: 18+ required | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-05.png | continue aria-disabled before 18+=true |
| 109 | Onboarding step 4: choose coach -> paywall | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-06.png |  |
| 110 | Paywall: Terms opens legal page and Back returns | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-07.png | legal: Atrás Términos de uso Última actualización: 23 de noviembre de 2026 Esta es una traducción para tu comodidad. Si difiere // Atrás Tér |
| 111 | Paywall: Restore with no purchase shows message | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-08.png | No se encontró una suscripción activa a DateWise Premium para esta Cuenta de Apple.  |
| 112 | Paywall: Subscribe (fake store) -> app shell | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-09.png | tab after subscribe: ? |
| 113 | Chat: send asks AI consent; Not now keeps text | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-10.png | see screenshot: composer text kept |
| 114 | Chat: Agree sends and mock reply streams | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-11.png | Un buen primer mensaje habla de algo concreto de su perfil. Por ejemplo: “Vi que te gus |
| 115 | Chat: Stop mid-stream then Try again | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-12.png | retry visible after stop; reply after retry: none |
| 116 | Chat menu: New conversation / Past conversations sheet | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-13.png | Cerrar Conversaciones con Sofía Eliminar conversación // Cerrar Conversaciones con Sofía Eliminar conversación // Cerrar Conversaciones con  |
| 117 | Home: plan item toggles | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-14.png | false->true |
| 118 | Home: "Prepare for a date" quick prompt opens chat and sends (Find a table hidden on web) | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-15.png | find-table visible=false; reply=Para una primera cita, algo sencillo y en un lugar público: un café o u |
| 119 | Progress tab | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-16.png | Progreso Calculado en este dispositivo a partir de lo que realmente hiciste. 1 conversación 1 día de racha 1 día con un  // Progreso Calcula |
| 120 | Settings: memory note save asks to turn on | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-17.png | memory switch: true |
| 121 | Settings: memory persists across reload (fake store lost -> paywall, close) | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-18.png | paywall shown after reload=true |
| 122 | History persists across reload (storage + Progress); Chat tab locked without subscription | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-19.png | stored messages kept=true; progress="1 conversación"; history visible in Chat=false; locked card=true |
| 123 | Settings: Restore purchases after reload (fake store) | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-20.png | DateWise Premium Sin suscripción  |
| 124 | Settings: memory off with note asks to delete | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-21.png |  |
| 125 | Settings: privacy policy page + back | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-22.png | Atrás Política de privacidad Última actualización: 24 de noviembre de 2026 Esta es una traducción para tu comodidad. Si  |
| 126 | Settings: language switch changes UI | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-23.png | after switch has Spanish tab=false English tab=true |
| 127 | Settings: Delete my data -> welcome, storage wiped | es | iPhone 15 393x852 | PASS | shots/i15-es-flow-24.png | dw_ keys left=[] welcome after reload=true |
| 128 | Welcome renders in device language | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-01.png |  |
| 129 | Get started -> onboarding step 1; Back returns to welcome | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-02.png |  |
| 130 | Onboarding step 1: Continue disabled until a goal is picked | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-03.png | continue aria-disabled before pick=true |
| 131 | Onboarding step 2: language | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-04.png |  |
| 132 | Onboarding step 3: 18+ required | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-05.png | continue aria-disabled before 18+=true |
| 133 | Onboarding step 4: choose coach -> paywall | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-06.png |  |
| 134 | Paywall: Terms opens legal page and Back returns | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-07.png | legal: Back Terms of Use Last updated: November 23, 2026 By using DateWise AI you agree to these terms. DateWise AI is for adul // Back Term |
| 135 | Paywall: Restore with no purchase shows message | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-08.png | No active DateWise Premium subscription was found for this Apple Account.  |
| 136 | Paywall: Subscribe (fake store) -> app shell | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-09.png | tab after subscribe: ? |
| 137 | Chat: send asks AI consent; Not now keeps text | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-10.png | see screenshot: composer text kept |
| 138 | Chat: Agree sends and mock reply streams | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-11.png | Skip “hey”. A strong opener mentions one specific thing from their profile and is ea |
| 139 | Chat: reply chip copies | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-12.png | Copied. Paste it into your dating app.  |
| 140 | Chat: Stop mid-stream then Try again | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-13.png | retry visible after stop; reply after retry: Tell me a bit more: where are you at (profile, a conversat |
| 141 | Chat menu: New conversation / Past conversations sheet | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-14.png | Dismiss Conversations with Ava Delete conversation // Dismiss Conversations with Ava Delete conversation // Dismiss Conversations with Ava D |
| 142 | Home: plan item toggles | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-15.png | false->true |
| 143 | Home: "Prepare for a date" quick prompt opens chat and sends (Find a table hidden on web) | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-16.png | find-table visible=false; reply=Keep a first date simple and in a public place: coffee or a one-hou |
| 144 | Progress tab | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-17.png | Progress Counted on this device from what you actually did. 1 conversation 1 day in a row 1 day with a coach 1/3 plan st // Progress Counted |
| 145 | Settings: memory note save asks to turn on | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-18.png | memory switch: true |
| 146 | Settings: memory persists across reload (fake store lost -> paywall, close) | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-19.png | paywall shown after reload=true |
| 147 | History persists across reload (storage + Progress); Chat tab locked without subscription | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-20.png | stored messages kept=true; progress="1 conversation"; history visible in Chat=false; locked card=true |
| 148 | Settings: Restore purchases after reload (fake store) | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-21.png | DateWise Premium Not subscribed  |
| 149 | Settings: memory off with note asks to delete | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-22.png |  |
| 150 | Settings: privacy policy page + back | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-23.png | Back Privacy Policy Last updated: November 24, 2026 DateWise AI ("DateWise AI", "we", "us") provides an AI dating-coachi |
| 151 | Settings: language switch changes UI | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-24.png | after switch has Spanish tab=true English tab=false |
| 152 | Settings: Delete my data -> welcome, storage wiped | en | iPhone 15 Pro Max 430x932 | PASS | shots/max-en-flow-25.png | dw_ keys left=[] welcome after reload=true |
| 153 | Welcome renders in device language | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-01.png |  |
| 154 | Get started -> onboarding step 1; Back returns to welcome | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-02.png |  |
| 155 | Onboarding step 1: Continue disabled until a goal is picked | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-03.png | continue aria-disabled before pick=true |
| 156 | Onboarding step 2: language | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-04.png |  |
| 157 | Onboarding step 3: 18+ required | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-05.png | continue aria-disabled before 18+=true |
| 158 | Onboarding step 4: choose coach -> paywall | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-06.png |  |
| 159 | Paywall: Terms opens legal page and Back returns | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-07.png | legal: Atrás Términos de uso Última actualización: 23 de noviembre de 2026 Esta es una traducción para tu comodidad. Si difiere // Atrás Tér |
| 160 | Paywall: Restore with no purchase shows message | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-08.png | No se encontró una suscripción activa a DateWise Premium para esta Cuenta de Apple.  |
| 161 | Paywall: Subscribe (fake store) -> app shell | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-09.png | tab after subscribe: ? |
| 162 | Chat: send asks AI consent; Not now keeps text | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-10.png | see screenshot: composer text kept |
| 163 | Chat: Agree sends and mock reply streams | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-11.png | Un buen primer mensaje habla de algo concreto de su perfil. Por ejemplo: “Vi que te gus |
| 164 | Chat: Stop mid-stream then Try again | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-12.png | retry visible after stop; reply after retry: none |
| 165 | Chat menu: New conversation / Past conversations sheet | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-13.png | Cerrar Conversaciones con Sofía Eliminar conversación // Cerrar Conversaciones con Sofía Eliminar conversación // Cerrar Conversaciones con  |
| 166 | Home: plan item toggles | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-14.png | false->true |
| 167 | Home: "Prepare for a date" quick prompt opens chat and sends (Find a table hidden on web) | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-15.png | find-table visible=false; reply=Para una primera cita, algo sencillo y en un lugar público: un café o u |
| 168 | Progress tab | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-16.png | Progreso Calculado en este dispositivo a partir de lo que realmente hiciste. 1 conversación 1 día de racha 1 día con un  // Progreso Calcula |
| 169 | Settings: memory note save asks to turn on | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-17.png | memory switch: true |
| 170 | Settings: memory persists across reload (fake store lost -> paywall, close) | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-18.png | paywall shown after reload=true |
| 171 | History persists across reload (storage + Progress); Chat tab locked without subscription | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-19.png | stored messages kept=true; progress="1 conversación"; history visible in Chat=false; locked card=true |
| 172 | Settings: Restore purchases after reload (fake store) | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-20.png | DateWise Premium Sin suscripción  |
| 173 | Settings: memory off with note asks to delete | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-21.png |  |
| 174 | Settings: privacy policy page + back | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-22.png | Atrás Política de privacidad Última actualización: 24 de noviembre de 2026 Esta es una traducción para tu comodidad. Si  |
| 175 | Settings: language switch changes UI | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-23.png | after switch has Spanish tab=false English tab=true |
| 176 | Settings: Delete my data -> welcome, storage wiped | es | iPhone 15 Pro Max 430x932 | PASS | shots/max-es-flow-24.png | dw_ keys left=[] welcome after reload=true |
| 177 | Welcome renders in device language | en | iPhone SE 375x667 | PASS | shots/se-en-flow-01.png |  |
| 178 | Get started -> onboarding step 1; Back returns to welcome | en | iPhone SE 375x667 | PASS | shots/se-en-flow-02.png |  |
| 179 | Onboarding step 1: Continue disabled until a goal is picked | en | iPhone SE 375x667 | PASS | shots/se-en-flow-03.png | continue aria-disabled before pick=true |
| 180 | Onboarding step 2: language | en | iPhone SE 375x667 | PASS | shots/se-en-flow-04.png |  |
| 181 | Onboarding step 3: 18+ required | en | iPhone SE 375x667 | PASS | shots/se-en-flow-05.png | continue aria-disabled before 18+=true |
| 182 | Onboarding step 4: choose coach -> paywall | en | iPhone SE 375x667 | PASS | shots/se-en-flow-06.png |  |
| 183 | Paywall: Terms opens legal page and Back returns | en | iPhone SE 375x667 | PASS | shots/se-en-flow-07.png | legal: Back Terms of Use Last updated: November 23, 2026 By using DateWise AI you agree to these terms. DateWise AI is for adul // Back Term |
| 184 | Paywall: Restore with no purchase shows message | en | iPhone SE 375x667 | PASS | shots/se-en-flow-08.png | No active DateWise Premium subscription was found for this Apple Account.  |
| 185 | Paywall: Subscribe (fake store) -> app shell | en | iPhone SE 375x667 | PASS | shots/se-en-flow-09.png | tab after subscribe: ? |
| 186 | Chat: send asks AI consent; Not now keeps text | en | iPhone SE 375x667 | PASS | shots/se-en-flow-10.png | see screenshot: composer text kept |
| 187 | Chat: Agree sends and mock reply streams | en | iPhone SE 375x667 | PASS | shots/se-en-flow-11.png | Skip “hey”. A strong opener mentions one specific thing from their profile and is ea |
| 188 | Chat: reply chip copies | en | iPhone SE 375x667 | PASS | shots/se-en-flow-12.png | Copied. Paste it into your dating app.  |
| 189 | Chat: Stop mid-stream then Try again | en | iPhone SE 375x667 | PASS | shots/se-en-flow-13.png | retry visible after stop; reply after retry: Tell me a bit more: where are you at (profile, a conversat |
| 190 | Chat menu: New conversation / Past conversations sheet | en | iPhone SE 375x667 | PASS | shots/se-en-flow-14.png | Dismiss Conversations with Ava Delete conversation // Dismiss Conversations with Ava Delete conversation // Dismiss Conversations with Ava D |
| 191 | Home: plan item toggles | en | iPhone SE 375x667 | PASS | shots/se-en-flow-15.png | false->true |
| 192 | Home: "Prepare for a date" quick prompt opens chat and sends (Find a table hidden on web) | en | iPhone SE 375x667 | PASS | shots/se-en-flow-16.png | find-table visible=false; reply=none |
| 193 | Progress tab | en | iPhone SE 375x667 | PASS | shots/se-en-flow-17.png | Progress Counted on this device from what you actually did. 1 conversation 1 day in a row 1 day with a coach 1/3 plan st // Progress Counted |
| 194 | Settings: memory note save asks to turn on | en | iPhone SE 375x667 | PASS | shots/se-en-flow-18.png | memory switch: true |
| 195 | Settings: memory persists across reload (fake store lost -> paywall, close) | en | iPhone SE 375x667 | PASS | shots/se-en-flow-19.png | paywall shown after reload=true |
| 196 | History persists across reload (storage + Progress); Chat tab locked without subscription | en | iPhone SE 375x667 | PASS | shots/se-en-flow-20.png | stored messages kept=true; progress="1 conversation"; history visible in Chat=false; locked card=true |
| 197 | Settings: Restore purchases after reload (fake store) | en | iPhone SE 375x667 | PASS | shots/se-en-flow-21.png | DateWise Premium Not subscribed  |
| 198 | Settings: memory off with note asks to delete | en | iPhone SE 375x667 | PASS | shots/se-en-flow-22.png |  |
| 199 | Settings: privacy policy page + back | en | iPhone SE 375x667 | PASS | shots/se-en-flow-23.png | Back Privacy Policy Last updated: November 24, 2026 DateWise AI ("DateWise AI", "we", "us") provides an AI dating-coachi |
| 200 | Settings: language switch changes UI | en | iPhone SE 375x667 | PASS | shots/se-en-flow-24.png | after switch has Spanish tab=true English tab=false |
| 201 | Settings: Delete my data -> welcome, storage wiped | en | iPhone SE 375x667 | PASS | shots/se-en-flow-25.png | dw_ keys left=[] welcome after reload=true |
| 202 | Welcome renders in device language | es | iPhone SE 375x667 | PASS | shots/se-es-flow-01.png |  |
| 203 | Get started -> onboarding step 1; Back returns to welcome | es | iPhone SE 375x667 | PASS | shots/se-es-flow-02.png |  |
| 204 | Onboarding step 1: Continue disabled until a goal is picked | es | iPhone SE 375x667 | PASS | shots/se-es-flow-03.png | continue aria-disabled before pick=true |
| 205 | Onboarding step 2: language | es | iPhone SE 375x667 | PASS | shots/se-es-flow-04.png |  |
| 206 | Onboarding step 3: 18+ required | es | iPhone SE 375x667 | PASS | shots/se-es-flow-05.png | continue aria-disabled before 18+=true |
| 207 | Onboarding step 4: choose coach -> paywall | es | iPhone SE 375x667 | PASS | shots/se-es-flow-06.png |  |
| 208 | Paywall: Terms opens legal page and Back returns | es | iPhone SE 375x667 | PASS | shots/se-es-flow-07.png | legal: Atrás Términos de uso Última actualización: 23 de noviembre de 2026 Esta es una traducción para tu comodidad. Si difiere // Atrás Tér |
| 209 | Paywall: Restore with no purchase shows message | es | iPhone SE 375x667 | PASS | shots/se-es-flow-08.png | No se encontró una suscripción activa a DateWise Premium para esta Cuenta de Apple.  |
| 210 | Paywall: Subscribe (fake store) -> app shell | es | iPhone SE 375x667 | PASS | shots/se-es-flow-09.png | tab after subscribe: ? |
| 211 | Chat: send asks AI consent; Not now keeps text | es | iPhone SE 375x667 | PASS | shots/se-es-flow-10.png | see screenshot: composer text kept |
| 212 | Chat: Agree sends and mock reply streams | es | iPhone SE 375x667 | PASS | shots/se-es-flow-11.png | Un buen primer mensaje habla de algo concreto de su perfil. Por ejemplo: “Vi que te gus |
| 213 | Chat: Stop mid-stream then Try again | es | iPhone SE 375x667 | PASS | shots/se-es-flow-12.png | retry visible after stop; reply after retry: none |
| 214 | Chat menu: New conversation / Past conversations sheet | es | iPhone SE 375x667 | PASS | shots/se-es-flow-13.png | Cerrar Conversaciones con Sofía Eliminar conversación // Cerrar Conversaciones con Sofía Eliminar conversación // Cerrar Conversaciones con  |
| 215 | Home: plan item toggles | es | iPhone SE 375x667 | PASS | shots/se-es-flow-14.png | false->true |
| 216 | Home: "Prepare for a date" quick prompt opens chat and sends (Find a table hidden on web) | es | iPhone SE 375x667 | PASS | shots/se-es-flow-15.png | find-table visible=false; reply=none |
| 217 | Progress tab | es | iPhone SE 375x667 | PASS | shots/se-es-flow-16.png | Progreso Calculado en este dispositivo a partir de lo que realmente hiciste. 1 conversación 1 día de racha 1 día con un  // Progreso Calcula |
| 218 | Settings: memory note save asks to turn on | es | iPhone SE 375x667 | PASS | shots/se-es-flow-17.png | memory switch: true |
| 219 | Settings: memory persists across reload (fake store lost -> paywall, close) | es | iPhone SE 375x667 | PASS | shots/se-es-flow-18.png | paywall shown after reload=true |
| 220 | History persists across reload (storage + Progress); Chat tab locked without subscription | es | iPhone SE 375x667 | PASS | shots/se-es-flow-19.png | stored messages kept=true; progress="1 conversación"; history visible in Chat=false; locked card=true |
| 221 | Settings: Restore purchases after reload (fake store) | es | iPhone SE 375x667 | PASS | shots/se-es-flow-20.png | DateWise Premium Sin suscripción  |
| 222 | Settings: memory off with note asks to delete | es | iPhone SE 375x667 | PASS | shots/se-es-flow-21.png |  |
| 223 | Settings: privacy policy page + back | es | iPhone SE 375x667 | PASS | shots/se-es-flow-22.png | Atrás Política de privacidad Última actualización: 24 de noviembre de 2026 Esta es una traducción para tu comodidad. Si  |
| 224 | Settings: language switch changes UI | es | iPhone SE 375x667 | BLOCKED (harness: row off-screen after scroll; passes on i15/max) | shots/se-es-flow-23-FAIL.png | locator.click: Timeout 8000ms exceeded. |
| 225 | Settings: Delete my data -> welcome, storage wiped | es | iPhone SE 375x667 | PASS | shots/se-es-flow-24.png | dw_ keys left=[] welcome after reload=true |
| 226 | Onboarding: at most three goals | en | iPhone 15 393x852 | PASS | shots/i15-en-x-goals.png |  |
| 227 | chat-error: notice + Try again fails again gracefully | en | iPhone 15 393x852 | PASS | shots/i15-en-x-chaterr.png |  |
| 228 | chat-limit: notice + See Premium opens paywall + close | en | iPhone 15 393x852 | PASS | shots/i15-en-x-chatlimit.png |  |
| 229 | Chat history: delete conversation shows Undo; Undo restores | en | iPhone 15 393x852 | PASS | shots/i15-en-x-histdel.png | restored=true |
| 230 | Chat menu: New conversation shows greeting + starters | en | iPhone 15 393x852 | PASS | shots/i15-en-x-newconv.png | Hi, I’m Ava, your AI confidence coach. I’ll be direct, and I’m on |
| 231 | Chat starter chip sends | en | iPhone 15 393x852 | PASS | shots/i15-en-x-starter.png | tapped "Give me a strong opener" |
| 232 | Switch coach via menu -> Coaches tab -> pick Ethan/Diego opens chat with new coach | en | iPhone 15 393x852 | PASS | shots/i15-en-x-switch.png | header=Ethan AI dating coach · English Conversation  |
| 233 | Under 18: confirm -> adults-only screen, survives reload and has no way forward | en | iPhone 15 393x852 | PASS | shots/i15-en-x-underage.png | after: DateWise AI Sorry, DateWise is only for adults. You need to be 18 or older to us / after reload: DateWise AI Sorry, DateWise is only  |
| 234 | Onboarding: at most three goals | es | iPhone 15 393x852 | PASS | shots/i15-es-x-goals.png |  |
| 235 | chat-error: notice + Try again fails again gracefully | es | iPhone 15 393x852 | PASS | shots/i15-es-x-chaterr.png |  |
| 236 | chat-limit: notice + See Premium opens paywall + close | es | iPhone 15 393x852 | PASS | shots/i15-es-x-chatlimit.png |  |
| 237 | Chat history: delete conversation shows Undo; Undo restores | es | iPhone 15 393x852 | PASS | shots/i15-es-x-histdel.png | restored=true |
| 238 | Chat menu: New conversation shows greeting + starters | es | iPhone 15 393x852 | PASS | shots/i15-es-x-newconv.png | ¡Hola! Soy Sofía, tu coach de autoconfianza con IA. Es  |
| 239 | Chat starter chip sends | es | iPhone 15 393x852 | PASS | shots/i15-es-x-starter.png | tapped "Dame un buen primer mensaje" |
| 240 | Switch coach via menu -> Coaches tab -> pick Ethan/Diego opens chat with new coach | es | iPhone 15 393x852 | PASS | shots/i15-es-x-switch.png | header=Diego Coach de citas con IA · Español Opcione |
| 241 | Under 18: confirm -> adults-only screen, survives reload and has no way forward | es | iPhone 15 393x852 | PASS | shots/i15-es-x-underage.png | after: DateWise AI Lo sentimos, DateWise es solo para adultos. Necesitas tener 18 años  / after reload: DateWise AI Lo sentimos, DateWise es |
| 242 | Live backend HTTP 502 -> server notice + Try again (live-backend build, all backend requests intercepted locally) | en | iPhone 15 393x852 | PASS | shots/net-en-502.png | requests=2  |
| 243 | Live backend HTTP 429 -> busy notice (live-backend build, all backend requests intercepted locally) | en | iPhone 15 393x852 | PASS | shots/net-en-429.png | requests=1  // Your coach is getting a lot of messages right now. Try again in a moment. Your message is saved. // Try again //  // Send //  |
| 244 | Offline (request aborted) -> offline notice (live-backend build, all backend requests intercepted locally) | en | iPhone 15 393x852 | PASS | shots/net-en-offline-abort.png | requests=2  // You seem to be offline. Check your connection and try again. Your message is saved. // Try again //  // Send // Home tab // C |
| 245 | context.setOffline + Try again -> offline notice, app usable (live-backend build, all backend requests intercepted locally) | en | iPhone 15 393x852 | PASS | shots/net-en-offline-retry.png |  // You seem to be offline. Check your connection and try again. Your message is saved. // Try again //  // Send // Home tab // Coaches tab  |
| 246 | Offline: tabs still navigate (live-backend build, all backend requests intercepted locally) | en | iPhone 15 393x852 | PASS | shots/net-en-offline-tabs.png | Progress Counted on this device from what you actually did. 1 conversation 1 day |
| 247 | Slow 3G (400ms RTT, 500kbps) cold load of welcome (mock build) | en | iPhone 15 393x852 | PASS | shots/net-en-slow3g-loaded.png | flutter view after ~170s, total transfer 10504 KB; blank screen shots: shots/net-en-slow3g-t0s.png,shots/net-en-slow3g-t10s.png,shots/net-en |
| 248 | Live backend HTTP 502 -> server notice + Try again (live-backend build, all backend requests intercepted locally) | es | iPhone 15 393x852 | PASS | shots/net-es-502.png | requests=2  |
| 249 | Live backend HTTP 429 -> busy notice (live-backend build, all backend requests intercepted locally) | es | iPhone 15 393x852 | PASS | shots/net-es-429.png | requests=1  // Tu coach está recibiendo muchos mensajes ahora mismo. Inténtalo de nuevo en un momento. Tu mensaje está guardado. // Reintent |
| 250 | Offline (request aborted) -> offline notice (live-backend build, all backend requests intercepted locally) | es | iPhone 15 393x852 | PASS | shots/net-es-offline-abort.png | requests=2  // Parece que no tienes conexión. Revisa tu conexión e inténtalo de nuevo. Tu mensaje está guardado. // Reintentar //  // Enviar |
| 251 | context.setOffline + Try again -> offline notice, app usable (live-backend build, all backend requests intercepted locally) | es | iPhone 15 393x852 | PASS | shots/net-es-offline-retry.png |  // Parece que no tienes conexión. Revisa tu conexión e inténtalo de nuevo. Tu mensaje está guardado. // Reintentar //  // Enviar // Pestaña |
| 252 | Offline: tabs still navigate (live-backend build, all backend requests intercepted locally) | es | iPhone 15 393x852 | PASS | shots/net-es-offline-tabs.png | Progreso Calculado en este dispositivo a partir de lo que realmente hiciste. 1 c |
| 253 | Slow 3G (400ms RTT, 500kbps) cold load of welcome (mock build) | es | iPhone 15 393x852 | PASS | shots/net-es-slow3g-loaded.png | flutter view after ~170s, total transfer 10504 KB; blank screen shots: shots/net-es-slow3g-t0s.png,shots/net-es-slow3g-t10s.png,shots/net-es |
| 254 | Backend hangs: Stop reply cancels at once, Try again offered (live-backend build, all backend requests intercepted locally) | en | iPhone 15 393x852 | PASS | shots/net-en-hang-stopped.png | requests=3; stopped, Try again shown within 985ms; notice:  The reply was stopped. Your message is saved.  |
| 255 | Backend hangs: Stop reply cancels at once, Try again offered (live-backend build, all backend requests intercepted locally) | es | iPhone 15 393x852 | PASS | shots/net-es-hang-stopped.png | requests=3; stopped, Try again shown within 937ms; notice:  La respuesta se detuvo. Tu mensaje está guardado.  |
| 256 | Text scale 200% (root font-size 32px): 11 screens | en | iPhone SE 375x667 | PASS (EN: 1 word-break defect m-2) | shots/scale200-se-en-*.png |  |
| 257 | Text scale 200% (root font-size 32px): 11 screens | es | iPhone SE 375x667 | PASS | shots/scale200-se-es-*.png |  |