# Voice comparison (2026-11-24, overnight)

Every file reads the same coach lines from `../dialogue.json` (the coach turns only, 0.7 s between turns), so the
voices can be compared directly. Nothing here is integrated into the app; the app still uses the on-device Apple voice.

Engines that ran here, free and commercially usable:

- **Kokoro-82M** (Apache-2.0): built-in voices. Ava: af_heart, af_bella, af_nicole. Ethan: am_michael, am_fenrir,
  am_puck. Sofía: ef_dora (Kokoro's only Spanish female voice). Diego: em_alex, em_santa.
- **Chatterbox Multilingual** (MIT, Resemble AI): zero-shot voice cloning from a reference clip. Each coach was given a
  Kokoro voice as the reference (Ava af_heart, Ethan am_michael, Sofía ef_dora, Diego em_alex) to keep the four voices
  distinct, with exaggeration 0.55 and cfg 0.45. Its output carries Resemble's inaudible Perth watermark (kept on).

## Objective checks (no human listening has been done)

Whisper small (int8, CPU) transcribed every file and the text was compared with the script; pitch was measured with
pYIN. A low "words wrong" score means the speech is clear. A wider pitch range usually means livelier intonation; a
very wide one, together with a slow rate, can mean odd pauses or pitch jumps.

| File | Engine | Words wrong (Whisper) | Median pitch (Hz) | Pitch range (semitones) | Words/min |
|---|---|---|---|---|---|
| [chatterbox-ava.mp3](chatterbox-ava.mp3) | Chatterbox | 0% | 206 | 9.9 | 153 |
| [chatterbox-diego.mp3](chatterbox-diego.mp3) | Chatterbox | 3% | 139 | 15.2 | 167 |
| [chatterbox-ethan.mp3](chatterbox-ethan.mp3) | Chatterbox | 0% | 134 | 12.1 | 150 |
| [chatterbox-sofia.mp3](chatterbox-sofia.mp3) | Chatterbox | 7% | 167 | 26.2 | 107 |
| [kokoro-ava-af_bella.mp3](kokoro-ava-af_bella.mp3) | Kokoro | 0% | 211 | 8.1 | 156 |
| [kokoro-ava-af_heart.mp3](kokoro-ava-af_heart.mp3) | Kokoro | 0% | 204 | 9.9 | 162 |
| [kokoro-ava-af_nicole.mp3](kokoro-ava-af_nicole.mp3) | Kokoro | 0% | 162 | 6.4 | 105 |
| [kokoro-diego-em_alex.mp3](kokoro-diego-em_alex.mp3) | Kokoro | 3% | 127 | 10.1 | 168 |
| [kokoro-diego-em_santa.mp3](kokoro-diego-em_santa.mp3) | Kokoro | 3% | 121 | 15.6 | 167 |
| [kokoro-ethan-am_fenrir.mp3](kokoro-ethan-am_fenrir.mp3) | Kokoro | 0% | 135 | 15.9 | 161 |
| [kokoro-ethan-am_michael.mp3](kokoro-ethan-am_michael.mp3) | Kokoro | 0% | 114 | 15.7 | 143 |
| [kokoro-ethan-am_puck.mp3](kokoro-ethan-am_puck.mp3) | Kokoro | 0% | 108 | 16.9 | 163 |
| [kokoro-sofia-ef_dora.mp3](kokoro-sofia-ef_dora.mp3) | Kokoro | 7% | 175 | 8.3 | 168 |

## Notes from the transcripts

- All 13 files are intelligible (0–7% words wrong; most errors are accent marks or Whisper's own slips).
- **Kokoro Spanish loses questions.** In ef_dora, em_alex and em_santa the questions come out flat: Whisper wrote
  "¿Dónde se van a ver?" as part of the previous sentence and "¿Quieres que te dé otra opción?" without question marks.
- **Chatterbox keeps question intonation and sentence breaks** in both languages, but Sofía has one 2.6 s gap, a wide
  pitch swing and some mispronunciations ("Pruéba", "cometa acos" for "come tacos", "te leí" for "te dé"). It needs a
  re-take or a different reference voice.
- **af_nicole** is a whispery, slow voice (105 words/min); it does not suit a coach.
- The voices are distinct by pitch: Ava about 205 Hz, Sofía about 170 Hz, Ethan about 110–135 Hz, Diego about 120–140 Hz.

## Engines not run tonight, and why

- **ElevenLabs, Cartesia, Deepgram Aura-2:** need an account or API key. The owner asked for no new accounts tonight.
  Deepgram Aura-2 is also on Cloudflare Workers AI, which needs the Cloudflare credentials not yet in GitHub.
- **Fish Speech / OpenAudio:** weights are licensed for non-commercial use only. Excluded.
- **CosyVoice 3 (Fun-CosyVoice3-0.5B, Apache-2.0):** licence-compatible; not run, because the CPU was busy with the
  portraits. A candidate for the next round.
- **Hume, PlayHT:** shut down.

## Suggested owner listening order

1. Ava: chatterbox-ava, then kokoro-ava-af_heart.
2. Ethan: chatterbox-ethan, then kokoro-ethan-am_michael.
3. Sofía: kokoro-sofia-ef_dora, then chatterbox-sofia (note the issues above).
4. Diego: chatterbox-diego, then kokoro-diego-em_alex.

Scripts: kokoro_cmp.py, cb_cmp.py, asr_check.py (raw numbers in measurements.json).
