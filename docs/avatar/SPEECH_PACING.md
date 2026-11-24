# Speech pacing and lip-sync rate (build 203 device findings)

Owner finding on a physical iPhone, TestFlight build 203: the coach speaks much too fast, the voice sounds robotic,
and the lips move too fast. This is tuning of existing code (no new native features, no image assets).

## What changed

| Area | Before (build 203) | After |
| --- | --- | --- |
| Rates (flutter_tts, 0.5 = platform default) | Ava 0.54, Ethan 0.49, Sofía 0.46, Diego 0.45 | Ava 0.45, Ethan 0.44, Sofía 0.455, Diego 0.445 |
| Pitch | 0.98 / 0.91 / 1.10 / 0.88 (up to about 2 semitones) | 1.00 / 0.97 / 1.05 / 0.92 (at most about 1.4 semitones) |
| Cadence | one continuous utterance | one utterance per sentence, 380 ms between sentences, 650 ms between paragraphs, 180 ms at clause cuts of sentences over 150 characters |
| Text | markdown characters stripped only | markdown, links, emoji, short stage directions removed; times, money, percent and abbreviations written out (en and es) |
| Voice picker | locale order, then quality | Siri/neural > Premium > Enhanced > default > compact > novelty voices (identifier is used when quality is missing); es-MX, es-US, es-419, es-ES (last resort) |
| Mouth | 10 shape changes/s on average, 14-15 in the worst second | about 5.4-5.6/s average, at most 8 in any second |

Mouth changes: minimum shape duration 50 ms to 120 ms, minor consonant shapes (generic consonant, l, th) are absorbed by
the neighbouring vowel, repeated and near-identical shapes (same rounding, openness within 0.16) merge, lip closures
(m b p), f/v and the clear vowel openings stay, holds up to 0.4 s, and a rate limiter merges the shortest minor shape in
any one-second window that would exceed 8 changes. Jaw opening is unchanged (proportional to the vowel or the audio
loudness). Reduce Motion handling is untouched.

The plan is made per sentence from the exact text spoken, and is re-anchored to the real speech by the word events
(flutter_tts progress handler, and the iOS 17 word markers on the native audio path) or the loudness alignment, as
before. Its nominal speed now comes from `SpeechPace` (lib/avatar/speech_pace.dart), calibrated to the slower rates.

## Measurements (test/speech_pacing_test.dart, deterministic, 4 sample replies per language)

Speaking pace is words per minute of speech with pauses excluded, from the planner (letters per second, model in
`SpeechPace`). Run `flutter test test/speech_pacing_test.dart` and read the `MEASURE` lines.

Before (build 203, same replies): Ava 0.54 about 185 wpm, Ethan 0.49 about 170, Sofía 0.46 about 145, Diego 0.45 about
142; shape changes 9.8-10.2/s average, 14-15 in the worst second.

After: Ava 158 wpm, Ethan 155 (English); Sofía 143, Diego 141 (Spanish); shape changes 5.4-5.6/s average and 8 in the worst
second (English 150-165 wpm, Spanish 140-160 wpm, at most 6/s average and 8/s worst second are asserted).

## What only a device can confirm

- The SpeechPace model is an assumption: the platform default 0.5 is taken as about 170 wpm and the rate as linear
  (3 wpm per 0.01). Real voices differ; compact voices run faster than Enhanced or Premium ones. Judge by ear and
  adjust `CoachVoiceProfile` rates in small steps (0.01 is about 3 wpm).
- Whether the system voices sound acceptable. Robotic quality comes mostly from the voice itself: iOS "compact"
  voices are the default and sound synthetic. The picker now prefers Premium/Enhanced/Siri voices when installed, but
  no rate or pitch tuning can turn a compact voice into a natural one. If the owner still finds the best installed
  voice unacceptable, that is the case for the separately commissioned neural-voice study (not built here).
- The iOS 17 word markers and loudness alignment (native audio path, only in TestFlight builds with
  `DW_AVATAR_AUDIO_PATH=true`). On that path the sentence-by-sentence playback starts a new native utterance per
  sentence, so the audio session is released and re-acquired between sentences (music ducking may flicker).

## How to hear the difference on a device

1. Settings > Accessibility > Spoken Content > Voices > English (or Spanish): download a voice marked Enhanced or
   Premium (for example Ava, Zoe, Evan; Paulina, Juan for Mexican Spanish). Restart the app (the voice list is read at
   launch).
2. Settings > More natural coach voices in DateWise shows the same steps.
3. Open a chat, tap listen on a 3-4 sentence reply: you should hear a calmer pace, a short breath between sentences
   and a longer one between paragraphs, and mouth movement about half as busy as in build 203.
4. Compare with and without a Premium voice installed; compare Ava (unshifted pitch) with Ethan.
