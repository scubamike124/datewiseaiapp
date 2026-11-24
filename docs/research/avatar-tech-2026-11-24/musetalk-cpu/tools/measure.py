# Compare Ditto-only vs MuseTalk 10 s clips: lip gap per frame (MediaPipe 13/14 over face height), correlation with
# audio loudness, min gap inside bilabial words (from faster-whisper word timestamps), and a mouth contact sheet.
import sys, json, cv2, numpy as np, mediapipe as mp, soundfile as sf
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision
S = '/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad'; W = f'{S}/musetalk'; T0 = 26.0
clips = {'Ditto': f'{W}/ava-ditto-10s.mp4', 'MuseTalk': f'{W}/ava-musetalk-10s.mp4'}
words = [w for w in json.load(open(f'{S}/avatar2/eval/review-ava/words.json')) if T0 <= w[0] < T0 + 10]
bil = [w for w in words if any(c in w[2].lower() for c in 'mbp')]
det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
    base_options=mpt.BaseOptions(model_asset_path=f'{S}/face_landmarker.task'), num_faces=1))
a, sr = sf.read(f'{W}/in/ava-coach-26-36.wav'); fps = 25; hop = sr // fps
env = np.array([np.sqrt(np.mean(a[k*hop:(k+1)*hop]**2)) for k in range(250)])
data = {}
for name, path in clips.items():
    cap = cv2.VideoCapture(path); gaps, frames, lms, jit = [], [], [], []
    while True:
        ok, fr = cap.read()
        if not ok: break
        r = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)))
        if r.face_landmarks:
            l = np.array([[p.x * fr.shape[1], p.y * fr.shape[0]] for p in r.face_landmarks[0]])
            fh = np.linalg.norm(l[10] - l[152]); gaps.append(np.linalg.norm(l[13] - l[14]) / fh); lms.append(l)
        else:
            gaps.append(np.nan); lms.append(None)
        frames.append(fr)
    data[name] = (np.array(gaps[:250]), frames[:250], lms[:250])
res = {'window_s': [T0, T0 + 10], 'frames': 250}
def corr(x, y): return float(np.corrcoef(x, y)[0, 1])
for name, (g, fr, lm) in data.items():
    ok = ~np.isnan(g); spk = env > 0.02
    lag = max(range(-4, 5), key=lambda s: corr(g[ok][max(0,-s):len(g[ok])-max(0,s)], env[ok][max(0,s):len(env[ok])-max(0,-s)]))
    # mouth-region jitter: frame-to-frame mean abs change of lip landmark positions relative to nose (px)
    lipidx = [0, 13, 14, 17, 61, 291, 78, 308]
    rel = np.array([l[lipidx] - l[1] for l in lm if l is not None]); jitter = float(np.mean(np.abs(np.diff(rel, 2, axis=0))))
    res[name] = {'gap_corr_lag0': round(corr(g[ok], env[ok]), 3), 'best_lag_frames': lag,
                 'gap_corr_best': round(corr(g[ok][max(0,-lag):len(g[ok])-max(0,lag)], env[ok][max(0,lag):len(env[ok])-max(0,-lag)]), 3),
                 'gap_min': round(float(np.nanmin(g)), 4), 'gap_speaking_mean': round(float(np.nanmean(g[spk])), 4),
                 'gap_silent_mean': round(float(np.nanmean(g[~spk])), 4),
                 'frames_lips_closed_lt_0.01': int(np.sum(g < 0.01)), 'lip_landmark_accel_px': round(jitter, 2),
                 'face_found_pct': round(float(ok.mean() * 100), 1),
                 'bilabial_min_gap': {w[2].strip(): round(float(np.nanmin(g[int((w[0]-T0)*fps):int((w[1]-T0)*fps)+1])), 4) for w in bil}}
print(json.dumps(res, indent=1)); json.dump(res, open(f'{W}/metrics.json', 'w'), indent=1)
# contact sheet: per bilabial word, the min-gap frame of each clip, mouth crop
def crop(fr, l, ref):
    cx, cy = l[[13, 14]].mean(0) if l is not None else ref; s = 110
    x0, y0 = int(cx - s), int(cy - s * 0.8); c = fr[max(0,y0):y0 + int(1.6*s), max(0,x0):x0 + 2*s]
    return cv2.resize(c, (300, 240))
rows = []
for w in bil:
    i0, i1 = int((w[0]-T0)*fps), int((w[1]-T0)*fps) + 1; tiles = []
    for name, (g, fr, lm) in data.items():
        k = i0 + int(np.nanargmin(g[i0:i1])); ref = data['Ditto'][2][k][[13, 14]].mean(0)
        t = crop(fr[k], lm[k], ref)
        cv2.putText(t, f'{name} "{w[2].strip()}" {T0 + k/fps:.2f}s', (6, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1)
        cv2.putText(t, f'gap {g[k]:.3f}', (6, 232), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1); tiles.append(t)
    rows.append(np.hstack(tiles))
sheet = np.vstack(rows)
cv2.imwrite(f'{W}/ava-lipclosure-sheet.jpg', sheet, [cv2.IMWRITE_JPEG_QUALITY, 88])
# lip gap plot strip (simple) for both clips + audio env
H, Wd = 200, 1000; im = np.full((H, Wd, 3), 255, np.uint8)
for (name, (g, _, _)), col in zip(data.items(), [(200, 80, 0), (0, 0, 220)]):
    pts = [(int(i * Wd / 250), int(H - 10 - (0 if np.isnan(v) else v) / 0.2 * (H - 20))) for i, v in enumerate(g)]
    cv2.polylines(im, [np.array(pts)], False, col, 2); cv2.putText(im, name, (10, 20 if name == 'Ditto' else 40), cv2.FONT_HERSHEY_SIMPLEX, 0.6, col, 2)
e = env / env.max(); cv2.polylines(im, [np.array([(int(i * Wd / 250), int(H - 10 - v * 60)) for i, v in enumerate(e)])], False, (150, 150, 150), 1)
cv2.imwrite(f'{W}/ava-lipgap-plot.png', im)
