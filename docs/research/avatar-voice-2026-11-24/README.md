# Avatar and voice research (2026-11-24) — paused

Owner rejected the frame-based talking portraits (robotic voice, fast mouth, unnatural blinks and expressions).
Research into replacements ran on 2026-11-24 and is **paused** by the owner: one problem at a time, starting with
a new photorealistic look for Ava, then her voice, then animation. Nothing here is integrated into the app, and
nothing was purchased. Facts below are from vendor pages as read on 2026-11-24; verify prices and terms before use.

## Contents
- `script.json`: the first short comparison script (one line per coach).
- `dialogue.json`: the 34–37 s comparison dialogue per coach (user turn, coach answer, user turn, coach advice).
  Coach-only tracks drive the face, so each clip also shows listening.
- `samples/`: voices made so far, all free and commercially licensed engines run locally on CPU:
  Kokoro-82M (Apache-2.0) for all four coaches (`kokoro-*.mp3`, `kokoro-*-mix.mp3` = full dialogue);
  Chatterbox Multilingual (MIT, with Resemble's Perth watermark) for Ava (`chatterbox-ava.mp3`).
- `run_space.py`: calls free Hugging Face Spaces (image + audio -> video). The anonymous ZeroGPU quota was
  exhausted on the first call, so no avatar video was produced.

## Commercial real-time avatars (summary)
| Vendor | Price per streaming minute (cheapest plan) | Notes |
|---|---|---|
| Simli | ~$0.009–0.01 (Hobby $10 / 1,000 min) | Takes our own TTS audio (PCM16); face from a photo on paid plans; legal/privacy docs not found |
| HeyGen LiveAvatar | $0.10 LITE / $0.20 FULL (Essential $99/mo) | Photo avatar; LITE = bring your own LLM/TTS; opt out of training |
| Anam (Cara-4) | $0.11–0.16 (enterprise from $0.04) | Own image on all plans; no training on content; DPA, SOC 2 |
| Tavus CVI | $0.26–0.35 | Strong realism and turn-taking; too costly for a $19.99 plan |
| bitHuman | $0.02 on-device / $0.04 cloud | Portrait-built; worth testing |
| D-ID V4 | unverified, higher tiers | Photo avatars; real-time V4 on higher plans |
| Azure TTS avatar | not published | Custom photo avatar is limited access |

All are WebRTC; LiveKit/Daily have native Swift SDKs. Every vendor loses money on a heavy user (150 replies/day);
avatar video needs a monthly cap (about 60–120 min) with voice/text after that.

## Open source (summary)
- Best licence-safe candidates: SoulX-FlashHead (Apache, 2026, photo + audio, real-time on one 4090),
  MuseTalk 1.5 via LiveTalking (MIT/Apache; mouth-only, needs a base video; check LiveTalking's watermark clause),
  EchoMimicV3-Flash (Apache, 12 GB, offline), Ditto (Apache code; replace the InsightFace detector).
- LivePortrait/JoyVASA, Hallo2 and KDTalker depend on InsightFace models (non-commercial) — replace before use.
  Sonic, FLOAT and KDTalker weights are non-commercial. SadTalker is Apache but visibly dated.
- Combining works best: a motion model for blinks/gaze/head (EchoMimicV3, FlashHead, Ditto or LivePortrait with a
  replaced detector) plus a lip model driven by the speech (MuseTalk, LatentSync), streamed over WebRTC.
- Needs GPU hosting; real-time options cost roughly $0.002–0.007 per streamed minute on a rented 4090.

## Voices (summary)
- ElevenLabs Flash v2.5 (~$0.036/min, best reputation, character timestamps; free tier not commercial).
- Cartesia Sonic 3.6 (~$0.035/min, word + phoneme timestamps for lip sync, commercial from $5).
- Deepgram Aura-2 (~$0.027/min, six Mexican Spanish voices; also on Cloudflare Workers AI, which the backend uses).
- Azure Neural (~$0.0135/min; es-MX Dalia/Jorge; visemes on standard voices).
- Hume and PlayHT have shut down. Open source: Kokoro (Apache), Chatterbox (MIT); XTTS-v2 and F5-TTS are
  non-commercial.

## Next (owner's order)
1. Ava's appearance (photorealistic candidates) — in progress.
2. Ava's voice.
3. Realistic animation (needs free GPU time, e.g. a Kaggle account, when the owner is ready).
