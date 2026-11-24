# Independent review: Ava talking-avatar demo (`videos/ava-demo.mp4`)

Reviewer did not make the clip. Method: per-frame MediaPipe landmarks + blendshapes on all 981 frames
(`review-ava/perframe.json`, script `review-ava/perframe.py`), faster-whisper word timestamps on the coach track
(`review-ava/words.json`), mouth/eye/face crop strips at 5-25 fps with word labels (`review-ava/strip.py`), temporal
pixel-variance heat map, F0 analysis of the voice. Render settings (from `render_all.sh`): Ditto (antgroup), source
`ava-1-blazer.jpg`, `--exp-scale 1.5`, default emotion vector.

## Scores (1-10)

| Area | Score |
|---|---|
| Photorealism / "real person" impression | **5** |
| Identity preserved vs portrait | **8** |
| Eye colour / blink naturalness | **9 / 7** |
| Lip-sync accuracy and mouth shapes | **4** |
| Listening behaviour | **3** |
| Expression and head movement | **4** |
| Artefacts (higher = fewer) | **7** |
| Voice naturalness and fit | **6** (not heard directly, see below) |
| **Overall readiness for a premium app** | **4 - not ready** |

## Evidence

### Photorealism (5)
Any single still is photoreal: frame 0 is practically identical to the portrait (`review-ava/portrait_vs_frame0.jpg`),
and the frame with the largest head motion (5.84 s, nose shifted 44 px) is still clean (`review-ava/full_t5.84_maxhead.jpg`).
In motion the "animated photograph" look comes back for three reasons:
1. **The grin and teeth never go away.** For all 39 s she shows a broad, open, toothy smile. Mean smile blendshape is 0.92-0.96
   in every segment, and the lowest lip gap in the whole clip is 0.038 of face height (the teeth are always visible).
   Real people talking drop the smile between phrases.
2. **Only the head moves; the body is frozen.** Temporal std of the pixels is 0.2-0.5 grey levels on the background and
   blazer against 20 on the face (`review-ava/temporal_std_heatmap.jpg`). The shoulders don't rise with breathing and
   don't follow the head, so the effect is "head on a still photo".
3. Hair moves rigidly with the skull (hot edge along the right-hand hair line in the heat map) and has no life of its own.

### Identity (8)
Face shape, freckles, brows, nose, hair and blazer all match. Minus points: freckles and skin texture are visibly
softened (compare `review-ava/eyes_hires_portrait.jpg` with `review-ava/eyes_hires_t20.jpg`), and the teeth go mushy
when the mouth moves (see lip sync). Nobody would mistake her for a different person.

### Eyes (colour 9, blinks 7)
The irises stay **dark brown** all the way through, with the catchlight kept (`review-ava/eyes_hires_t20.jpg`). There are
10 blinks (15.3/min by the metrics script; the blendshape count is 10 at 2.88, 6.28, 9.28, 12.6, 15.68, 19.8, 23.4, 26.92,
30.96 and 34.6 s), which is a natural rate with natural spacing. Most blinks close for only 2 frames (80 ms), which is
short (100-150 ms is typical). The one at 26.92-26.96 s is a single-frame half closure with a smeared lid that reads as a
twitch or wink (`review-ava/eyes_blink_26.8-27.6.jpg`). The one at 30.96-31.04 s is good (`review-ava/eyes_wink_30.8-31.2.jpg`).
Gaze is locked on camera and never shifts, which is slightly uncanny over 39 s.

### Lip sync (4)
- The headline correlation of 0.468 is inflated by the contrast between speech and silence. **Inside the coach turns only,
  the correlation between mouth opening and loudness is 0.18 at lag 0 and 0.23 at +1 frame** (the mouth trails the audio
  by about 40 ms, which is acceptable). Mean mouth opening during pauses inside her turns is 0.108, nearly the same as
  while she is speaking (0.117).
- **Bilabials never close.** "me" in "Tell me" at 11.24-11.44 s narrows to 0.081 and then reopens with the teeth showing
  (`review-ava/mouth_tellme_10.9-12.1.jpg`). In "Want **m**e" (34.16 s) and "**b**ackup" (34.88-34.96 s) the lips narrow
  to about 0.04 but never seal; the upper teeth stay visible (`review-ava/mouth_wantme_backup_33.8-35.3.jpg`).
  "o**p**ener" at 23.52 s is the same.
- **There is no lip rounding.** "Oh", "Want", "opener" and "you" are all said with spread, smiling corners, with no pucker
  or funnel. Every viseme is a variation on one grin.
- **Wrong-phase openings:** at 11.48-11.80 s the audio is silent (rms 0.00) but the mouth is held open at 0.11-0.12; it
  then *closes* to 0.05 just as "what" starts (11.84-11.96 s).
- Good moments: "Ha!" at 22.16-22.56 s opens properly, with tongue and lower teeth visible
  (`review-ava/mouth_ha_opener_22.0-23.6_wide.jpg`), and "Tell" at 11.12-11.20 s shows the tongue.
- Teeth quality: the lower row smears into an indistinct band during speech (e.g. 11.00-11.08 s and 22.88-23.12 s),
  and the upper teeth lose their edges.

### Listening (3)
- First user turn (1.2-6.25 s): the head drifts and tilts (nose std about 11 px), but the face is the same fixed grin
  with no reaction (`review-ava/face_user1_listen_1-6.jpg`).
- Second user turn (15.6-21.6 s): **she is almost frozen**. Nose std is 1.7 px horizontal and 0.9 px vertical, the mouth
  holds a toothy grin at 0.053-0.086 for 6 s, and the only events are two blinks
  (`review-ava/mouth_listening_16-20_5fps.jpg`, `review-ava/face_user2_listen_16-21.jpg`).
- After she finishes (37.2-39.2 s) the head std is 0.5 px, i.e. a still photo.
- There are no nods, eyebrow raises, mouth softening or "mm-hm" micro-expressions. Driving the listening phase with
  silent audio gives either random drift or a freeze, never active listening.

### Expression and head movement (4)
Head motion inside her turns is plausible in size (up to about 6 px per frame around 10.0-11.1 s, a 44 px total range)
and not jerky. But the expression is the same beaming smile throughout, with no brow work tied to the questions
("what caught your eye?", "Want me to give you a backup line?"), and no change of intensity between turns. With exp-scale 1.5
on top of an open-mouth smiling source, the extra amplitude mostly goes into a wider grin and jaw drops (the
"Ha!" at 29.04 s is close to a cartoon laugh, `review-ava/face_coach2_29-31.jpg`), not into articulation.

### Artefacts (7)
- Clean: no background wobble (bokeh and windows have temporal std of 0.2-0.5), no neck seam, the blazer is stable, and
  the hair below the shoulders looks right in a side-by-side of 0 s and 5.84 s (`review-ava/neck_hair_t0_vs_t5.84.jpg`).
  The face was found in 100% of frames.
- Problems: teeth smearing, softened skin texture, the smeared single-frame eyelid at 26.96 s, rigid hair-shell motion,
  and the static torso. The neck lengthens slightly when the head rises 39 px at 5.84 s, but stays plausible.

### Voice (6, provisional)
I can't hear audio, so this is indirect. Whisper transcribes the coach lines word for word against the script. The pace
is 159 words/min, and the pitch is expressive (median F0 215 Hz, a 10-semitone p10-p90 range), which fits a young woman.
There are short pauses at the commas. A permanent wide grin matches an upbeat voice but not the calmer clauses ("It's
playful, it's specific..."). A human listener has to judge prosody and any Chatterbox artefacts before sign-off.

## Concrete improvements (in priority order)
1. **A new source portrait with the lips closed or a soft, closed-lip smile** (approved face, brown eyes, same identity
   gate). Ditto drives *relative* motion from the source, so a toothy open-smile source means the mouth can never close
   and every viseme stays a grin. This one change should fix the bilabials, the rounding, the constant teeth and much of
   the "photo" feel.
2. Then **drop exp-scale to about 1.1-1.25**. 1.5 was compensating for the open source and now exaggerates laughs and jaw drops.
   Try a neutral/calm `--emo` label rather than the averaged vector, and compare 2-3 seeds.
3. **A real listening state**: don't drive listening with silent audio. Use a pre-made idle/listening motion
   sequence (slow nods at the user's phrase ends, a slight smile change, a brow raise, small gaze shifts, a blink rate of
   about 15-20/min) and cross-fade into speech, or feed Ditto a low-level "listening" audio/motion prior if supported. Keep
   head motion consistent across both listening turns (now 11 px versus 1.7 px).
4. **Bilabial closure check**: use the word/phoneme timings (whisper or forced alignment) to verify or force lip closure on
   m/b/p frames. Add this as a metric to `lipsync.py`, along with correlation inside coach turns only (the current 0.468
   overstates sync).
5. **Teeth/skin detail**: test a commercially licensed face-restoration pass on the mouth region only (e.g. GFPGAN,
   Apache-2.0; avoid CodeFormer, which is non-commercial) at low blend, and check it doesn't change identity or iris colour.
6. **Body life**: add subtle torso/shoulder breathing (a 1-2 px vertical warp below the neck, about 0.25 Hz) and some
   hair-tip lag so the head isn't moving on a frozen photo.
7. Blink length: aim for 3-4 frame closures, and drop or smooth single-frame partial closures.
8. If a closed-mouth source plus settings still doesn't articulate visemes, evaluate an audio-driven mouth-inpainting stage
   on top of the Ditto head motion (license check first, per the reuse-first rule).

## Verdict
Good identity and eyes, and clean, stable frames, but the lip sync is weak (within-speech correlation about 0.2, no lip
closures, no rounding), the toothy grin never changes, and the listening is passive and partly frozen. It still reads as
an animated photograph. **Not ready for a premium app.** Re-render with a closed-mouth source and lower exp-scale before
any further judgement.
