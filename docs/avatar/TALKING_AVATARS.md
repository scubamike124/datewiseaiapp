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
assets/coaches/<id>-hero.jpg                     native audio path (iOS 13+ API, app min iOS 15):
  -> LivePortrait retargeting (CPU, 1.9x crop)     AVSpeechSynthesizer.write -> PCM buffers
     (YuNet replaces InsightFace)                  -> AVAudioEngine playback
  -> sharpness + grain matched to the portrait     -> RMS per 10 ms (+ word markers on iOS 17)
  -> blend into the untouched portrait inside           |   (fallback: flutter_tts word ranges)
     a feathered mouth (clipped at the jaw)      LipSyncDriver (lib/avatar/lip_sync.dart)
     or eye mask; half blink equalized per eye     plan: EN/ES spelling -> mouth shapes,
  -> SFace identity + iris-colour gate                   stress, n+b/v/p/m -> lips closed
  -> assets/avatar/<id>/<frame>.jpg + manifest     AudioAlignment: loudness DTW-warped onto
                                                         the plan (or markers / word events)
                                                   jaw = loudness; vowel opening = loudness
                                                         |
                                                 AvatarAnimator -> AvatarPainter
                                                   portrait + patches (hard switches),
                                                   jaw-drop mesh warp, head transform
```

* **Frames:** 19 per coach (16 mouth shapes, 2 blink stages, 1 glance),
  76 in all, 1.5 MB of JPEGs. Pipeline and licences: `tool/avatar/README.md`.
* **Native audio path (iOS; off in App Store builds until a device test):**
  `ios/Runner/AppDelegate.swift` registers a small platform channel. It
  renders the reply with the chosen voice, pitch and rate through
  `AVSpeechSynthesizer.write(_:toBufferCallback:)` (iOS 13+), plays the
  buffers through `AVAudioEngine`/`AVAudioPlayerNode` (completion on
  `.dataPlayedBack`, so the tail is never cut), and streams the RMS of every
  10 ms, the output latency (so Bluetooth headphones do not put the mouth
  ahead of the sound) and, on iOS 17+ only, word markers (byte offsets
  converted with the buffer format's bytes per frame and sample rate)
  to Dart (`lib/avatar/speech_audio.dart`).
  * An audio-session interruption (a call, Siri), losing the output route
    (headphones unplugged), an engine configuration change or the app going
    to the background ends the utterance with "done": the stage stops
    speaking; the next reply uses the native path again.
  * If the synthesizer renders no audio at all, the channel reports an error
    before playback (the same reply is spoken through flutter_tts and the
    app keeps flutter_tts for the session). Dart also waits at most 3 s for
    playback to start; a timeout falls back for that reply only (a cold
    Premium voice can be slow), and two in a row turn the path off. An
    explicit stop releases the audio session, if this channel activated it,
    so other apps' audio is no longer ducked.
  * **Build flag:** `--dart-define=DW_AVATAR_AUDIO_PATH=true` turns it on
    (`DeviceVoiceService.useAudioPath`). **Default off**: App Store builds use
    the flutter_tts word-range path until the native path has passed an
    iPhone test. For that test, run the `iOS build` workflow by hand with
    `signed_build`, `upload_testflight` and `avatar_audio_path` ticked, and
    install the TestFlight build. Such a build is marked "AVATAR AUDIO-PATH
    TEST BUILD" in the run summary and its build number is 5000 higher, so
    it cannot be mistaken for an App Store candidate (checklist E7).
  * **The app minimum stays iOS 15.** It compiles in CI.
* **Alignment:** with markers (iOS 17), the plan is mapped word by word
  (markers out of order or past the audio are ignored; binary search over a
  cached marker list; lip-closure windows rebuilt at most once per second
  of new audio: worst call 8 ms, 0.5 s in total for a 114 s reply in a
  debug test). Otherwise the
  loudness is aligned to the plan by dynamic time warping (20 ms steps, both
  ends fixed once synthesis is complete; at most 250k cells, coarser for
  long replies; re-warped at most once per second of new audio, so the UI
  isolate does little work: about 22 ms worst case per call for a 52 s
  reply in a debug test). Each planned M/B/P closure is moved onto a
  clear dip in the loudness (below 30% of the local median) within ±60 ms.
  A ±120 ms search was tried and measured worse (an "m" is voiced, so the
  quietest moment is often elsewhere): closures within ±80 ms of the real
  M/B/P fell from 54% to 45% (loudness only) and from 96% to 76% (iOS 17
  markers). On the
  flutter_tts path, each word-range event re-anchors the plan (iOS 15+).
* **Jaw and opening:** the jaw drop follows the real loudness (a mesh warp of
  the lower lip and chin, up to 12% of the mouth width, zero at the patch
  border), and loud vowels get the full opening, soft ones the half opening.
  While the audio is audible the resting face is never shown. On the
  fallback path the jaw follows a per-syllable envelope from the plan.
* **Transitions:** every change of mouth shape is a hard switch between two
  whole photos (no crossfade, so no teeth through lips); closed lips and an
  open or smiling mouth pass through a just-parted shape (and a middle
  shape for large jumps). Every shape stays on screen at least 50 ms,
  measured in time: shorter shapes in the plan are merged into the
  neighbour closest in openness, and the driver holds a shape 50 ms before
  it may change. Blinks are switched too.
* **Blinks:** 150 ms; the first one at a random moment 1.5–4 s in; sometimes
  a double blink, never three in a row; the schedule is seeded per coach and
  per session; the half-closed frame closes both eyes equally.
* **Head motion:** a whole-image transform (listening nods, phrase-start and
  emphasis nods, small tilts under half a degree on stressed vowels, a
  thinking tilt); the zoom that hides the frame edges is
  computed from the stage size and the largest motion, so the short
  large-text stage and the wide iPad stage never show an edge.
* **Constants:** `VisemeTimeline.lead` 0.08 s (word path),
  `LipSyncDriver.audioLead` 0.03 s (audio path), `maxHold` 0.25 s,
  `bridgeJump` 0.4, `bridgeLength` and `minShape` 0.05 s, `minAfterBridge` 0.05 s,
  `AudioAlignment.closureSearch` 0.06 s, `AvatarPainter.jawDrop` 0.12.
  Tune on a device.
* **Memory:** only the coach on screen is decoded (11.1–12.6 MB of images).
  Switching coach disposes the previous coach's images; closing the voice
  stage disposes them; a failed load disposes whatever was decoded; nothing
  is decoded under Reduce Motion. If another holder frees them, the stage
  shows the still portrait.
* **Battery:** while not speaking the pose updates at 30 fps.
* **Auto-stop:** the mouth stops by itself 1 s after the plan once the pace
  is confirmed (word event or audio), and only after twice the plan's length
  on a voice that never sends word events.

## Voices

* Unchanged on-device TTS. `pickVoice` ranks **Premium > Enhanced >
  default** before the coach's known voice names, so a downloaded Premium
  voice is used automatically.
* With the native audio path, the same voice identifier, pitch and rate are
  passed to AVSpeechSynthesizer, so the coach sounds the same as before.
* Same-gender coaches who share the only installed voice of a language
  (Ava answering in Spanish with Sofía's voice, Ethan with Diego's) are kept
  apart by rate and pitch: Ava/Sofía rate 0.54/0.46 (16%) and pitch
  0.98/1.10 (2 semitones); Ethan/Diego rate 0.49/0.45 (8%) and pitch
  0.91/0.88.
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

## Evidence (2026-11-23, round 5)

**Frames:** 76/76 pass the gate. Identity vs approved reference ≥ 0.657
(threshold 0.45, own coach always highest), vs master ≥ 0.772, iris chroma
shift ≤ 2.8 (limit 5). Half blink: both eyes at 0.47–0.53 of their open size.

**Offline simulation**, 8 clips (4 coaches × EN/ES; each coach its own Piper
voice; es-MX for every Spanish clip, the shared voices separated by pitch and
~8% rate). The app's own `LipSyncDriver` runs on a simulated clock, fed like
the app, and the app's painter draws the frames. Reproducible with
`tool/avatar/eval/`.

Mouth vs loudness, measured on the videos the visual reviewer's way (mouth-
region difference from the idle frame vs audio RMS; head motion cancelled by
aligning on the upper face):

| | Round 1 (04cff76) | Round 2 (3ab5ea8) | Round 3 (72bb738) | Round 4 (70eb4c3), native | Round 5, native audio path | Round 5, flutter_tts path (App Store default) |
|---|---|---|---|---|---|---|
| r at 0 lag | 0.45 | 0.71 | 0.82 | 0.81 | **0.80** | 0.64 |
| best lag / r there | +86 ms / 0.67 | −16 ms / 0.72 | −8 ms / 0.82 | −9 ms / 0.82 | **−5 ms / 0.80** | +1 ms / 0.64 |
| longest unchanged mouth while audible | 67 ms | 33 ms | 0 ms | 33 ms | 33 ms | 33 ms |
| longest rest while audible | 67 ms | 100 ms | 0 ms | 33 ms | 33 ms | 200 ms |

Rounds 1–3 used earlier demo voices. (An earlier version of the measurement
script aligned frames on the whole picture, which the mouth disturbed; all
numbers here use the fixed script.)

Mouth shape vs Piper's phoneme alignments (what the frames showed):

| Path | Exact shape | Openness r | M/B/P within ±80 ms | Lag |
|---|---|---|---|---|
| Native audio, iOS 15/16 (loudness only) | 32% | 0.31 | 51% | −39 ms |
| Native audio, iOS 17 (+ word markers) | 47% | 0.43 | 85% | −13 ms |
| flutter_tts path (word events) | 35% | 0.27 | 73% | −38 ms |

(Round 5's 50 ms minimum per shape merges very short closures into their
neighbours: with markers, closures within ±80 ms went from 96% to 85%; on
the flutter_tts path they went from 62% to 73%.)

The jaw follows the real loudness on the native path, which is what the
viewer mostly sees. Which shape is shown comes from spelling rules and an
estimated alignment, so exact-shape agreement is modest without markers.

**Performance (host CPU):** 7–30 µs to record a frame; about 8–9 ms to
rasterize a 1098×510 px frame in software (an upper bound; iPhones use the
GPU). Decoded images 11.1–12.6 MB per coach. iPhone numbers are still to be
measured.

## Blocked / to do

1. **Real iPhone test** of the native audio path (playback, ducking, the
   RMS stream, iOS 17 markers, fallback), word-event timing on the fallback
   with the default, Enhanced and Premium voices, A/V sync (tune `lead` and
   `audioLead`), frame time and memory in a profile build.
2. **Final portraits:** run the intake check, then `tool/avatar/regenerate.sh`.
4. Store copy: only after the device test.
