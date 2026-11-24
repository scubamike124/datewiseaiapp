# Ava portraits, round 3: blazer vs sweater review

Reviewer: independent photo-editor pass, 2026-11-24. All images 896x1152, viewed in full and with the lower half (y 650-1152) cropped out and enlarged.
Face and hair match the sweater originals in every case. Only the clothing was judged.

## Per-image verdicts

### ava-v2b3-blazer-23: 7/10, KEEP (crop)
- Outfit: navy waistcoat/vest over an ivory blouse, with an ivory jacket sleeve on the right shoulder. It reads as smart-casual more than a blazer. The navy fabric has believable weave and shading.
- Artefacts: the blouse cuff has a fussy beaded or picot edge, and there is a small white ruffle under the hand at the neckline. Both look slightly costume-like.
- Boundaries: hair over the vest and sleeve is clean, with no halos or smears and no hair cut off.
- Hand: unchanged from the original. It has 4 fingers plus a hidden thumb, which is plausible, but it is still distracting.
- Neckline: modest and appropriate.
- Cropping out the hand (bottom edge at about y=830) also removes the cuff and ruffle. What remains is a clean navy/ivory shoulder that reads as professional.

### ava-v2b3-blazer-11: 3/10, REJECT
- There is no top under the jacket. Bare skin runs from the throat down past the sternum, which is a plunging neckline and inappropriate for a coach.
- The left sleeve is beige with a beaded cuff and the right lapel is white, so the two halves don't match.
- There is a stray gold bar pin on the lapel.
- The notch lapel itself is well drawn.

### ava-b1-blazer-23: 6/10, KEEP WITH CROP (borderline)
- Outfit: ivory blazer with a believable notch lapel and buttonhole stitch, worn over a navy shirt. The shirt button is realistic.
- Artefact: the shirt is asymmetric. The left side shows a white collar and the right side a navy placket, as if two different shirts were merged. It is noticeable at full size and less so at phone size.
- Artefact: there is a dark, jagged vertical seam at the far-left edge (x about 30-50, y about 800-1000), where the sleeve meets the chair.
- The thin necklace chain is fine. The neckline opens to bare chest below the chain at the bottom of the frame.
- Boundaries: hair over the lapels is clean.

### ava-b1-blazer-11: 3/10, REJECT
- No top under the blazer. The deep V of bare chest runs to the bottom of the frame, which is not professional.
- There is an odd squiggle/stitch mark on the lapel (about x=710, y=1020).
- There is a faint jagged "neckline" line drawn across the skin.

### ava-v2b4-blazer-23: 4/10, REJECT
- The "blazer" has no lapels. A flat navy vertical band runs down one side like a sash or apron strap, over a white tee, and it looks unnatural.
- There is a hard straight seam line on the right forearm sleeve.
- The left front edge is ambiguous.
- Hair boundaries are clean and the neckline is modest, but the garment does not read as real clothing.

### ava-v2b4-blazer-11: 8/10, KEEP (best of set)
- Outfit: stone/ivory single-breasted blazer with a correct notch lapel, a welt chest pocket, natural sleeve creases and a navy top underneath. This is the most convincing tailoring in the set.
- Neckline: modest navy V, appropriate.
- Odd object: a small crystal teardrop lapel pin (about x=600, y=815). It is minor, but it should be retouched out or accepted knowingly.
- Bottom edge (about y=1095-1152): crossed hands and cuffs are smeared, and there is a dark watch/cuff blob near x=410. Crop the bottom by about 60-90 px.
- Boundaries: hair over the lapel and left shoulder is clean, with no halo.

## Sweater originals (baseline)
- ava-v2b3-iris: realistic knit, but the hand is prominent at the bottom. Approachable, not professional.
- ava-b1-iris: realistic knit with a clean crew neck and no artefacts. Very approachable, casual.
- ava-v2b4-iris: realistic knit, with a cuff/hand sliver at the bottom edge. Casual.

## Final 3 for the owner (one per pose)

| Pose | Pick | Crop / fix |
|------|------|------------|
| v2b3 | ava-v2b3-blazer-23 | Crop the bottom to about y=830 (896x830) so the hand, beaded cuff and ruffle are gone. That leaves face, hair and a navy/ivory shoulder. |
| b1 | ava-b1-blazer-23 (fallback: ava-b1-iris sweater) | Trim about 56 px from the left (removes the jagged edge seam) and crop the bottom to about y=1000 (hides the open chest). The asymmetric white-collar/navy-shirt mismatch remains. If the owner notices it, use the sweater original, which is flawless but casual. |
| v2b4 | ava-v2b4-blazer-11 | Crop the bottom to about y=1080 to remove the smeared hands/cuffs. Optionally clone out the crystal lapel pin. |

Rejected: v2b3-blazer-11, b1-blazer-11 (no top under the jacket, plunging neckline) and v2b4-blazer-23 (lapel-less navy strip).
