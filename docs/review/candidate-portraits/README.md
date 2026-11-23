# Candidate coach portraits: owner review

**Status: CANDIDATE, pending owner approval. Nothing here is approved or final.**

These files open on an iPhone directly from GitHub. The videos are H.264/AAC
MP4 and play in iOS Safari.

| File | What it shows |
|--|--|
| `ava-sheet.jpg`, `ethan-sheet.jpg`, `sofia-sheet.jpg`, `diego-sheet.jpg` | Approved reference crop, interim portrait, candidate hero, candidate avatar |
| `all-four.jpg` | The four candidate heroes side by side, to judge how distinct they are |
| `{coach}-talking-en.mp4`, `{coach}-talking-es.mp4` | Talking demo per coach: one short sentence in English and one in Spanish, rendered with the app's own painter and lip-sync code from the candidate portrait. The voice is an offline Piper TTS review voice, not the app's voice. |

## What changed per coach (no face was replaced)

| | Ava | Sofía | Ethan | Diego |
|--|--|--|--|--|
| Hair | auburn (was brunette) | near-black (was brunette with highlights) | lighter chestnut | near-black |
| Lips / expression | nude-rose (less gloss), closed, soft smile | soft berry (less gloss and outline), closed, soft smile | closed, soft smile (restored in fix round 1) | closed, soft smile |
| Facial hair | – | – | stubble softened | stubble denser and darker |
| Accessories | no earrings (hoops removed, fix round 3) | gold hoops | – | – |
| Clothing (generated) | ivory collared shirt | black knit top | grey fine-knit turtleneck (re-generated in fix round 1; his hand under the chin is gone) | light-blue chambray shirt over a dark tee |
| Backdrop | dark teal | terracotta | slate blue | olive |

All four: the head is levelled, there are no teeth at rest, and the frame is
a 3:4 portrait. The face, eyes (brown) and features are the approved
pixels; the only change to the face itself is the relaxed mouth.

## Unmet targets, stated plainly

- **Face similarity between the pairs stays over the 0.5 goal:** Ava↔Sofía
  is 0.59 (interim 0.68) and Ethan↔Diego 0.64 (interim 0.645).
  The faces were not changed, and the face matcher ignores hair, clothes
  and backdrop, so the pairs differ only by styling.
- **Sharpness:** each face comes from a reference about 100 px wide, enlarged
  about 10x. Faces look soft at full size, and the lips are not crisp.
- **Ava's head is turned about 13°** (goal ≤ 10°). It was left as is, because
  correcting it would re-render her face.
- **Identity vs reference** (hero / avatar; gate ≥ 0.45): Ava 0.74 / 0.77,
  Ethan 0.89 / 0.91, Sofía 0.69 / 0.73, Diego 0.84 / 0.87 (interim 0.87–0.91). Each is closest to its own
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
  | Candidate (round 3) | 0.57/0.52 | 0.52/0.61 | 0.41/0.47 | 0.64/0.54 | 0.53 |
  | Candidate (round 4) | 0.55/0.48 | 0.52/0.60 | 0.41/0.47 | 0.66/0.57 | 0.53 |
  | Candidate (round 5) | 0.54/0.48 | 0.48/0.59 | 0.41/0.47 | 0.66/0.58 | 0.53 |

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

## Fix round 3

Ava and Sofía restart from the round-1 portraits; round 2's hair fill on
them is dropped. Ethan and Diego continue from round 2.

| Item | Status |
|--|--|
| Sofía's hair: smeared fill from round 2 | **FIXED** (reverted). Only her three reviewed grey patches were re-inpainted with narrow masks. Two read as hair now; the bottom-left one is still a light strip (**PARTIAL**). |
| Ava's ears: half-removed jewellery | **FIXED**: both hoops removed cleanly, no earrings; hair and earlobe only. |
| Ethan: orange disc at the left temple, ghost curls at the right temple | **FIXED** (re-inpainted as hair) |
| Diego: forehead smudge where the loop was | **FIXED** |
| Ava: crown blob, pale rim strands | Crown **FIXED** (smooth crown with a centre parting). Rim **PARTIAL**: the left edge is clean; a few pale strands remain on the right edge. |
| Diego: chin light/dark split | **PARTIAL**: mid-frequency shading equalised, but a faint central line remains |
| Diego: mottled crown | **FIXED** (re-inpainted) |
| Diego: neck seam | **PARTIAL**: softened, still faintly visible |
| Ava's eyeliner, both wings evenly | **NOT DONE**. The edit greyed the lashes, so it was reverted; her eyes are the round-1 pixels. |
| Visemes: `o`/`o2` teeth | **FIXED**: smaller opening, more purse; teeth mostly hidden on all four (review sheets) |
| Visemes: `a` shape | **PARTIAL**: opening reduced (lip 0.6 to 0.5). Ethan and Sofía still show a front-teeth gap in `a`. |
| Teeth colour | **FIXED**: brightened toward ivory (L* toward 82, a* 1.5, b* 10); `teeth_tone` uses one L* scale |
| Coach cards: full head with margin | **PARTIAL**. 150 px of backdrop was added above every head (crown completed where the hair reached the top), and `heroFocus` is (0, -1) for all four. Phone cards now show the hair with a margin, the eyes and the nose; the fade covers the mouth. iPad cards (wider) show the hair and the eyes, with the eyes in the fade. A card about 1.1:1 cannot show a 3:4 portrait's full head and chin at once. |
| Reproducibility | **FIXED**: scripts, parameters and the intake gate are in `tool/avatar/portrait/`. ES demos and the sync and AV measurement outputs are in `metrics/` here. |

Closures (M/B/P within ±80 ms; 53 closures, 8 clips), measured by the
coordinator per driver path at v2 `c0d9833`:

| Driver path | Closure hit rate |
|--|--|
| words (flutter_tts, the App Store default) | 0.73 |
| markers (iOS 17+ native path) | 0.85 |
| audio-only (iOS 15/16, off by default via `DW_AVATAR_AUDIO_PATH`) | 0.51 |

The demos here are rendered on the audio-only path; their `analyze_sync.py`
output is `metrics/sync_audio.txt` (mean closure hit 0.51, matching the
coordinator's audio-only figure; Diego EN 0/5). `metrics/av_final.txt` holds
the video-versus-audio measures. Round 3's smaller O/O2 opening lowered the
openness correlation from 0.59 to 0.53 (table above): rounder lips at the
cost of a weaker open/close signal on O.

## Fix round 4

| Item | Status |
|--|--|
| Coach cards (round 3 had pushed the faces into the fade) | **FIXED**. The card photo is now portrait-shaped (height 1.2 × the card width on phones, square on iPad) and aligned to the top of the portrait. The fade starts at 72%. Phone and iPad cards show the hair with a margin, the eyes, the nose and the smile above the fade, and nobody's curls are clipped. Other screens use per-coach `heroFocus` (round-2 framing, adjusted for the headroom). With taller cards, the bottom row's buttons sit partly under the tab bar in the ES 6.5" screenshot (the list scrolls). |
| Headroom band: streaks and a ladder line | **FIXED**: a smooth, grain-matched continuation of each backdrop; no seam at row 150 |
| Ava's right hair edge: glyph squiggles | **FIXED**: back to the round-1 pixels. The original pale rim strands are back with it (**PARTIAL** on the round-1 rim issue). |
| Ava: orange dots at the right jaw | **PARTIAL**: filled, but a faint bump remains on the jaw line |
| Diego's chin: grey ghost soul patch and dark crease | **FIXED** (back to round 2). The round-2 light/dark chin split and neck seam remain. |
| Men's teeth: chalk-white | **FIXED**: every coach's teeth now measure L* 71–73 and b* 9–11.5 (ivory) |
| Visemes: Ava's teeth on O, O2, U | **FIXED**: rounded shapes drop her smile offset and take extra purse |
| Visemes: `a` | **PARTIAL**: lip 0.44 for Ava, Ethan and Diego, and the dark gaps between teeth are filled toward the tooth colour. Some dark mouth interior between the rows remains. |
| Openness correlation | Unchanged at a mean of 0.53 (table above) |
| Sofía: blue speck above the crown | **FIXED**. Her bottom-left light strip is left as is (**not fixed**). |
| `portrait_intake.py` | **FIXED**: `import os` follows the docstring, default output is outside the repo (`~/dw-portrait-intake`), and it exits 1 on any rejection |

## Fix round 5

| Item | Status |
|--|--|
| Teeth: grey-green shaded teeth, dark gaps, grey/chalk tone | **FIXED** (`teeth_tone` rewritten). Teeth are found inside the mouth opening only (changed, low-chroma pixels inside an ellipse around the lips, with lip above and below), with a cut-off relative to the brightest teeth in the frame, so shaded teeth are included. One uniform lift per frame moves them to one shared ivory; gaps between teeth are closed at a scale set by the mouth width. Measured on `a`, `e`, `a2`, `e2`: L* 71.7–73.2, b* 10.9–12.0, a* 2.1–2.5 for all four coaches (round 4: men b* about 9.5, Sofía near chalk). Ethan's O, O2 and U openings are smaller and rounder (lip 0.08/0.07/0.05, purse 24/18/14), so no half-hidden grey teeth show; all coaches' `o` is now lip 0.10, purse 21. Ethan's `a` is lip 0.40. **PARTIAL** on Ethan's slightly uneven upper incisor in `a` (renderer geometry; smaller, not gone) and a thin dark line between the rows on Diego's `a`. |
| Ava: smile pumping on rounded shapes | **FIXED**: rounded shapes keep a smile offset of 0.15 (open shapes 0.3), with purse +6 and a smaller opening (O 0.09, O2 0.08, U 0.06), so her teeth stay hidden. |
| Ava's right side | **FIXED**: the pale crescent in the hair is now backdrop seen through the hair, the light lines in the teal backdrop are gone, and both jaw-edge specks are replaced by hair (the jaw line itself is not moved). No generation. |
| Diego: tick and dot in the soul patch, pale chin stripe | Tick and dot **FIXED** (tick contrast −29.7 → −7.5 L). Chin stripe **PARTIAL**: its lightness is matched to the stubble on both sides and it has the stubble texture from beside it; a faint seam is still visible at full size. Jaw geometry unchanged. The soul patch is no longer lifted to tooth colour on O2, U, U2 (a round-5 regression caught before push). |
| Sofía: bottom-left strip, blue-grey wisp at the crown | **FIXED** (wisp replaced by the backdrop above it; strip darkened to the hair beside it). |
| Coach cards | **FIXED**: the photo becomes the 120 pt strip whenever the cards stack (text scale above `CoachGrid.stackAboveScale`, 1.3), centred on the face; phone landscape uses 0.8 × the card width. New tests: iPad square photos, landscape 0.8, the strip at text scale 1.4 and 2.0, and the last card's button above the tab bar after scrolling at 375×667 (text 1.0 and 2.0). `coverDecodeWidth` is unchanged (optional item not done). |
| Screenshots | **FIXED**: the Coaches shots now scroll to the first position where no row or button is cut (the same helper as the privacy shot). In ES 6.5" and 6.9" every "Chatear con …" button is above the tab bar; all 30 screenshots were retaken with the round-5 portraits. |
| Openness r vs audio | Mean unchanged at 0.53 (table above). Ethan EN fell from 0.52 to 0.48: his O and U openings are smaller to hide the grey teeth. |
| `portrait_intake.py --apply` | **FIXED**: files are written only when all 8 pass; otherwise nothing is written and it exits 1. |
