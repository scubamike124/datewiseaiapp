# Adapted from scratchpad/musetalk/tools/measure.py (reuse): lip gap per frame (MediaPipe 13/14 over face height),
# correlation with audio loudness, min gap inside m/b/p words, bilabial contact sheet, plus blink count (eye openness).
import sys, os, json, cv2, numpy as np, mediapipe as mp, soundfile as sf
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision
S = '/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad'; W = f'{S}/imtalker'; T0 = 26.0
clips = {'Ditto': f'{S}/musetalk/ava-ditto-10s.mp4', 'IMTalker': f'{W}/ava-imtalker-10s.mp4'}
if os.path.exists(f'{S}/musetalk/ava-musetalk-10s.mp4'): clips['MuseTalk'] = f'{S}/musetalk/ava-musetalk-10s.mp4'
if os.path.exists(f'{W}/out/ava-imtalker-opensmile.mp4'): clips['IMT-opensmile'] = f'{W}/out/ava-imtalker-opensmile.mp4'
words = [w for w in json.load(open(f'{S}/avatar2/eval/review-ava/words.json')) if T0 <= w[0] < T0 + 10]
bil = [w for w in words if any(c in w[2].lower() for c in 'mbp')]
det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
    base_options=mpt.BaseOptions(model_asset_path=f'{S}/face_landmarker.task'), num_faces=1))
a, sr = sf.read(f'{S}/musetalk/in/ava-coach-26-36.wav'); fps = 25; hop = sr // fps
env = np.array([np.sqrt(np.mean(a[k*hop:(k+1)*hop]**2)) for k in range(250)])
data = {}
for name, path in clips.items():
    cap = cv2.VideoCapture(path); gaps, frames, lms, eyes, yaw = [], [], [], [], []
    while True:
        ok, fr = cap.read()
        if not ok: break
        r = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)))
        if r.face_landmarks:
            l = np.array([[p.x * fr.shape[1], p.y * fr.shape[0]] for p in r.face_landmarks[0]])
            fh = np.linalg.norm(l[10] - l[152]); gaps.append(np.linalg.norm(l[13] - l[14]) / fh); lms.append(l)
            eyes.append((np.linalg.norm(l[159] - l[145]) + np.linalg.norm(l[386] - l[374])) / 2 / fh)
            yaw.append((l[1][0] - (l[234][0] + l[454][0]) / 2) / fh)
        else:
            gaps.append(np.nan); lms.append(None); eyes.append(np.nan); yaw.append(np.nan)
        frames.append(fr)
    data[name] = (np.array(gaps[:250]), frames[:250], lms[:250], np.array(eyes[:250]), np.array(yaw[:250]))
res = {'window_s': [T0, T0 + 10]}
def corr(x, y): return float(np.corrcoef(x, y)[0, 1])
for name, (g, fr, lm, ey, yw) in data.items():
    n = len(g); e = env[:n]; ok = ~np.isnan(g); spk = e > 0.02
    lag = max(range(-4, 5), key=lambda s: corr(g[ok][max(0,-s):len(g[ok])-max(0,s)], e[ok][max(0,s):len(e[ok])-max(0,-s)]))
    lipidx = [0, 13, 14, 17, 61, 291, 78, 308]
    rel = np.array([(l[lipidx] - l[1]) / np.linalg.norm(l[10] - l[152]) * 300 for l in lm if l is not None])
    eo = ey / np.nanmedian(ey); blinks = int(np.sum((eo[1:] < 0.5) & (eo[:-1] >= 0.5)))
    nose = np.array([l[1] / np.linalg.norm(l[10] - l[152]) for l in lm if l is not None])
    res[name] = {'frames': n, 'gap_corr_lag0': round(corr(g[ok], e[ok]), 3), 'best_lag_frames': lag,
                 'gap_corr_best': round(corr(g[ok][max(0,-lag):len(g[ok])-max(0,lag)], e[ok][max(0,lag):len(e[ok])-max(0,-lag)]), 3),
                 'gap_min': round(float(np.nanmin(g)), 4), 'gap_speaking_mean': round(float(np.nanmean(g[spk])), 4),
                 'gap_silent_mean': round(float(np.nanmean(g[~spk])), 4),
                 'frames_lips_closed_lt_0.01': int(np.sum(g < 0.01)),
                 'lip_landmark_accel_norm300': round(float(np.mean(np.abs(np.diff(rel, 2, axis=0)))), 2),
                 'blinks': blinks, 'yaw_range_facefrac': round(float(np.nanmax(yw) - np.nanmin(yw)), 3),
                 'nose_xy_std_facefrac': [round(float(v), 4) for v in nose.std(0)],
                 'face_found_pct': round(float(ok.mean() * 100), 1),
                 'bilabial_min_gap': {w[2].strip(): round(float(np.nanmin(g[int((w[0]-T0)*fps):int((w[1]-T0)*fps)+1])), 4) for w in bil}}
print(json.dumps(res, indent=1)); json.dump(res, open(f'{W}/metrics.json', 'w'), indent=1)
def crop(fr, l):
    fh = np.linalg.norm(l[10] - l[152]); cx, cy = l[[13, 14]].mean(0); s = int(fh * 0.33)
    x0, y0 = int(cx - s), int(cy - s * 0.8); c = fr[max(0,y0):y0 + int(1.6*s), max(0,x0):x0 + 2*s]
    return cv2.resize(c, (300, 240))
rows = []
for w in bil:
    i0, i1 = int((w[0]-T0)*fps), int((w[1]-T0)*fps) + 1; tiles = []
    for name, (g, fr, lm, _, _) in data.items():
        k = i0 + int(np.nanargmin(g[i0:i1])); t = crop(fr[k], lm[k])
        cv2.putText(t, f'{name} "{w[2].strip()}" {T0 + k/fps:.2f}s', (6, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1)
        cv2.putText(t, f'gap {g[k]:.3f}', (6, 232), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1); tiles.append(t)
    rows.append(np.hstack(tiles))
cv2.imwrite(f'{W}/lipclosure-sheet.jpg', np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 88])
