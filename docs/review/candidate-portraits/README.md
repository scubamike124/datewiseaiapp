# Candidate coach portraits: owner review

**Status: CANDIDATE, pending owner approval. Nothing here is approved or final.**

These files open on an iPhone directly from GitHub. The videos are H.264/AAC
MP4 and play in iOS Safari.

| File | What it shows |
|--|--|
| `ava-sheet.jpg`, `ethan-sheet.jpg`, `sofia-sheet.jpg`, `diego-sheet.jpg` | Approved reference crop, interim portrait, candidate hero, candidate avatar |
| `all-four.jpg` | The four candidate heroes side by side, to judge how distinct they are |
| `ava-talking-en.mp4`, `ethan-talking-en.mp4`, `sofia-talking-en.mp4`, `diego-talking-en.mp4` | Talking demo per coach: one short English sentence, rendered with the app's own painter and lip-sync code from the candidate portrait. The voice is an offline Piper TTS review voice, not the app's voice. |

## What changed per coach (no face was replaced)

| | Ava | Sofía | Ethan | Diego |
|--|--|--|--|--|
| Hair | auburn (was brunette) | near-black (was brunette with highlights) | lighter chestnut | near-black |
| Lips / expression | nude-rose, closed, soft smile | berry, closed, soft smile | closed, soft smile (restored in fix round 1) | closed, soft smile |
| Facial hair | – | – | stubble softened | stubble denser and darker |
| Accessories | silver hoops (were gold) | gold hoops | – | – |
| Clothing (generated) | ivory collared shirt | black knit top | grey fine-knit turtleneck (re-generated in fix round 1; his hand under the chin is gone) | light-blue chambray shirt over a dark tee |
| Backdrop | dark teal | terracotta | slate blue | olive |

All four: the head is levelled, there are no teeth at rest, and the frame is
a 3:4 portrait. The face, eyes (brown) and features are the approved
pixels; the only change to the face itself is the relaxed mouth.

## Unmet targets, stated plainly

- **Face similarity between the pairs stays high:** Ava↔Sofía 0.60 (was
  0.68), Ethan↔Diego 0.64 (was 0.645); the goal was below 0.5. The faces
  were not changed, and the face matcher ignores hair, clothes and backdrop,
  so the pairs differ only by styling.
- **Sharpness:** each face comes from a reference about 100 px wide, enlarged
  about 10x. Faces look soft at full size, and the lips are not crisp.
- **Ava's head is turned about 13°** (goal ≤ 10°). It was left as is, because
  correcting it would re-render her face.
- **Identity vs reference** (hero; gate ≥ 0.45): Ava 0.76, Ethan 0.90,
  Sofía 0.70, Diego 0.87 (interim 0.87–0.91). Each is closest to its own
  coach. The reference smiles with teeth; the candidates do not.
- **Artefacts kept from the source:** Diego's dark jaw outline. Also faint
  light wisps at the edge of Ava's hair, and generated clothing that looks
  slightly painterly up close (Ethan's knit, Diego's shirt).
- **Lip-sync proxy:** the earlier Ethan figure of −0.27 was a measurement
  artefact. The old teeth test (HSV S < 70) missed his warm-lit teeth, and
  the dark term followed his collar. `measure_av.py` now looks only inside
  the lips and detects teeth by CIELAB lightness and a*.

  | Openness r vs audio (EN/ES) | Ava | Ethan | Sofía | Diego | Mean |
  |--|--|--|--|--|--|
  | Interim | 0.49/0.47 | 0.69/0.69 | 0.34/0.46 | 0.51/0.55 | 0.52 |
  | Candidate | 0.62/0.56 | 0.51/0.55 | 0.53/0.58 | 0.65/0.63 | 0.58 |

  Ethan stays below his interim figure; the interim showed teeth at rest.
- **Demos** were rendered on the native-audio path only (AVATAR_DEMO_MODE=audio,
  the review path). The flutter_tts word-event path was not re-rendered. Its
  timing does not depend on the portraits.
- **Lighting warmth** was not varied between coaches; one shared grade is
  used.
- Not yet tested on an iPhone.

## Fix round 1 (visual review of PR #40)

Done:
- Ethan re-generated: natural symmetric shoulders, a fine-knit turtleneck,
  and a soft closed-mouth smile. Identity rose to 0.90.
- Diego: the black jaw and neck outlines from the source are inpainted into
  a soft shadow (same jaw geometry). The crosshatch texture on the shirt is
  smoothed and the dark seam band at the bottom removed. The avatar crop is
  moved up so his hair is not clipped.
- Ava: the gold stud on her left ear is now silver.
- Measurement fixed (above). Large portraits decode near their layout size
  (the decoded-memory regression), with a test.

Not done in this round (still open):
- Hair-edge halos and grey patches (Ethan's hair top, including blobby
  generated curls; Ava's streaks; Sofía's patches and outline).
- The orange strand at the top of Ava's left hoop.
- Ava vs Sofía still read as sisters. Ava keeps the hoops and the liner.
- Sofía's lips (outline, gloss, saturation).
- Ava's waxy lips and green cupid's bow.
- Teeth tint in open-mouth frames.
- Ava's smile drops while she speaks.
- Rounder O/U vowels.
- Diego's chin seam, hair loops and specks, and his M/B/P closures.
- Per-coach lighting warmth.

Details, licences and gate numbers: `docs/legal/ASSET_PROVENANCE.md`.
