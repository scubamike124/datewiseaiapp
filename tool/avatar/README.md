# Talking-avatar frame generator

The voice stage animates each coach from small photo patches generated
**offline** from the coach's approved portrait. The app composites them on the
device (`lib/avatar/`); nothing is generated or streamed at runtime.

## Regenerate (one command)

After replacing any portrait in `assets/coaches/` (for example with the
owner's final portraits, after they pass the portrait intake check):

```sh
tool/avatar/regenerate.sh            # all four coaches, ~2-3 min each on 4 CPU cores
flutter test test/avatar_widget_test.dart
```

The first run calls `setup.sh`, which installs everything **outside the repo**
in `$AVATAR_TOOLS` (default `~/.cache/datewise-avatar-tools`, about 2.5 GB, no
GPU). `regenerate.sh` exits non-zero if any frame fails the identity or
eye-colour gate, and writes review sheets to `build/avatar-review/`.
Look at the sheets before committing.

If a portrait changes and the frames are **not** regenerated, the app notices
(the portrait's pixel size no longer matches `manifest.json`) and falls back
to the still portrait. A same-size replacement is not detected, so always
regenerate.

## What is generated (per coach)

| Group | Frames | Region blended |
|---|---|---|
| Mouth shapes (visemes) | `mbp` (M B P), `a`, `e`, `i`, `o`, `u` (U/W), `fv`, `l`, `th`, `cons` (T D N S K G R CH...) | lips, chin, jaw |
| Blinks | `blink_half`, `blink_closed` | eyes and lids |
| Expressions | `nod_1`, `nod_2` (listening nod), `attentive` (brows), `think` (eyes up/aside, lips closed) | whole head |

`rest` is the approved portrait itself. Each frame is rendered by
LivePortrait's keypoint retargeting (lip open/close, eye open/close, smile,
purse/grin, brows, gaze, small head pitch/roll), then blended into the
**untouched** portrait inside a feathered mask; outside the mask the pixels are
the original ones. Only the mask's bounding box is saved (JPEG q88).

## Gate (verify.py)

Every frame must pass, or it is not written:

* SFace (Apache-2.0) similarity to the approved identity crop
  (`refs/crop-<coach>.png`, the same reference the portrait intake uses)
  >= 0.45, and higher than to any other coach;
* similarity to the portrait it came from >= 0.75;
* iris colour (CIELAB chroma/lightness of each iris) within 5 / 15 of the
  portrait's; a brown-to-blue or brown-to-green recolour is rejected
  (checked with a synthetic recolour test). Not applied to blink frames.

No face restoration (GFPGAN, CodeFormer) is used anywhere.

## Licences of the tools

| Tool | Licence | Used for |
|---|---|---|
| LivePortrait code (KwaiVGI, pinned commit) | MIT | keypoint retargeting, warping, rendering |
| LivePortrait human weights (HF `KlingTeam/LivePortrait`, incl. `landmark.onnx`) | MIT (model card) | same |
| InsightFace detector/landmarks | non-commercial | **not used, not downloaded**: replaced by YuNet |
| YuNet face detector (OpenCV Zoo) | MIT | face box and 5 landmarks for the crop and masks |
| SFace recogniser (OpenCV Zoo) | Apache-2.0 | identity gate |
| PyTorch (CPU), OpenCV, NumPy, SciPy, onnxruntime | BSD / Apache-2.0 / MIT | runtime of the generator |

The generated frames are derived from the owner's portraits and belong to the
owner; none of the tools ship in the app.

## Demo renderer

`render_demo_test.dart` renders frames with the app's own painter and
timeline from a job file (text, word timings, audio length), for review videos:

```sh
AVATAR_DEMO_JOBS=<jobs dir> AVATAR_DEMO_OUT=<out dir> flutter test tool/avatar/render_demo_test.dart
```
