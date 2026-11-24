# MuseTalk 1.5 over Ditto (Ava): CPU research test, 2026-11-24

Research only. Nothing here goes to production.

## What ran
- Code: `TMElyralab/MuseTalk`, fresh shallow clone in `repo/` (commit 2536eaf, 2026-11-19). Official `scripts/inference.py` run unmodified, `--version v15 --batch_size 4`, fp32 on CPU. Defaults: `parsing_mode=jaw`, `extra_margin=10`. v1.5 forces `bbox_shift=0`.
- Environment: own venv `venv/` (uv, Python 3.10, torch 2.0.1+cpu, mmcv 2.0.1 CPU wheel, mmdet 3.1.0, mmpose 1.1.0). TensorFlow and gradio were left out. Install fixes I needed: `chumpy` must be built with `--no-build-isolation` (with pip installed in the venv), and `setuptools<70` is needed because mmengine imports `pkg_resources`. `/root/ditto/venv` was not touched.
- Weights were all downloaded anonymously with no token or login: `TMElyralab/MuseTalk` (musetalkV15 unet.pth + json), `stabilityai/sd-vae-ft-mse`, `openai/whisper-tiny`, `yzd-v/DWPose` (dw-ll_ucoco_384.pth), resnet18 from download.pytorch.org, and S3FD from adrianbulat.com (sha256 prefix matches the file name 619a3168). face-parse `79999_iter.pth` came from the official Google Drive id via drive.usercontent.google.com (53,289,463 bytes). Nothing needed a login. I did not download the LatentSync SyncNet: the repo uses it only as a training loss and has no offline eval script.
- Input: `ava-face.mp4` 26.0-36.0 s (inside the coach turn 22.21-37.16), 250 frames at 25 fps, plus the matching slice of `ava-coachonly.wav`. The window contains these bilabials: "im-p-ortant", "p-layful", "s-p-ecific", "want m-e", "b-ack-u-p".
- Rendering started only after `pgrep -f softsmile/inpaint.py` returned nothing (the job had already finished at 16:49).

## Timings and RAM (4 CPU cores, 10 s / 250 frames)
| Stage | Time | Per frame |
|---|---|---|
| Landmarks + bbox (S3FD + DWPose on 896x1080) | 10:39 | 2.6 s |
| UNet + VAE decode (63 batches of 4) | 9:48 | 2.35 s |
| Blend back with face parsing | 6:56 | 1.7 s |
| Model load, frame extract, VAE encode, ffmpeg | ~7:15 | |
| **Total wall** | **34.7 min (2081 s)** | **208 s of compute per 1 s of video** |

Peak RSS of the process tree was **7.84 GB**, sampled every 0.5 s with psutil (`tools/peakmem.py`, `run-stats.json`). That would not have fitted next to the 9 GB inpaint job. On CPU this is offline-only. A real-time deployment needs a GPU, as the research notes already said.

## Artifacts (all in this folder)
- `ava-musetalk-10s.mp4`: Ditto frames with the mouth re-synced by MuseTalk 1.5, with audio.
- `ava-ditto-10s.mp4`: the same 10 s of Ditto alone, with audio.
- `ava-compare.mp4`: side by side, Ditto on the left and MuseTalk on the right.
- `ava-lipclosure-sheet.jpg`: for each bilabial word, the most-closed frame of each clip (mouth crop and lip-gap value).
- `ava-mouth-strip-27.6s.jpg`: 10 consecutive frames ("dog get"), left vs right, to check jitter and teeth.
- `ava-frame-27.8s.jpg`, `ava-frame-32.7s.jpg`: full-face comparison frames.
- `ava-lipgap-plot.png`: lip gap over time (blue = Ditto, red = MuseTalk, grey = audio loudness).
- `metrics.json`: numbers below. Scripts are in `tools/` (`run.sh`, `peakmem.py`, `measure.py`); `run.log` is the full run log.

## Measurements (MediaPipe lip gap = landmarks 13-14 / face height)
| | Ditto | MuseTalk |
|---|---|---|
| Min lip gap in clip | 0.038 | **0.004** |
| Frames with lips closed (< 0.01) | 0 | 6 |
| Min gap in important / playful / specific / me / backup | 0.054 / 0.051 / 0.083 / 0.040 / 0.038 | 0.016 / 0.025 / 0.034 / 0.015 / 0.031 |
| Mean gap speaking / silent | 0.113 / 0.109 | 0.055 / 0.057 |
| Corr(lip gap, loudness), best lag | 0.12 (lag -1) | 0.03 (lag 0 is -0.13) |
| Lip-landmark jitter (mean abs 2nd diff, px) | 1.46 | 1.38 |

No SyncNet score: the repo has no offline lip-sync metric script.

## Observations
- **Lip closure: better.** The open grin is gone. Lips close or nearly close on "important" and "me", and the teeth are covered on most bilabials. Ditto never got below 0.038.
- **Articulation and sync: not better, possibly worse.** The mouth barely opens (mean gap halves), and lip gap does not follow loudness (corr about 0). Watching the strip, the motion is a small mumble with little difference between vowels. Neither the loudness correlation nor eyeballing showed MuseTalk syncing better than Ditto. Judge `ava-compare.mp4` by ear and eye.
- **Blur and texture:** the lower face is visibly softer (256 px inpaint). Freckles and skin texture disappear below the nose, and lip edges are soft. The seam is not obvious at normal size.
- **Teeth:** usually hidden. When visible, the upper incisors repeatedly show a dark notch that reads as a gap tooth or missing tooth (see the mouth strip and `ava-frame-27.8s.jpg`). This is a clear artifact.
- **Expression mismatch / identity drift:** the eyes and cheeks (from Ditto) still smile broadly, but the mouth is neutral. The face reads slightly different: narrower smile, softer jaw, paler lips. Eyes and the brown eye colour are unchanged because MuseTalk does not touch the upper face.
- **Jitter:** no bbox jump visible. Lip-landmark jitter is similar to Ditto's.

## Blockers / caveats
- None for running on CPU, but it is slow (about 3.5 min of compute per second of video) and needs about 8 GB RAM.
- Possible improvements I did not try (one run only): give MuseTalk a Ditto clip rendered with a less-smiling source or lower `--exp-scale` so the upper and lower face agree; tune `left/right_cheek_width` and `extra_margin`; restore the mouth with a face restorer (GFPGAN is Apache-2.0, but check its weights).

## Licence facts confirmed from files
- MuseTalk code: `LICENSE` = MIT (Tencent Music Entertainment Group, 2024).
- Weights: the HF model card front matter says `license: mit`. Repo `NOTICE`: "Model weight available trained on the HDTF and private dataset. Please, communicate with the HDTF owner about commercialization issues." The HF README says other models "must comply with their license, such as whisper, ft-mse-vae, dwpose, S3FD".
- sd-vae-ft-mse: HF card `license: mit`. whisper: MIT (NOTICE). DWPose weights: HF card `license: apache-2.0`.
- face-parsing.PyTorch code: MIT (NOTICE). The `79999_iter.pth` weights have no licence in the files. They are trained on CelebAMask-HQ (non-commercial research dataset, per the research notes, not re-verified here), so flag them for the owner.
- S3FD: code adapted from face-alignment (BSD-3, per the `musetalk/utils/face_detection/README.md` attribution). The weight file from adrianbulat.com has no licence stated in the repo.
- LatentSync SyncNet: Apache-2.0 (NOTICE). Training only; not downloaded.
- Installed package metadata: mmpose, mmdet, mmcv, mmengine Apache-2.0; diffusers, transformers Apache-2.0; torch BSD-3; chumpy MIT; librosa ISC; moviepy MIT; xtcocotools has no licence in its metadata. No GPL seen.
