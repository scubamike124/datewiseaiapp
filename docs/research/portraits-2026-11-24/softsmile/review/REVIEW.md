# Soft-smile mouth edits: independent visual review (research only)

Method: viewed full images, a phone-scale side-by-side (`review/phone-scale.png`), 2x mouth crops
(`review/*-mouth.png`, order: original | soft-3 | soft-17) and 3x artifact zooms (`review/zoom-*.png`).
Pixel diff vs. original: every variant's changes stay inside the mouth mask (outside-mask mean diff
< 0.02, max 15-42 only on the feathered mask edge). **Eyes, irises, hair, nose and background are
pixel-identical to the originals in all six variants, so the brown eye colour is preserved.**

Common to all variants: the eyes keep the original grin's squint and cheek lift, so the face reads
"smiling eyes, closed mouth". That looks natural enough (a soft Duchenne smile) and is acceptable.

## Scores (1-10)

| Coach | Variant | Identity | Mouth realism | Unintended changes | Eye colour |
|---|---|---|---|---|---|
| Ava | soft-3 | 8 | 4 | 6 | 10 |
| Ava | soft-17 | 8 | 7 | 7 | 10 |
| Ethan | soft-3 | 8 | 7 | 6 | 10 |
| Ethan | soft-17 | 7 | 5 | 6 | 10 |
| Sofia | soft-3 | 9 | 8 | 9 | 10 |
| Sofia | soft-17 | 8 | 6 | 7 | 10 |

## Ava (ava-1-blazer)

- **soft-3**: lips not actually closed. There is a dark parted gap with a tooth edge showing at
  centre-left, and the upper lip has a lopsided dip, so it reads as a smirk. New dark specks/moles
  appear in the mask area (left mouth corner, right of the right corner, below the left corner)
  plus a faint hair-like line on the chin. Fails the closed-lip goal.
- **soft-17**: lips cleanly closed with a believable seam and texture, and roughly symmetric.
  Defects: a yellow-green, waxy skin patch at the left mouth corner/nasolabial area (mask edge,
  visible at 2x and faintly on a phone), and the mouth is a little narrower than the original.
- **Pick: soft-17**, with a recommended touch-up: colour-match the left-corner skin patch to the
  surrounding skin, which you can do with a feathered blend from the original.

## Ethan (ethan-v3a2)

- **soft-3**: natural closed lips, good shape and symmetry. Defects: orange/brown blotches in the
  stubble under the left nostril and at the left mouth corner, and the moustache stubble above the
  lip is smeared and soft compared with the crisp stubble outside the mask, leaving a texture seam
  at the mask edge. The stubble also looks slightly denser, a minor identity drift.
- **soft-17**: the lower lip is swollen and glossy, with an odd fold or tuck at the left corner,
  as if the upper lip were rolled over it. It also has an orange blotch under the nose. On a phone
  it reads as a pout.
- **Pick: soft-3**, with a recommended touch-up: re-texture or colour-correct the stubble patches
  above the lip and at the left corner. These are noticeable on a phone in close crops but not at
  thumbnail size.

## Sofia (sofia-v3a1)

- **soft-3**: the best of the six. The closed lips are symmetric, with natural colour, texture
  and seam, and the smile lines match the cheeks. Only nit: the lip and philtrum texture is
  slightly softer than the surrounding skin, which you would not notice on a phone.
- **soft-17**: the lower lip is over-glossy and puffy with a white specular smear, there is a
  lighter patch above the upper lip, and the left nasolabial area has a crease/seam line.
- **Pick: soft-3**, usable as is.

## Blocking defects

- None of the picks is blocked outright. Ava soft-3 is rejected (lips parted, tooth visible, new
  moles). Ava soft-17 and Ethan soft-3 each need a small skin or stubble colour fix at the mask edge
  before production use.
- Identity: all picks remain clearly the same person, and the eyes are untouched.
- Not verified: how the animation model behaves on these images. This review covers stills only.
