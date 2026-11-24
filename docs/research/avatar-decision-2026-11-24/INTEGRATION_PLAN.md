# INTEGRATION PLAN: top two options (Simli first, Anam second)

Date: 2026-11-24. Plan only. Nothing here is built, signed up for or approved. Day counts are my estimates for one engineer who knows the repo.

Constraints applied (AGENTS.md): reuse first; Flutter iOS app gets bug fixes, security fixes and App Store requirements only, **no new native-only features** (so no vendor Swift SDK, no native PCM bridge); new work goes into shared app code and the Worker; no vendor key in the app; spending stays at $0 until the owner approves; no merge to `main`, no production deploy, no App Store submission without the owner.

## 1. What exists today and what each option reuses or replaces

| Part | Today (file) | Reused | Replaced or added |
|---|---|---|---|
| Face | On-device frame compositing (`lib/avatar/talking_avatar.dart`, `avatar_frames.dart`, `avatar_animator.dart`, `lip_sync.dart`, `viseme.dart`, `coach_stage_avatar.dart`) | **Kept unchanged as the fallback and the default** | Add a live-video face widget beside it, chosen by a flag |
| Voice out | System TTS (`lib/services/voice_service.dart`, `flutter_tts`); optional native audio path that renders PCM for levels and word markers (`lib/avatar/speech_audio.dart`, `ios/Runner/AppDelegate.swift`) | Used for the fallback exactly as now | **Live avatar needs the reply as audio on a server or in a WebRTC stream.** Plan: Worker neural TTS (Workers AI Aura-2, placeholder; voice research is separate). The live path therefore changes the coach's voice from the system voice to a neural voice. That is a product change the owner must see and approve |
| Voice in | On-device STT (`speech_to_text`, `onDevice: true`) | Unchanged. The user's speech never leaves the phone | none |
| Text AI | `backend/worker.js` `handleChat`, Llama 3.3, server-side coach prompts | Unchanged | none |
| Auth and caps | StoreKit 2 JWS verified in `backend/apple_jws.js`; `admit()` with `requireToken` in `backend/cost_guard.js`; `UsageGuard` Durable Object counters; kill switches via wrangler vars | **Reuse `admit()` and `UsageGuard` for the new endpoints** | One new counter (avatar seconds per month), one new `kind` |
| Consent | AI consent dialog naming Cloudflare Workers AI and Meta Llama (`app_en.arb`, `chat_screen.dart`, `storage_service.dart` `dw_ai_consent`) | Same pattern and storage | Second consent naming the avatar vendor; separate stored flag |
| Transport | none | | `flutter_webrtc` (Flutter pub package, MIT) or a WebView page; no first-party native code |

Reuse check: reuses the StoreKit JWS gate, UsageGuard counters, consent pattern, voice-service interface and the on-device avatar as fallback. Nothing duplicated: the vendor path is an added renderer, not a second chat, auth or limit system.

## 2. Architecture (same for both vendors; only the token call and the client adapter differ)

```
iPhone (Flutter)                                         Cloudflare Worker (ours)                 Vendor
 on-device STT (unchanged)
 text -> /chat (unchanged, SSE) --------------------->   Llama reply stream
 sentence chunks of the reply ---- POST /avatar/tts -->  Aura-2 TTS (PCM stream)  [admit(kind=avatar)]
 app starts a session:  POST /avatar/session ------->    verify StoreKit JWS (requireToken)
                                                         check monthly seconds in UsageGuard
                                                         call vendor token API with secret --->  returns short-lived token
                        <-- {token, vendor, maxSeconds}
 WebRTC / vendor client  <==== video+audio of the coach, token only ==========================> vendor renders
 PCM chunks from /avatar/tts  ---> vendor audio-in (WebSocket or data channel)
 close or idle 45-60 s: POST /avatar/end -> counters settled
 any failure, cap, offline: stage swaps to TalkingAvatar + system voice (no dialog)
```

Key rules: the vendor API key lives only in Worker secrets (`wrangler secret put`); the app holds a token that expires in minutes and is bound to `maxSeconds`; the Worker refuses to mint when the StoreKit token is missing, expired, revoked or over the monthly avatar-seconds cap; one flag (`AVATAR_LIVE`, wrangler var, default `0`) turns the whole path off server-side. The vendor receives the coach's reply audio and our coach portraits; it receives no microphone audio, no typed text and no user photos.

## 3. Option A: Simli (pilot first)

**Why first:** lowest cost by far ($1.85 at 60 min, $3.87 at 120), plain WebRTC with a token (no JS-only SDK), audio-in so we keep our LLM, prompts and safety rules, own faces from Hobby $10, enterprise offers zero data retention and a 99.95% SLA. **Weakest part:** quality and Spanish are unverified, and its privacy and acceptable-use terms were not readable today.

| Phase | Work | Days |
|---|---|---|
| 0 Approvals | Owner approvals in section 7 of DECISION_BRIEF; Simli Hobby account; upload Ava and Sofia portraits (one custom avatar per month on Hobby: Ava first, Sofia after the monthly reset, or Pro $49 for one month); written vendor questions (below) | 1 |
| 1 Worker | `POST /avatar/session` (JWS gate, cap, vendor token), `POST /avatar/tts` (Aura-2 stream, sentence by sentence), `POST /avatar/end`; `UsageGuard` avatar-seconds counter; `AVATAR_LIVE` flag; tests extending `worker.test.mjs`, `cost_guard.test.mjs`, `security_attacks.test.mjs` (forged/expired token, cap reached, flag off) | 3-4 |
| 2 Flutter | `LiveAvatarStage` widget (RTCVideoView), vendor adapter, consent dialog (EN/ES ARB), state machine with fallback, audio-session handling next to `speech_to_text`, count-only telemetry, remote flag read | 4-5 |
| 3 Device test | TestFlight, iPhone 12 / 15 / 16, Wi-Fi, LTE, Bluetooth headphones, backgrounding, call interruption; the gates in section 6 | 2-3 |
| 4 Compliance | Privacy Policy and Terms text, App Privacy label review, 5.1.2(i) review notes, store copy only after the device test | 1-2 |
| **Total** | | **11-15 days** (pilot subset: section 6, 5-6 days) |

Simli-specific notes: community package `simli_client` 1.0.1 is stale (flutter_webrtc ^0.11.5 constraint) [pub.dev/packages/simli_client]; use flutter_webrtc directly against Simli's documented session-token and audio endpoints, or the WebView route below. Concurrency: Hobby 2, Pro 10, so the pilot is fine and launch needs Pro or higher (concurrency is the cheap-tier limit to watch: 1 concurrent session per roughly 200 daily users is Anam's own rule of thumb, Simli has none).

## 4. Option B: Anam (challenger and premium benchmark)

**Why second:** best quality claims, own-image avatar on the **Free** plan (so a $0-cash test with our portrait), SOC 2 Type II, DPA, no-training statement, region selection and zero retention at Enterprise. **Problems:** $0.11-0.16 per minute at list ($10.83 at 60 min), the $0.04 enterprise rate is unquoted, SDKs are JavaScript/Python only, free sessions are 3 minutes.

Differences from Simli: the client is a **WebView page** (hosted on our Cloudflare Pages, loading the Anam JS SDK with a session token from `POST /avatar/session`) with a JS channel for PCM chunks and state events; WebView needs inline media playback and no user-gesture requirement, and its audio session must coexist with `speech_to_text`. +2-3 days over Simli: **13-18 days**. Bring-your-own audio ("send audio you've already generated") is on the Anam docs introduction [V]; the exact audio-passthrough API and interruption call were not on the page fetched and must be confirmed in the spike.

If Anam is chosen at list price it is a capped premium feature (15-30 min/month, COSTS.md section 6) or needs the enterprise quote first.

## 5. WebView page versus flutter_webrtc (decide in the 1-day spike)

A web page that runs the vendor's JS SDK works in Flutter's WebView today and would work unchanged inside a White Glove Capacitor shell later (AGENTS.md: DateWise moves to White Glove only after the owner verifies DateWise). flutter_webrtc gives lower overhead but ties the stage to Flutter. Recommended: build the stage as a hosted web page first (portable, swaps vendors by changing one file), measure time-to-first-frame in both on a real iPhone, keep flutter_webrtc as the alternative. UNVERIFIED: WKWebView audio-session coexistence with on-device speech recognition and `AVSpeechSynthesizer`; this is the single biggest technical risk and the spike must test it first.

## 6. Minimal pilot that proves it inside DateWise (5-6 days, before any commitment)

Scope: TestFlight/internal only, flag default off, two coaches (Ava EN, Sofia es-MX), one vendor, 60-minute per-tester cap, Workers staging config, no production deploy, no public release.

Build: the three Worker endpoints with JWS gate and cap; `LiveAvatarStage` behind `AVATAR_LIVE`; fallback to `TalkingAvatar`. No payment, no changes to StoreKit or the paywall.

Gates (all must pass; measured on a real iPhone, not simulated):

| Gate | Method | Pass |
|---|---|---|
| Works inside DateWise | A full coaching turn: speak (on-device STT) -> Llama reply -> neural TTS -> live face, 20 turns, EN and ES | 20/20 turns complete, no manual retry |
| Entitlement gate | Call `/avatar/session` with no token, expired token, forged token, sandbox token over cap | 403/429 every time, no vendor call made (check Worker logs, count-only) |
| Identity | `tool/avatar/verify.py` on 10 frames per coach: SFace vs approved reference, plus iris-colour check (existing gates, AGENTS.md: keep approved faces and brown eyes) | SFace >= 0.45, own coach highest, eye colour within gate |
| Lip-sync | `tool/avatar/eval/measure_av.py` on screen recordings; 5 bilabial words per language | lag within +/-80 ms; lips close on m/b/p |
| Spanish | A native es-MX listener rates the Sofia and Diego-voice clips | no visibly English mouth shapes |
| Latency | End of user speech to first moving frame, p50 and p95, Wi-Fi and LTE | p50 <= 2.0 s, p95 <= 3.5 s (estimate for our pipeline: LLM first token 0.3-0.8 s + TTS first chunk 0.2-0.5 s + vendor render) |
| Quality vs today | Blind owner rating of 8 matched clips: current on-device avatar vs vendor | vendor clearly preferred in at least 6 of 8 |
| Fallback | Airplane mode mid-session; kill switch; cap reached; vendor 5xx | stage swaps to the on-device avatar within 3 s with no error dialog |
| Cost | Measured session seconds x list price vs the counters | within 10% |
| Privacy | Vendor's written answers (retention, training, sub-processors, region, minors, acceptable use for dating coaching, fictional likeness) | no training on content; retention <= 30 days or ZDR; acceptable use confirmed in writing |

Vendor questions to send before uploading anything: (1) do you train on or retain uploaded portraits, audio-in or session video, and for how long? (2) where is it processed and who are the sub-processors? (3) is a dating/relationship-coaching app, with fictional AI-generated coach faces, within your acceptable-use policy? (4) minimum age of end users? (5) DPA and SOC 2 availability on our plan? (6) can the custom avatar be deleted on request?

## 7. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Vendor face drifts from the approved portrait or recolours eyes | Medium | Identity gate; the owner's rule is no loosening |
| Source portraits are 1024 px crops of a hero upscaled from about 314x198 references (`docs/legal/ASSET_PROVENANCE.md`); vendor image-to-avatar may amplify softness | Medium | Test with the real files first; fall back |
| Audio-session conflict (WebRTC/WebView vs on-device STT and TTS) | High | Spike first; pause STT while the avatar plays, as the system TTS path already does |
| Neural voice replaces the system voice, so Spanish voice quality and cost become product issues | High | Audition Aura-2 es voices (separate voice research); owner decides |
| Vendor price change or plan lock-in | Medium | One adapter interface; flag; the web-page stage swaps vendors in a day |
| Idle session bills while nobody talks | High | 45-60 s idle close; max token duration |
| Free Workers AI allowance exhausted by TTS neurons | High | Workers Paid is already needed above about 21 typical subscribers (COSTS.md s5); owner approval |
| App Review: 5.1.2(i) third-party AI sharing | Medium | Specific consent before the first live session, decline path to on-device avatar |
| Concurrency ceilings (Simli Hobby 2, Anam 1-10) | Medium | Plan upgrade at launch; queue to fallback |

## 8. Privacy disclosures needed (owner approves the text)

- **Privacy Policy and Terms (`lib/content/legal_text.dart`):** name the avatar vendor as a processor of the coach's reply audio and of the coach portraits for rendering the animated coach; say no microphone audio, typed text or user photos are sent to it; state its retention and no-training commitments once confirmed; say the on-device animation is the alternative.
- **App Privacy label:** the audio sent is synthetic speech whose content can reflect what the user told the coach. Conservative position (as PAID_PROVIDER_BAKEOFF s5): declare data shared with a third party for App Functionality, not linked, not tracking; confirm with the owner's legal check.
- **5.1.2(i):** a one-time dialog before the first live session, EN/ES, naming the vendor and what is sent, with "Use on-device animation only"; stored like `dw_ai_consent`; Delete my data withdraws it; sending is refused in state without it.
- **Spain/EU:** vendor as sub-processor, DPA, processing region (Anam offers region selection on Enterprise; Simli unverified).

## 9. Rollback

1. Server: set `AVATAR_LIVE=0` (wrangler var). `/avatar/session` returns a coded response and the app shows the on-device avatar. No release needed.
2. Client: the flag also hides the live widget; `lib/avatar/*` was never modified, so the shipped avatar is the rollback.
3. Data: delete the custom avatars at the vendor, revoke the Worker secret, cancel the plan.
4. The Worker endpoints are additive; removing them changes nothing else.
