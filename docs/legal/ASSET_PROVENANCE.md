# Asset provenance: coach portraits

Status: **candidate, pending owner approval.** The eight files below are a
*candidate* final set made locally from the approved interim portraits. They
are **not approved**. The owner must look at them and approve (or reject)
them before release. Until then they are in the same position as the interim
placeholders they replace (AI/voice QA report D10, D11, D12).

## What ships on this branch

| File | Pixels | SHA-256 (first 16) | Original pixels* |
|--|--|--|--|
| `assets/coaches/ava-hero.jpg` | 1784×2376 | `f72e0487eeb90728` | 56% |
| `assets/coaches/ava-avatar.jpg` | 1024×1024 | `d4a1344429aa37b9` | crop of the hero |
| `assets/coaches/ethan-hero.jpg` | 1832×2448 | `fe6b1af67dafb943` | 24% |
| `assets/coaches/ethan-avatar.jpg` | 1024×1024 | `c677a27eec5471e5` | crop of the hero |
| `assets/coaches/sofia-hero.jpg` | 1856×2472 | `586f9bd26aa15155` | 46% |
| `assets/coaches/sofia-avatar.jpg` | 1024×1024 | `5c750a9282fd4bf3` | crop of the hero |
| `assets/coaches/diego-hero.jpg` | 1968×2624 | `6de39cf58382d61e` | 27% |
| `assets/coaches/diego-avatar.jpg` | 1024×1024 | `24a54be45490a410` | crop of the hero |

\* Share of the hero whose pixels come from the approved portrait (the face,
hair and, except for Ethan, the upper neck). The rest (clothing, shoulders,
the parts of the hair outside the original crop, and the backdrop) was
**generated** (see "Processing").

The interim files they replace (1212×762 to 1228×658, hero = avatar) are in
git history at `45bbfd9`.

## Source

- **Origin:** the approved coach crops of the owner-supplied reference image
  (`ref-003`, about 314×198 px per coach; copies in `tool/avatar/refs/`),
  upscaled 4x with Real-ESRGAN (the interim portraits). The owner generated
  the reference images with ChatGPT (OpenAI image generation) on the owner's
  own account.
- **Not real people.** The coaches are AI characters. The portraits are
  illustrations of those characters, as the Terms of Use say ("Their portraits
  are illustrations of the coach characters").
- **No stock photography.** The former stock photo (`images/hero.jpg`) was
  removed from the app in `b36b0eb`; a test checks that only the coach
  portraits, the avatar patches derived from them (`assets/avatar/`), the
  icon and the fonts are bundled.
- **No new people were generated.** Every face is the approved face. No
  text-to-image generation of a person was used. No face swap and no face
  restoration (GFPGAN, CodeFormer) were used.
- **OWNER to record:** the generation date(s) and the account used for the
  reference images, and keep the original reference files.

## Processing (candidate set, 2026-11-23)

All steps ran locally on CPU. No image was sent to any service. No paid tool
or API was used.

1. **Head levelled.** The whole 4x-upscaled crop was rotated so the eyes and
   mouth corners are level (Ava 16.1°, Ethan 10.8°, Sofía 16.5°, Diego 12.1°).
   The angle comes from LivePortrait's 203-point landmarks. A rotation of the
   image does not change the face.
2. **Mouth relaxed (the one change to the face).** LivePortrait's own
   retargeting closed the lips and softened the smile, so no teeth show at
   rest (lip ratio 0; smile −0.6, or −0.3 for Sofía, to stay closer to her
   reference). Only a feathered mouth region, clipped at the jaw line, is
   blended in; eyes, nose, brows and face shape are the approved pixels.
3. **Non-face styling** (colour edits inside a segmentation mask; no
   generation): hair colour (Ava auburn, Sofía near-black, Ethan lighter
   chestnut, Diego near-black); lip colour (Ava nude-rose, Sofía berry);
   Ava's hoops recoloured silver (Sofía keeps gold); stubble contrast (Ethan
   slightly softer, Diego denser and darker; only the existing dark detail is
   scaled, nothing is drawn).
4. **Portrait framing (generated regions).** The frame was extended to a 3:4
   portrait. Stable Diffusion 1.5 inpainting generated everything outside a
   protected mask, at 512×680. The protected mask covers face skin plus a
   13 px margin (backdrop and clothing pixels inside that margin are not
   protected), hair, earrings and upper neck. Prompts named only clothing and
   a plain studio backdrop; negative prompts excluded hands, jewellery and
   bare chests. Outfits: Ava an ivory collared shirt, Ethan a camel crew-neck
   sweater over a blue tee (this replaces his hand under the chin; neck and
   collar are generated), Sofía a black knit top (generated grey, then
   recoloured), Diego a light-blue chambray shirt over a dark tee. The
   generated layer was upscaled (Real-ESRGAN x4 blended with Lanczos), and
   the original face and hair pixels were composited back on top at full
   resolution with a feathered seam.
5. **Backdrop and grade.** Each backdrop was recoloured to a dark, muted
   per-coach studio gradient (Ava teal, Ethan slate blue, Sofía terracotta,
   Diego olive). The recolour shifts the old colour, so hair edges keep their
   texture. The same gentle contrast curve, a light unsharp mask (no face
   restoration) and fine grain were applied to all four.
6. **Crops.** Hero = the full 3:4 frame, with the face box about 1024 px tall.
   Avatar = a square crop around the face, saved at 1024×1024, because YuNet
   (used by the intake and lip-sync tools) misses faces above about 700 px.

Tool chain: `fp/bin/{neutral,style,compose,finish,iris}.py` in the working
scratchpad. These are not in the repository.

### Tools and models

| Tool / model | Licence | Used for |
|--|--|--|
| Real-ESRGAN x4 weights (`ai-forever/Real-ESRGAN`) | BSD-3-Clause | 4x upscale of the reference crops; upscale of the generated layer |
| spandrel | MIT | loading the Real-ESRGAN weights |
| LivePortrait code + human weights (KwaiVGI / `KlingTeam/LivePortrait`) | MIT | mouth relaxation (step 2), landmarks for levelling |
| YuNet face detector, SFace recogniser (OpenCV Zoo) | MIT, Apache-2.0 | landmarks; identity gate |
| MediaPipe Tasks + Selfie Multiclass Segmentation model (256×256) | Apache-2.0 (library and model card) | hair, skin, clothing, accessory and backdrop masks |
| Stable Diffusion 1.5 inpainting (`stable-diffusion-v1-5/stable-diffusion-inpainting`, rev `8a4288a7`) | CreativeML OpenRAIL-M (commercial use allowed, with the licence's use restrictions) | clothing, shoulders, outer hair and backdrop (step 4) |
| diffusers, PyTorch (CPU), OpenCV, NumPy | Apache-2.0 / BSD / MIT | runtime |

OpenRAIL-M obligations: its use-based restrictions (Attachment A) apply to the
generated parts and must be passed on to anyone who redistributes the
*model*; the app ships only images, not the model. A copy of the licence
travels with the model on Hugging Face.

InsightFace (non-commercial) was **not** used; YuNet replaces it everywhere.

## Identity and quality gates (2026-11-23)

`portrait_intake.py` (outside the repo; YuNet + SFace): 8/8 accepted. The
thresholds are unchanged: identity ≥ 0.45 against the approved reference,
closest to its own coach, eye-tone shift within limits, avatar roll ≤ 8°,
hero portrait ≥ 1024×1400, avatar ≥ 1024. The only change to the script is
detection: when YuNet finds no face, it retries on a smaller copy (1280 or
1024 px), because it misses faces of about 700 px and up.

| Coach | Identity vs reference (hero / avatar) | Interim | Eye-tone shift hue / brightness (hero) | Avatar roll |
|--|--|--|--|--|
| Ava | 0.76 / 0.80 | 0.91 | 7.5 / 11.0 | 1.8° |
| Ethan | 0.83 / 0.86 | 0.91 | 4.8 / 35.3 | 2.2° |
| Sofía | 0.70 / 0.69 | 0.87 | 2.1 / 10.6 | 3.7° |
| Diego | 0.87 / 0.89 | 0.90 | 10.9 / 20.3 | 4.4° |

Identity drops from the interim scores because the approved reference smiles
broadly with teeth and the candidates have closed lips. Each candidate is
still closest to its own coach.

Explicit iris check: the mean CIELAB of the iris ring, compared at the
reference's face scale. Every candidate keeps brown irises (hue within 3° of
the reference; ΔE 5–9.5). On the same measure, the rejected GFPGAN images
shifted the iris hue by 32–74° (to blue or grey).

Cross-coach face similarity (SFace, hero):

| Pair | Interim | Candidate |
|--|--|--|
| Ava ↔ Sofía | 0.68 | 0.60 |
| Ethan ↔ Diego | 0.645 | 0.64 |

The earlier target of below 0.5 is **not met**. The faces were deliberately
not changed, and SFace looks only at the aligned face. The pairs now differ
by hair, clothing, accessories, lip colour and backdrop instead.

Known limits, for the owner's review:

- Detail is limited by the reference (about 100 px across each face). The
  face is upscaled about 10x in all and looks soft at full size.
- Ava's head is turned about 13° (yaw), over the 10° goal. Correcting the yaw
  would re-render the whole face, so it was left.
- Diego's dark jaw outline and Ethan's chin patch are in the approved source
  and were left as they are.
- Faint lighter wisps remain at the edge of Ava's hair.

## Animated frames (derived from the portraits)

- `assets/avatar/<coach>/*.jpg` are small patches generated offline from
  each `-hero.jpg`: 16 mouth shapes, two blink stages and a sideways glance
  (19 per coach, 76 in all; no whole-head frames). They were regenerated from
  the candidate heroes with `tool/avatar/regenerate.sh`, working on each hero
  scaled to 1080 px wide (the app decodes the hero at that size on the voice
  stage, at 15–16 MB per coach, under the 20 MB budget). All 76 passed the
  identity and iris gate. They were made with LivePortrait (MIT code and
  weights; InsightFace replaced by YuNet, MIT), with sharpness and grain
  matched to the portrait (no face restoration). Outside each patch's mask
  the pixels are the portrait's own. They are derivatives of the portraits
  above and follow their status. Pipeline and licences:
  `tool/avatar/README.md`.
- The app draws them on the device, timed to the device's own speech;
  nothing is sent to an avatar provider. Not described in the store text
  until it has been tested on an iPhone.

## Approval

| Item | Status |
|--|--|
| Candidate set made (this branch) | Done, 2026-11-23 |
| Owner review of the candidate set | **Pending (owner)** |
| Owner approval of the finals | **Pending (owner)** |
| This record signed off with the finals | **Pending (owner)** |

If the owner rejects the candidates, revert `assets/coaches/` and
`assets/avatar/` to `45bbfd9` (the interim set), or supply finals and run the
intake check and `tool/avatar/regenerate.sh`.
