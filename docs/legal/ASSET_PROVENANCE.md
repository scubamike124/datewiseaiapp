# Asset provenance: coach portraits

Status: **interim**. The eight files below are interim placeholders. The final
eight portraits are pending owner supply and approval (AI/voice QA report D10,
D11, D12).

## What ships today

| File | Pixels | SHA-256 (first 16) | Notes |
|--|--|--|--|
| `assets/coaches/ava-hero.jpg` | 1212×762 | `a9d87d2ba3a11d46` | Same image as the avatar |
| `assets/coaches/ava-avatar.jpg` | 1212×762 | `a9d87d2ba3a11d46` | |
| `assets/coaches/ethan-hero.jpg` | 1228×762 | `16974190a1ec55b2` | Same image as the avatar |
| `assets/coaches/ethan-avatar.jpg` | 1228×762 | `16974190a1ec55b2` | |
| `assets/coaches/sofia-hero.jpg` | 1212×658 | `4738c22f3579235b` | Same image as the avatar |
| `assets/coaches/sofia-avatar.jpg` | 1212×658 | `4738c22f3579235b` | |
| `assets/coaches/diego-hero.jpg` | 1228×658 | `6e3040631893221f` | Same image as the avatar |
| `assets/coaches/diego-avatar.jpg` | 1228×658 | `6e3040631893221f` | |

Added in commit `0037076` (2026-11-22).

## Source

- **Origin:** interim crops of reference images supplied by the owner. The
  owner generated those reference images with ChatGPT (OpenAI image
  generation) on the owner's own account.
- **Not real people.** The coaches are AI characters. The portraits are
  illustrations of those characters, as the Terms of Use say ("Their portraits
  are illustrations of the coach characters").
- **No stock photography.** The former stock photo (`images/hero.jpg`) was
  removed from the app in `b36b0eb`; a test checks that only the coach
  portraits, the icon and the fonts are bundled.
- **OWNER to record:** the generation date(s) and the account used, and keep
  the original reference files.

## Processing

1. Crop of each coach from the owner-supplied reference image.
2. 4x upscale with **Real-ESRGAN** (x4 model; code and released weights
   under the BSD-3-Clause licence), run through **spandrel** (MIT), the
   model-loading library. Run locally; no image was sent to any service.
3. Saved as JPEG. Hero and avatar are currently the same file per coach.

No face swap, retouching of identity, or generative editing was applied after
the upscale.

## Identity check

Each file was checked against its approved reference with a local script
(`portrait_intake.py`, kept outside the repository) built on OpenCV
(Apache-2.0) with:

- **YuNet** face detector (MIT), `face_detection_yunet` from the OpenCV Zoo;
- **SFace** face recognizer (Apache-2.0), `face_recognition_sface` from the
  OpenCV Zoo.

Result (2026-11-22): every file matches its own reference best (cosine
similarity 0.87–0.91), so no faces are swapped. All eight fail the intake
size rules (hero must be portrait, at least 1024×1400; avatar short side at
least 1024). Same-language pairs look alike (Ava↔Sofía about 0.71,
Ethan↔Diego about 0.68); the finals should differ in hair, wardrobe,
accessories and background, with cross-coach similarity below 0.5.

## Animated frames (derived from the portraits)

- `assets/avatar/<coach>/*.jpg` are small patches (mouth shapes, blinks,
  nods, a thinking look) generated offline from each `-hero.jpg` with
  LivePortrait (MIT code and weights; InsightFace replaced by YuNet, MIT) and
  gated by SFace identity and iris-colour checks. Outside each patch's mask
  the pixels are the original portrait. They are derivatives of the portraits
  above and follow their status. Pipeline and licences: `tool/avatar/README.md`.
- The app composites them on the device (lip-synced to the device's own
  speech); nothing is sent to an avatar provider.
- When the finals arrive, run `tool/avatar/regenerate.sh` after the intake
  check.

## Final portraits (pending)

- The owner supplies eight finals: `{ava,ethan,sofia,diego}-{hero,avatar}.jpg`,
  hero at least 1024×1400 portrait, avatar at least 1024 on the short side.
- Run the identity and size check on them, re-check `heroFocus` /
  `avatarFocus` in `lib/models/coach.dart`, regenerate the animated frames
  (`tool/avatar/regenerate.sh`) and the App Store screenshots.
- Then update this file: per-file source, generation date and account,
  processing, and the owner's approval date.

| Item | Status |
|--|--|
| Final 8 portraits supplied | Pending (owner) |
| Owner approval of the finals | Pending (owner) |
| This record signed off with the finals | Pending (owner) |
