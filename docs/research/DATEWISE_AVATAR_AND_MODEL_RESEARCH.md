> **Superseded by DateWise v2 (one $9.99/month plan).** DateWise v2 has a single auto-renewable subscription, `datewise_premium_monthly`, with no free tier and no free trial. Plans, prices, tiers or free-launch notes below are historical; see `docs/appstore/metadata.md` for the current offer.

# DateWise AI: Talking-Avatar, Voice and Coaching-Model Research

**Prepared:** 2026-11-22. **All sources accessed:** 2026-11-22.
**Scope:** four real-time bilingual coach identities (Emily EN-F, James EN-M, Isabella ES-F, Mateo ES-M) for a Flutter mobile app plus web build, with a Cloudflare Worker backend (currently `@cf/meta/llama-3.3-70b-instruct-fp8-fast` for chat and `@cf/meta/llama-3.2-11b-vision-instruct` for the photo coach, per `backend/worker.js`).
**Constraints honoured:** no sign-ups, no API keys, no spending.

---

## 0. How to read the evidence

This session's network policy blocked many vendor websites (Tavus marketing site, D-ID, Simli, Anam, Synthesia, Akool, LiveKit, Cartesia, Deepgram, Groq, Azure, ai.google.dev, NVIDIA, Hugging Face). Every claim therefore carries one of these evidence tags:

| Tag | Meaning |
|---|---|
| **[F]** | I fetched the primary source page (vendor docs, pricing page, license file or legal page) and read the figure myself. |
| **[S]** | Seen only in a web-search result that quotes or summarises the vendor's own page. I could not open the page. **Treat as UNVERIFIED.** |
| **[T]** | Third-party source only (blog, aggregator, tracker). **UNVERIFIED.** |
| **[A]** | My own assessment or arithmetic. It is not a vendor claim. |

Source IDs such as `[C1]` point to the source list in section 7. Every item tagged [S] or [T] also appears in the **Unverified** list in section 6.

**Important:** before any money is committed, re-check every [S] or [T] price on the vendor's live page. The network allowlist for this session would need these hosts for that: tavus.io, d-id.com, simli.com, anam.ai, synthesia.io, akool.com, livekit.io, cartesia.ai, deepgram.com, groq.com, ai.google.dev, azure.microsoft.com, learn.microsoft.com, huggingface.co, docs.daily.co.

---

## 1. Executive summary

**Avatars (Part A)**
- **$0 test path:** use HeyGen **LiveAvatar Sandbox Mode**. It is free, uses no credits, and has unlimited ~1-minute sessions with one stock avatar [F, H2]. Add the **Tavus Free plan**, about 20 CVI minutes a month with a 5-minute cap per conversation [S/T, V1]. Tavus officially supports Flutter through Daily's Flutter SDK [F, V3], and `daily_flutter` 0.41.0 is on pub.dev [F, P1]. Optionally also try **Anam Free** (30 min a month, 3-minute sessions) [S, AN1]. Drive all of them from the existing Worker as a custom OpenAI-compatible LLM endpoint where the vendor supports it. Tavus supports this [F, V4], and so does LiveAvatar FULL mode [F, H3].
- **Low-cost production path:** **LiveAvatar LITE mode** (avatar video only, $0.09-0.095 per credit at 1 credit per minute [F, H2]), plus your own speech pipeline (Workers AI Deepgram Nova-3 STT, Workers AI Deepgram Aura-2 EN/ES TTS [F, C1], and your existing Worker LLM). It runs over LiveKit (`livekit_client` Flutter SDK [F, P1]).
  - **Estimate:** about **$1.04-1.14 per 10-minute session**, and about **$1,040-1,140 a month for 1,000 sessions** [A].
  - **Cheaper alternative to benchmark:** Simli, at about $0.05/min [T]. That works out to about **$0.70 per session** and about **$700 a month** [A]. The price is UNVERIFIED.
  - **Most turnkey but dearest:** Tavus Business. That is about **$2.54 per session** and about **$2,535 a month** [A on S/T prices].
- **Identities:** start with **vendor stock avatars**, which the vendor has already licensed. For launch, move to **four licensed adult actors**: native EN and ES speakers on a written AI-likeness and voice release, plus each platform's own consent recording. For voices, either clone the same actors with consent, or use **designed synthetic voices** (ElevenLabs Voice Design, OpenAI prompt-to-voice), which need no consent recording [F, O5]. Avoid celebrity look-alikes and "photo of a stranger" faces, which several platforms auto-reject [F, V2].

**Models (Part B)**
- **Free baseline:** keep Workers AI, but plan to move chat from Llama 3.3 70B to **`@cf/google/gemma-4-26b-a4b-it`** (not deprecated, 256K context, Cloudflare's own recommended replacement [F, C3]).
  - **Cost per message:** about 21.8 neurons, against 101.4 for Llama 3.3 70B. That means about 4.6x more free messages a day (458 against 98) [A on F prices].
  - **Monthly cost:** 1k MAU about **$14.40/mo**, 10k MAU about **$144/mo**. Llama 3.3 70B costs $66.92 and $669.24 [A].
  - **Caveat:** neither figure counts the $5/mo Workers Paid minimum [F, C6] or the free allowance.
  - Spanish quality must be checked with a bilingual eval first.
- **Paid upgrade candidates to evaluate:** (1) **Claude Haiku 5.5**, $0.10 / $0.50 per MTok, about **$18 / $180 a month** [F, AN-P]. (2) **OpenAI GPT-6 Luna**, $0.10 / $0.50 per MTok, about **$18 / $180 a month** [F, O1].
  - Both providers state that API data is not used for training by default [F].
  - Both are far more capable than small open models for nuanced coaching (assessment, needs eval).
  - Avoid the **Gemini free tier** for user conversations: unpaid-tier content may be used to improve Google products, and may be seen by human reviewers [S, G2].

---

## 2. Part A: Real-time talking avatars

### 2.1 Platform comparison (real-time, two-way)

| Platform | Free tier / trial | Price per minute | Real-time latency (vendor claim) | Flutter / web path | Stock vs custom; consent rules | Commercial use | Data retention / privacy |
|---|---|---|---|---|---|---|---|
| **Tavus CVI** (Phoenix-4/4.5 face, Raven perception, Sparrow turn-taking) | Free: 20 min/mo, 5-min cap per conversation [T, V1] (older pages said 25 min) | Starter $22/mo (60 min, no overage); Builder $59 (175 min), overage $0.35; Growth $397 (1,300 min), overage $0.31; Business $975 (4,000 min), overage $0.26 [T, V1]. The Tavus page snippet showed $0.37 and $0.32 [S]. Billed in 6-s increments [T] | "Low utterance-to-utterance latency", "world's lowest latency"; no ms figure in the docs I read [F, V5] | **Native:** Daily Flutter SDK joins the Tavus `conversation_url` (officially documented) [F, V3]. **Web:** `@tavus/embed`, `@tavus/cvi-ui` React, iframe/hosted embed [F, V6]. **LiveKit plugin** [F, L1] | 100+ stock faces, some plan-locked [F, V7]. Custom: video-to-face or image-to-face (Phoenix-4.5) [F, V6]. You must hold rights to the likeness, voice and footage. The checker rejects celebrities and anyone appearing under 18 [F, V2] | Yes on paid plans (ToS not fetched) | Delete endpoints exist for conversations, faces and voices; ZDR conversations mentioned [F, V6]. Privacy policy: conversation logs up to 90 days, possibly for the consumer product only [S, V8] |
| **HeyGen LiveAvatar** (successor to HeyGen Interactive/Streaming Avatar) | Free: 10 credits/mo, no overage. **Sandbox Mode: free, unlimited, ~1-min sessions, one stock avatar ("Wayne")** [F, H2] | FULL mode (STT+LLM+TTS included) 2 credits/min; LITE mode (video only) 1 credit/min. Essential $99/mo = 1,100+10 credits, overage $0.095/credit; Business $475 = 6,000+10 credits, overage $0.09 [F, H2]. **That is about $0.09-0.18/min.** Separate from HeyGen API credits [F, H1] | Not stated in the pages I read | LiveKit, Pipecat and Agora plugins. Connectors for ElevenLabs Agents, Cartesia, OpenAI Realtime and Gemini Live [F, H3]. LiveKit plugin `livekit-plugins-liveavatar` [F, L1]. Flutter via the LiveKit SDK [A] | Stock avatars. Custom LiveAvatars on paid plans need about 2 min of footage **plus a separate consent recording** from the person [S, H4] | Paid plans (terms not fetched) | Biometric notice: face geometry and voiceprint collected for custom avatars [S, H4]. ZDR is Enterprise-only, 24 h-100 days [S, H4] |
| **D-ID Agents / Streams** | 14-day trial, about 3 shared min (one source says 10 streaming min), watermarked [T, D1] | Build about $14.40/mo (annual), personal use only; Launch about $35/mo, 90 streaming min; commercial use from Launch [T, D1]. No public per-minute overage found | "Near-human latency"; uses WebRTC [S, D2] | WebRTC streaming API; LiveKit plugin [F, L1]. No Flutter SDK found [A] | Stock and photo/video avatars. Personal avatars "only with explicit consent" [S, D2] | From the Launch tier [T] | Biometric data not used for training; retention "as long as necessary" [S, D3] |
| **Simli** (Legacy 30 fps, Trinity 25 fps) | Reported $10 signup credit plus 50 min/mo [T, SI1] | About $0.05/min pay-as-you-go [T, SI1] | <300 ms speech-to-video (homepage claim) [S, SI2] | `simli_client` Flutter package 1.0.1, last published 2024-12-15, stale [F, P1]. LiveKit and Pipecat plugins [F, L1, L2] | Stock plus custom faces made in the dashboard. Consent terms not found [S]. Users must be 18+ [T] | Not confirmed | Directory says user content may train models [T, SI2]. **Verify before use** |
| **Anam** (CARA models) | Free: 30 min/mo, 3-min sessions, no overage, no card [S, AN1] | "From $0.04/min" at volume, billed per second [S, AN1]. Third-party sources say Starter is $12/mo with $0.16-0.18/min overage [T] | 150-180 ms avatar generation; 1.24 s median full-pipeline reply [S, AN2] | JS/React/Python SDKs; no Flutter SDK [S]. LiveKit plugin [F, L1]. Web works inside a Flutter web build or a WebView [A] | Stock plus unlimited custom avatars and voice cloning on all plans [S]. Consent terms not found | Not confirmed | Not found |
| **Synthesia Interactive** | Not found | Avatar-only $0.10/min; full stack $0.20/min ("coming soon") [S, SY1] | Not stated | LiveKit plugin `livekit-plugins-synthesia` [F, L1] | Stock avatars and personal avatars (consent process not verified) | Paid | Not checked |
| **Akool Streaming Avatar** | About 5-min free streaming session [T] | 1-1.2 credits per 10 s, i.e. 6-7.2 credits/min; $ per credit not published [S, AK1]. API from about Pro Max ($41-59/mo) [T] | Not stated | Web SDK (not verified) | Stock and custom | Not confirmed | Not checked |
| **LiveKit-based stack** (transport plus agent framework; bring your own avatar, STT, LLM, TTS) | Build plan free: 1,000 agent-session min/mo, 5 concurrent, hard cap [S, LK1] | Ship/Scale: $0.01 per extra agent minute [S, LK1] | Transport only (WebRTC) | **Best Flutter fit:** `livekit_client` 2.14.0 (2026-11-19) and `livekit_components` [F, P1]. Avatar plugins for Tavus, LiveAvatar, D-ID, Simli, Anam, Synthesia, bitHuman, Beyond Presence and others [F, L1] | Depends on the avatar vendor | `livekit/agents` is Apache-2.0 [F, L1] | Self-host option (open source) |
| **NVIDIA ACE / Audio2Face-3D** | SDK is open source | Self-host GPU cost only; NIM container under NVIDIA license | Real-time on GPU | Drives **3D rigged characters** (Unreal, Maya), **not photoreal video**. No Flutter path without a game-engine renderer [A] | Your own 3D characters; no likeness issues if fictional | SDK: MIT. Training framework: Apache. Models: NVIDIA Open Model License. NIM: NVIDIA SLA [F, N1]. An older NIM listing said "non-commercial" [S] | Self-hosted |
| **bitHuman** | Not checked | Not checked | Renders locally on CPU from a `.imx` model, "no GPU required", or in the cloud [F, L1] | LiveKit plugin [F, L1] | Not checked | Not checked | Local render keeps video on your servers [A] |

### 2.2 Open-source avatar routes (self-hosted; all need a GPU server for real-time, so none is truly $0 in production)

| Project | Code license (from the repo LICENSE) | Commercial-use catches | Real-time? | Last commit |
|---|---|---|---|---|
| **MuseTalk** (Tencent Music) | MIT [F, OS1] | Depends on the SD-VAE, Whisper and other weights it downloads (not re-checked) | **Yes:** "30fps+ on an NVIDIA Tesla V100" [F, OS1] | 2026-11-19 |
| **LivePortrait** (Kuaishou) | MIT [F, OS2] | **InsightFace detection models are "for non-commercial research purposes only"**; you must swap them for commercial use [F, OS2] | Near real-time on GPU (not measured) | 2026-06-02 |
| **SadTalker** (Tencent) | Apache-2.0; the non-commercial restriction was removed [F, OS3] | Third-party components are listed separately in the LICENSE | No (offline generation) | 2023-10-11 (inactive) |
| **Wav2Lip** | No LICENSE file in the repo [F, OS4] | README now promotes the commercial sync.so API. The original model is widely described as non-commercial [T]. **Do not use commercially** | Near real-time but low-res | 2025-06-22 |
| **Hallo / Hallo2** (Fudan) | MIT [F, OS5] | The high-res feature uses CodeFormer, **S-Lab License 1.0** (non-commercial) [F, OS5] | No (diffusion, slow) | 2024-09 / 2025-02 |
| **NVIDIA Audio2Face-3D** | SDK MIT; models NVIDIA Open Model License [F, N1] | 3D only | Yes | 2025-09-24 |

**Verdict [A]:** open source makes sense only if you later want to own the stack on rented GPUs. For a small team, a managed real-time avatar API is cheaper than keeping a V100/A10-class GPU warm 24/7.

### 2.3 Voice comparison (TTS and voice agents)

Price per minute assumes about 900 characters per minute of speech (150 words/min x about 6 chars) [A].

| Provider | Free tier | Price | Approx $/speech-min [A] | Latency (vendor) | EN / ES | Integration | Custom voice and consent | Commercial use | Data / retention |
|---|---|---|---|---|---|---|---|---|---|
| **ElevenLabs TTS** | Free: 10k credits/mo [F, E2] | Flash/Turbo and v4 Turbo $0.04/1k chars; v4/v3/Multilingual v2 $0.08/1k chars [F, E1] | $0.036 (Flash) to $0.072 | Flash ~75 ms; v4 Turbo ~100 ms; v3 Conversational ~280 ms [F, E1] | 32 languages (Flash) to 90+ (v4) [F, E1] | REST/WebSocket. The Flutter package is a stale 2023 community wrapper [F, P1], so call from the Worker or LiveKit | Instant clone from Starter, Professional clone from Creator [F, E2]. Cloning a living person needs "explicit and informed consent"; no voices of anyone under 18 [F, E3] | **Free users: non-commercial only** [F, E4]. Commercial from Starter ($6/mo) [F, E2] | Content may be used for training unless you opt out in "Data use" settings [F, E4]. **Apps directed at under-18s prohibited unless approved in writing** [F, E3] |
| **ElevenLabs Agents** (STT+TTS+turn-taking; LLM billed at cost) | 15 call-min/mo, 4 concurrent [F, E5] | $0.08/min plus LLM; burst $0.16/min [F, E5] | $0.08 + LLM | Not stated | Multilingual | Web widget, WebRTC/WS SDKs; LiveAvatar connector [F, H3] | As above | Starter+ [F, E5] | Configurable retention, can be set to 0 days; audio saving can be disabled [F, E6] |
| **Cartesia Sonic 3/3.5** | 20k credits/mo [S, CA1] | About 1 credit per char; Pro $5/mo = 100k credits [S, CA1] | Not computable without a $/credit figure | Sub-90 ms TTFA for Sonic 3.5 (vendor); 128-166 ms median in a Vapi benchmark [S/T, CA2] | 42 languages incl. Spanish [S] | WebSocket; LiveKit plugin [F, L1] | Instant cloning on Pro. Cloning without permission is prohibited [S, CA2] | **Free tier: no commercial license** [S] | Not checked |
| **OpenAI TTS** (`gpt-4o-mini-tts`, `tts-1`) | No free tier | gpt-4o-mini-tts: $0.60/1M text-in, $12/1M audio-out tokens. tts-1: $15/1M chars; tts-1-hd: $30/1M chars [F, O1] | tts-1 ≈ $0.0135 | tts-1 "lower latency" [F, O3] | 13 voices "optimized for English"; follows Whisper language support [F, O3] | REST | **Must disclose that the voice is AI-generated** [F, O3]. Recording-based custom voices: eligible customers only, with a consent recording. Prompt-to-voice needs no consent recording but works only with GPT-Live [F, O5] | Yes | API data not used for training by default. Abuse logs kept up to 30 days [F, O4] |
| **OpenAI GPT-Live / Realtime** (speech-to-speech) | No | GPT-Live $0.05/min active, $0.02/min standby [F, O1]. gpt-realtime-2.1-mini audio $10 in / $20 out per 1M tokens [F, O1] | $0.05 (GPT-Live) | Full-duplex: "can listen and speak at the same time" [F, O6] | GPT-Live extra voices list EN/PT/DE/FR/HI/JA/KO; **no Spanish-specific voice listed** [F, O6] | WebRTC and WebSocket [F, O6]. LiveAvatar connector [F, H3] | Prompt-to-voice (no consent needed) [F, O5] | Yes | As OpenAI API |
| **Azure Speech neural** (en-US, es-MX, es-ES) | F0: 0.5M neural chars/mo [S, AZ1] | Price not captured (search showed "$-"). Commonly about $15-16/1M chars [T] | About $0.014 [T] | Not checked | Strong es-MX/es-ES/en-US catalogue (not re-verified) | REST, WebSocket, Speech SDK | **Custom Neural Voice is Limited Access** (application required) [S, AZ1]. Talent consent statement required (not re-verified) | Yes (paid) | Not checked |
| **Google Cloud TTS** | Chirp 3 HD: 1M chars/mo free; Neural2: 1M free; WaveNet/Standard: 4M free [F, G3] | Chirp 3 HD $30/1M; Neural2 $16/1M; WaveNet/Standard $4/1M; Instant custom voice $60/1M; Gemini 3.8 Flash TTS (preview) $0.50 in / $9 audio-out per 1M tokens until 2026-12-31 [F, G3] | Chirp 3 HD $0.027; Neural2 $0.014; WaveNet $0.0036 | Not checked | en-US, es-US, es-ES voices exist (not re-verified this session) | REST/gRPC streaming | Instant custom voice priced; consent process not checked | Yes; **billing must be enabled even for the free tier** [F, G3] | Cloud terms |
| **Deepgram Aura-2** | Signup credit not confirmed | Direct: $0.030/1k chars (volume $0.027) [S, DG1]. **Via Workers AI: `@cf/deepgram/aura-2-en` and `aura-2-es` at $0.030/1k chars, counted against the free 10k neurons/day** [F, C1] | $0.027 | Not checked | aura-2-es has 10 Spanish speakers (e.g. sirio, nestor, carina, celeste, alvaro, diana, aquila, selena, estrella, javier) [F, C4] | **Already inside your Worker:** no new vendor account, Cloudflare data terms (no training, zero retention) [F, C5] | Stock voices only on Workers AI | Deepgram terms apply [F, C4] | Workers AI: no training, no retention for standard inference [F, C5] |
| **Piper** | Free, self-host | $0 plus CPU | Fast on CPU | Many EN/ES voices; each voice has its own license | ONNX, runs anywhere | Voice licenses vary per voice | **Current repo (`OHF-Voice/piper1-gpl`) is GPL-3.0** [F, OS6]. The old `rhasspy/piper` was MIT [F, OS6] | GPL affects only distribution of a modified engine. Running it server-side is fine, but get legal sign-off [A] | Self-hosted |
| **Coqui XTTS-v2** | Free | $0 plus GPU | <200 ms streaming (README) [F, OS7] | 17 languages incl. ES [F, OS7] | Python | Voice cloning from short samples | **Code MPL-2.0 [F, OS7], but the XTTS-v2 weights are under the Coqui Public Model License: non-commercial only. Coqui shut down, so there is no commercial license route** [T, OS8] | **Not usable commercially** | Self-hosted |
| **MeloTTS on Workers AI** | Was free in neurons | - | - | - | - | - | - | - | **Deprecated 2026-11-20**; Cloudflare's replacement is aura-2-en [F, C3] |

### 2.4 Cost per 10-minute session and per 1,000 sessions a month

**Assumptions [A]:**
- A 10-minute session has about 5 min of coach speech (~4,500 chars), about 5 min of user speech, and about 20 LLM turns of 1,500 input and 300 output tokens each. That is 30k input and 6k output tokens per session.
- 1,000 sessions = 10,000 avatar-minutes a month.

| Stack | Avatar | STT | TTS | LLM | Transport | **Per 10-min session** | **1,000 sessions/mo** |
|---|---|---|---|---|---|---|---|
| **A. LiveAvatar LITE + Workers AI pipeline (recommended)** | Business plan: $475 + 4,000 overage credits x $0.09 = **$835** [F, H2 worked example] | Workers AI nova-3 WebSocket $0.0092/min x 5 = $0.046 [F, C1] | Aura-2 EN/ES 4.5k chars x $0.03 = $0.135 [F, C1] | Llama 3.3 70B: 0.03 x 0.293 + 0.006 x 2.253 = $0.022. Gemma 4: $0.005 [A] | LiveKit Ship, about $0.01/min overage [S] | **≈ $1.04 (≈ $1.14 with LiveKit overage)** | **≈ $1,040-1,140** |
| **B. LiveAvatar FULL** (everything bundled) | $1,735 for 20,000 credits [F, H2] | incl. | incl. | incl. (or custom LLM) | incl. | **≈ $1.74** | **≈ $1,735** |
| **C. Simli + Workers AI pipeline** | $0.05/min x 10 = $0.50 [T] | $0.046 | $0.135 | $0.022 | LiveKit about $0.10 [S] | **≈ $0.70-0.80** | **≈ $700-800** (UNVERIFIED) |
| **D. Synthesia avatar-only + pipeline** | $0.10/min x 10 = $1.00 [S] | $0.046 | $0.135 | $0.022 | about $0.10 | **≈ $1.30** | **≈ $1,300** (UNVERIFIED) |
| **E. Tavus Business** (full pipeline incl. STT/TTS/LLM) | $975 for 4,000 min + 6,000 x $0.26 = $2,535 [T] | incl. | incl. | incl. (or BYO LLM) | Daily incl. | **≈ $2.54** | **≈ $2,535** (UNVERIFIED) |
| **F. Tavus Growth** | $397 + 8,700 x $0.31 = $3,094 [T] | incl. | incl. | incl. | incl. | ≈ $3.09 | ≈ $3,094 (UNVERIFIED) |
| **G. Anam at the advertised floor** | $0.04/min x 10 = $0.40 [S] (typical tier likely higher, $0.11-0.18 [T]) | + pipeline if BYO | | | | ≈ $0.40-1.80 | ≈ $400-1,800 (UNVERIFIED) |
| **H. Voice-only fallback** (no video): ElevenLabs Agents | - | incl. | incl. | + LLM at cost | incl. | $0.08 x 10 + LLM ≈ $0.82 [F, E5] | ≈ $820 |
| **I. Voice-only fallback: OpenAI GPT-Live** | - | incl. | incl. | incl. | WebRTC | $0.05 x 10 = $0.50 active [F, O1] | ≈ $500 |

**Notes [A]:**
- Plan prices and included minutes are step functions. At 100 sessions a month (1,000 min), LiveAvatar Essential ($99) covers LITE mode entirely, which is about **$0.99 per session** for the avatar alone.
- Free sessions should not hit paid avatar minutes. Gate video sessions to paid tiers and offer text or voice-only coaching on the free tier.
- The Workers Paid plan has a $5/month minimum [F, C6]. Workers AI usage beyond 10k neurons/day costs $0.011 per 1k neurons [F, C1].

### 2.5 Flutter and web integration paths

| Path | Mobile (Flutter) | Web build | Notes |
|---|---|---|---|
| **LiveKit room + avatar plugin** (Tavus / LiveAvatar / Simli / Anam / D-ID / Synthesia) | `livekit_client` 2.14.0 [F, P1] | Same SDK on Flutter web | One transport for every vendor, so you can switch avatar vendors without app changes. The agent runs server-side (Python/Node LiveKit Agents) [A]. **Note:** LiveKit agents do not run inside a Cloudflare Worker. You need a small always-on agent host, or LiveKit Cloud's hosted agents [A, UNVERIFIED] |
| **Tavus via Daily** | `daily_flutter` 0.41.0 [F, P1]; Tavus docs officially point to it [F, V3] | `@tavus/embed` web component, or the hosted link (iframe) [F, V6] | Fastest Tavus route. Your Worker creates the conversation server-side and returns `conversation_url`. The API key never ships in the app [A] |
| **iframe / WebView** | `webview_flutter` with the vendor-hosted page | iframe | Quickest prototype. Camera and mic permissions in a WebView need extra platform setup [A] |
| **REST only** | - | - | Used only to mint session tokens; real-time media always goes over WebRTC |

### 2.6 Recommendations: avatars

**(1) $0 testing path (do first, in this order) [A]**
1. **LiveAvatar Sandbox Mode** (free, no credits, one stock avatar, ~1-min sessions) [F, H2]. Use it to prove the end-to-end LiveKit + Flutter + Worker loop in LITE mode. Feed your own TTS audio from Workers AI Aura-2 EN/ES, which fits inside the 10k free neurons/day. That is ~3,600 chars/day, about 4 minutes of speech [A, on C1]. Use Nova-3 for STT.
2. **Tavus Free** (about 20 min/mo) [T]. Test Phoenix-4.5 stock faces, Spanish (`languages: ["es"]`) [F, V9], and the custom-LLM option pointing at your Worker [F, V4]. Join from Flutter with `daily_flutter`.
3. Optional head-to-head on quality and latency: **Anam Free** (30 min) [S] and **Simli Free** (reported 50 min) [T].
4. **Voices:** pick candidate EN and ES voices from Aura-2 (Workers AI), ElevenLabs Free (non-commercial, testing only), Google Chirp 3 HD (1M free chars, but billing must be enabled) and Cartesia Free.
5. **Do not** test with real user data on free tiers whose terms allow training (ElevenLabs Free unless you opt out [F, E4]; Simli [T]).

**(2) Low-cost production path [A]**
- **Default:** LiveAvatar LITE mode with a Workers AI speech pipeline and your existing Worker LLM, over LiveKit, which gives the same SDK for Flutter mobile and web.
- **Cost:** ≈ $1.04-1.14 per 10-min session, ≈ $1,040-1,140 a month at 1,000 sessions.
- **Run a 1-week bake-off** against Simli (≈ $0.70/session) and Tavus (≈ $2.54/session, best turnkey perception and turn-taking) on the same 4 test scripts in EN and ES. Pick on lip-sync quality in Spanish, latency and price.
- **Tier-gate video coaching.** Offer voice-only (≈ $0.50-0.82/session) or text on lower tiers.

**(3) Four distinct, consistent coach identities, legally**

| Option | How | Legal position | Fit |
|---|---|---|---|
| **Stock avatars** (vendor library) | Pick 2 female and 2 male stock faces with matching stock or designed voices | Vendor has the model releases; you get a license to use them on that platform [A]. **Not exclusive:** other apps may use the same face | **MVP / beta**. Fastest, zero likeness risk |
| **AI-generated faces** (synthetic person, then image-to-face) | Generate a non-existent adult face, train via Tavus image-to-face [F, V6] or another vendor | No real person's consent needed, **but** you must check that the face does not resemble a real or famous person (Tavus auto-rejects celebrities and minors [F, V2]). Check each vendor's AUP for synthetic-face training (not verified). Copyright in purely AI-generated images may be weak, so brand protection is limited [A] | Unique and cheap, but legal novelty and "uncanny" risk |
| **Licensed actors (recommended for launch)** | Hire 4 adult native speakers (EN-US female/male, ES female/male; pick es-MX or es-ES deliberately). Shoot each vendor's training footage plus the **vendor consent recording** (HeyGen/LiveAvatar requires one [S, H4]; Tavus requires rights to likeness, voice and footage [F, V2]) | **Written talent release:** AI likeness and voice synthesis, named platforms, dating-coaching context, territories, term, exclusivity, compensation, approval rights, revocation and takedown, morality clause (no sexual or explicit use) [A]. Voice clones need "explicit and informed consent" (ElevenLabs [F, E3]; OpenAI consent recording [F, O5]). Biometric-privacy notices apply (HeyGen [S, H4]; BIPA-type laws) | **Production.** Exclusive, consistent, defensible |
| **Designed voices** (pair with any face option) | ElevenLabs Voice Design or OpenAI prompt-to-voice (no consent recording needed [F, O5]) | No real-person rights involved; disclosure still required | Good when the face is stock or synthetic |

**Consistency rules [A]:**
- Fix one face ID and one voice ID per coach per language.
- Keep a persona sheet (age range, backstory, tone, catch-phrases) inside the LLM system prompt.
- Never let Emily or James speak Spanish with their EN voice. Route ES users to Isabella or Mateo.
- **Disclose AI** at the start of every session. This is required by Anthropic's usage policy for consumer chatbots [F, AN-AUP] and OpenAI's TTS policy [F, O3]. EU AI Act Art. 50 transparency obligations also likely apply [UNVERIFIED].

---

## 3. Part B: Conversational models for coaching

### 3.1 Cloudflare Workers AI: current status (catalogue checked 2026-11-22)

- **Deprecations:**
  - **2026-11-20:** Cloudflare deprecated, among others, `qwen3-30b-a3b-fp8`, `qwq-32b`, `llama-3.1-8b-instruct-fp8`, `llama-3.2-1b/3b-instruct`, `glm-5.3-flash`, `kimi-k2.6/2.7-code`, `nemotron-3-120b-a12b`, `deepseek-r1-distill-qwen-32b` and `melotts`. Requests now return **HTTP 410 / error 5028** [F, C3].
  - **2026-05-30:** Cloudflare deprecated `llama-3.1-8b-instruct`, `llama-3.1-70b-instruct`, `gemma-3-12b-it`, `mistral-7b-instruct-v0.1` and others [F, C3].
  - **Pricing page lag:** the pricing page still lists some retired models (e.g. gemma-3-12b-it, mistral-7b-v0.1), but their model pages return 404 [F, C1/C4].
- **Your repo is already aligned.** `backend/worker.js` uses `llama-3.3-70b-instruct-fp8-fast` (still active), and `worker.test.mjs` pins the retired list.
- **Free allowance:** 10,000 neurons/day on both Free and Paid plans. Beyond that, $0.011 per 1,000 neurons, and only on Workers Paid ($5/mo minimum) [F, C1, C6].
- **Data:** no training on customer content and zero retention for standard inference; model pages show "Zero data retention: Yes" [F, C5, C4].
- **Rate limit:** text generation 300 requests/min [F, C2]. Streaming is supported (the app already streams SSE).

| Workers AI model (active) | $/M in | $/M out | Context | Neurons per message (1,500 in + 300 out) [A] | Free msgs/day [A] | Notes |
|---|---|---|---|---|---|---|
| `@cf/meta/llama-3.3-70b-instruct-fp8-fast` (current) | 0.293 | 2.253 | **24,000** | 101.4 | ~98 | Llama 3.3 license and AUP [F, C4] |
| `@cf/google/gemma-4-26b-a4b-it` | 0.100 | 0.300 | 256,000 | 21.8 | ~458 | Cloudflare-recommended "smaller model" replacement [F, C3] |
| `@cf/openai/gpt-oss-120b` | 0.350 | 0.750 | 128,000 | 68.2 | ~146 | Reasoning model (hidden reasoning tokens add output cost [A]) |
| `@cf/openai/gpt-oss-20b` | 0.200 | 0.300 | 128,000 | - | - | |
| `@cf/qwen/qwen3.8-27b` | 0.450 | 3.200 | 262,144 | - | - | Cloudflare-recommended replacement [F, C3] |
| `@cf/mistralai/mistral-small-3.1-24b-instruct` | 0.351 | 0.555 | 128,000 | - | - | Strong in European languages [A] |
| `@cf/meta/llama-4-scout-17b-16e-instruct` | 0.270 | 0.850 | 131,000 | - | - | |
| `@cf/zai-org/glm-4.7-flash` | 0.060 | 0.400 | 131,072 | 19.2 | ~521 | "Fast multilingual" (Cloudflare) [F, C3] |
| `@cf/deepseek-ai/deepseek-v4.1-flash-1017` | 0.300 | 1.200 | 1,048,576 | - | - | **Paid billing required** [F, C1] |

### 3.2 Model provider comparison

| Provider / model | $/M in | $/M out | Free tier | Trains on API data? Retention | Usage-policy points for dating coaching | Spanish [A unless noted] | Streaming |
|---|---|---|---|---|---|---|---|
| **Workers AI** (above) | 0.06-0.45 | 0.30-3.20 | 10k neurons/day [F, C1] | **No training; zero retention** [F, C5] | Each model's own license and AUP applies [F, C5] (Llama, Gemma, Apache) | Good for Llama 3.3 / Gemma 4 / Mistral Small, needs eval | Yes (in use) |
| **Groq** `openai/gpt-oss-120b` | 0.15 [T] | 0.60 [T] | Free: 30 RPM, 1K RPD, 8K TPM, 200K TPD for gpt-oss-120b [S, GQ1] (≈ 110 messages/day at 1,800 tokens) | ZDR self-serve in Data Controls [S, GQ2]. Default logs up to 30 days [T]. No-training commitment reported but not confirmed [T] | Groq AUP not checked | gpt-oss multilingual, mid quality [A] | Yes |
| **Groq** `qwen3-32b` | 0.29 [T] | 0.59 [T] | Free limits per model [S] | as above | | Good | Yes |
| **Groq** `llama-3.3-70b-versatile` | 0.59 [T] | 0.79 [T] | - | as above | | Good | Yes. **May now be Enterprise/contact-sales** [T] |
| **Google Gemini 3.1 Flash-Lite** | 0.25 [F, G1] | 1.50 [F, G1] | Free tier exists [S, G4] (RPD limits not captured) | **Unpaid tier: content used to improve Google products; human reviewers may read it (after de-linking).** Paid tier: not used to improve products [S, G2] | Archived Gemini API terms: **users must be 18+, and API clients "directed at or likely to be used by" under-18s are prohibited** [S, G2]. Current 2026-03-23 terms: "for professional or business purposes" [S] | Very good | Yes |
| **Gemini 3.5 Flash-Lite** | 0.30 [F, G1] | 2.50 [F, G1] | Free tier [S, G4] | as above | as above | Very good | Yes |
| **Gemini 3.8 Flash** | 0.75 until 2026-12-31, then 1.50 [F, G1] | 3.75, then 7.50 [F, G1] | - | as above | | Excellent | Yes |
| **OpenAI GPT-6 Luna** ("most efficient, high-volume") | 0.10 (cached 0.01) [F, O1, O2] | 0.50 [F, O1] | No free API tier [A] | **Not used for training by default** (since 2023-03-01). Abuse-monitoring logs up to 30 days. ZDR/MAM by approval [F, O4] | Prohibits sexual content involving or shown to minors and "underaged sexual or violent roleplay"; non-consensual intimate content; **likeness or voice without consent**; licensed-professional advice without a professional (don't market coaching as therapy) [F, O7]. TTS must be disclosed as AI [F, O3]. Policy update effective 2026-11-20 [F, O7] | Very good | Yes |
| **OpenAI GPT-5.6 Luna** / **gpt-5-mini** / **gpt-4.1-mini** | 0.20 / 0.25 / 0.40 | 1.20 / 2.00 / 1.60 | - | as above | as above | Very good | Yes |
| **Anthropic Claude Haiku 5.5** | **0.10** (prompts ≤100K; 0.50 above); cache read 0.01 [F, AN-P] | **0.50** [F, AN-P] | No free API tier [A] | **"Anthropic may not train models on Customer Content"** (Commercial Terms) [F, AN-CT]. API inputs/outputs deleted within 30 days; flagged content kept up to 2 years [S, AN-R] | AUP (effective 2026-11-12): **no sexually explicit content or "erotic chats"**; **consumer-facing chatbots must disclose AI at the start of each session**; products serving minors need extra safeguards; no impersonating humans [F, AN-AUP] | Very good | Yes |
| **Claude Sonnet 5.5** | 2.00 [F, AN-P] | 10.00 [F, AN-P] | - | as above | as above | Excellent | Yes |
| **Claude Haiku 4.5** (older) | 1.00 | 5.00 [F, AN-P] | - | as above | as above | Very good | Yes |
| **Mistral Small 4** | 0.15 [S, MI1] | 0.60 [S, MI1] | "Experiment" free plan [S, MI2] | **Experiment-plan API data may be used for training unless you opt out** (Admin Console > Privacy). Scale plan opted out by default. ZDR available [S, MI2] | Mistral usage policy not checked | Excellent (EU-native) | Yes |
| **Mistral Medium 3.5** | 1.50 [S, MI1] | 7.50 [S, MI1] | - | as above | | Excellent | Yes |

**Cross-provider policy implications for DateWise [A, based on F sources above]:**
- **Age-gate the app at 18+.** ElevenLabs bans apps directed at under-18s without written approval [F, E3], the Gemini API (archived terms) did too [S], and Anthropic and OpenAI add extra minor-safety duties [F].
- **Keep coaching non-explicit.** Anthropic bans erotic chat [F]. OpenAI bans sexual content shown to minors and non-consensual intimate content [F]. Add a refusal style for explicit requests and a safety path for abuse or self-harm disclosures (OpenAI also prohibits self-harm promotion [F]).
- **AI disclosure** at session start in the chat UI and spoken by the avatar.
- **Don't claim credentials.** Present as a "coach", not a therapist or counsellor [F, O7].
- **Consent for likeness and voice.** All the platforms reviewed prohibit clones without consent [F].

### 3.3 Monthly cost at 1,000 and 10,000 MAU

**Workload:**
- 60 messages per user per month, with 1,500 input and 300 output tokens per message.
- Per user: 90,000 input and 18,000 output tokens a month.
- 1,000 MAU: 60,000 messages = **90M input + 18M output tokens**.
- 10,000 MAU: 600,000 messages = **900M input + 180M output tokens**.
- Formula: cost = (input tokens in M x $/M in) + (output tokens in M x $/M out). The 10k column is exactly 10x the 1k column.

| Model | $/M in | $/M out | **1,000 MAU**: 90 x in + 18 x out | **10,000 MAU** |
|---|---|---|---|---|
| CF llama-3.3-70b-instruct-fp8-fast (current) | 0.293 | 2.253 | 90 x 0.293 + 18 x 2.253 = **$66.92** | **$669.24** |
| CF gemma-4-26b-a4b-it | 0.100 | 0.300 | 90 x 0.1 + 18 x 0.3 = **$14.40** | **$144.00** |
| CF glm-4.7-flash | 0.060 | 0.400 | 90 x 0.06 + 18 x 0.4 = **$12.60** | **$126.00** |
| CF gpt-oss-120b | 0.350 | 0.750 | 90 x 0.35 + 18 x 0.75 = **$45.00** | **$450.00** |
| CF gpt-oss-20b | 0.200 | 0.300 | 90 x 0.2 + 18 x 0.3 = **$23.40** | **$234.00** |
| CF mistral-small-3.1-24b | 0.351 | 0.555 | 90 x 0.351 + 18 x 0.555 = **$41.58** | **$415.80** |
| CF llama-4-scout-17b | 0.270 | 0.850 | 90 x 0.27 + 18 x 0.85 = **$39.60** | **$396.00** |
| CF qwen3.8-27b | 0.450 | 3.200 | 90 x 0.45 + 18 x 3.2 = **$98.10** | **$981.00** |
| Groq gpt-oss-120b (UNVERIFIED price) | 0.15 | 0.60 | 90 x 0.15 + 18 x 0.6 = **$24.30** | **$243.00** |
| Groq qwen3-32b (UNVERIFIED) | 0.29 | 0.59 | 90 x 0.29 + 18 x 0.59 = **$36.72** | **$367.20** |
| Groq llama-3.3-70b (UNVERIFIED) | 0.59 | 0.79 | 90 x 0.59 + 18 x 0.79 = **$67.32** | **$673.20** |
| Gemini 3.1 Flash-Lite (paid) | 0.25 | 1.50 | 90 x 0.25 + 18 x 1.5 = **$49.50** | **$495.00** |
| Gemini 3.5 Flash-Lite (paid) | 0.30 | 2.50 | 90 x 0.3 + 18 x 2.5 = **$72.00** | **$720.00** |
| Gemini 3.8 Flash (promo to 2026-12-31) | 0.75 | 3.75 | 90 x 0.75 + 18 x 3.75 = **$135.00** | **$1,350.00** |
| Gemini 3.8 Flash (from 2027-01-01) | 1.50 | 7.50 | 90 x 1.5 + 18 x 7.5 = **$270.00** | **$2,700.00** |
| **OpenAI GPT-6 Luna** | 0.10 | 0.50 | 90 x 0.1 + 18 x 0.5 = **$18.00** | **$180.00** |
| OpenAI GPT-5.6 Luna | 0.20 | 1.20 | 90 x 0.2 + 18 x 1.2 = **$39.60** | **$396.00** |
| OpenAI gpt-5-mini | 0.25 | 2.00 | 90 x 0.25 + 18 x 2 = **$58.50** | **$585.00** |
| OpenAI gpt-4.1-mini | 0.40 | 1.60 | 90 x 0.4 + 18 x 1.6 = **$64.80** | **$648.00** |
| OpenAI gpt-5.4-mini | 0.75 | 4.50 | 90 x 0.75 + 18 x 4.5 = **$148.50** | **$1,485.00** |
| OpenAI GPT-6.1 Terra | 1.00 | 5.00 | 90 x 1 + 18 x 5 = **$180.00** | **$1,800.00** |
| **Claude Haiku 5.5** | 0.10 | 0.50 | 90 x 0.1 + 18 x 0.5 = **$18.00** | **$180.00** |
| Claude Haiku 4.5 | 1.00 | 5.00 | 90 x 1 + 18 x 5 = **$180.00** | **$1,800.00** |
| Claude Sonnet 5.5 | 2.00 | 10.00 | 90 x 2 + 18 x 10 = **$360.00** | **$3,600.00** |
| Mistral Small 4 (UNVERIFIED) | 0.15 | 0.60 | 90 x 0.15 + 18 x 0.6 = **$24.30** | **$243.00** |
| Mistral Medium 3.5 (UNVERIFIED) | 1.50 | 7.50 | 90 x 1.5 + 18 x 7.5 = **$270.00** | **$2,700.00** |

**Adjustments [A]:**
- **Workers AI free allowance:** 10k neurons/day x 30 = 300k neurons = **$3.30/month off**. Add the **$5/month Workers Paid minimum** [F, C1, C6].
- **Free-only capacity:** on llama-3.3-70b the free allowance carries only about 98 messages/day, i.e. about 49 users at 60 messages a month. On gemma-4-26b it carries about 458 messages/day, about 229 users.
- **Prompt caching** (most of the 1,500 input tokens is a stable system prompt plus history) cuts input cost sharply on Claude (cache read $0.01/M on Haiku 5.5 [F, AN-P]) and OpenAI (GPT-6 Luna cached input $0.01/M [F, O1]). With 70% cache hits, Haiku 5.5 or GPT-6 Luna at 1k MAU drops from $18.00 to about **$12.33** (90 x 0.3 x 0.10 + 90 x 0.7 x 0.01 + 18 x 0.50 = 2.70 + 0.63 + 9.00 = $12.33, before cache-write premiums). That is an approximation.
- **Reasoning models** (gpt-oss, some GPT/Gemini/Claude settings) emit hidden reasoning tokens billed as output. Measure real output tokens, keep effort or reasoning low for chat, and cap `max_tokens`.

### 3.4 Recommendations: models

1. **Free baseline (now):** stay on Workers AI and the existing Worker. A/B test **`gemma-4-26b-a4b-it`** against the current **`llama-3.3-70b-instruct-fp8-fast`** on a 50-prompt bilingual (EN/ES) coaching eval. Gemma 4 is about 4.6x cheaper per message, has a 256K context (Llama on Workers AI has only 24K), and is Cloudflare's own recommended replacement [F, C3/C4].
   - **Cost:** $14.40/mo at 1k MAU, $144 at 10k MAU, plus $5 for the plan.
   - **Data protection:** strongest of all options. No training, zero retention [F, C5].
   - **Keep as fallbacks:** `glm-4.7-flash` and `mistral-small-3.1-24b`.
   - **Use Groq's free tier only for developer testing.** Its 1K RPD / 200K TPD cap is too small for users [S].
2. **Paid upgrade candidate #1: Claude Haiku 5.5.** $0.10 / $0.50 per MTok, ≈ $18 / $180 a month at 1k / 10k MAU before caching [F]. It has a contractual no-training term [F] and 30-day API retention [S]. Its AUP explicitly covers consumer-chatbot disclosure (aligns with the coaching UX). Use Sonnet 5.5 ($360 / $3,600) only for premium "deep-dive" sessions.
3. **Paid upgrade candidate #2: OpenAI GPT-6 Luna.** Same price as Haiku 5.5 [F]. No training by default, 30-day abuse logs [F]. A natural fit if you adopt OpenAI GPT-Live for voice.
4. **Do not use** the Gemini free tier for real user conversations: unpaid content may be used for product improvement or human review [S]. The Mistral Experiment plan is the same unless you opt out [S]. Paid Gemini Flash-Lite ($49.50 / $495) is a reasonable third candidate if Spanish eval scores favour it.
5. **Reuse check (per AGENTS.md):** this plan reuses the existing Worker, Workers AI binding, SSE streaming and deprecation tests. Avatar vendors are integrated, not built. The only new component is a LiveKit agent host or a vendor-hosted pipeline.

---

## 4. Proposed architecture (summary) [A]

```
Flutter app (mobile + web)
  ├─ text chat ──SSE──> Cloudflare Worker ──> Workers AI LLM (gemma-4 / llama-3.3) | paid: Claude Haiku 5.5 or GPT-6 Luna
  └─ video coach ─WebRTC (livekit_client)──> LiveKit room
                         ├─ avatar participant: LiveAvatar LITE (or Simli / Tavus via plugin)
                         └─ agent (LiveKit Agents, Python/Node, small VM or LiveKit Cloud):
                              STT  : Workers AI nova-3 (or ElevenLabs Scribe)
                              LLM  : calls the same Cloudflare Worker (OpenAI-compatible endpoint)
                              TTS  : Workers AI aura-2-en / aura-2-es (or ElevenLabs Flash)
Session tokens are minted by the Worker; no vendor API key ships in the app.
```

---

## 5. Next steps (no spend required) [A]

1. Allow the blocked hosts listed in section 0 and re-verify every [S]/[T] price.
2. Build the LiveAvatar Sandbox + LiveKit Flutter proof of concept (free).
3. Write a 50-prompt EN/ES coaching eval (rubric: empathy, safety, cultural fit, Spanish naturalness). Run it on Workers AI gemma-4 and llama-3.3 (free).
4. Draft the talent release with counsel before contacting any actors.
5. Get owner authorization before any paid plan (per AGENTS.md).

---

## 6. UNVERIFIED items (not confirmed from a primary source this session)

**Avatar platforms**
1. **Tavus:**
   - Free plan minutes: 20/month, with a 5-minute conversation cap. Older pages said 25.
   - Plan prices: Starter $22, Builder $59, Growth $397, Business $975.
   - Included minutes and overage rates: $0.35, $0.31 and $0.26 per minute. Also seen: $0.37 and $0.32.
   - Billing in 6-second increments.
   - Conversation-log retention of 90 days (it is unclear whether this covers the API product).
   - Sources: tracker sites and a search snippet of tavus.io/pricing.
2. **HeyGen LiveAvatar:** the custom-avatar consent recording requirement, the biometric notice details and ZDR terms (search snippets of heygen.com and developers.heygen.com).
3. **D-ID:** all prices (trial, Build, Launch, Scale), latency, consent and retention claims.
4. **Simli:** all prices ($0.05/min, $10 credit, 50 free minutes), <300 ms latency, training on user content, and the 18+ rule.
5. **Anam:**
   - Free plan (30 min/month, 3-minute sessions) and the "$0.04/min" floor.
   - Third-party Starter prices and overage.
   - Latency figures (180 ms, 150 ms, 1.24 s), 70+ languages, and the SDK list.
6. **Synthesia Interactive:** $0.10/min avatar-only, and $0.20/min full stack ("coming soon").
7. **Akool:** 1-1.2 credits per 10 s; the price per credit is unknown; API plan prices.
8. **LiveKit Cloud:** Build plan (1,000 free agent minutes, 5 concurrent), and the $0.01/min overage on Ship and Scale.
9. **NVIDIA:** commercial-use status of the Audio2Face-3D NIM container, and any ACE pricing.

**Open-source licenses**

10. **Wav2Lip:** commercial-use status (the repo has no license file).
11. **XTTS-v2:** the weights are under the CPML and non-commercial. Hugging Face was not reachable.
12. **MuseTalk:** licenses of the dependent weights.

**Voice providers**

13. **Cartesia:** free credits, Pro price, $ per credit, latency and the license terms.
14. **Azure Speech:**
    - The neural price per 1M characters (shown as $15-16 by third parties).
    - Free-tier conflict: 0.5M neural characters versus 5M standard.
    - The Custom Neural Voice Limited Access and consent-statement details.
    - The es-MX/es-ES voice catalogue.
15. **Deepgram:** the direct Aura-2 price ($0.030 per 1k characters) and any signup credit. The Workers AI price is verified.
16. **Google Cloud TTS:** the Chirp 3 HD es-US/es-ES voice availability (the docs host was blocked).

**LLM providers**

17. **Groq:**
    - All per-token prices.
    - The free-tier limits (search snippet of console.groq.com).
    - The ZDR toggle, the 30-day default logs, the no-training commitment, the AUP, and whether Llama 3.3 70B is now Enterprise-only.
18. **Gemini API:**
    - Free-tier existence and rate limits.
    - Unpaid-tier data use and human review, and the "paid" definition.
    - The 18+ and minors-directed clauses, which are in archived terms; the current status is unconfirmed.
    - Vertex prices were verified from cloud.google.com. The ai.google.dev Developer API prices are assumed to match.
19. **Anthropic:** API retention of 30 days, and the 2-year retention for flagged content (search of privacy.claude.com). The no-training term and AUP are verified.
20. **Mistral:** Small 4 at $0.15/$0.60 and Medium 3.5 at $1.50/$7.50. Experiment-plan training and opt-out. The usage policy.

**General claims**

21. Streaming support for each LLM provider. This is generally documented, but I re-checked it only for Workers AI (already in use) and OpenAI GPT-Live.
22. EU AI Act Art. 50 transparency obligations applying to DateWise.
23. Every Spanish-quality judgement in the tables. These are [A] assessments and must be confirmed with a bilingual eval.
24. Whether LiveKit Agents can be hosted on LiveKit Cloud (versus self-hosting).

---

## 7. Sources (all accessed 2026-11-22)

| ID | Source | URL | Evidence |
|---|---|---|---|
| C1 | Workers AI pricing (updated 2026-11-18) | https://developers.cloudflare.com/workers-ai/platform/pricing/ | F |
| C2 | Workers AI limits | https://developers.cloudflare.com/workers-ai/platform/limits/ | F |
| C3 | Workers AI deprecations: 2026-11-05 post (effective 2026-11-20) and 2026-05-08 post | https://developers.cloudflare.com/changelog/post/2026-11-05-planned-model-deprecations/ ; https://developers.cloudflare.com/changelog/post/2026-05-08-planned-model-deprecations/ ; https://developers.cloudflare.com/workers-ai/changelog/ | F |
| C4 | Workers AI model pages (llama-3.3-70b-instruct-fp8-fast, gemma-4-26b-a4b-it, gpt-oss-120b, aura-2-es, aura-2-en, melotts, qwen3-30b-a3b-fp8, etc.) | https://developers.cloudflare.com/workers-ai/models/ | F |
| C5 | Workers AI data usage (updated 2026-10-16) | https://developers.cloudflare.com/workers-ai/platform/data-usage/ | F |
| C6 | Workers pricing ($5/mo Paid minimum) | https://developers.cloudflare.com/workers/platform/pricing/ | F |
| V1 | Tavus pricing (trackers and snippet) | https://tavus.io/pricing ; https://www.activepieces.com/blog/tavus-pricing-plans-per-minute-rates-2026-guide ; https://usagepricing.com/blueprint/tavus | S/T |
| V2 | Tavus Face FAQs | https://docs.tavus.io/sections/faces/face-faqs.md | F |
| V3 | Tavus Mobile (Daily Flutter SDK) | https://docs.tavus.io/sections/conversational-video-interface/mobile.md | F |
| V4 | Tavus LLM layer (custom OpenAI-compatible LLM) | https://docs.tavus.io/sections/conversational-video-interface/pal/llm.md | F |
| V5 | Tavus CVI overview | https://docs.tavus.io/sections/conversational-video-interface/overview-cvi.md | F |
| V6 | Tavus docs index (embed, image-to-face, delete endpoints, ZDR) | https://docs.tavus.io/llms.txt | F |
| V7 | Tavus Stock Faces | https://docs.tavus.io/sections/faces/stock-faces.md | F |
| V8 | Tavus privacy policy | https://www.tavus.io/privacy-policy | S |
| V9 | Tavus Language Support | https://docs.tavus.io/sections/conversational-video-interface/language-support.md | F |
| H1 | HeyGen API pricing help article | https://help.heygen.com/en/articles/10060327-heygen-api-liveavatar-pricing-subscriptions-explained | F |
| H2 | LiveAvatar Credits and Subscriptions; Sandbox Mode | https://docs.liveavatar.com/docs/faq/credits.md ; https://docs.liveavatar.com/docs/sandbox-mode.md | F |
| H3 | LiveAvatar docs index (modes, plugins, connectors, custom LLM/TTS) | https://docs.liveavatar.com/llms.txt | F |
| H4 | HeyGen avatar consent, biometric notice, compliance | https://developers.heygen.com/docs/avatar-consent ; https://www.heygen.com/biometric-privacy-notice ; https://developers.heygen.com/docs/compliance.md | S |
| D1 | D-ID pricing (third parties) | https://www.d-id.com/pricing ; https://www.activepieces.com/blog/d-id-pricing-2026-every-plan-cost-and-limit | T |
| D2 | D-ID latency and consent | https://www.computerweekly.com/blog/CW-Developer-Network/Inside-D-IDs-real-time-AI-avatar-technology ; https://www.d-id.com/ | S |
| D3 | D-ID Biometric Privacy Policy 2025 | https://d-id.com/wp-content/uploads/2024/12/D-ID-Biometric-Privacy-Policy-2025.pdf | S |
| SI1 | Simli pricing (directories) | https://www.itechguides.com/products/simli/ ; https://o-mega.ai/agents/simli | T |
| SI2 | Simli latency and Trinity | https://docs.pipecat.ai/api-reference/server/services/video/simli ; https://justcall.io/ai-agent-directory/simli/ | S/T |
| AN1 | Anam pricing | https://anam.ai/pricing | S |
| AN2 | Anam latency | https://anam.ai/compare ; https://anam.ai/resources/glossary/sub-second-latency | S |
| SY1 | Synthesia API pricing | https://www.synthesia.io/api-pricing | S |
| AK1 | Akool API pricing | https://www.akool.com/api-pricing | S |
| LK1 | LiveKit pricing | https://livekit.com/pricing ; https://docs.livekit.io/home/cloud/pricing/ | S |
| L1 | livekit/agents repo (Apache-2.0; plugin list and READMEs) | https://github.com/livekit/agents | F |
| L2 | pipecat-ai/pipecat repo (BSD-2; services incl. heygen, simli, tavus, piper, xtts) | https://github.com/pipecat-ai/pipecat | F |
| P1 | pub.dev package API: daily_flutter, livekit_client, livekit_components, flutter_webrtc, simli_client, elevenlabs_flutter | https://pub.dev/api/packages/daily_flutter (etc.) | F |
| N1 | NVIDIA Audio2Face-3D repo README (license table) | https://github.com/NVIDIA/Audio2Face-3D | F |
| OS1 | MuseTalk LICENSE and README | https://github.com/TMElyralab/MuseTalk | F |
| OS2 | LivePortrait LICENSE (InsightFace note) | https://github.com/KwaiVGI/LivePortrait | F |
| OS3 | SadTalker LICENSE and README | https://github.com/OpenTalker/SadTalker | F |
| OS4 | Wav2Lip README (no license file) | https://github.com/Rudrabha/Wav2Lip | F |
| OS5 | Hallo / Hallo2 LICENSE and README (CodeFormer S-Lab) | https://github.com/fudan-generative-vision/hallo2 | F |
| OS6 | Piper: OHF-Voice/piper1-gpl (GPL-3.0) and rhasspy/piper (MIT) | https://github.com/OHF-Voice/piper1-gpl ; https://github.com/rhasspy/piper | F |
| OS7 | Coqui TTS (MPL-2.0), idiap fork README | https://github.com/coqui-ai/TTS ; https://github.com/idiap/coqui-ai-TTS | F |
| OS8 | XTTS-v2 CPML status | https://huggingface.co/coqui/XTTS-v2 ; https://localaimaster.com/blog/xtts-coqui-commercial-license | T |
| E1 | ElevenLabs API pricing | https://elevenlabs.io/pricing/api | F |
| E2 | ElevenLabs plans | https://elevenlabs.io/pricing | F |
| E3 | ElevenLabs Prohibited Use Policy | https://elevenlabs.io/use-policy | F |
| E4 | ElevenLabs Terms of Use | https://elevenlabs.io/terms-of-use | F |
| E5 | ElevenLabs Agents pricing | https://elevenlabs.io/pricing/agents | F |
| E6 | ElevenLabs Agents privacy and retention | https://elevenlabs.io/docs/eleven-agents/customization/privacy.md | F |
| CA1 | Cartesia pricing | https://cartesia.ai/pricing ; https://www.cloudtalk.io/blog/cartesia-pricing/ | S/T |
| CA2 | Cartesia latency and license | https://cartesia.ai/sonic ; https://humannessindex.vapi.ai/models/cartesia-sonic-3-5 ; https://cartesia.ai/legal/acceptable-use | S/T |
| AZ1 | Azure Speech pricing | https://azure.microsoft.com/en-us/pricing/details/speech/ | S |
| DG1 | Deepgram pricing | https://www.deepgram.com/pricing | S |
| G1 | Vertex AI generative AI pricing (Gemini) | https://cloud.google.com/vertex-ai/generative-ai/pricing | F |
| G2 | Gemini API Additional Terms (current and archived) | https://ai.google.dev/gemini-api/terms ; https://ai.google.dev/gemini-api/terms-archive/terms_05_14_24 | S |
| G3 | Google Cloud Text-to-Speech pricing | https://cloud.google.com/text-to-speech/pricing | F |
| G4 | Gemini API pricing | https://ai.google.dev/gemini-api/docs/pricing | S |
| GQ1 | Groq rate limits | https://console.groq.com/docs/rate-limits | S |
| GQ2 | Groq Your Data | https://console.groq.com/docs/your-data | S |
| GQ3 | Groq pricing (third parties) | https://groq.com/pricing ; https://www.morphllm.com/groq-pricing | T |
| O1 | OpenAI API pricing | https://developers.openai.com/api/docs/pricing | F |
| O2 | OpenAI models | https://developers.openai.com/api/docs/models | F |
| O3 | OpenAI Text-to-speech guide | https://developers.openai.com/api/docs/guides/text-to-speech | F |
| O4 | OpenAI Your data | https://developers.openai.com/api/docs/guides/your-data | F |
| O5 | OpenAI Custom voices | https://developers.openai.com/api/docs/guides/custom-voices | F |
| O6 | OpenAI GPT-Live sessions | https://developers.openai.com/api/docs/guides/live-conversations | F |
| O7 | OpenAI Usage Policies (update effective 2026-11-20) | https://openai.com/policies/usage-policies/ | F |
| AN-P | Anthropic pricing | https://platform.claude.com/docs/en/about-claude/pricing | F |
| AN-CT | Anthropic Commercial Terms | https://www.anthropic.com/legal/commercial-terms | F |
| AN-AUP | Anthropic Usage Policy (effective 2026-11-12) | https://www.anthropic.com/legal/aup | F |
| AN-R | Anthropic API data retention | https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data | S |
| MI1 | Mistral API pricing | https://mistral.ai/pricing ; https://docs.mistral.ai/models/pricing | S (mistral.ai fetched, but the per-model table is JS-rendered) |
| MI2 | Mistral training opt-out (Experiment plan) | https://help.mistral.ai/en/articles/455207-can-i-opt-out-of-my-input-or-output-data-being-used-for-training | S |
