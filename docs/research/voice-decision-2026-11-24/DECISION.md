# NATURAL VOICE DECISION: DateWise AI (2026-11-24)

## One-page summary
**Verdict.** Replace system TTS with a hosted neural voice for the paid experience, keep the system voice as the free fallback. System-voice tuning alone will not reach "premium": it can fix "too fast" and pauses, but the "robotic" quality is the voice model itself, and Apple gives apps no way to fetch Premium/Enhanced voices or the Siri voices (judgment from the sources in COMPARISON.md section 1; I have not heard build 203).

**Ranked recommendation**
1. **Cloudflare Workers AI Aura-2 (Deepgram model) on the Worker's existing `env.AI` binding.** No new vendor, account or secret; the same StoreKit-gated Worker; Cloudflare's model page states zero data retention; Deepgram labels six voices Mexican (the Workers AI list exposes sirio, javier and estrella; aquila and selena are "Latin American"). $0.027 per minute of speech. Weakness: no pace/SSML control in the Workers AI schema (control by sentence chunking and player rate) and no independent naturalness benchmark found, so a listening test must confirm it.
2. **Azure Neural (es-MX Dalia/Jorge; en-US Jenny/Guy/Aria/Davis/Jason) and Neural HD (es-MX Ximena/Tristan; MAI Valeria/Alejo).** Real es-MX locale, full SSML pace/pause/style control, free 0.5M characters/month, $0.0135/min Neural, $0.0198/min HD, no text retention for real-time synthesis (Microsoft doc). Costs a new Azure account and secret. Choose it if Aura-2 fails the ear test or pace control proves necessary.
3. **ElevenLabs Flash v2.5 / Multilingual v2 (or Cartesia Sonic)** for the highest-reputation naturalness: $0.036/min (Flash) to $0.072/min (Multilingual v2), Free plan not commercial, Mexican accent not verified. Premium upsell only, with a smaller minutes cap.
Not recommended for v1: Kokoro and Chatterbox self-hosted (Spanish has no documented Mexican voice, one female and two male, flat questions; Kokoro is about 100-150 arena Elo below commercial leaders; Chatterbox needs a GPU; you run the servers). Google Chirp 3 HD has no es-MX. Polly Neural (Mia/Andres) is a cheap, safe es-MX alternative at $0.0144/min but older-sounding. OpenAI cannot select a Mexican accent.

**Cheapest next step ($0, no new account).** Run the listening test: synthesise the English and 6 Mexican-marker sentences (COMPARISON.md section 4) with Aura-2 voices through the owner's existing Cloudflare account (about 2,700 neurons, inside one free daily allowance), and have a native Mexican listener plus the owner compare them with build 203. I made no call to any hosted service (credentials not available here).

**Owner approvals/decisions needed**
- A: Approve the listening test (uses the existing Cloudflare account; or supply a token).
- B: Approve Workers Paid ($5/month) and raising `DAILY_NEURON_BUDGET` for voice (voice = about 2,455 neurons per minute; the free 10,000/day is about 4 minutes a day for everyone).
- C: Decide native-code exception: AGENTS.md forbids new native-only features in the Flutter app; the plan plays audio and computes lip-sync levels in Dart (no Swift) instead. Confirm.
- D: Included-minutes policy and the AI-voice consent wording (below).
- E: Only if Azure/ElevenLabs is chosen: a new account and billing.

**Policy.** Include 60 minutes of natural voice per subscriber per month (about 2 minutes a day), counted in characters (54,000) in the Worker; after that, or offline, or on any error, the coach speaks with the system voice at no cost. 60 minutes with Aura-2 costs $1.62 and fits a $4 total AI budget even with the $1.50 avatar placeholder ($3.44). Do not go to 120 minutes unless the avatar is $0 (3.56) or the voice is Azure Neural ($0.0135/min: 3.44 with avatar).

**Cost per subscriber per month (voice only; net revenue after Apple 15% / 30% and voice; fits $4-5 total AI with text $0.32 and avatar $0 / $1.50)**
| Minutes | Aura-2 voice | Left after Apple+voice (15% / 30%) | Total AI avatar $0 / $1.50 | Azure Neural voice | Total AI (Azure) $0 / $1.50 | ElevenLabs Flash voice | Total AI (Flash) $0 / $1.50 |
|---|---|---|---|---|---|---|---|
| 15 | $0.40 | $16.59 / $13.59 | 0.72 / 2.23 fits | $0.20 | 0.52 / 2.02 fits | $0.54 | 0.86 / 2.36 fits |
| 30 | $0.81 | $16.18 / $13.18 | 1.13 / 2.63 fits | $0.40 | 0.72 / 2.23 fits | $1.08 | 1.40 / 2.90 fits |
| 60 | $1.62 | $15.37 / $12.37 | 1.94 / 3.44 fits $4 | $0.81 | 1.13 / 2.63 fits | $2.16 | 2.48 / 3.98 fits $4 |
| 120 | $3.24 | $13.75 / $10.75 | 3.56 / 5.06: fits only with avatar $0 | $1.62 | 1.94 / 3.44 fits | $4.32 | 4.64 / 6.14 over $4; $5 only at avatar $0 |
| 300 | $8.10 | $8.89 / $5.89 | 8.86 / 10.36 over | $4.05 | 4.81 / 6.31: $5 only at avatar $0 | $10.80 | 11.56 / 13.06 over |
Full table for all options: COSTS.md, costs.py, costs.json. Fixed fees: Workers Paid $5/month; Azure F0 free 0.5M chars (about 555 min, shared); ElevenLabs commercial use needs at least Starter $6/month; self-hosting floors $40 (CPU) / $248 (GPU).

**Measured here (free).** Kokoro-82M on this CPU: 0.73 CPU-seconds per audio-second per vCPU (conservative, host loaded); 1-thread wall RTF 1.0 to 1.3, first sentence about 2 s, so not interactive-grade on a small CPU box. 9 sample clips for Ava/Ethan (EN) and Sofia/Diego (ES) are in `samples/`. Accent: not claimed; Mexican accent can only be confirmed by a native listener (sentences in COMPARISON.md section 4).

**Files:** COMPARISON.md (matrix and sources), COSTS.md / costs.py / costs.json, INTEGRATION_PLAN.md (about 7.5 days), samples/.
Reuse check: reuses the Worker's `env.AI` binding, `admit()`/StoreKit JWS gate, `UsageGuard`, the existing `AudioAlignment` levels lip-sync, and `DeviceVoiceService` as fallback; nothing duplicated.
