# Independent QA of the on-device talking avatars (2026-11-24)

Scope: the owner-approved avatars (assets/avatar, lib/avatar, unchanged since de430f7). Videos are a SIMULATION drawn by
the app's own Dart code under `flutter test` on Linux (loudness path, iPhone stage 390×195 pt), not a device recording.
Not covered: GPU filtering, iOS audio latency, the iOS 17 word-marker path.

## Verdicts
| Coach | Verdict | Reason |
|---|---|---|
| Ava | PASS WITH FIXES | Clenched-teeth open vowels; strong `o` pout overused in English; red blotch on lower lip in a.jpg |
| Ethan | PASS | Best identity (SFace 0.81–0.90); minor teeth irregularity in a/l |
| Sofía | PASS WITH FIXES | Lowest identity (0.54 on a/a2; gate 0.45); uneven teeth, dark gap/spot in a.jpg; flat teeth band in i2/sh |
| Diego | PASS WITH FIXES | Crooked teeth with black gaps in a/a2/l; gaze eye colour Δab 4.4 (limit 5.0) |
| **Overall** | **PASS WITH FIXES** | No gate or test fails; clean at iPhone stage size; all fixes cosmetic; changed frames need owner re-approval |

## Checks
- regate.py: 76/76 frames pass (YuNet/SFace fetched at the pinned revisions; SHA-256 match). Eyes brown on every frame.
- Flutter avatar tests: 86/86 on an idle CPU. The AudioAlignment timing test failed once (153.9 ms vs 150 ms) while a
  render loaded the CPU; 17–18 ms on three re-runs. Load-sensitive: give it more headroom.
- Behaviour: jaw follows loudness (r 0.75–0.90); 7–10 mouth changes/s; blinks 150 ms every 2.8–6 s; seams are
  JPEG noise only (≤1.4 grey levels); 340–404 KB of patches per coach.

## Scores (1–10)
| Criterion | Ava | Ethan | Sofía | Diego |
|---|---|---|---|---|
| Identity | 8 | 9 | 7 | 9 |
| Eye colour | 9 | 8 | 10 | 8 |
| Seams/jumps | 9 | 9 | 9 | 9 |
| Mouth EN | 6 | 7 | 6 | 7 |
| Mouth ES | 7 | 7 | 7 | 7 |
| Blink | 8 | 8 | 8 | 8 |
| Listening/idle | 7 | 7 | 7 | 7 |
| iPhone-size artifacts | 8 | 9 | 8 | 8 |
| Full-size artifacts | 6 | 7 | 6 | 5 |
| Frame weight | 9 | 9 | 9 | 9 |

## Defects
Frames (need regeneration and owner re-approval):
1. a/a2/l (all coaches): teeth stay clenched; the jaw lowers the lip but no cavity opens. Acceptable at 390 pt.
2. diego a/a2/l: crooked teeth with black gaps (worst). 3. sofia a: dark gap and spot; i2/sh flat pale teeth band.
4. ava a: red blotch on the lower lip. 5. ethan a/a2/l: gappy lower teeth.
6. o/o2: strong "kiss" pout, overused for English o/au/or (about 13% of Ava's English frames).
7. u/u2/fv near-identical to rest on Ava and Sofía (no visible /f/).
8–10. gaze frames: Ava's eyes widen and lose lid shimmer; Ethan's right eye soft; Diego Δab 4.4.

Animation code (no frame changes):
11. A blink during "thinking" swaps the gaze frame for forward-looking blink frames.
12. Thinking→speaking: gaze snaps forward on the same frame the mouth opens (largest jump in every clip).
13. Listening is still apart from nods, breathing and sway.
14. Stage framing: on 390×195 pt the brows are cut off (mouth at 55% of stage height).
15. 0.3–0.6 s per clip of open mouth on near-silence (minor).

## Recommended fixes
- Code: hold gaze 100–150 ms into speech or exit through a blink; use gaze-preserving blinks while thinking; more
  headroom for the AudioAlignment timing test.
- Frames (owner re-approval, must pass regate): regenerate a/a2/l with parted teeth and a visible cavity (Diego,
  Sofía first); soften o/o2 or map English /oʊ/ /ɔ/ to o2; fix ava/a.jpg.
- Owner decision: mouth at about 60% of the stage height so the brows show.
- Before release: record the real app on iOS 16 and iOS 17 for one clip per coach.

Files: `videos/*-390px.mp4` (1× stage, labelled SIMULATION), `sheets/`, `frame-metrics.json`, `behaviour-metrics.json`.
