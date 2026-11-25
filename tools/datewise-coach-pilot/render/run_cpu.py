"""CPU runner for IMTalker audio-driven inference (research test only).
- Forces device=cpu (upstream hard-codes cuda/rank 0).
- Replaces face_alignment (S3FD/FAN weights, licence unstated) with a MediaPipe
  FaceLandmarker bbox, using the same 0.8x half-side crop rule as upstream.
Usage: run_cpu.py SRC_DIR CKPT_DIR IMG WAV OUT_MP4 CROP_PNG [nfe] [cfg]
"""
import sys, os, time, types, json, threading
src, ckpt, img_path, wav, out, crop_png = sys.argv[1:7]
nfe = int(sys.argv[7]) if len(sys.argv) > 7 else 10
cfg = float(sys.argv[8]) if len(sys.argv) > 8 else 3.0
LM = os.environ["FACE_LANDMARKER"]
sys.modules["face_alignment"] = types.ModuleType("face_alignment")  # stub: never loads S3FD/FAN
sys.path[:0] = [src, os.path.join(src, "generator")]
import psutil, torch, numpy as np
torch.set_num_threads(int(os.environ.get("THREADS", "4")))
proc = psutil.Process(); peak = [0]
def mon():
    while True:
        peak[0] = max(peak[0], proc.memory_info().rss); time.sleep(0.2)
threading.Thread(target=mon, daemon=True).start()
t0 = time.time()
from PIL import Image
import mediapipe as mp
from mediapipe.tasks.python import vision, BaseOptions as MPBase

def mp_crop(path, size=512):
    arr = np.array(Image.open(path).convert("RGB")); h, w = arr.shape[:2]
    det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(base_options=MPBase(model_asset_path=LM), num_faces=1))
    res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=arr))
    pts = np.array([[p.x * w, p.y * h] for p in res.face_landmarks[0]])
    x1, y1 = pts.min(0); x2, y2 = pts.max(0)
    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    half = int(max(x2 - x1, y2 - y1) * 0.8)
    X1, Y1, X2, Y2 = int(cx - half), int(cy - half), int(cx + half), int(cy + half)
    if X1 < 0: X2 -= X1; X1 = 0
    if Y1 < 0: Y2 -= Y1; Y1 = 0
    if X2 > w: X1 -= X2 - w; X2 = w
    if Y2 > h: Y1 -= Y2 - h; Y2 = h
    X1, Y1 = max(0, X1), max(0, Y1); side = min(X2 - X1, Y2 - Y1)
    box = (X1, Y1, X1 + side, Y1 + side)
    im = Image.fromarray(arr[box[1]:box[3], box[0]:box[2]]).resize((size, size), Image.LANCZOS)
    return im, box

from generate import InferenceAgent, InferenceOptions
sys.argv = [sys.argv[0], "--wav2vec_model_path", os.path.join(ckpt, "wav2vec2-base-960h"),
            "--generator_path", os.path.join(ckpt, "generator.ckpt"),
            "--renderer_path", os.path.join(ckpt, "renderer.ckpt"),
            "--input_size", "512", "--nfe", str(nfe), "--a_cfg_scale", str(cfg)]
opt = InferenceOptions().parse(); opt.rank, opt.ngpus = "cpu", 1
opt.fps = int(opt.fps)  # PyAV expects an integer or rational video time base.
opt.window_size = 8  # as in upstream app.py
import generate
generate.face_alignment = types.SimpleNamespace(FaceAlignment=lambda *a, **k: None, LandmarksType=types.SimpleNamespace(TWO_D=None))
agent = InferenceAgent(opt)
t_load = time.time() - t0
crop, box = mp_crop(img_path); crop.save(crop_png)
t1 = time.time()
agent.run_inference(out, crop_png, wav, crop=False, a_cfg_scale=cfg, nfe=nfe, seed=42)
t_inf = time.time() - t1
import subprocess
dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", wav]).strip())
stats = dict(load_s=round(t_load, 1), render_s=round(t_inf, 1), audio_s=dur, render_s_per_video_s=round(t_inf / dur, 2),
             peak_rss_gb=round(peak[0] / 2**30, 2), crop_box=box, nfe=nfe, cfg=cfg, threads=torch.get_num_threads())
print("STATS", json.dumps(stats)); json.dump(stats, open(out + ".stats.json", "w"))
