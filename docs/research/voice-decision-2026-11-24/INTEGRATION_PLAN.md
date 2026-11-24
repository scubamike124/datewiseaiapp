# INTEGRATION PLAN: natural voice via the Worker (written 2026-11-24)

Primary design: Workers AI Aura-2 (`@cf/deepgram/aura-2-en`, `aura-2-es`) through the Worker's existing `env.AI` binding. The same design works for Azure or ElevenLabs by swapping step 3 (one `fetch` plus one secret).

## 1. Facts about today's code (file:line)
- App audio today: `flutter_tts` only in the default build (`lib/services/voice_service.dart:4`, `pubspec.yaml:64`). `pubspec.yaml:61` has `http`; there is **no audio-player package**, so the app cannot play server audio now.
- The app can already compute lip-sync from **loudness**: `AudioAlignment.addLevels(t0, hop, values)` (`lib/avatar/speech_audio.dart:152`) takes RMS per 10 ms hop and aligns the viseme plan by dynamic time warping at 20 ms steps (`speech_audio.dart:128`, class at 114). Today those levels come from native code: `AppDelegate.swift:237` sends `{"e":"levels","t0","hop":0.01,"v":[rms]}` per PCM buffer, computed in `levels()` (`AppDelegate.swift:289`), played through `AVAudioEngine` + `AVAudioPlayerNode` (`AppDelegate.swift:48-49`, `scheduleBuffer` at 242). But that path is **fed by `AVSpeechSynthesizer.write`** (`AppDelegate.swift:188-194`), not by arbitrary audio, and is off unless `DW_AVATAR_AUDIO_PATH` (`voice_service.dart:124`), untested on a phone per the code comment.
- So: **server audio cannot play today; lip-sync from loudness is already implemented and reusable** (the Dart side takes any levels stream).
- Fallback machinery exists: a 3 s start watchdog and `viaTts` replay (`voice_service.dart:128`, `387-420`, `_audioFailure`).
- Worker: POST routing in `route()` (`backend/worker.js:703`), chat in `handleChat` (`worker.js:615`) which calls `admit(request, env, cors, {kind, model, inTokens, outTokens, requireToken: !legacy})` (`worker.js:640`; `admit` at `backend/cost_guard.js:596`). `admit` accepts an explicit `neurons` reservation (`cost_guard.js:596,667`), verifies the StoreKit 2 JWS from header `X-DateWise-Entitlement` (CORS header list at `worker.js:55`, verifier `backend/apple_jws.js`), enforces daily/monthly caps and the global neuron budget (`DAILY_NEURON_BUDGET: 10000`, `cost_guard.js:53`). `wrangler.toml:5-6` already binds `AI`.
- The guard budget default equals the free allowance, so natural voice will **need Workers Paid** (already needed beyond about 10 typical subscribers, AI_COST_MODEL.md) and a raised budget: one audio minute of Aura-2 = 900 chars x 2.727 = about 2,455 neurons, so 10,000 neurons/day is only about 4 audio-minutes a day for the whole service.

## 2. Conflict with the owner's rule (decision needed)
AGENTS.md: the Flutter iOS app gets "no new native-only features, bug fixes only". Playing server audio through new Swift code would violate that. Recommended route avoids it:
- **Play in Dart with an existing open-source plugin** (candidates: `just_audio` or `audioplayers`; check licence and iOS audio-session behaviour; both work on web too, which suits "website first, White Glove wraps it").
- **Compute levels in Dart**: request `encoding=linear16, container=wav` (Workers AI schema supports it), decode the PCM (a few lines of Dart), RMS every 10 ms, call `AudioAlignment.addLevels` once per sentence. No Swift change.
- Audio session (duck/mix): keep using `flutter_tts.setIosAudioCategory` (`voice_service.dart:457`) or the plugin's own session config.
If the owner prefers the existing native engine (lower latency, bluetooth latency report), that is a small Swift method but needs an explicit exception.

## 3. Worker endpoint
`POST /tts` (new branch in `route()` before the `messages` check):
1. Parse `{coachId, text, lang?}`; cap body (reuse `readBodyCapped`), cap `text` to 600 chars per call (one or two sentences), reject markup.
2. Auth: `admit(request, env, corsHeaders(), {kind: 'tts', neurons: ceil(chars * 2.727), requireToken: true})` so a missing/invalid StoreKit JWS gets the same 403 `SUBSCRIPTION_REQUIRED`. Add a **separate per-subscriber monthly voice-minute counter** in the existing `UsageGuard` Durable Object (chars, not messages), default 54,000 chars (60 min).
3. Voice map (server-side, versioned): Ava `luna` (or the best of thalia/asteria after listening), Ethan `apollo`/`orion`, Sofia `estrella`, Diego `sirio` (or `javier`); pick after the listening test. Model by detected language (`aura-2-es` for Spanish text; any coach can speak either language, as in `ReplyLanguage.detect`).
4. `env.AI.run('@cf/deepgram/aura-2-es', {text, speaker, encoding: 'linear16', container: 'wav', sample_rate: 24000})` returns a ReadableStream: pass it through with `Content-Type: audio/wav`, `Cache-Control: private, max-age=0`, plus the guard's quota headers (`ticket.headers`).
5. Settle usage with `ticket.finish(actualNeurons, {refund})` via `ctx.waitUntil`; refund on upstream error.
6. Cache (optional, phase 2): key `sha256(voice + normalised text)` in Workers KV for coach greeting and stock phrases only (not user-specific text); KV free tier is 1,000 writes/day.
7. Tests: extend `worker.test.mjs` and `security_attacks.test.mjs`: no token = 403, oversize text = 413, quota exhausted = 429 with `Retry-After`, voice id never taken from the client.

## 4. App changes
1. `NaturalVoiceService implements VoiceService, LipSyncSource` next to `DeviceVoiceService`. Pipeline: split the reply into sentences as the chat stream arrives, request `/tts` per sentence (max 2 in flight), play sentence N while N+1 downloads, call `addLevels` per sentence with the running time offset.
2. Pace and pauses (the owner's complaint): Aura-2 has no rate parameter in the Workers AI schema. Control it on the client by (a) sentence chunking with a 250-400 ms gap inserted by the player between sentences and (b) if the pace is still fast, playback-rate 0.92-0.95 on the player (pitch-preserving on iOS, verify) . If this is not enough, Azure (SSML `<prosody rate>` and `<break>`) or Google (`speaking_rate`) are the control-rich alternatives.
3. Fallback chain: natural voice, then on 402/403/429, network error, or no first audio in 3 s, speak that reply with the system voice (existing `viaTts` path). Remember a failed start for the session after two failures in a row (same pattern as `maxStartTimeouts`).
4. Settings: "Natural voice" toggle with the consent text (section 5); minutes-left indicator from response headers; offline = system voice automatically.
5. Cache the last N sentence audios on device (LRU, 30 MB) so replays and repeated phrases cost nothing.
6. Keep `DeviceVoiceService` untouched as the fallback; it already has the voice-picking tuned by the other agent.

## 5. Privacy and consent
- Add to the privacy policy and App Store privacy answers: the coach reply text is processed by the voice provider to generate audio; with Workers AI Aura-2 the processor is Cloudflare (hosting Deepgram's model, "zero data retention" per the model page); no audio recording of the user is involved (speech recognition stays on device).
- First use: one-screen consent ("To use natural voices, the coach's reply text is sent to our server and a voice provider. It is not stored. Turn off any time."). Store consent per install; default to system voice until accepted.
- Label the voice as AI-generated in the settings text; check regional synthetic-media disclosure rules with counsel (not assessed here).
- Do not log reply text on the Worker (count-only logs, as the cost guard already does).

## 6. Maintenance
Model/voice names can change (Workers AI model catalogue); pin speakers server-side, add a coach-monitor style probe (like `coach-monitor.yml`) that synthesises one sentence hourly-daily, and keep the system voice as permanent fallback. Re-check prices quarterly (this file's prices are 2026-11-24).

## 7. Days of work (one engineer, with Claude)
| Item | Days |
|---|---|
| Worker `/tts`, voice-minute counter, tests | 1.5 |
| Dart NaturalVoiceService: sentence queue, playback plugin, PCM levels, lip-sync hookup | 2.5 |
| Consent UI, settings, minutes indicator, fallback, caching | 1.5 |
| TestFlight build and on-phone tuning (pace, gaps, Bluetooth) | 1.5 |
| Privacy policy / App Store details | 0.5 |
| **Total** | **about 7.5** (about 2 more if the owner insists on the native Swift route with tests) |
Prerequisite before any build: the listening test below (half a day, owner time). Nothing here may merge to main or deploy without owner approval (AGENTS.md).

## 8. The cheapest next step (no spend, no new account)
Synthesise the 8 test sentences (about 1,000 characters = about 2,700 neurons, inside one free daily allowance of 10,000) with `aura-2-en` and `aura-2-es` through the owner's existing Cloudflare account, for the candidate voices (luna/thalia, apollo/orion, estrella, sirio, javier), and have a native Mexican listener plus the owner judge them against build 203. The Cloudflare credentials are not yet in GitHub (research README), so the owner or an agent given the existing Cloudflare token must run it; I made no call to any hosted service.
