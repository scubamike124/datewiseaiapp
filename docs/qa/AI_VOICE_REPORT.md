# DateWise AI v2: AI coaches, backend, avatars and voices (independent QA)

- Scope: PR #27, branch `claude/datewise-v2-app` at `b36b0eb`. QA branch: `claude/datewise-qa-ai`.
- Date: 2026-11-22 (live probe at 23:48–23:49 UTC).
- Method: code reading, one live probe of the production Worker (read-only POSTs, no deploy, no Cloudflare changes, no spend), new client tests against a local fake server, and image checks.
- **No simulated or mock AI output is counted as a production pass in this report.** Anything that needs the live chat-v6 backend, a physical iPhone, a microphone or Apple credentials is marked **BLOCKED**.

Reuse check: the new tests reuse the shipping `BackendAIService`, `AppState` and `StorageService` with a real `IOClient` (no new client code). The live probe reuses `dwtools/live-chat-test.mjs` with the v2 coach names and the app's own system prompts. The portrait check reuses `dwtools/portrait_intake.py` (OpenCV YuNet/SFace).

## 1. Summary

| Area | Result |
|---|---|
| Four distinct coaches (code) | PASS. Ava and Ethan (en-US), Sofía and Diego (es-MX). Each has its own name, style rules, greeting, starters and voice profile. |
| Live chat (production) | **BLOCKED.** `?version` = `chat-v5`. Every chat POST returns **HTTP 502**: `AiError: 5028: @cf/meta/llama-3.1-8b-instruct-fp8 was deprecated on 2026-11-20`. No real reply came back, so persona and language adherence is unverified. |
| Client behavior tests (no live AI) | 30 new tests, all passing. 3 consecutive reruns were green. |
| Voice mapping, plist and copy tests | 16 new tests, all passing. |
| Full suite on the branch | 339 tests, all passing (existing tests plus the 46 new ones). |
| Legacy v1 profile fields sent | None on origin. The payload `profile` holds only `goals` and `language`, plus `memory` while memory is ON. This is verified by a test with v1 keys pre-seeded in storage. |
| Portraits | Placeholders: 0/8 pass intake. Each hero file is identical to its avatar file, and all are landscape at about 1.2 MP. Identities match the references (SFace 0.87–0.91). |
| Copy honesty | PASS. No claim of animation, lip-sync, video or a "live/talking avatar" in the ARB files, App Store metadata, legal text or coach copy. |

## 2. Area 1: AI coaches and backend

### 2.1 Coach identities (`lib/models/coach.dart`, `lib/services/persona.dart`)

| Coach | id | Language / locale | Gender | Personality (style rules) | Greeting opens with |
|---|---|---|---|---|---|
| Ava | `ava` | en / en-US | female | Confidence coach: direct, supportive, results-focused. Short punchy sentences. Names what works, then the one change that matters most. Ends with one next step for today. | "Hi, I'm **Ava**, your AI confidence coach…" |
| Ethan | `ethan` | en / en-US | male | Strategy coach: practical, modern, laid-back. Casual, dry humor, never lectures. Gives exact wording and a simple step-by-step plan. | "Hey, I'm **Ethan**, your AI strategy coach…" |
| Sofía | `sofia` | es / es-MX | female | Confidence coach: warm and motivating. Acknowledges effort first, then gives honest, concrete advice. Neutral Latin-American Spanish with "tú". Ends with a small step. | "¡Hola! Soy **Sofía**, tu coach de confianza con IA…" |
| Diego | `diego` | es / es-MX | male | Relationship coach: practical, honest, direct. Covers communication, expectations and boundaries. Neutral Latin-American Spanish with "tú". No sermons. | "¡Hola! Soy **Diego**, tu coach de relaciones con IA…" |

All four share the same system prompt. It contains, in order: identity and style rules; a language rule; an AI disclosure ("Never claim to be human"); safety rules; the shared voice rules; the optional `OPTIONS:` line; the profile and memory lines; and "never mention prices". Legacy ids (`emily`, `james`, `isabella`, `mateo`) migrate to the new ones.

**Language-switch behavior (from the code):**

- **The user writes in the other language.** `CoachPersona.languageRule` (persona.dart:35–40) tells the model to reply in the user's language. The coach, its greeting, starters, composer hint, TTS voice and mic locale do not change. The model-side behavior is **BLOCKED** (live backend down).
- **The user changes the app language mid-chat** (You › Language, `AppState.setLanguage`):
  - The UI language changes. The selected coach, the open thread and the coach's default reply language do not.
  - The system prompt's profile line flips to "prefers English" or "prefers Español", which contradicts a coach whose default is the other language (defect D8).
  - Speech recognition and TTS stay on the coach's locale (defects D6 and D7).

### 2.2 Live test

The original script still used the v1 coaches (Emily/James/Isabella/Mateo) and its own simplified prompts. I ran it unchanged, then ran an adapted copy. The copy sends the exact system prompts the v2 app builds (`CoachPersona.systemPrompt`, dumped from Dart) for Ava/Ethan/Sofía/Diego, plus two cross-language cases. The adapted copy lives outside the repo, at `scratchpad/qa-ai-work/live-chat-test-v2.mjs`.

```
Backend version: chat-v5 (expected chat-v6)  <-- MISMATCH
| Coach | Asked in | HTTP | Reply lang | Pass |
| ava | en | 502 | - | NO |
| ethan | en | 502 | - | NO |
| sofia | es | 502 | - | NO |
| diego | es | 502 | - | NO |
| ava (cross-language: EN coach, ES user) | es | 502 | - | NO |
| diego (cross-language: ES coach, EN user) | en | 502 | - | NO |
body: {"error":"Workers AI error","detail":"AiError: 5028: @cf/meta/llama-3.1-8b-instruct-fp8 was deprecated on 2026-11-20. ..."}
```

**Status: BLOCKED.** Production is chat-v5 and returns HTTP 502 for every chat. No reply was produced, so there is nothing to judge for persona or language adherence. The PR's own `backend/worker.js` is still chat-v5 with the deprecated model; chat-v6 lives only in PR #17 (defect D1).

### 2.3 Client behavior tests (no live AI)

These tests are in `test/qa_ai_client_behavior_test.dart`. The requests go through the real `IOClient` and a real TCP socket to a local `HttpServer` or raw `ServerSocket` on 127.0.0.1. The production URL is rewritten to the local server; the rest of the client is the shipping code. All replies are canned SSE: **these tests do not test the AI.**

| Group | What is proven | Result |
|---|---|---|
| Streaming chunk assembly | Tokens flushed one per event arrive in order. Spanish/emoji UTF-8 and CRLF events split into 3-byte TCP writes reassemble exactly. AppState shows the text growing and saves it as complete. | PASS (3) |
| Retries | No automatic retry: a 503 is exactly one request, then a failed reply with the user message kept. `retryLastReply` sends the conversation again, without the failed reply and with the user message once. Connection refused gives one attempt and a `network` failure. | PASS (2) |
| Timeouts | No headers within `connectTimeout` gives `timeout` well before the server answers. Silence longer than `idleTimeout` gives the tokens so far, then `timeout`. In AppState the partial text stays visible, the reply is marked failed, and the partial text is never sent as history. | PASS (3) |
| Mid-stream disconnect | A TCP drop mid-chunk gives a `stream` failure, not a silently short reply. **Finding:** a cleanly closed response without `data: [DONE]` is saved as a complete reply (D2). | PASS (2, one documents the defect) |
| Error mapping | HTTP 400/401/403/404/413/429/500/502/503/504 each give `CoachUnavailableException(http, code)` with no text. An in-stream `{"error"}` event fails the reply. The recorded chat-v5 502 body gives a failed reply with empty text. Recovery via "Try again" works. **Finding:** 429/Retry-After is not distinguished in the UI (D3). | PASS (13) |
| Memory and history | The system prompt comes first, then every complete turn; failed and stopped turns are excluded. **No client-side cap**: a 40-turn thread sends 81 messages (D5). The server keeps the system prompt plus the newest 24 turns within 24,000 characters, each message cut to 6,000 characters; this was checked locally on `worker.js` `sanitizeMessages`: 81 in, 25 out. Memory is OFF by default and nothing is sent. When ON, the note goes in `profile.memory` and the system prompt; switching OFF or clearing removes it from the next request. The note is capped at 500 characters. No v1 fields are sent. Changing the app language keeps the coach. | PASS (7) |

### 2.4 Legacy v1 fields (origin, `b36b0eb`)

`buildPayload` sends exactly `{tier, coachId, profile, messages}` (backend_ai_service.dart:181–192). `UserProfile.toJson` emits only `goals`, `language` and `memory` (user_profile.dart:76–80). `UserProfile.fromJson` ignores `age`, `gender`, `city`, `interestedIn`, `goal` and `app`. The test seeds all six v1 keys in storage and asserts none appears anywhere in the request. **Nothing legacy is sent on origin.**

## 3. Area 2: avatars and voices

### 3.1 Portraits shipped (`assets/coaches/`; there is no `images/` directory any more)

| File | Pixels | Coach (visual) | Notes |
|---|---|---|---|
| ava-hero.jpg / ava-avatar.jpg | 1212×762, landscape | Ava: brunette, long wavy hair, gold hoops, brown eyes, dark blazer | The two files are byte-identical (md5 c81a2a0e…). Waxy skin and painterly hair from the upscale; soft at hero size. |
| ethan-hero.jpg / ethan-avatar.jpg | 1228×762 | Ethan: dark wavy hair, stubble, navy blazer, hand on chin | Byte-identical. Sharpest anatomy, low texture (Laplacian variance 37). |
| sofia-hero.jpg / sofia-avatar.jpg | 1212×658 | Sofía: brunette, long wavy hair, large gold hoops, broad smile | Byte-identical. Top of the head cropped. Upscale smoothing on the skin. |
| diego-hero.jpg / diego-avatar.jpg | 1228×658 | Diego: short dark curly hair, stubble, dark shirt, broad smile | Byte-identical. Forehead cropped at the top. |

- **Hero vs avatar identity:** consistent, trivially, because each pair is one image.
- **Quality in use:**
  - On the welcome hero (390×~422 pt at 3x, so 1170×1266 px), a 762 px-tall source is scaled up about 1.7x on top of the Real-ESRGAN upscale, so it looks soft.
  - Avatars (ClipOval, small) look fine.

`portrait_intake.py` (OpenCV YuNet + SFace) results on the 8 files:

| File | Intake | Own-coach similarity | Highest other coach | Eye shift (hue/brightness) | Head roll |
|---|---|---|---|---|---|
| ava-hero/avatar | FAIL (hero must be portrait ≥1024×1400; avatar short side <1024) | 0.908 | sofia 0.714 | 5.1 / 8.9 | 14.1° |
| ethan-hero/avatar | FAIL (same) | 0.909 | diego 0.660 | 2.1 / 3.5 | 10.8° |
| sofia-hero/avatar | FAIL (same) | 0.866 | ava 0.710 | 10.2 / 9.5 | 13.5° |
| diego-hero/avatar | FAIL (same) | 0.904 | ethan 0.689 | 6.0 / 20.0 | 12.9° |

- **Identity:** every file matches its own approved reference best (0.87–0.91), so no faces are swapped.
- **Size:** the failures are all resolution and orientation.
- **Head roll:** the head-roll warnings target lip-sync masters, which v2 does not use, so they are not applicable.
- **Concern:** Ava and Sofía score 0.71 against each other, and Ethan and Diego about 0.67–0.69. Both are far above OpenCV's 0.363 same-person threshold, and visually each pair reads as one person (D11).

**Provenance and licensing:**

- Per the owner, the portraits were cropped from owner-supplied ChatGPT-generated reference images and upscaled with Real-ESRGAN (BSD-3).
- Git history and docs contain **no provenance record**:
  - Commit `0037076` adds the files without a note.
  - `docs/appstore/checklist.md:36–39` only says to replace the "placeholder" portraits and keep a licence record (D12).
- **Stock photo:** `images/hero.jpg` (stock) was removed from the app in `b36b0eb`. A test asserts that only coach portraits, the icon and fonts are bundled. It still exists in git history (`1a814c3`) but is not shipped.

### 3.2 Voices (`lib/services/voice_service.dart`)

| Coach | TTS locales (in order) | Preferred iOS voices | Pitch | Rate | Stock-iOS pick (test) |
|---|---|---|---|---|---|
| Ava | en-US > en-GB > en-AU > en | Ava, Samantha, Allison, Susan, Zoe, Nicky… | 1.05 | 0.50 | Samantha |
| Ethan | en-US > en-GB > en-AU > en | Evan, Nathan, Alex, Tom, Aaron, Daniel… | 0.92 | 0.47 | Aaron |
| Sofía | es-MX > es-US > es-ES > es | Paulina, Mónica, Marisol, Angélica… | 1.08 | 0.49 | Paulina |
| Diego | es-MX > es-US > es-ES > es | Juan, Jorge, Diego, Carlos, Eddy, Reed | 0.90 | 0.46 | Juan |

- **Voice not installed:**
  - `pickVoice` returns null and `speak()` calls `setLanguage(coach.language.locale)`, so the system default voice for en-US or es-MX is used with the coach's own pitch and rate.
  - With a single voice per language, both coaches of that language share it, and only pitch and rate tell them apart.
  - A wrong-language voice is never chosen.
- **Speech recognition** (`speech_service.dart`, `chat_screen.dart:197–199`):
  - **Locale:** recognition uses the coach's locale (`en_US` / `es_MX`), on device only (`onDevice: true`), dictation mode, 60 s max, 6 s pause.
  - **Permission:** asked on first use (`initialize`). A denial hides the mic and shows `voicePermissionNeeded`, and `recheckPermission` on resume restores it without prompting.
  - **Unsupported:** an unsupported language shows `voiceLanguageUnsupported`.
  - **Captions:** on by default in the voice session, toggleable, showing the last 240 characters of the current reply.
- **iOS strings:** `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are present in `Info.plist`, `en.lproj/InfoPlist.strings` (same text) and `es.lproj/InfoPlist.strings` (Spanish). Both are registered in the Xcode project, `knownRegions` includes `es`, and `CFBundleLocalizations` lists en and es.

### 3.3 Copy honesty

I grepped `app_en.arb`, `app_es.arb`, `docs/appstore/metadata.md`, `legal_text.dart` and `coach.dart` for: animat, lip(-sync), video call/videollamada, live avatar, talking avatar, avatar animado/que habla, labios, face-to-face/cara a cara, FaceTime.

- **No hits.** The only "video" match is App Privacy "Photos or Videos: No".
- The voice-session portrait has the semantic label `coachPortraitStill`, and the chat_screen doc comment says "no video, no lip-sync".
- The metadata describes "Hold the talk button… hear replies read aloud".
- The app is honestly still portraits plus voice. A regression test guards this in `test/qa_voice_mapping_test.dart`.

## 4. Defects

| # | Severity | Location | Defect | Suggested fix |
|---|---|---|---|---|
| D1 | **High (release blocker)** | backend/worker.js:82, :574 | The PR's Worker still uses `@cf/meta/llama-3.1-8b-instruct-fp8`, retired 2026-11-20, and reports `chat-v5`. Production returns 502 on every chat. backend_ai_service.dart:29–32 documents chat-v6, which is not in this branch. | Bring PR #17's worker into this branch: `const TEXT_MODEL = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';` and the version `'chat-v6'`. The owner then deploys it (dashboard paste or `wrangler deploy`) and confirms `GET /?version` returns `chat-v6`. Re-run the live test. |
| D2 | Medium | backend_ai_service.dart:141–153 (and :116) | A response that ends without `data: [DONE]` (a proxy, Worker crash or cut stream that closes cleanly) is accepted as a complete reply, saved as OK, and sent as history. | In `parseSse`, after the `await for` loop add `throw const CoachUnavailableException('truncated');`, which is reached only when `[DONE]` never arrived. Update the one existing fixture test that ends without `[DONE]`. |
| D3 | Low | app_state.dart:367 (`onError: (Object _)`), chat_message.dart:6 | The status code is dropped. 429/Retry-After, offline and server-down all show the same generic notice. | Add `int? failedStatus` (persisted) to `ChatMessage`. In `onError`, set it from `e is CoachUnavailableException ? e.statusCode : null`. In chat_screen, show a "busy, try again in a moment" text for 429 and an offline text when `reason` starts with `network`. |
| D4 | Low | backend_ai_service.dart:86–100 | No automatic retry for transient failures before the first token. Every 502/503/504 or connection error goes straight to the user. | Retry once after 1 s when no token has been emitted and (status ∈ {502, 503, 504} or a network error). Never retry after tokens. |
| D5 | Low | backend_ai_service.dart:209–219 | No client-side history cap: the whole thread is uploaded on every turn, while the Worker keeps only 24 turns / 24k characters (worker.js:90–91, 504–513). | In `buildMessages`, keep only the last 24 complete turns: collect the eligible turns into `turns`, then `for (final m in turns.skip(math.max(0, turns.length - 24)))`. |
| D6 | Medium | voice_service.dart:207–216; chat_screen.dart:113 | TTS always uses the coach's locale. When a coach replies in the user's language (allowed by persona.dart:35–40), English text is read by a Spanish voice or vice versa. | Either (a) product decision: the coach always replies in its own language; change `languageRule` to say so. Or (b) detect the reply language and speak with the same-gender profile of that language: `CoachVoiceProfile.of(Coaches.forLanguage(lang).firstWhere((c) => c.gender == coach.gender))`. |
| D7 | Medium | chat_screen.dart:198; speech_service.dart:134 | Mic recognition is fixed to the coach locale: a user speaking English to Sofía is transcribed as Spanish. There is no fallback when on-device `es_MX` is missing (es-US/es-ES are never tried). | Before `listen`, read `await _stt.locales()` and choose the first available of `CoachVoiceProfile.of(coach).locales`. Offer a mic-language toggle (coach language / app language). |
| D8 | Low | user_profile.dart:72; persona.dart:63–65 | After an app-language change, a coach's prompt says "By default reply in Spanish" and "prefers English" at once. | Drop `prefers ${language.label}` from `UserProfile.summary`, or reword it as "The app interface is in X; follow your LANGUAGE rule." |
| D9 | Low | speech_service.dart:94–106 | `ensureReady` sets `_denied = !_ready`. A recognizer that is unavailable (for example, Siri & Dictation off) is reported as "permission needed" and hides the mic. | After `initialize` returns false, set `_denied = !(await _stt.hasPermission)` and return unsupported otherwise. |
| D10 | Medium (assets) | assets/coaches/*.jpg | Placeholder portraits: landscape, about 1.2 MP, hero identical to avatar, 0/8 pass intake. Soft on the welcome hero. | The owner supplies the 8 finals (hero ≥1024×1400 portrait, avatar ≥1024 short side). Run `portrait_intake.py --apply`. |
| D11 | Medium (assets) | assets/coaches/ava-*, sofia-* (also ethan-*/diego-*) | The coach pairs look like the same person (SFace Ava↔Sofía 0.71, Ethan↔Diego about 0.68). Ava and Sofía share hair, gold hoops, smile and background. | In the finals, differentiate hair, wardrobe, accessories and background tone. Add an intake rule: cross-coach similarity < 0.5. |
| D12 | Medium (compliance) | (missing) docs; docs/appstore/checklist.md:36–39 | No provenance or licence record for the portraits. | Add `docs/legal/ASSET_PROVENANCE.md`. Per file: source (owner-supplied ChatGPT-generated reference, date, account owner), processing (crop; Real-ESRGAN BSD-3 code and its model-weights licence), "not a real person", and the approval date. |
| D13 | Low (copy) | docs/appstore/metadata.md:14 | Stale: "the app's interface labels are in English", but the app ships a full Spanish UI. | Replace with "The interface is available in English and Spanish (follows the device or the language chosen in the app)." |
| D14 | Low (copy) | ios/Runner/es.lproj/InfoPlist.strings:3 | "mantienes pulsado" is Spain-Spanish; the Spanish copy targets es-MX. | Use "mientras mantienes presionado el botón para hablar". |
| D15 | Low | ai_service.dart:35–38 | A release build with a non-HTTPS `COACH_BACKEND_URL` silently ships the canned `MockAIService` as if it were real coaching (`providerLabel` is not shown anywhere). | In `kReleaseMode`, never return `MockAIService`: return a service that fails with `CoachUnavailableException('not configured')`, or `assert`/throw at startup. |

## 5. BLOCKED items (not tested; reason)

| Item | Blocked by |
|---|---|
| Persona adherence (Ava/Ethan/Sofía/Diego) and reply language, including cross-language | The live chat-v6 backend: production is chat-v5 and returns HTTP 502 (D1). |
| Real streaming latency (first byte / total) and real SSE framing from Workers AI | The live chat-v6 backend. |
| How each TTS voice actually sounds, and voice download prompts | A physical iPhone. |
| Mic recognition accuracy in en-US/es-MX, on-device availability, the permission prompt text as shown, the deny → Settings → resume flow | A physical iPhone and a microphone. |
| Localized permission strings in the iOS system prompt, App Store metadata and screenshots | A signed device build or App Store Connect (Apple credentials). |

## 6. Assets needing the owner's approval

1. `assets/coaches/ava-hero.jpg`
2. `assets/coaches/ava-avatar.jpg`
3. `assets/coaches/ethan-hero.jpg`
4. `assets/coaches/ethan-avatar.jpg`
5. `assets/coaches/sofia-hero.jpg`
6. `assets/coaches/sofia-avatar.jpg`
7. `assets/coaches/diego-hero.jpg`
8. `assets/coaches/diego-avatar.jpg`

Also needed:

- the provenance record (D12) signed off with them;
- the `heroFocus`/`avatarFocus` values in `lib/models/coach.dart` re-checked for the new crops;
- the App Store screenshots (`docs/appstore/screenshots/en`, `es`) regenerated and approved after the finals land, since they show today's placeholders.

## 7. How to re-run

```bash
flutter test test/qa_ai_client_behavior_test.dart test/qa_voice_mapping_test.dart   # no network
# Live (after D1 is deployed): dump the prompts, then run the adapted script
NODE_USE_ENV_PROXY=1 node live-chat-test-v2.mjs chat-v6
python portrait_intake.py <dir with {ava,ethan,sofia,diego}-{hero,avatar}.jpg>
```
