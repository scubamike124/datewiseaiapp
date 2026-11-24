# Ditto talking-head on CPU (no GPU, no InsightFace)

Status: **works**. Tested 2026-11-24 on a 4-core Xeon @ 2.3 GHz (AVX-512 BF16 / AMX), 15 GB RAM.

Folder abbreviation used below: `S=/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad`

## 1. Install (exact commands)

```bash
mkdir -p /root/ditto && cd /root/ditto
git clone --depth 1 https://github.com/antgroup/ditto-talkinghead.git repo    # commit c3e47eee2e626500017a0556b470d6d4182f85e8
uv venv /root/ditto/venv -p 3.11
VIRTUAL_ENV=/root/ditto/venv uv pip install --index-url https://download.pytorch.org/whl/cpu torch torchvision torchaudio
VIRTUAL_ENV=/root/ditto/venv uv pip install librosa tqdm filetype imageio imageio-ffmpeg opencv-python-headless \
    scikit-image cython colored "numpy<2.2" onnxruntime mediapipe einops

# weights (anonymous HF download). The InsightFace files det_10g.onnx / 2d106det.onnx are deliberately NOT downloaded.
mkdir -p /root/ditto/checkpoints && cd /root/ditto/checkpoints
for f in ditto_cfg/v0.4_hubert_cfg_pytorch.pkl \
         ditto_pytorch/aux_models/face_landmarker.task \
         ditto_pytorch/aux_models/hubert_streaming_fix_kv.onnx \
         ditto_pytorch/aux_models/landmark203.onnx \
         ditto_pytorch/models/{appearance_extractor,decoder,lmdm_v0.4_hubert,motion_extractor,stitch_network,warp_network}.pth \
         LICENSE README.md; do
  mkdir -p "$(dirname "$f")"
  curl -sfL -o "$f" "https://huggingface.co/digital-avatar/ditto-talkinghead/resolve/main/$f"
done
```

Versions installed: torch 2.15.0+cpu, onnxruntime 1.32.0, mediapipe 1.2.3, numpy 2.1.3, opencv-python-headless 5.1.0.95,
librosa 0.11.0, imageio 2.38.2, scikit-image 0.26.0, einops 0.8.2. Disk: venv 2.2 GB, checkpoints 2.2 GB.

## 2. Run

```bash
/root/ditto/venv/bin/python $S/avatar2/make_clip.py IMAGE.jpg AUDIO.wav OUT.mp4 [--exp-scale 1.4] [--emo N] [--steps 50]
```

* Any audio format/rate works (converted to 16 kHz mono internally). The output is H.264 (CRF 14) plus AAC audio at
  25 fps, the same size as the source image (max side 1920).
* **Resumable**: work files go in `OUT.mp4.work/`. The audio-to-motion result is saved once, and frames are rendered in
  100-frame (4 s) chunks, each written as a finished mp4 segment. After a crash or restart, rerun the same command and
  it continues from the next unfinished chunk (tested: killed after chunk 1, rerun rendered only chunk 2). The script
  refuses to resume if the settings differ; delete the `.work` dir to start over. On success the work dir is deleted
  unless you pass `--keep-work`.
* Run it in the background with a log, e.g. `nohup ... > clip.log 2>&1 &`. Progress lines start with `[render]`.
* Options: `--exp-scale` (expression/lip amplitude), `--emo 0-7` (Ditto emotion label; the default is the cfg's
  averaged emotion vector), `--steps` (diffusion steps, default 50; this stage is only about 10 s per 8 s clip, so it is
  not worth lowering), `--seed`, `--delta-pitch` (cfg default +2 degrees), `--chunk`, `--threads` (default 4),
  `--fp32` (disable bf16).

## 3. What was patched / replaced

The clone is **unmodified** (`git status` clean). Everything is done with runtime patches inside `make_clip.py`, which
lives outside the clone:

| Patch | Why |
|---|---|
| Config pkl loaded with a restricted unpickler (only numpy `_reconstruct` / `ndarray` / `dtype` allowed) | Untrusted pickle. Its opcodes were inspected first: only numpy globals. |
| Every `device` in the cfg set to `"cpu"`; `SDK.audio2motion.lmdm.model.device = "cpu"` | The cfg hard-codes cuda, and LMDM's inner nn.Module has its own `device='cuda'` default that `create_model()` never overrides. |
| `torch.autocast(device_type="cpu", dtype=float16)` turned into **bf16** autocast (or disabled with `--fp32`) | Ditto wraps the extractor, warp and decoder in fp16 autocast, which is meant for CUDA. bf16 vs fp32 on real frames: PSNR 52 dB (no visible difference), and about 2.5x faster on this AMX CPU. |
| `torch.load(..., weights_only=True)` forced | Untrusted .pth files (torch 2.15 already defaults to this). |
| `core.utils.blend` replaced by a numpy blend | Avoids pyximport compiling the repo's Cython/C at import time. Same formula. |
| Ditto's threaded `StreamSDK` workers replaced by our own sequential loop (motion, then chunked render) | Needed for resumable chunks. The motion maths is the same code path as `_audio2motion_offline`. |
| **InsightFace det_10g (SCRFD) + 2d106det replaced by MediaPipe Face Landmarker** | Licence (InsightFace weights are non-commercial). See below. |

### InsightFace replacement (exact)

In Ditto these two models are used in exactly one place: `core/atomic_components/source2info.py: Source2Info._crop()`,
for the first rough crop of the source image (box, then 106 landmarks, then `crop_image(scale=1.5)` to make a 224x224
crop for `landmark203`, which then makes the real 512x512 crop). `crop_image` only uses (a) the two eye centres
(106-idx 33/35/40/39 and 87/89/94/93) and the two mouth corners (106-idx 52 and 61) for the face's vertical axis and
roll, and (b) the overall point extent for the crop centre and size.

* `s2i.InsightFaceDet` is replaced by `MPFaceDet`: the MediaPipe Face Landmarker (`face_landmarker.task`, Apache-2.0,
  byte-identical to `$S/face_landmarker.task`) runs on the full image, and the box is the min/max of the 478 landmarks.
* `s2i.Landmark106` is replaced by `MPLandmark106`: MediaPipe 478 points mapped into the 106 slot layout. Jaw contour
  (the face oval minus the forehead, resampled to 33 points) goes to 0-32. Eye contours go to 33-42 and 87-96, with the
  centre slots set to corners plus top and bottom (MP 33/159/133/145 and 263/386/362/374). Brows go to 43-51 and 97-105,
  the outer lip to 52-71 with corners MP 61 and 291 at 52 and 61, and the nose to 72-86.
* Verified visually: the mapped points line up with landmark203's 203 points on ava-1 (`dbg_lmk.jpg`: green = MediaPipe
  mapping, red = landmark203), and the 512 crop is the normal LivePortrait framing.
* `sys.modules["insightface"] = None` blocks any import. The InsightFace ONNX files are not on disk at all.

## 4. Speed (4 threads, machine otherwise idle)

| Stage | Time |
|---|---|
| Model load | about 5 s (14 s cold) |
| Avatar registration (MediaPipe, landmark203, extractors) | about 2 s |
| HuBERT features + LMDM diffusion (50 steps) + stitching | about 10 s per 4 s of audio, about 22 s per 8 s |
| Render (warp + decoder + paste-back + x264), **bf16** | **about 60 s of compute per 1 s of video** (2.4 s per frame) |
| Render, fp32 (first smoke test) | about 157 s per 1 s of video |

Per frame in bf16: warp network about 0.75 s, SPADE decoder about 1.5 s, paste-back and encode run in parallel in a
writer thread. Both networks are convolution-bound (mkldnn), so a faster runtime would not help much.

**Estimated time for a 35 s clip: about 36-38 minutes** (875 frames x 2.4 s, plus about 1 min of motion and overhead).
Four coaches at 35 s each is about 2.5 hours. Peak RAM is about 4.0 GB (RSS), so do not run it alongside another 4 GB
job if the container limit is tight. Do not run two renders at once: both would share the 4 cores.

## 5. Quality notes (ava-1-blazer.jpg)

Smoke test: `smoke_ava1_8s.mp4` (8 s, fp32, default settings). Frame grabs: `smoke_ava1_t1.0.jpg`, `_t4.2.jpg`,
`_t7.0.jpg`. Mouth close-ups: `smoke_mouth_strip.jpg`. bf16 test with `--exp-scale 1.6`: `test_exp16_4s.mp4`,
`test_exp16_t2.6.jpg`, `test_exp16_mouth_strip.jpg`.

* **Identity: preserved.** Same face, freckles, hair, blazer and background. The paste-back is seamless, with no visible
  crop border.
* **Eyes: still dark brown**, sharp, with natural blinks (Ditto drives eye open/close and gaze for still images).
* **Head motion: natural.** Small nods and sways, and the gaze stays on the camera.
* **Mouth/teeth: no artefacts** (teeth stay stable, no smearing). But with the default settings the lip movement is
  **subtle**: the source photo is a broad open-teeth smile and Ditto drives motion *relative to the source expression*,
  so the smile is held and only small open/close changes appear. `--exp-scale 1.6` gives clearly visible mouth opening
  and still looks natural and artefact-free. **Recommended: `--exp-scale 1.4`-`1.6` for smiling sources.** A source
  photo with a softer, closed-lip or slight smile will articulate better than a big toothy grin.
* Hair: the long curly hair outside the face crop is static (not animated), which is normal for this family of models
  and not noticeable at these motion amplitudes.

## 6. Licences of every model and component used

| Item | Licence | Notes |
|---|---|---|
| Ditto code (antgroup/ditto-talkinghead) | Apache-2.0 | |
| Ditto weights: appearance_extractor, motion_extractor, warp_network, decoder, stitch_network, lmdm_v0.4_hubert (.pth), v0.4_hubert_cfg_pytorch.pkl | Apache-2.0 (HF repo LICENSE) | The renderer architecture comes from LivePortrait (MIT). |
| landmark203.onnx | Apache-2.0 as distributed by Ditto | Originally LivePortrait's landmark model (MIT). |
| hubert_streaming_fix_kv.onnx | Apache-2.0 as distributed by Ditto | A HuBERT-derived audio encoder. Ditto does not state the upstream checkpoint. HuBERT/fairseq is MIT, but this was **not independently verified**. |
| face_landmarker.task (MediaPipe) | Apache-2.0 | Replaces InsightFace. |
| InsightFace det_10g.onnx / 2d106det.onnx | non-commercial | **Not downloaded, not loaded, import blocked.** |
| Python libs: torch (BSD-3), onnxruntime (MIT), mediapipe (Apache-2.0), opencv (Apache-2.0), numpy/scikit-image/imageio (BSD), librosa (ISC), einops (MIT) | permissive | |
| ffmpeg / libx264 (system binary, used only to encode) | GPL | Only an external tool used for encoding. Nothing is linked into our code. |

## 7. Files

* `/root/ditto/repo`: unmodified clone. `/root/ditto/checkpoints`: weights. `/root/ditto/venv`: Python 3.11 venv.
* `$S/avatar2/make_clip.py`: the renderer (self-contained; paths can be changed with `DITTO_ROOT`).
* `/root/ditto/scripts/`: the test and profiling scripts used here (test_crop.py, profile*.py, bf16_check.py).
