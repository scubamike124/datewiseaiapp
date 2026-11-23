# Talking AI avatars (prototype)

**Status:** working prototype on branch `claude/datewise-talking-avatars`.
$0, on-device, no avatar provider. Frames come from the **interim** portraits
and must be regenerated (`tool/avatar/regenerate.sh`) when the owner's final
portraits arrive.

## What the user sees

On the voice stage (`chat_screen.dart` › `_Stage`) the coach is an **animated
AI coach with lip-synced speech**:

| State | When | Animation |
|---|---|---|
| Speaking | the reply is read aloud | mouth shapes follow the device's speech, blinks, breathing and a slight sway |
| Listening | the user holds the talk button | small nods every ~3.4 s, blinks |
| Thinking | the reply is being written (streaming) | eyes up and aside, lips closed, held with a crossfade |
| Idle | otherwise | blinks every 2.5–6 s, breathing |

It is **frame compositing, not video**: photo patches generated offline from
the approved portrait are drawn over that portrait on the device. There is no
real-time neural rendering, no head turns, and the expressions are a fixed set.

Accessibility: VoiceOver reads "Ava, animated AI coach, speaking" ("Sofía,
coach con IA animado, hablando"), and listening/thinking/idle variants. With
**Reduce Motion** on, the stage shows the still portrait ("… (still
portrait)") and no ticker runs. If the frames are missing or no longer match
the portrait's size, it also falls back to the still portrait.

## How it works

```
offline (once per portrait)                      on the iPhone
---------------------------                      -------------
assets/coaches/<id>-hero.jpg                     AVSpeechSynthesizer (flutter_tts)
  -> LivePortrait retargeting (CPU)                start / word range / done callbacks
     (YuNet replaces InsightFace)                        |
  -> blend into the untouched portrait           LipSyncDriver (lib/avatar/lip_sync.dart)
     inside a feathered mouth/eye/head mask        plan: EN/ES spelling -> mouth shapes,
  -> SFace identity + iris-colour gate                   word lengths from the speech rate
  -> assets/avatar/<id>/<frame>.jpg + manifest     each word event re-anchors the plan
                                                         |
                                                 AvatarAnimator -> AvatarPainter
                                                   portrait + patches, 60 ms crossfades,
                                                   blinks, nods, breathing
```

* **Frames:** 16 per coach (10 mouth shapes, 2 blink stages, 2 nod stages,
  attentive brows, thinking). 2.2 MB of JPEGs for all four coaches. The
  pipeline and its licences are in `tool/avatar/README.md`.
* **Timing (Option 1, chosen):** iOS calls
  `speechSynthesizer(_:willSpeakRangeOfSpeechString:)` at the start of every
  word; flutter_tts forwards it as `setProgressHandler`. The driver moves the
  plan so that word starts *now*, measures the pace between words, and holds
  a closing mouth at a word's end until the next word event, so it never runs
  ahead of the audio. Without events it free-runs on the rate model.
* **Why not Option 2 now** (render to file, analyse, play back): it needs an
  audio player plugin and delays the first word until the whole reply is
  synthesized. A possible next step is
  `AVSpeechSynthesizer.write(_:toBufferCallback:toMarkerCallback:)`
  (`AVSpeechSynthesisMarker` is iOS 16+, the marker-delivery callback iOS
  17+), which gives word (and possibly phoneme) markers plus PCM for
  amplitude. It would sit behind an `#available(iOS 17, *)` check with this
  word-range path as the fallback; **the app minimum stays iOS 15** (the
  prototype uses only flutter_tts's word-range callback, which works on
  iOS 15). That needs a Swift method channel and a device to test on.

## Voices

* Unchanged on-device TTS. `pickVoice` now ranks **Premium > Enhanced >
  default** before the coach's known voice names, so a downloaded Premium
  voice is used automatically. With several voices installed each coach gets a
  distinct one (e.g. Ava, Evan, Paulina, Juan); with one voice per language the
  two coaches of that language differ only in pitch and rate (device-dependent).
* Settings › "More natural coach voices" explains how to download Premium /
  Enhanced voices (Settings › Accessibility › Spoken Content › Voices).

### Cloudflare Workers AI TTS (evaluated, not built, no calls made)

| Model | Languages | Price | Output | Timing data |
|---|---|---|---|---|
| `@cf/deepgram/aura-2-en` | English | $0.030 / 1k chars (2,727 neurons) | MP3 (also linear16, opus, aac) | none |
| `@cf/deepgram/aura-2-es` | Spanish (10 speakers; es-MX accent per voice not stated) | $0.030 / 1k chars | MP3 | none |
| `@cf/myshell-ai/melotts` | — | — | — | deprecated 2026-11-20: do not use |

About $0.027 per minute of coach speech; the 10,000 free neurons a day cover
about 4 minutes of speech for the whole service. Source: the research doc's
fetch of Cloudflare's pages (2026-11-22). Design if the owner approves it: a
Worker route that returns the reply audio (zero data retention on Aura), a
build flag `DW_CLOUD_TTS` (off by default), an audio player, and lip-sync from
the audio's amplitude (Aura gives no word timings), falling back to on-device
TTS. **Not implemented**: it costs money and would change the privacy answers
(the reply text goes to one more processing step at Cloudflare, which already
runs the chat).

## Privacy

Nothing new leaves the phone. The avatar is drawn on the device from bundled
images; speech and its timing come from the device's own synthesizer. No
avatar vendor is involved, so no third party sees conversations. App Privacy
answers are unchanged.

## Evidence (prototype run, 2026-11-23)

* 64/64 frames passed the identity gate (SFace vs. approved reference ≥ 0.45
  and own coach highest; vs. master ≥ 0.75) and the iris-colour gate. Review
  sheets: `build/avatar-review/` after a regenerate.
* Lip-sync accuracy, offline, 8 clips (4 coaches × EN/ES, ~8–9 s each).
  Ground truth: Piper TTS phoneme alignments (sample-exact). The app's
  timeline gets only each word's start/end, as iOS's word callbacks give it:

  | Timeline | Exact mouth shape (11 classes) | Mouth-openness correlation | M/B/P closures shown within ±80 ms |
  |---|---|---|---|
  | With word events (shipping path) | 63% | r = 0.63 | 96% (51/53) |
  | Rate model only, no word events | 19% | r ≈ 0 | 34% |

  So the word events are essential: on a voice that sends none, the mouth
  still moves but is not in sync. This is the first thing to check on an
  iPhone.
* Painter: 7–30 µs to record a frame; 8–10 ms to rasterize a 1098×510 px
  frame in software on the host CPU (an upper bound; iPhones rasterize on the
  GPU). `test/avatar_widget_test.dart` prints both. iPhone profile-build
  numbers are still to be measured.
* Memory: 17.5–21.6 MB of decoded images for the coach on screen (portrait
  plus 16 patches; the four whole-head patches are most of it); only the
  selected coach is decoded. Can be cut by about 4x by decoding head patches
  at half size if a device test shows memory pressure.

## Blocked / to do

1. **Real iPhone test** of word-event timing with the default, Enhanced and
   Premium voices (do they all send word ranges?), A/V sync (target ±80 ms),
   and frame time in a profile build.
2. **Final portraits:** run the intake check, then `tool/avatar/regenerate.sh`.
3. Optional: iOS 16 marker + PCM path (above); idle loops with head motion.

## Paid upgrade path (needs the owner's approval)

Real-time neural avatars (true video, head motion) are paid services. From
`AVATAR_REQUIREMENTS_AND_OPTIONS.md` (prices UNVERIFIED unless marked):
Simli ~$0.05/min (audio-in, it sees only reply audio), Anam from $0.04/min,
HeyGen LiveAvatar LITE ~$0.09–0.10/min, Tavus $0.26–0.37/min (sees the
conversation). At 60 min per subscriber per month, Simli + Aura voice is about
$381 / $3,810 / $19,050 a month for 100 / 1,000 / 5,000 subscribers. Nothing is
signed up for or enabled. Steps: free-tier bake-off → owner approves vendor,
data terms, privacy-label change and a per-subscriber minute cap.
