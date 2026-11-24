# DateWise AI coach voices: independent verification (2026-11-24)

Research only. Nothing committed, no accounts, no paid services, CPU only. Inputs: `docs/research/avatar-voice-2026-11-24/voices-v2/chatterbox-v2-{ava,ethan,sofia,diego}.mp3` (24 kHz mono, 96 kbps), `report-*.json`, SQUIM JSONs, `dialogue.json`, `script.json`.
Tools: faster-whisper (small and medium, int8), SpeechBrain ECAPA-VoxCeleb, librosa pYIN, Praat (parselmouth) formants, pyloudnorm, jiwer. All scripts and raw outputs are in this folder (`an1..an6.py`, `an*.json`, `table.csv`).

## 0. Which voices does a paying user hear today? (the owner's key question)

**Not these recordings.** Findings from the app code (`lib/services/voice_service.dart`, `lib/models/coach.dart`):

- The app speaks coach replies with the **phone's own text-to-speech voices** through `flutter_tts` (Apple `AVSpeechSynthesizer` on iOS, Android TTS on Android). The class doc says "device's own text-to-speech voices ... Nothing is sent to a server." `DeviceVoiceService.create()` returns a no-voice service on web and in tests.
- `pickVoice` chooses an installed system voice per coach by locale, gender and quality (Premium > Enhanced > default), trying `en-US, en-GB, en-AU, en` for Ava/Ethan and `es-MX, es-US, es-ES, es` for Sofía/Diego. Preferred iOS names: Ava `Ava, Samantha, Allison...`; Ethan `Evan, Nathan, Alex...`; Sofía `Paulina, Mónica...`; Diego `Juan, Jorge, Diego...`.
- Each coach also gets a pitch and rate (Ava 0.98/0.54, Ethan 0.91/0.49, Sofía 1.10/0.46, Diego 0.88/0.45) so coaches stay distinct when a device has one voice per language.
- There is a native audio path (`DW_AVATAR_AUDIO_PATH`, AVSpeechSynthesizer rendered to PCM for the avatar's mouth). It is **off unless the build sets that define**, and per the code comment it "has not been tested on an iPhone yet". It still uses the Apple voices, not Chatterbox.
- No audio file, Chatterbox or Kokoro reference exists in `assets/` or `lib/`. Only `docs/business/AI_COST_MODEL.md` and a morning report mention them. The research README itself says: "Nothing here is integrated into the app; the app still uses the on-device Apple voice."

So today: **paying user hears Apple/Android system voices** (quality depends on whether the user downloaded Premium/Enhanced voices; the app shows a tip for that). The four Chatterbox files are **research recordings only**. Everything below judges those recordings; it says nothing about what ships.

Two consequences the owner should know:
1. **Dialect risk on device:** if the phone has no `es-MX` voice installed, the picker falls back to `es-US` then **`es-ES` (Castilian)**. A Mexican-Spanish promise is not guaranteed on device.
2. **Bilingual by design:** the voice follows the language of the reply text (`ReplyLanguage.detect`), so any coach can speak either language (English coach answering Spanish text gets a same-gender Spanish device voice, with the coach's own pitch/rate). See section 5.

## 1. Distinctness

Speaker embeddings: ECAPA cosine, whole file (higher = more alike). SpeechBrain's own example same-speaker threshold is about 0.25; treat as a rough guide only (TTS, mp3, 20 s files).

| | Ava | Ethan | Sofía | Diego |
|---|---|---|---|---|
| Ava | 1 | 0.14 | **0.26** | 0.17 |
| Ethan | | 1 | 0.06 | 0.06 |
| Sofía | | | 1 | **0.53** |
| Diego | | | | 1 |

3-second segment level (a speaker versus itself, mean / min): Ava 0.58 / 0.36, Ethan 0.69 / 0.61, Sofía 0.69 / 0.47, Diego 0.74 / 0.67. Across speakers (mean / max): Ava-Sofía 0.20 / 0.34, Ethan-Diego 0.07 / 0.17, **Sofía-Diego 0.42 / 0.59**.

Prosody and spectrum (`table.csv`; pYIN F0 over voiced frames, p5-p95 range in semitones):

| Coach | F0 median Hz | F0 p5-p95 Hz | range st | F1 / F2 / F3 Hz | tilt dB/oct | 99% energy below |
|---|---|---|---|---|---|---|
| Ava | 218 | 163-295 | 10.3 | 725 / 2093 / 3094 | -6.8 | 4.8 kHz |
| Ethan | 124 | 89-160 | 10.2 | 578 / 1766 / 2635 | -5.3 | 6.8 kHz |
| Sofía | 164 | 132-246 | 10.8 | 592 / 1878 / 2743 | -7.2 | **3.2 kHz** |
| Diego | 133 | 99-182 | 10.5 | 480 / 1709 / 2641 | -7.5 | 6.2 kHz |

Speaking rate (Whisper medium word timestamps, words per second over the whole span / excluding pauses over 250 ms): Ava 2.4 / 3.4, Ethan 3.0 / 3.8, Sofía 2.8 / 3.4, Diego 2.9 / 3.5. Ethan is the fastest and Ava the slowest overall; the rates are similar enough that rate does not separate the Spanish pair (Sofía and Diego differ by 0.1 w/s).

Plots: `ecapa_heatmap.png`, `f0_hist.png`, `ltas.png`.

Reading, strictly:
- **Ethan vs the rest, Ava vs Ethan/Diego: clearly different people** (ECAPA 0.06-0.17, F0 and formants far apart).
- **Ava vs Sofía: different by pitch (about 4.9 semitones) and formants, but ECAPA 0.26 is right at the threshold**, not "clearly different". Cross-language and the shared Chatterbox rendering inflate this; the same relationship exists between their Kokoro reference clips (0.21), so the clones inherited it. A listener will hear different languages, which helps, but I cannot claim "clearly different" from embeddings alone.
- **Ethan vs Diego: clearly different** by ECAPA (0.056) even though median F0 is only 1.3 semitones apart (124 vs 133 Hz). They differ in formants (F1 578 vs 480) and brightness (Diego has more energy in the low band, tilt -7.5 vs -5.3).
- **Sofía vs Diego is the weakest pair: ECAPA 0.53 (segment max 0.59 overlaps Sofía's own within-speaker minimum 0.47).** A speaker-verification model would likely call these the same speaker. They do differ in pitch (about 3.7 semitones) and formants, and the model may be confusing "same language and same rendering path". Their Kokoro references already score 0.49 against each other, so the similarity comes from the reference choice. This needs a human ear.
- **Not a generic default voice? Partly false.** Each Chatterbox voice is a clone of a Kokoro **stock voice** (af_heart, am_michael, ef_dora, em_alex): cosine to its own reference Ava 0.87, Ethan 0.81, Sofía 0.88, Diego 0.90. The four are distinct from each other, but Ava, Sofía and Diego remain close to Kokoro's public stock voices (anyone using Kokoro can produce them). Ethan is the most altered (0.81). I could not compare against the Apple default voices (no audio available), so "does not sound like the phone's default voice" is **not** tested.

## 2. Language correctness

Whisper language ID on the whole file, medium model (small agrees). Per-segment IDs (every 1+ s speech segment) were all the expected language at 0.94-0.999.

| File | Expected | Detected | P(expected) | Runner-up | WER vs script (strict) | WER (accent-folded) |
|---|---|---|---|---|---|---|
| Ava | en | en | 0.998 | cy 0.0003 | 0.0% | 0.0% |
| Ethan | en | en | 0.995 | nn 0.0015 | 0.0% | 0.0% |
| Sofía | es | es | 0.995 | en 0.0013 | 0.0% | 0.0% |
| Diego | es | es | 0.997 | en 0.0012 | 5.0% (small: 3.3%) | 1.7% |

Script = the coach turns of `dialogue.json` (the full text, not the partial `report-*.json`). WER ignores punctuation. Diego's errors: medium wrote "alargar" as "largar", dropped a comma/colon, "te de" for "te dé", "guión" for "guion" (accent only). Whisper small got "alargar" right. So one possibly clipped syllable ("a-largar") is worth a listen.

Not a fault but note: Whisper dropped the question marks/inverted marks in Sofía ("¿el perro también come tacos...?" came out as a statement run-on). Whisper punctuation is unreliable; the research README says Chatterbox questions sound right, which I did not verify by ear.

Housekeeping: `report-ava.json` covers only 4 sentences (the second coach turn), while the Ava MP3 is 24.5 s and holds both turns. The JSON report is incomplete for Ava (the audio is fine; my WER used the full script).

## 3. Mexican versus Castilian Spanish

**Verdict: unproven. Language is Spanish for certain; dialect is not demonstrated either way.**

What the spoken text contains (`dialogue.json` coach lines, which are what the v2 files read):
- Pronoun/verb forms: only "tú" (`tienes`, `pienses`, `quieres`, `te dé`); no "vosotros/os", no "ustedes". "¿Dónde se van a ver?" is third-person plural, neutral. (Evidence the text is not Castilian-vosotros, but also not Mexican-specific.)
- Castilian-only words ("vale", "móvil", "coche", "tío", "coger", "guay"): **none**. Mexican-marked words ("ahorita", "platicar", "padre", "chido", "carro", "celular"): **none**. The text is deliberately "neutral Latin-American Spanish" (the persona rule in `persona.dart` says exactly that). The earlier `script.json` had "plática" (Mexican) for Diego, but the v2 recordings use `dialogue.json`, which dropped it.
- So lexical testing of the voices is **impossible** from these lines; the text can't separate the two dialects. If the owner wants "Mexican", the script needs at least a couple of Mexican markers (ahorita, plática, qué padre) and then a native listener checks them.

Seseo check (acoustic, weak): lines with soft c/z: Sofía "atención, específico, fácil, opción"; Diego "cita, fácil, necesitas". I measured the fricative centroid and level at the onset of those words against /s/ in other words (`an3.py`).
- **Diego, "cita": /s/-like in both the clone (centroid 6.5 kHz, -9 dB) and the Kokoro reference (6.3 kHz, -7 dB), same as /s/ in "significan" (6.6 kHz) and "consejo" (6.0-6.5 kHz). That is consistent with seseo (no interdental /θ/).** It is one word.
- **Sofía: not testable.** Her files have almost no energy above 3 kHz (99% of energy below 3.2 kHz; the others reach 4.8-6.8 kHz), so my detector found no sibilant even in plain /s/ words ("así", "su", "mensaje"). Her sibilants are muffled, so seseo, /s/ aspiration and /θ/ cannot be judged acoustically, and the muffling is a quality flaw in itself (section 4).
- /s/ aspiration (coda s weakened to [h], typical of Caribbean/Andalusian, not Mexico): Diego's coda /s/ in "es", "los", "nervios" show strong high-band frication (centroid 5.5-6.3 kHz) in several instances, so not aspirated. Sofía not testable. This is ASR-timestamp-based and rough.

How the synthesiser gets its accent (code, not a proof):
- `best_of.py` uses Chatterbox Multilingual with `language_id='es'` and a **Kokoro Spanish voice as the reference clip** (`ef_dora`, `em_alex`). There is no `es-MX` option; the accent comes from the model's idea of "es" plus the reference clip. The Kokoro Spanish voices are generated through its Spanish (`lang_code='e'`, espeak-ng "es", whose default is the Spain variant) pipeline. I did not verify what accent those references actually have, and nothing in the research folder claims the voices are Mexican; the owner's `voice_brief` asks for Mexican but no accent check was done. Treat Mexican accent as **assumed, not evidenced**.
- Whisper language ID (es 0.995+) says nothing about dialect. Whisper's transcripts being correct only shows the Spanish is understandable.

**A native Mexican listener must settle it. Play these four sentences** (all from the actual files; timestamps are start times in each MP3):
1. Sofía, ~14.9 s: "Es divertido, es específico y es muy fácil de contestar." (soft c in específico/fácil; coda s in "es": listen for [θ] versus [s], and any [h]).
2. Sofía, ~18.8 s: "¿Quieres que te dé otra opción, por si acaso?" (ción, rising question contour, "acaso").
3. Diego, ~4.1 s: "Muy bien, un café es perfecto para una primera cita." ("cita" as [s]; overall rhythm).
4. Diego, ~17.8 s: "No necesitas un guion. Solo ten curiosidad." (necesitas, coda s in the plural endings; Diego at ~1.6 s, "Los nervios solo significan que te importa.", is a bonus s-aspiration test).
Ask the listener: "Does this sound Mexican, neutral Latin American, or Spain? Any [θ]? Does it sound like a real person from Mexico?"

## 4. Quality

SQUIM exists only for Ava (STOI 1.0, PESQ 3.50, SI-SDR 22.7) and Sofía (STOI 1.0, PESQ 3.77, SI-SDR 22.8). **No SQUIM for Ethan or Diego**, and STOI exactly 1.0 means the estimator saturated, so those numbers are weak evidence. My own measurements (`an4.json`, `loudness.png`):

| | Ava | Ethan | Sofía | Diego |
|---|---|---|---|---|
| Integrated LUFS | -25.0 | -25.0 | -26.8 | -27.1 |
| True peak dBTP | -5.2 | **-0.7** | -2.5 | -7.5 |
| 3 s LUFS min / max | -31.4 / -24.3 | -26.7 / -22.2 | -29.3 / -24.8 | -27.8 / -26.4 |
| Clipped samples | 0 | 0 | 0 | 0 |
| Leading / trailing silence | 60 ms / 980 ms | 20 / 980 | 80 / 980 | 70 / 990 |
| Longest internal gap | 940 ms | 970 | 980 | 1050 |
| Biggest 10 ms energy step in speech | 21 dB | 20 | **29** | 25 |

- **No clipping, no dropouts, no large silences.** Digital-zero gaps (-75 to -120 dB floor, 12-17% of samples are exact zeros) because gaps were inserted as zeros; the speech has no room tone, so each sentence starts from dead silence. Gaps between sentences are nearly constant (about 330-350 ms in all four files): metronomic, which can sound stitched.
- **Loudness is consistent within 2.1 LU across the four (-25.0 to -27.1) but all are very quiet** (about 10 dB below -16 LUFS streaming norm). Normalise in the app/pipeline. Sofía and Diego are about 2 LU quieter than Ava/Ethan. True peaks vary from -0.7 (Ethan, almost full scale from a single transient) to -7.5 (Diego), so a simple peak normalise would give uneven loudness; use LUFS.
- **Sentence joins:** at each sentence boundary I compared the last 5 ms with the preceding 100 ms (`an6.py`). Natural decays are -15 to -38 dB; a hard cut would be near 0 dB. Flags (listen at these times): Ava 7.92 s (end -4.4 dB), Ethan 7.60 s (-9.2) and 3.08 s (-10.1), Sofía 4.96 s (an onset only -0.8 dB below the following speech: abrupt start) and 5.70 s (end -9.4), Diego 19.25 s (-8.3), 1.25 s (-10.2). Most are probably final fricatives or plosives (loud by nature) rather than cuts, but these are the places a cut would be. Sofía's 28.9 dB step is the largest energy discontinuity of the set.
- **Sofía is dull/muffled** (99% energy below 3.2 kHz, HF ratio 0.01 against 0.03-0.09 for the others). Ava is also somewhat band-limited (4.8 kHz). This hurts intelligibility of /s/, "presence", and the dialect tests.
- Chatterbox output carries Resemble's Perth watermark (inaudible; kept on). Fine for the licence, note it for any commercial use review.
- The earlier v1 defects (a 2.6 s gap in Sofía, mispronunciations like "cometa acos") are **not present** in v2: Sofía WER 0% and longest gap is 0.98 s (the turn gap).

## 5. Bilingual coverage

The app model: four coaches, two default languages. Voice follows the reply text: Ava/Ethan are English coaches (`CoachLanguage.en`), Sofía/Diego Spanish coaches (`es`, locale `es-MX`). A coach replies in the user's language, so the app can ask any coach to speak either language (`forLanguage` maps to the same-gender coach's voice profile for that language).

| Coach | English | Spanish |
|---|---|---|
| Ava | **Recording exists** (research only) | none (device falls to Sofía's voice profile: a Spanish device voice, female) |
| Ethan | **Recording exists** | none (device uses Diego's profile) |
| Sofía | none (device uses Ava's profile) | **Recording exists** |
| Diego | none (device uses Ethan's profile) | **Recording exists** |

So the research recordings cover 4 of 8 coach-language pairs; the other 4 exist only as device voices. If the same Chatterbox voices were ever used in the app, an English coach reading Spanish would sound like a different person (or a mismatch), and vice versa. Today (device TTS) the pairing is by gender and shared pitch/rate, with the code comments openly saying Ava and Sofía "share the only installed voice" when a device has one voice per language. Whether the owner needs full 8-pair coverage depends on whether the English-coach-answering-Spanish case is a product feature; the code treats it as supported ("Coaches answer in the user's language").

## Verdicts (recordings only; the shipping voices are the Apple device voices)

| Voice | Verdict | Why |
|---|---|---|
| **Ava (en)** | **PASS WITH FIXES** | English 0.998, WER 0%, clean, distinct from Ethan/Diego. Fixes: raise level (-25 LUFS), the 7.9 s join, Ava-vs-Sofía embedding is borderline (0.26), it is a clone of Kokoro af_heart (0.87), report JSON misses the first turn. |
| **Ethan (en)** | **PASS WITH FIXES** | English 0.995, WER 0%, most distinct voice of the four, most altered from its Kokoro reference. Fixes: true peak -0.7 dBTP and an unusually loud transient, normalise; no SQUIM; listen at 3.1 and 7.6 s. |
| **Sofía (es)** | **PASS WITH FIXES** (language yes; "Mexican" unproven) | Spanish 0.995, WER 0%. Fixes: muffled highs (3.2 kHz), the abrupt onset at 4.96 s, quiet, close to Diego by ECAPA (0.53), and the Mexican accent cannot be confirmed by any of these checks. Becomes FAIL if the listener hears Castilian or lisping. |
| **Diego (es)** | **PASS WITH FIXES** (language yes; "Mexican" unproven) | Spanish 0.997, WER 5% strict / 1.7% folded ("alargar" possibly clipped). Seseo-consistent on "cita". Fixes: similar to Sofía by ECAPA, quiet, native-ear dialect check. |

## What only a human ear can settle

1. Is the Spanish **Mexican** (the four sentences in section 3, native Mexican listener), not Castilian, not generic?
2. Do **Sofía and Diego sound like two different people** (ECAPA says close: 0.53), and Ava and Sofía (0.26)?
3. Do the voices sound like real people, or like stock Kokoro voices; are questions and the laugh ("¡Ja!", "Ha!") natural?
4. Joins at Ava 7.9 s, Ethan 3.1/7.6 s, Sofía 4.96/5.7 s, Diego 19.25 s: any clicks or clipped words? "alargar" at Diego about 10.5 s.
5. Is Sofía's dull sound acceptable, and does Diego's "cita" really sound like [s]?
6. How these compare with what users actually hear today: the Apple voices (Paulina/Juan, Ava/Evan, etc.) were not evaluated at all here.
