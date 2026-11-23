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
| Lips / expression | nude-rose (less gloss), closed, soft smile, lighter liner | soft berry (less gloss and outline), closed, soft smile | closed, soft smile (restored in fix round 1) | closed, soft smile |
| Facial hair | – | – | stubble softened | stubble denser and darker |
| Accessories | small studs, hoops removed (fix round 2) | gold hoops | – | – |
| Clothing (generated) | ivory collared shirt | black knit top | grey fine-knit turtleneck (re-generated in fix round 1; his hand under the chin is gone) | light-blue chambray shirt over a dark tee |
| Backdrop | dark teal | terracotta | slate blue | olive |

All four: the head is levelled, there are no teeth at rest, and the frame is
a 3:4 portrait. The face, eyes (brown) and features are the approved
pixels; the only change to the face itself is the relaxed mouth.

## Unmet targets, stated plainly

- **Face similarity between the pairs stays over the 0.5 goal:** Ava↔Sofía
  is 0.58 (interim 0.68; round 1 0.60) and Ethan↔Diego 0.64 (interim
  0.645). Ava's face now scores 0.48 against Sofía's approved reference.
  The faces were not changed, and the face matcher ignores hair, clothes
  and backdrop, so the pairs differ only by styling.
- **Sharpness:** each face comes from a reference about 100 px wide, enlarged
  about 10x. Faces look soft at full size, and the lips are not crisp.
- **Ava's head is turned about 13°** (goal ≤ 10°). It was left as is, because
  correcting it would re-render her face.
- **Identity vs reference** (hero; gate ≥ 0.45): Ava 0.74, Ethan 0.90,
  Sofía 0.70, Diego 0.87 (interim 0.87–0.91). Each is closest to its own
  coach. The reference smiles with teeth; the candidates do not.
- **Artefacts:** Diego's dark jaw outline from the source is softened, not
  gone. The generated clothing looks slightly painterly up close (Ethan's
  knit, Diego's shirt).
- **Lip-sync proxy:** the earlier Ethan figure of −0.27 was a measurement
  artefact. The old teeth test (HSV S < 70) missed his warm-lit teeth, and
  the dark term followed his collar. `measure_av.py` now looks only inside
  the lips and detects teeth by CIELAB lightness and a*.

  | Openness r vs audio (EN/ES) | Ava | Ethan | Sofía | Diego | Mean |
  |--|--|--|--|--|--|
  | Interim | 0.49/0.47 | 0.69/0.69 | 0.34/0.46 | 0.51/0.55 | 0.52 |
  | Candidate (round 2) | 0.64/0.60 | 0.49/0.55 | 0.51/0.70 | 0.66/0.59 | 0.59 |

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

Not done in round 1: hair-edge halos and grey patches; the hoop strand; Ava
vs Sofía looking like sisters; lips; teeth tint; Ava's smile in speech; O/U
shapes; Diego's chin seam, loops and specks. All of these are addressed in
round 2 below.

## Fix round 2

Done:
- Hair edges, all coaches:
  - Grey patches (the old backdrop showing between strands) and light
    rims are filled with hair colour and texture from the surrounding
    hair. This is a classical fill, not generation.
  - Ethan's blobby generated curls and Ava's crown and edge halo were
    re-inpainted locally with SD 1.5, with the face masked.
  - Stray specks over the backdrop were removed.
- Ava:
  - Hoops removed; only the small studs remain.
  - Lighter eyeliner wing.
  - Lips are less glossy, and the green tint in the cupid's bow is gone.
  - Ava↔Sofía face similarity is now 0.58 (was 0.60). Ava now scores 0.48
    against Sofía's reference.
- Sofía: berry lips with less saturation, gloss and outline.
- Diego:
  - Chin seam, forehead specks and the hair-loop "wire" over the forehead
    inpainted. The jaw geometry is unchanged.
  - Grey bits in the crown filled.
- Avatar frames:
  - The grey/cyan tint on the teeth in open-mouth frames is now warm and
    neutral. Only the teeth change.
  - Ava's mouth shapes keep her rest smile, so she no longer "pumps"
    between smiling and neutral.
  - O and U are rounder, with less opening.
- Coach cards: `heroFocus` is re-centred on the new portraits, so Ethan's
  head is not cropped.

Still open:
- Faint traces of the left hoop's gold top under Ava's earlobe.
- Slight blockiness where hair texture was borrowed along Sofía's top-right
  edge.
- Pair face similarity stays above 0.5 (Ava↔Sofía 0.58, Ethan↔Diego
  0.64); the faces are unchanged by design.
- Diego's M/B/P closures on the audio-only (iOS 15/16) demo path: the
  closures are there but land 0.1–0.2 s off the true phoneme. On the
  word-marker path he hits 100%.
- Per-coach lighting warmth.
- Not yet tested on an iPhone.

Details, licences and gate numbers: `docs/legal/ASSET_PROVENANCE.md`.
