# Paid real-time avatar providers: free-tier bake-off plan

**Status:** a plan only. Nothing has been signed up for, no keys exist, and
no conversation or audio has been sent to any vendor. Every step marked
**OWNER** needs the owner's explicit approval first.

**Why consider paid providers at all:** the on-device avatar
(`docs/avatar/TALKING_AVATARS.md`) composites a fixed set of photo patches.
Real-time neural video adds natural head motion, every mouth shape and
expressive eyes, but it costs money per minute and a vendor receives at least
the coach's reply audio.

**Sources:** prices and terms come from the research doc
`AVATAR_REQUIREMENTS_AND_OPTIONS.md` (2026-11-22/23) and its sources. Tags:
**[F]** = fetched from the vendor's own page; **[S]** = seen only in a search
snippet; **[T]** = third party only. **[S] and [T] are UNVERIFIED** (the
vendor sites were blocked from the research session). Re-check every price on
the live page before any money is committed.

## 1. Candidates

| | Simli | Anam | HeyGen LiveAvatar (optional) | Tavus CVI (optional) |
|---|---|---|---|---|
| **Free tier** | reported $10 signup credit + 50 min/month [T] | 30 min/month, 3-min sessions, no card [S] | Sandbox: free, unlimited ~1-min sessions, one stock avatar only [F]; 10 credits/month [F] | 20 min/month, 5-min cap per conversation [T] |
| **Published price** | ~$0.05/min pay-as-you-go [T] | "from $0.04/min" at volume, per-second billing [S]; third parties: overage $0.11–0.18/min [T] | LITE (video only) 1 credit/min; FULL 2 credits/min; Essential $99/mo = 1,100+10 credits, overage $0.095; Business $475/mo = 6,000+10 credits, overage $0.09 [F] (newer snippets conflict [S]) | Starter $22 (60 min); Builder $59 (175 min, +$0.35/min); Growth $397 (1,300 min, +$0.31); Business $975 (4,000 min, +$0.26) [T] |
| **$/session-minute** | ~$0.05 | $0.04 (floor) – $0.18 | LITE ≈ $0.09–0.13 | $0.26–0.37 |
| **Custom face from our still portraits** | yes, image faces [S] | yes, custom avatars on all plans [S] | custom avatars need ~2 min of footage **and a consent recording from the person** [S]: impossible for fictional coaches, so stock avatars only (fails the identity rule) | yes, Phoenix-4.5 image-to-face [F] |
| **What the vendor sees** | **audio in, video out**: only the coach's reply audio if we send our own TTS [A] | depends on mode; audio-in mode would see only reply audio (to verify) | LITE: our audio only; FULL: runs STT+LLM+TTS, sees the whole conversation [F] | full pipeline: sees the conversation; with our own LLM endpoint it still sees audio and transcripts [F] |
| **Retention / training** | a directory says user content may train models [T]: **must verify** | not found | ZDR Enterprise-only [S] | delete endpoints, ZDR conversations mentioned [F] |
| **Flutter path** | `simli_client` 1.0.1 (stale, 2024-12-15) [F]; WebRTC (LiveKit/Pipecat plugins) [F] | JS/React SDK, no Flutter SDK [S]; LiveKit plugin [F]; WebView fallback | LiveKit (`livekit_client` Flutter SDK) [F] | official Flutter via `daily_flutter` [F] |

Only **Simli and Anam** are bake-off candidates for production: both take
images of our own coaches and can run audio-in, so the vendor never receives
the user's speech, transcript or the model context. LiveAvatar is useful
only to compare latency (stock face). Tavus keeps identity well but sees the
conversation and costs about 5x more.

## 2. Integration shape (same for Simli and Anam)

```
iPhone (Flutter)                                     Cloudflare Worker (ours)
  user speaks -> on-device STT (unchanged)             LLM reply (unchanged)
  text -> Worker ------------------------------------>  streams reply text
  reply text -> TTS (option A or B) -> reply audio
  reply audio ---- WebRTC (flutter_webrtc / LiveKit) ---> vendor renders face
  <------------------ video track of the coach -------- vendor
```

* **Session tokens:** the Worker mints a short-lived vendor session token per
  call (vendor key stays in Worker secrets, never in the app), and counts
  minutes against the per-subscriber cap.
* **Where the reply audio comes from**:
  * **A. Device TTS streamed out:** `AVSpeechSynthesizer.write(…)` gives PCM
    buffers (iOS 13+; markers need iOS 16/17) that a Swift channel forwards
    to the WebRTC audio track. $0 for voice; the vendor receives the audio
    the user would hear anyway. Needs native work and a device test; the
    vendor must accept client-sent audio (Simli and LiveAvatar LITE take an
    audio stream [F]; Anam to verify).
  * **B. Cloudflare Workers AI Aura-2 voice:** the Worker synthesizes the
    reply (`@cf/deepgram/aura-2-en` / `aura-2-es`, $0.030 per 1k
    characters, ≈ $0.027 per speech-minute [F]) and pipes the audio to the
    vendor server-side, so the phone only receives video. Simpler client,
    distinct high-quality voices per coach (es-MX accent per voice to be
    auditioned), but it adds the voice cost and Workers Paid.
* **Fallback:** on any vendor error, cap reached or poor network, the stage
  falls back to the on-device avatar with device TTS (no user-visible error).
* **Flutter packages:** `flutter_webrtc` or `livekit_client` (both
  permissive licences, to confirm at the time); no vendor SDK in the app if
  the vendor offers plain WebRTC/LiveKit.

## 3. The bake-off (once approved)

Same inputs for every vendor: the **8 demo clips** (4 coaches × EN/ES; the
texts and reference audio from `tool/avatar/eval/make_jobs.py`), using each
coach's **approved portrait** as the face (or the closest stock avatar for
LiveAvatar).

| Measure | How | Pass |
|---|---|---|
| Identity | `tool/avatar/verify.py` on 10 frames per clip: SFace vs approved reference | ≥ 0.45 and own coach highest, every frame |
| Eye colour | same, iris-colour check | within the gate (no re-coloured eyes) |
| Lip-sync | `tool/avatar/eval/measure_av.py` (openness vs audio, best lag) | lag within ±80 ms; openness r above the on-device result |
| Spanish | the 4 ES clips, judged by a native es-MX listener | no visibly English mouth patterns |
| Latency | time from reply audio start to first moving frame | < 500 ms |
| Privacy | written answer from the vendor: retention, training, sub-processors, region | no training on content; retention ≤ 30 days or ZDR |
| Cost | measured minutes × verified price | fits the cap below |

Output: one table per vendor plus the side-by-side videos, attached to the
decision PR.

## 4. Cost and the per-subscriber cap

At 60 avatar session-minutes per subscriber per month (3 sessions a week of
~5 min; the vendor bills while the avatar listens too) [A]:

| Option | 100 subs | 1,000 subs | 5,000 subs | per sub |
|---|---|---|---|---|
| On-device (today) | $0 | $0 | $0 | $0 |
| Simli + device voice (A) | ~$300 | ~$3,000 | ~$15,000 | ~$3.00 |
| Simli + Aura voice (B) | ~$381 | ~$3,810 | ~$19,050 | ~$3.81 |
| Anam at $0.04 floor + Aura | ~$321 (likely $660–1,080 at this size) | ~$3,210 | ~$16,050 | $3.21+ |
| Tavus Business | ~$1,495 | ~$15,535 | ~$77,935 | ~$15 |

DateWise Premium nets about $6.99 a month per subscriber, so **a hard cap is
required**: proposed **30 avatar-minutes per subscriber per month**, after
which the stage silently uses the on-device avatar, enforced in the Worker
next to the existing fair-use caps (`lib/config/fair_use.dart`,
`backend/cost_guard.js`).

## 5. Privacy-label and policy changes

* **App Privacy:** "Audio Data" changes from **No** to **Yes: collected,
  linked = No, tracking = No, purpose = App Functionality** if reply audio
  generated on the device is sent to the vendor (option A). With option B
  the audio is generated server-side from text the Worker already processes;
  disclose the vendor as a processor either way.
* **Privacy Policy and Terms (`lib/content/legal_text.dart`):** name the
  vendor as a processor of the coach's reply audio for rendering the
  animated coach; state retention and no training.
* **App Review (Guideline 5.1.2):** third-party AI processing disclosed with
  consent. Show a one-time notice before the first video session, with an
  "on-device animation only" choice.
* **Store copy:** only after the device test; "video" claims only for the
  paid real-time mode.

## 6. Owner-approval steps (in order)

1. **OWNER:** approve the bake-off itself, i.e. creating free accounts at
   Simli and Anam (optionally LiveAvatar Sandbox and Tavus Free) with a
   company email. No card, no paid plan.
2. **OWNER:** approve uploading the four approved coach portraits to those
   vendors for image-to-face avatars (the portraits leave our control).
3. Run the bake-off (section 3); publish the results.
4. **OWNER:** choose the vendor and plan, after reading its data-processing
   terms (retention, training, sub-processors, region).
5. **OWNER:** choose the voice source: device TTS streamed out (A) or
   Workers AI Aura-2 (B, needs Workers Paid and per-character spend).
6. **OWNER:** approve the App Privacy label, Privacy Policy and Terms changes
   (section 5).
7. **OWNER:** set the monthly per-subscriber avatar-minute cap and a monthly
   spend alert/ceiling at the vendor.
8. Build behind a remote flag, default off; TestFlight; compare with the
   on-device avatar; then **OWNER** approves enabling it.
