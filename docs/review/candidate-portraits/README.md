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
| Lips / expression | nude-rose, closed, soft smile | berry, closed, soft smile | closed, relaxed | closed, soft smile |
| Facial hair | – | – | stubble softened | stubble denser and darker |
| Accessories | silver hoops (were gold) | gold hoops | – | – |
| Clothing (generated) | ivory collared shirt | black knit top | camel crew-neck sweater over a blue tee (his hand under the chin is gone) | light-blue chambray shirt over a dark tee |
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
- **Identity vs reference is lower than the interim's** (Sofía 0.70, Ava
  0.76, Ethan 0.83, Diego 0.87; gate ≥ 0.45), because the reference smiles
  with teeth and the candidates do not.
- **Artefacts kept from the source:** Diego's dark jaw outline. Also faint
  light wisps at the edge of Ava's hair, and generated clothing that looks
  slightly painterly up close (Ethan's knit, Diego's shirt).
- **Lip-sync proxy:** mouth openness tracks the audio better for Ava, Sofía
  and Diego (r 0.46–0.58, was 0.25–0.39). For Ethan it got worse on the
  automatic measure (−0.27 EN, 0.08 ES; was 0.47 / 0.50), although his
  frames open visibly in review. This is not resolved.
- **Demos** were rendered on the native-audio path only (AVATAR_DEMO_MODE=audio,
  the review path). The flutter_tts word-event path was not re-rendered. Its
  timing does not depend on the portraits.
- **Lighting warmth** was not varied between coaches; one shared grade is
  used.
- Not yet tested on an iPhone.

Details, licences and gate numbers: `docs/legal/ASSET_PROVENANCE.md`.
