# Talking AI avatars (prototype)

**Status:** working prototype on branch `claude/datewise-talking-avatars`.
$0, on-device, no avatar provider. **Not yet tested on an iPhone**, so it is
not described in the App Store text. Frames come from the **interim**
portraits and must be regenerated (`tool/avatar/regenerate.sh`) when the
owner's final portraits arrive.

## What the user sees

On the voice stage (`chat_screen.dart` › `_Stage`) the coach's portrait moves:

| State | When | Animation |
|---|---|---|
| Speaking | the reply is read aloud | 16 mouth shapes timed to the device's speech (full opening on stressed syllables, half on the others); a small nod and tilt at each phrase start and on emphasis; blinks; breathing |
| Listening | the user holds the talk button | 400 ms nods (3 px, ~0.5°) every 2.6–3.6 s; blinks |
| Thinking | the reply is being written | eyes glance up and aside, lips closed, slight head tilt |
| Idle | otherwise | blinks (150 ms, sometimes double), breathing |

It is **frame compositing, not video**: photo patches generated offline from
the approved portrait are drawn over that portrait on the device, and head
motion is a small whole-image transform. There is no real-time neural
rendering, no head turns, and the expressions are a fixed set.

Accessibility: VoiceOver reads "Ava, animated AI coach, speaking" (Spanish,
gender-neutral: "Retrato animado de Sofía, coach con IA, hablando"), and
listening/thinking/idle variants. With **Reduce Motion** on, the stage shows
the still portrait ("… (still portrait)"), nothing is decoded and no ticker
runs. If the frames are missing or no longer match the portrait's size, it
also falls back to the still portrait.

## How it works

```
offline (once per portrait)                      on the iPhone
---------------------------                      -------------
assets/coaches/<id>-hero.jpg                     AVSpeechSynthesizer (flutter_tts)
  -> LivePortrait retargeting (CPU, 1.9x crop)     start / word range / done callbacks
     (YuNet replaces InsightFace)                        |
  -> sharpness + grain matched to the portrait   LipSyncDriver (lib/avatar/lip_sync.dart)
  -> blend into the untouched portrait inside      plan: EN/ES spelling -> mouth shapes,
     a feathered mouth (clipped at the jaw)              stress, n+b/v/p/m -> lips closed
     or eye mask                                   each word event re-anchors the plan
  -> SFace identity + iris-colour gate             mouth shown 80 ms ahead (lead)
  -> assets/avatar/<id>/<frame>.jpg + manifest           |
                                                 AvatarAnimator -> AvatarPainter
                                                   portrait + patches; 30 ms crossfades
                                                   between open shapes, hard switches for
                                                   closed lips and eyelids; head transform
```

* **Frames:** 19 per coach (16 mouth shapes, 2 blink stages, 1 glance),
  76 in all, 1.5 MB of JPEGs. Pipeline and licences: `tool/avatar/README.md`.
* **Timing (word ranges, iOS 15+):** iOS calls
  `speechSynthesizer(_:willSpeakRangeOfSpeechString:)` at the start of every
  word; flutter_tts forwards it as `setProgressHandler`. The driver moves the
  plan so that word starts *now*, measures the pace between words, and holds
  a closing mouth at a word's end until the next word event. Without events
  it free-runs on the rate model, and it stops by itself 1 s after the plan
  ends if the completion callback never comes.
* **Transitions:** closed lips (M/B/P, F/V, small U) and blinks switch
  without a crossfade (a half-faded frame shows teeth through the lips or the
  iris through the lids); open shapes crossfade over 30 ms; a jump in
  openness above 0.4 goes through a 35 ms middle shape.
* **No frozen mouth:** no shape is held longer than 250 ms while speaking;
  long sounds alternate between the full and half opening. Rest appears only
  at real pauses (punctuation).
* **Openness and loudness:** without audio analysis, the opening follows
  stress: the stressed syllable gets the full shape (Spanish: written accent
  or the standard rule; English: first syllable, the syllable before -tion,
  unstressed function words), the others the half shape.
* **Constants** (in `VisemeTimeline`): `lead` 0.08 s, `blend` 0.03 s,
  `maxHold` 0.25 s, `bridgeJump` 0.4, `bridgeLength` 0.035 s. The lead is a
  first estimate; tune it on a device.
* **Upgrade (not built): audio-driven opening.**
  `AVSpeechSynthesizer.write(_:toBufferCallback:toMarkerCallback:)`
  (`AVSpeechSynthesisMarker` iOS 16+, marker callback iOS 17+) gives word
  (and possibly phoneme) markers plus PCM buffers. A Swift method channel
  would play the buffers through `AVAudioEngine` and send per-buffer RMS (and
  markers) to the driver, so the opening follows the real loudness and the
  audio and mouth share one clock. It goes behind `if #available(iOS 17, *)`
  with this word-range path as the fallback; **the app minimum stays
  iOS 15**. Needs a device to build and test.
* **Memory:** only the coach on screen is decoded (11.1–12.6 MB of images,
  down from 17.5–21.6 MB with the old whole-head frames). Switching coach
  disposes the previous coach's images; closing the voice stage disposes
  them; a failed load disposes whatever was decoded.
* **Battery:** while not speaking the pose updates at 30 fps.

## Voices

* Unchanged on-device TTS. `pickVoice` ranks **Premium > Enhanced >
  default** before the coach's known voice names, so a downloaded Premium
  voice is used automatically.
* Each coach gets a distinct voice when the device has several: Ava and
  Ethan (en-US) and Sofía and Diego (es-MX) differ by gender; a coach
  answering in the other language avoids the voice of that language's own
  same-gender coach (Ava in Spanish does not borrow Sofía's voice) when
  another fitting voice is installed.
* **When the device has one voice per language and gender** (common: a stock
  iPhone has few Spanish voices), the coaches who share it differ only in
  pitch and rate. Settings › About › "More natural coach voices" explains how
  to download more voices (Settings › Accessibility › Spoken Content ›
  Voices).

### Cloudflare Workers AI TTS (evaluated, not built, no calls made)

| Model | Languages | Price | Output | Timing data |
|---|---|---|---|---|
| `@cf/deepgram/aura-2-en` | English | $0.030 / 1k chars (2,727 neurons) | MP3 (also linear16, opus, aac) | none |
| `@cf/deepgram/aura-2-es` | Spanish (10 speakers; es-MX accent per voice not stated) | $0.030 / 1k chars | MP3 | none |
| `@cf/myshell-ai/melotts` | — | — | — | deprecated 2026-11-20: do not use |

About $0.027 per minute of coach speech; the 10,000 free neurons a day cover
about 4 minutes of speech for the whole service. Design if the owner approves
it: a Worker route returning the reply audio, a build flag `DW_CLOUD_TTS`
(off by default), an audio player, and the opening driven by the audio's
amplitude (Aura gives no word timings), falling back to on-device TTS.
**Not implemented.** Paid real-time avatars: `PAID_PROVIDER_BAKEOFF.md`.

## Privacy

Nothing new leaves the phone. The avatar is drawn on the device from bundled
images; speech and its timing come from the device's own synthesizer. No
avatar vendor is involved. App Privacy answers are unchanged.

## Evidence (2026-11-23, after the review fixes)

**Frames:** 76/76 pass the gate. Identity vs approved reference ≥ 0.657
(Sofía's wide "o"; threshold 0.45, own coach always highest), vs master
≥ 0.772, iris chroma shift ≤ 2.8 (limit 5).

**Lip-sync**, offline, 8 clips (4 coaches × EN/ES, each coach with its own
Piper voice), reproducible with `tool/avatar/eval/`. Before = the code at
04cff76 on the same clips; after = this code.

| Timeline vs Piper's phoneme alignments | Before | After |
|---|---|---|
| Exact mouth shape (11 classes), lead removed | 62% | 61% |
| Openness correlation, lead removed | 0.62 | 0.60 |
| M/B/P closures shown within ±80 ms | 97% | 100% |
| Longest single shape held while audible | 0.29 s | 0.20 s (mean max 0.16 s) |
| Longest rest while audible (real pauses only) | 0.16 s | 0.16 s |
| Mouth timing vs phonemes | +1 ms | −79 ms (the 80 ms lead) |

| Rendered video vs audio loudness (`measure_av.py`) | Before (old clips) | After |
|---|---|---|
| Openness proxy (cavity + teeth area): best lag | +75 ms (mouth late) | +4 ms |
| Openness proxy: r at 0 lag / at best lag | 0.17 / 0.23 | 0.17 / 0.22 |
| Mouth-region difference from master: r at best lag | 0.16 | 0.09 |

Reading these honestly:
* The lead removes the visible lag (+75 ms → +4 ms in the video), at the
  cost of the mouth running ~80 ms ahead of the phoneme timing; a slight
  lead is far less noticeable than a lag. It is a tunable constant to settle
  on a device.
* Openness vs loudness did not improve: stress weighting is a weak stand-in
  for audio. The real fix is the audio path above.
* "Difference from master" is a poor openness measure for these portraits:
  the masters smile with teeth showing, so closed lips differ from the
  master more than an open mouth does.

**Performance (host CPU):** 7–16 µs to record a frame; 7.4–9.1 ms to
rasterize a 1098×510 px frame in software (an upper bound; iPhones use the
GPU). iPhone profile numbers are still to be measured.

## Blocked / to do

1. **Real iPhone test** of word-event timing with the default, Enhanced and
   Premium voices, A/V sync (target ±80 ms; tune `lead`), frame time and
   memory in a profile build.
2. **Final portraits:** run the intake check, then `tool/avatar/regenerate.sh`.
3. Optional: the iOS 17 marker + PCM path (above).
4. Store copy: only after the device test.
