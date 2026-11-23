# Candidate portrait pipeline (reproducibility record)

These scripts made the **candidate** coach portraits in `assets/coaches/`,
which are pending owner approval. They are kept here so the steps in
`docs/legal/ASSET_PROVENANCE.md` can be re-run and reviewed. They are not
part of the app or of `flutter test`.

Environment:
- Python 3.13 with `torch` (CPU), `diffusers` 0.43, `spandrel`, `mediapipe`
  1.2.x, `opencv-python-headless` 4.10, and LivePortrait from
  `tool/avatar/setup.sh` (`AVATAR_TOOLS`).
- `DW_PORTRAIT_WORK` is a work folder. It holds:
  - the 4x Real-ESRGAN reference upscales `dw-ref/up-<coach>.png` and the
    crops `dw-ref/crop-<coach>.png`;
  - the MediaPipe model `fp/models/mc.tflite`;
  - the SD 1.5 inpainting weights `fp/sd-inpaint`
    (`stable-diffusion-v1-5/stable-diffusion-inpainting`, rev `8a4288a7`,
    fp16 files).

| Step | Script | What it does |
|--|--|--|
| 1 | `neutral.py <coaches> '<json params>'` | Level the head by rotating the whole image (LivePortrait 203-point eyes and mouth corners), then relax the mouth with LivePortrait retargeting. Params used: `{"lip":0,"smile":-0.6}`; Sofía `-0.3`; Ethan `+0.3`. |
| 2 | `style.py <coaches>` | Hair, lip and earring colour and stubble contrast in segmentation masks (`CFG` in the file). |
| 3 | `compose.py <coach> <seeds>` | 3:4 frame; SD 1.5 inpaints clothing, shoulders, outer hair and backdrop outside the protected face, hair and neck. Seeds used: Ava 3, Ethan 1, Sofía 1, Diego 1. |
| 4 | `finish.py <coach> <seed>` | Real-ESRGAN upscale of the generated layer, original face and hair composited back, per-coach backdrop recolour, shared grade, hero and avatar crops. |
| 5 | `herofix.py`, `herofix_run.py` | Fix round 2 helpers (lips, liner, patch fills, local SD inpaint, headroom). |
| 6 | `round3.py`, then `diego_r3.py`, `ava_r3b.py`, `headroom_all.py` and `ava_r3c.py` (steps `ear`, `crown`, `edges`; order in its header) | Fix round 3 local repairs, starting from 9b58790 for Ava and Sofía and from fa7da02 for Ethan and Diego. |
| gate | `portrait_intake.py <dir>` | Intake gate: identity ≥ 0.45 vs `tool/avatar/refs`, closest to own coach, eye tone, roll, sizes. Models come from `$AVATAR_TOOLS/models`. |
| gate | `iris.py <coach> <images>` | Iris colour vs the reference, compared at the same face scale. |

`herofix.py` points `AVATAR_TOOLS` at `$DW_PORTRAIT_WORK/avatar-tools` (the folder
`tool/avatar/setup.sh` creates); change it if yours is elsewhere.

The SD and LivePortrait steps are deterministic on CPU for a given seed and
library version, but different hardware or library versions can change the
pixels. The intake numbers in ASSET_PROVENANCE are the record.
