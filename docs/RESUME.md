# RESUME (updated 2026-11-25) — handoff for the next AI

This replaces the 2026-11-24 handoff. Older notes that conflict with this file are superseded.

Owner rules: AGENTS.md. $0 spend unless the owner approves. No App Store review submission. No main merge without owner approval
(except the merges the owner has explicitly approved, listed below). No secrets in chat or logs.

## Owner decisions (2026-11-25)
- Build our OWN avatar system. Do NOT buy Anam, Simli, HeyGen, D-ID or any other hosted avatar service. Earlier notes that
  recommended Anam are superseded.
- Reuse the existing prototype assets before starting over: docs/research/avatar-tech-2026-11-24/ (IMTalker CPU test),
  docs/avatar/TALKING_AVATARS.md, tool/avatar/ (gen_frames.py, lp_engine.py, verify.py), and the candidate mp4s in docs/review/.
  The frame-based engine stays as a fallback only.
- Commercially licensed components only. Replace anything that cannot be used commercially.
- GPU: this sandbox has no GPU (4 CPU, 15 GB). Live avatars need a GPU; offline clip rendering works on CPU. Do not call the GPU a
  blocker until a GPU source has been checked. Any paid GPU needs owner approval (spend).
- Merge order, after required checks and independent review: PR #57 (deploy health-check retry), then PR #54 (overnight fixes).
- TestFlight upload is approved. Signing has been verified (see below). Do not submit for App Review.

## Verified facts
- Signing works: iOS build run 45526534614 (2026-11-25 01:32) passed "Check signing secrets", API signing, and
  "Upload to App Store Connect (TestFlight)". Do not ask the owner for signing credentials again.
- PR #57 checks are green (test, staging-dry-run, worker, unsigned build). PR #54 head be7c04e: iOS build and StoreKit E2E green;
  backend suite 143/143 on that commit.
- Avatar licences (from docs/research/avatar-tech-2026-11-24/imtalker-cpu/REPORT.md): IMTalker code Apache-2.0, weights MIT,
  wav2vec2 Apache-2.0, MediaPipe Apache-2.0. Face detector: the CPU run (docs/research/avatar-tech-2026-11-24/imtalker-cpu/tools/run_cpu.py) stubs out
  face_alignment, so the S3FD/FAN weights never load; cropping uses MediaPipe FaceLandmarker (Apache-2.0 package). Still to
  confirm: the licence of the FaceLandmarker model file itself. Training data for the MIT weights is unnamed: record as a residual risk.
- IMTalker on CPU: 50-90 s to render one second of video. Best lip closure of the three free options tested (Ditto, MuseTalk,
  IMTalker). Offline clips only until a GPU exists.
- Voices: Piper (current repo GPL-3.0, older MIT release), Coqui XTTS-v2 (non-commercial weights, do not use), Cartesia (free tier not
  licensed for commercial use). Pick a commercially licensed voice route and record the licence per voice.

## Voice test results (2026-11-25, measured on this sandbox CPU: 4 vCPU, no GPU)
- Engine: Kokoro-82M v1.0 via kokoro-onnx 0.6.1 (MIT). Weights Apache-2.0 (model card). Phonemizer espeakng-loader bundles
  libespeak-ng (GPL-3.0): fine server-side; shipping it in the app needs legal review. Install with prebuilt wheels only.
- English voice af_heart: 0.75-0.80x real time for batch rendering. Short sentence: about 1.5 s to first audio.
- Spanish voices ef_dora and em_alex: 0.69-0.72x real time. Short sentence: about 1.2 s to first audio.
- Speaking speed: speed 0.9 gives 6.7 s of audio for the Spanish test sentence, 1.0 gives 6.3 s.
- NOT verified by ear: naturalness and Spanish pronunciation need a listening review by the owner before any choice.
- Live use: render sentence by sentence (about 1.2-1.5 s of latency per sentence, with the next sentence rendered while the first plays).

## Open items (in order)
1. Merge PR #57, then PR #54, once required checks pass and the independent reviews approve.
2. App Store subscription metadata: check `datewise_premium_monthly` through the App Store Connect API using the existing key
   secrets (read-only), and list exactly which fields are missing. Do not ask the owner to repeat steps already done.
3. Avatar: confirm the FaceLandmarker model-file licence, then render the four coach clips on CPU, check them against the approved
   portraits, and wire them into the existing clip player.
4. Voice: Kokoro (MIT engine, Apache-2.0 weights) is the leading route. Owner listening review of the ef_dora and em_alex samples, then a licence check of each voice's model card before use.
5. Device checks still needed: purchase, restore, renew, cancel, refund; Spanish chat; voice pace; lip sync; keyboard behaviour.
