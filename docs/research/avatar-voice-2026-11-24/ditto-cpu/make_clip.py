#!/root/ditto/venv/bin/python
"""
make_clip.py IMAGE AUDIO_WAV OUT_MP4 [options]

CPU-only Ditto (antgroup/ditto-talkinghead, PyTorch variant) talking-head renderer.

- No InsightFace: face detection + 106-point landmarks are replaced by MediaPipe
  Face Landmarker (Apache-2.0). The InsightFace model files are never downloaded,
  imported or loaded (the import is blocked).
- The Ditto clone at DITTO_REPO is NOT modified; CPU support is done by runtime
  patches in this file (device='cpu', fp16 autocast disabled on CPU, numpy blend
  instead of compiling the Cython blend, torch.load forced to weights_only=True,
  config pickle loaded with a numpy-only restricted unpickler).
- Resumable: work files live in OUT_MP4 + ".work/". Motion (audio->keypoints) is
  computed once and saved; frames are rendered in chunks (default 100 frames =
  4 s) that are each written as a finished mp4 segment. Re-running the same
  command skips finished work. Delete the .work dir to start over.

Options:
  --steps N        diffusion sampling steps (default 50, Ditto's default)
  --emo N          emotion label 0-7 (default: the cfg's averaged emotion vector)
  --seed N         RNG seed for the motion diffusion (default 1024)
  --chunk N        frames per render chunk (default 100)
  --threads N      torch / onnxruntime threads (default 4)
  --exp-scale X    multiply the driven expression change (default 1.0; 1.3-1.6
                   gives clearer lip movement on smiling source photos)
  --delta-pitch D  extra head pitch in degrees (cfg default 2)
  --max-size N     max source image side (default 1920)
  --fp32           full fp32 instead of bf16 autocast (about 2x slower, same look)
  --keep-work      keep the .work dir after a successful finish
"""
import argparse
import os
import sys
import json
import math
import time
import types
import pickle
import shutil
import subprocess

DITTO_ROOT = os.environ.get("DITTO_ROOT", "/root/ditto")
DITTO_REPO = os.path.join(DITTO_ROOT, "repo")
DATA_ROOT = os.path.join(DITTO_ROOT, "checkpoints", "ditto_pytorch")
CFG_PKL = os.path.join(DITTO_ROOT, "checkpoints", "ditto_cfg", "v0.4_hubert_cfg_pytorch.pkl")
FACE_TASK = os.path.join(DATA_ROOT, "aux_models", "face_landmarker.task")

import numpy as np


# --------------------------------------------------------------------------
# Safe config loading (only numpy reconstruction globals allowed)
# --------------------------------------------------------------------------
_ALLOWED = {("numpy._core.multiarray", "_reconstruct"), ("numpy.core.multiarray", "_reconstruct"),
            ("numpy", "ndarray"), ("numpy", "dtype")}


class _SafeUnpickler(pickle.Unpickler):
    def find_class(self, module, name):
        if (module, name) not in _ALLOWED:
            raise pickle.UnpicklingError(f"blocked global {module}.{name}")
        return super().find_class(module, name)


def safe_load_pkl(path):
    with open(path, "rb") as f:
        return _SafeUnpickler(f).load()


def load_cfg_cpu(path):
    cfg = safe_load_pkl(path)
    for sec in ("base_cfg",):
        for k, v in cfg[sec].items():
            if isinstance(v, dict) and "device" in v:
                v["device"] = "cpu"
    cfg["audio2motion_cfg"]["device"] = "cpu"
    return cfg


# --------------------------------------------------------------------------
# MediaPipe replacement for InsightFace det_10g (RetinaFace/SCRFD) + 2d106det
# --------------------------------------------------------------------------
# Ditto only uses these two models in Source2Info._crop() for the FIRST rough
# crop: box -> 106 landmarks -> crop_image(scale=1.5) -> 224x224 crop that is fed
# to landmark203 (LivePortrait's landmark model). crop_image() only needs:
#   * the eye centres  (106-idx 33,35,40,39 and 87,89,94,93) and
#   * the mouth corners (106-idx 52 and 61) for the roll / vertical axis, and
#   * the overall point extent (jaw contour + brows + eyes + nose + mouth)
#     for the crop centre and size.
# We build a 106x2 array with MediaPipe points placed at those semantic slots,
# using the jaw part of the face oval (not the forehead, which InsightFace's
# 106 layout does not cover) so the extent matches.

_MP_JAW = [356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176,
           149, 150, 136, 172, 58, 132, 93, 234, 127]
_MP_EYE_A = [33, 246, 161, 160, 159, 158, 157, 173, 133, 155]   # 10 pts -> 106 idx 33..42
_MP_EYE_B = [263, 466, 388, 387, 386, 385, 384, 398, 362, 382]  # 10 pts -> 106 idx 87..96
_MP_BROW_A = [70, 63, 105, 66, 107, 55, 65, 52, 53]              # 9 pts -> 43..51
_MP_BROW_B = [300, 293, 334, 296, 336, 285, 295, 282, 283]       # 9 pts -> 97..105
_MP_MOUTH = [61, 185, 40, 39, 37, 0, 267, 269, 270, 291,         # 20 pts -> 52..71
             409, 375, 321, 405, 314, 17, 84, 181, 91, 146]
_MP_NOSE = [168, 6, 197, 195, 5, 4, 1, 19, 94, 2, 98, 327, 64, 294, 129]  # 15 pts -> 72..86


def _resample_polyline(pts, n):
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    t = np.linspace(0, s[-1], n)
    return np.stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], 1)


def mp478_to_pt106(lmk):
    """lmk: (478, 2) pixel coords -> (106, 2) array in InsightFace slot layout."""
    p = np.zeros((106, 2), dtype=np.float32)
    p[0:33] = _resample_polyline(lmk[_MP_JAW], 33)
    p[33:43] = lmk[_MP_EYE_A]
    p[87:97] = lmk[_MP_EYE_B]
    # eye-centre slots used by parse_pt2_from_pt106: corners + top + bottom
    p[[33, 35, 40, 39]] = lmk[[33, 159, 133, 145]]
    p[[87, 89, 94, 93]] = lmk[[263, 386, 362, 374]]
    p[43:52] = lmk[_MP_BROW_A]
    p[97:106] = lmk[_MP_BROW_B]
    p[52:72] = lmk[_MP_MOUTH]
    p[52] = lmk[61]    # mouth corner
    p[61] = lmk[291]   # mouth corner
    p[72:87] = lmk[_MP_NOSE]
    return p


class _MPFaceShared:
    detector = None
    task_path = FACE_TASK
    last = None  # (img id, shape, list of (box5, lmk478xy))

    @classmethod
    def get(cls):
        if cls.detector is None:
            from mediapipe.tasks.python import vision, BaseOptions
            opts = vision.FaceLandmarkerOptions(
                base_options=BaseOptions(model_asset_path=cls.task_path),
                num_faces=4, min_face_detection_confidence=0.5)
            cls.detector = vision.FaceLandmarker.create_from_options(opts)
        return cls.detector

    @classmethod
    def detect(cls, img):
        import mediapipe as mp
        h, w = img.shape[:2]
        res = cls.get().detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(img)))
        faces = []
        for fl in res.face_landmarks:
            xy = np.array([[l.x * w, l.y * h] for l in fl], dtype=np.float32)
            box = np.array([xy[:, 0].min(), xy[:, 1].min(), xy[:, 0].max(), xy[:, 1].max(), 1.0], dtype=np.float32)
            faces.append((box, xy))
        cls.last = (id(img), img.shape, faces)
        return faces


class MPFaceDet:
    """Drop-in for core.aux_models.insightface_det.InsightFaceDet."""
    def __init__(self, *a, **k):
        _MPFaceShared.get()

    def __call__(self, img, **kwargs):
        faces = _MPFaceShared.detect(img)
        if not faces:
            return np.zeros((0, 5), dtype=np.float32), None
        return np.stack([f[0] for f in faces]), None


class MPLandmark106:
    """Drop-in for core.aux_models.insightface_landmark106.Landmark106."""
    def __init__(self, *a, **k):
        pass

    def __call__(self, img, bbox):
        last = _MPFaceShared.last
        faces = last[2] if (last and last[0] == id(img) and last[1] == img.shape) else _MPFaceShared.detect(img)
        best = min(faces, key=lambda f: np.abs(f[0][:4] - np.asarray(bbox[:4])).sum())
        return mp478_to_pt106(best[1])


# --------------------------------------------------------------------------
# Runtime patches + Ditto import
# --------------------------------------------------------------------------
def import_ditto(threads, bf16=True):
    import torch
    torch.set_num_threads(threads)
    os.environ.setdefault("OMP_NUM_THREADS", str(threads))

    # Ditto's PyTorch models wrap inference in fp16 autocast (a CUDA setting). On CPU
    # we use bf16 autocast instead (fast on AMX / AVX512-BF16 CPUs; measured 52 dB PSNR
    # vs fp32, i.e. visually identical) or plain fp32 with bf16=False.
    _orig_autocast = torch.autocast

    class _Autocast(_orig_autocast):
        def __init__(self, device_type, dtype=None, enabled=True, cache_enabled=None):
            if device_type == "cpu":
                dtype, enabled = torch.bfloat16, enabled and bf16
            super().__init__(device_type, dtype=dtype, enabled=enabled, cache_enabled=cache_enabled)
    torch.autocast = _Autocast

    # Untrusted .pth files: never allow arbitrary pickle code.
    _orig_load = torch.load

    def _safe_torch_load(*a, **k):
        k["weights_only"] = True
        return _orig_load(*a, **k)
    torch.load = _safe_torch_load

    # Block InsightFace entirely.
    for name in ("insightface",):
        sys.modules[name] = None

    sys.path.insert(0, DITTO_REPO)

    # Avoid compiling the repo's Cython blend at import time: numpy equivalent.
    blend_mod = types.ModuleType("core.utils.blend")

    def blend_images_cy(mask_warped, frame_warped, frame_rgb, out):
        m = mask_warped[..., None]
        out[...] = np.clip(m * frame_warped + (1 - m) * frame_rgb, 0, 255).astype(np.uint8)
    blend_mod.blend_images_cy = blend_images_cy
    sys.modules["core.utils.blend"] = blend_mod

    import core.atomic_components.cfg as dcfg
    dcfg.load_pkl = load_cfg_cpu  # restricted unpickler + device=cpu

    import core.atomic_components.source2info as s2i
    s2i.InsightFaceDet = MPFaceDet
    s2i.Landmark106 = MPLandmark106
    # make sure nothing else can load the InsightFace modules
    for m in ("core.aux_models.insightface_det", "core.aux_models.insightface_landmark106",
              "core.aux_models.modules.retinaface", "core.aux_models.modules.landmark106"):
        mod = sys.modules.get(m)
        if mod is not None:
            for attr in ("InsightFaceDet", "Landmark106", "RetinaFace"):
                if hasattr(mod, attr):
                    setattr(mod, attr, None)

    from stream_pipeline_offline import StreamSDK
    from core.atomic_components.condition_handler import _mirror_index
    return StreamSDK, _mirror_index


# --------------------------------------------------------------------------
# Pipeline
# --------------------------------------------------------------------------
def atomic_save_npy(path, arr):
    tmp = path + ".tmp.npy"
    np.save(tmp, arr)
    os.replace(tmp, path)


def run(args):
    t_start = time.time()
    out_mp4 = os.path.abspath(args.out_mp4)
    work = out_mp4 + ".work"
    os.makedirs(work, exist_ok=True)
    os.makedirs(os.path.dirname(out_mp4), exist_ok=True)

    # 16 kHz mono audio copy (also what gets muxed)
    wav16 = os.path.join(work, "audio16k.wav")
    if not os.path.exists(wav16):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", args.audio, "-ac", "1", "-ar", "16000",
                        wav16 + ".tmp.wav"], check=True)
        os.replace(wav16 + ".tmp.wav", wav16)

    StreamSDK, _mirror_index = import_ditto(args.threads, bf16=not args.fp32)
    import librosa
    import torch

    t0 = time.time()
    SDK = StreamSDK(CFG_PKL, DATA_ROOT)
    # LMDM's nn.Module defaults to device='cuda' (create_model() does not pass the
    # device through), which breaks its DDIM setup on CPU.
    SDK.audio2motion.lmdm.model.device = "cpu"
    print(f"[load] models loaded in {time.time() - t0:.1f}s", flush=True)

    audio, _ = librosa.load(wav16, sr=16000)
    num_f = math.ceil(len(audio) / 16000 * 25)

    setup_kwargs = {"sampling_timesteps": args.steps, "max_size": args.max_size}
    if args.emo is not None:
        setup_kwargs["emo"] = args.emo
    if args.exp_scale != 1.0:
        # relative motion: x = x_src + (x_drv - x_drv[0]) * scale  -> stronger lip articulation
        setup_kwargs["use_d_keys"] = {"exp": args.exp_scale, "pitch": 1.0, "yaw": 1.0, "roll": 1.0, "t": 1.0}
    if args.delta_pitch is not None:
        setup_kwargs["overall_ctrl_info"] = {"delta_pitch": args.delta_pitch}

    # --- replicate StreamSDK.setup() without starting its worker threads ---
    t0 = time.time()
    _orig_thread_start = None
    import threading
    _orig_thread_start = threading.Thread.start
    threading.Thread.start = lambda self: None  # SDK.setup() starts 6 workers we don't use
    try:
        SDK.setup(args.image, os.path.join(work, "unused.mp4"), **setup_kwargs)
    finally:
        threading.Thread.start = _orig_thread_start
    try:
        SDK.writer.close()
    except Exception:
        pass
    SDK.setup_Nd(N_d=num_f, fade_in=-1, fade_out=-1, ctrl_info={})
    print(f"[setup] avatar registered in {time.time() - t0:.1f}s, {num_f} frames", flush=True)

    # --- stage 1: audio -> motion (saved, so a restart never changes the motion) ---
    motion_path = os.path.join(work, "x_d.npy")
    xs_path = os.path.join(work, "x_s.npy")
    meta_path = os.path.join(work, "meta.json")
    meta = {"image": os.path.abspath(args.image), "audio": os.path.abspath(args.audio), "steps": args.steps,
            "emo": args.emo, "seed": args.seed, "num_f": num_f, "chunk": args.chunk, "delta_pitch": args.delta_pitch,
            "fp32": args.fp32, "exp_scale": args.exp_scale}
    if os.path.exists(meta_path):
        old = json.load(open(meta_path))
        if old != meta:
            sys.exit(f"work dir {work} was made with different settings:\n{old}\nDelete it or use another OUT_MP4.")
    else:
        json.dump(meta, open(meta_path, "w"))

    if not (os.path.exists(motion_path) and os.path.exists(xs_path)):
        t0 = time.time()
        np.random.seed(args.seed)
        torch.manual_seed(args.seed)
        aud_feat = SDK.wav2feat.wav2feat(audio)
        t_feat = time.time() - t0
        aud_cond_all = SDK.condition_handler(aud_feat, 0)
        a2m = SDK.audio2motion
        seq_frames, valid = a2m.seq_frames, a2m.valid_clip_len
        n = len(aud_cond_all)
        idx, res = 0, None
        while idx < n:
            cond = aud_cond_all[idx:idx + seq_frames][None]
            if cond.shape[1] < seq_frames:
                pad = np.stack([cond[:, -1]] * (seq_frames - cond.shape[1]), 1)
                cond = np.concatenate([cond, pad], 1)
            res = a2m(cond, res)
            idx += valid
        res = res[:, :n]
        res = a2m._smo(res, 0, res.shape[1])
        x_d_info_list = a2m.cvt_fmt(res)
        xs_all, xd_all = [], []
        for gi, x_d_info in enumerate(x_d_info_list):
            fi = _mirror_index(gi, SDK.source_info_frames)
            x_s, x_d = SDK.motion_stitch(SDK.source_info["x_s_info_lst"][fi], x_d_info, **SDK._get_ctrl_info(gi))
            xs_all.append(x_s)
            xd_all.append(x_d)
        atomic_save_npy(xs_path, np.stack(xs_all))
        atomic_save_npy(motion_path, np.stack(xd_all))
        print(f"[motion] hubert {t_feat:.1f}s, total motion {time.time() - t0:.1f}s for {len(xd_all)} frames",
              flush=True)
    xs_all = np.load(xs_path)
    xd_all = np.load(motion_path)
    n_frames = len(xd_all)

    # --- stage 2: render chunks ---
    import imageio
    import queue
    n_chunks = math.ceil(n_frames / args.chunk)
    seg_paths = []
    render_time, rendered = 0.0, 0
    for c in range(n_chunks):
        seg = os.path.join(work, f"seg_{c:04d}.mp4")
        seg_paths.append(seg)
        if os.path.exists(seg):
            continue
        s, e = c * args.chunk, min(n_frames, (c + 1) * args.chunk)
        t0 = time.time()
        tmp = seg + ".tmp.mp4"
        w = imageio.get_writer(tmp, fps=25, format="mp4", codec="libx264", pixelformat="yuv420p",
                               macro_block_size=2, ffmpeg_params=["-crf", "14", "-preset", "medium"])
        q = queue.Queue(maxsize=4)
        err = []

        def _writer():  # paste-back + encode overlap with the next frame's network pass
            try:
                while True:
                    item = q.get()
                    if item is None:
                        break
                    fi_, render_ = item
                    w.append_data(SDK.putback(SDK.source_info["img_rgb_lst"][fi_], render_,
                                              SDK.source_info["M_c2o_lst"][fi_]).copy())
            except Exception as ex:  # surface in main thread
                err.append(ex)
        th = threading.Thread(target=_writer)
        th.start()
        for gi in range(s, e):
            if err:
                break
            fi = _mirror_index(gi, SDK.source_info_frames)
            f_s = SDK.source_info["f_s_lst"][fi]
            f_3d = SDK.warp_f3d(f_s, xs_all[gi], xd_all[gi])
            q.put((fi, SDK.decode_f3d(f_3d)))
        q.put(None)
        th.join()
        w.close()
        if err:
            raise err[0]
        os.replace(tmp, seg)
        dt = time.time() - t0
        render_time += dt
        rendered += e - s
        print(f"[render] chunk {c + 1}/{n_chunks} frames {s}-{e - 1}: {dt:.1f}s "
              f"({dt / ((e - s) / 25):.1f} s per s of video)", flush=True)

    # --- stage 3: concat + mux audio ---
    lst = os.path.join(work, "segments.txt")
    with open(lst, "w") as f:
        for p in seg_paths:
            f.write(f"file '{p}'\n")
    tmp_out = out_mp4 + ".tmp.mp4"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-i", wav16,
                    "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-shortest",
                    "-movflags", "+faststart", tmp_out], check=True)
    os.replace(tmp_out, out_mp4)
    stats = {"frames": n_frames, "video_seconds": n_frames / 25, "render_seconds_this_run": round(render_time, 1),
             "render_s_per_video_s": round(render_time / (rendered / 25), 2) if rendered else None,
             "wall_seconds_this_run": round(time.time() - t_start, 1)}
    print("[done]", out_mp4, json.dumps(stats), flush=True)
    with open(os.path.join(work, "stats.json"), "w") as f:
        json.dump(stats, f)
    if not args.keep_work:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("audio")
    ap.add_argument("out_mp4")
    ap.add_argument("--steps", type=int, default=50)
    ap.add_argument("--emo", type=int, default=None)
    ap.add_argument("--seed", type=int, default=1024)
    ap.add_argument("--chunk", type=int, default=100)
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--delta-pitch", type=float, default=None)
    ap.add_argument("--max-size", type=int, default=1920)
    ap.add_argument("--exp-scale", type=float, default=1.0)
    ap.add_argument("--fp32", action="store_true", help="fp32 instead of bf16 autocast (about 2x slower)")
    ap.add_argument("--keep-work", action="store_true")
    run(ap.parse_args())
