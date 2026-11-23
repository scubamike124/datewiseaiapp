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

The first run calls `setup.sh`, which asks before installing everything
**outside the repo** in `$AVATAR_TOOLS` (default
`~/.cache/datewise-avatar-tools`, about 2.5 GB, no GPU; `AVATAR_YES=1` skips
the question). Every model comes from a pinned Hugging Face revision and is
checked by SHA-256 before use; PyTorch is pinned to 2.9.1 (`weights_only`
loading by default). `regenerate.sh` exits non-zero if any frame fails the
identity or eye-colour gate, and writes review sheets to
`build/avatar-review/`. Look at the sheets before committing.

Frames are made on the portrait scaled to at most 1080 px wide
(`--max-width`); the app decodes the portrait at that size on the voice stage,
so a large final portrait does not raise its memory use (the test keeps it
under 20 MB per coach). `manifest.json` records both sizes.

If a portrait changes and the frames are **not** regenerated, the app notices
(the portrait file's pixel size no longer matches `manifest.json`) and falls back
to the still portrait. A same-size replacement is not detected, so always
regenerate.

## What is generated (per coach)

| Group | Frames | Region blended |
|---|---|---|
| Mouth shapes | `mbp` (M B P), `a`/`a2`, `e`/`e2`, `i`/`i2`, `o`/`o2`, `u`/`u2` (full and half opening), `fv`, `l`, `th`, `cons` (T D N S K G R...), `sh` (SH CH J) | lips, chin and jaw, clipped at the jaw line |
| Eyes | `blink_half` (both eyes equally half closed), `blink_closed`, `gaze` (thinking: eyes up and aside) | eyes and lids |

`rest` is the approved portrait itself. `blink_half` is assembled per eye:
one eye-ratio setting closes the two eyes unevenly on a tilted or smiling
face (it read as a wink), so each eye takes the render whose opening (eye
outline area / width, from LivePortrait's landmarks) is closest to 45% of
its open size. `manifest.json` also records the lips' center and width,
which the app uses for the jaw drop (a mesh warp of the lower lip and chin,
zero at the patch border). Head motion (listening nods, tilts at
phrase starts, emphasis) is a small whole-image transform in the app, so no
frame warps the hair, a hand or the background.

Each frame is rendered by LivePortrait's keypoint retargeting (lip open/close,
eye open/close, smile, purse/grin, gaze) on a crop of 1.9x the face (more
pixels on the mouth than LivePortrait's default 2.3x), then:

1. its fine detail and grain are matched to the portrait inside the mask (an
   unsharp mask scaled to the portrait's high-frequency energy, then luma
   noise for any remaining difference; no face restoration);
2. it is blended into the **untouched** portrait inside a feathered mask. The
   mouth mask is clipped to the face contour from LivePortrait's 203-point
   landmarks, so a hand under the chin (Ethan) or the collar is never warped.
   Outside the mask the pixels are the original ones. Only the mask's
   bounding box is saved (JPEG q88).

Mouth-shape settings (`VISEMES` in `gen_frames.py`) assume a master with
closed, relaxed lips (the candidate final portraits). The earlier values
were tuned against a broad toothy smile (negative smile, strong purse) and
turned O and U into a pout on a neutral mouth; if a master with a smile is
ever used again, re-check the review sheets. Per-coach offsets
(`COACH_MOUTH`, `COACH_ROUNDED`, `COACH_A`, `COACH_SHAPES`) keep Ava's soft
smile through speech (0.3 on open shapes, 0.15 on rounded ones, with extra
purse so her teeth stay hidden) and give Ethan smaller, rounder O and U
openings.

Teeth (`teeth_tone`): the renderer's teeth come out grey, grey-green or
cyan, with dark gaps. Only the mouth opening is edited: pixels the renderer
changed, low in chroma, inside an ellipse around the portrait's lips and
with lip both above and below them (so stubble and the chin are never
selected). Teeth use a cut-off relative to the brightest teeth in the frame
(shaded teeth count), get one uniform lift toward the shared ivory (L* 74,
a* 1.5, b* 11.5; small O/U openings stay dimmer and are smoothed), and the
gaps between them are closed at a scale set by the mouth width.

Large portraits: YuNet misses faces of roughly 700 px and up, so
`lp_engine.py` and `verify.py` detect on a copy at most 1280 px on the long
side and map the box and points back (detection only; the frames are
rendered from the full-size portrait).

## Gate (verify.py)

Every frame must pass, or it is not written:

* SFace (Apache-2.0) similarity to the approved identity crop
  (`refs/crop-<coach>.png`, the same reference the portrait intake uses)
  >= 0.45, and higher than to any other coach;
* similarity to the portrait it came from >= 0.75;
* iris colour (CIELAB chroma/lightness of each iris) within 5 / 15 of the
  portrait's; a brown-to-blue or brown-to-green recolour is rejected
  (checked with a synthetic recolour test). Not applied to blink frames.
  The iris is sampled at the master's eye points: YuNet's points can jump
  20-30 px on an open-mouth frame, which sampled lids instead of the iris
  and flagged unchanged eye pixels. The gaze frame, which moves the irises,
  is sampled at its own points.

No face restoration (GFPGAN, CodeFormer) is used anywhere.

## Licences of the tools

| Tool | Licence | Used for |
|---|---|---|
| LivePortrait code (KwaiVGI, pinned commit) | MIT | keypoint retargeting, warping, rendering |
| LivePortrait human weights (HF `KlingTeam/LivePortrait`, incl. `landmark.onnx`) | MIT (model card) | same |
| InsightFace detector/landmarks | non-commercial | **not used, not downloaded**: replaced by YuNet |
| YuNet face detector (OpenCV Zoo) | MIT | face box and 5 landmarks for the crop and masks |
| SFace recogniser (OpenCV Zoo) | Apache-2.0 | identity gate |
| PyTorch 2.9.1 (CPU), OpenCV, NumPy, SciPy, onnxruntime | BSD / Apache-2.0 / MIT | runtime of the generator |
| Piper TTS (`eval/` only) | GPL-3.0 | offline review audio; never in the app or the repo |

The generated frames are derived from the owner's portraits and belong to the
owner; none of the tools ship in the app.

## Demo renderer and lip-sync evaluation

`render_demo_test.dart` renders frames with the app's own painter, animator
and timeline from a job file (text, word timings, audio length). `eval/`
reproduces the review videos and the numbers in the PR:

```sh
# 1. Audio + word timings (Piper TTS in its own venv; voices from rhasspy/piper-voices)
PIPER_PYTHON=<venv>/bin/python python3 tool/avatar/eval/make_jobs.py <demo>/jobs
# 2. Frames with the app's code (LipSyncDriver on a simulated clock).
#    AVATAR_DEMO_MODE: audio (default; native audio path, loudness only, iOS 15/16),
#    markers (+ iOS 17 word markers), words (flutter_tts fallback, word events only).
#    AVATAR_DEMO_NO_PNG=1 records only the shown shapes, for measurement.
AVATAR_DEMO_STATES=1 AVATAR_DEMO_JOBS=<demo>/jobs AVATAR_DEMO_OUT=<demo>/render \
  flutter test tool/avatar/render_demo_test.dart
# 3. MP4s, then the measurements
tool/avatar/eval/mux.sh <demo>
python3 tool/avatar/eval/analyze_sync.py <demo>/jobs <demo>/render      # timeline vs phonemes
python3 tool/avatar/eval/measure_av.py $AVATAR_TOOLS/models/yunet.onnx <demo>/*-e[ns].mp4   # video vs audio
```

`analyze_sync.py` compares the shown mouth shape with Piper's sample-exact
phoneme alignments (exact shape, openness correlation and lag, M/B/P
closures within ±80 ms, rest or held shapes while audio is audible).
`measure_av.py` measures the rendered video the way the visual reviewer did:
mouth-region difference from the idle frame, and a cavity-plus-teeth
openness proxy, each against the audio loudness, with the best lag over
±300 ms.
