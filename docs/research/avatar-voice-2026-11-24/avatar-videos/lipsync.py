# Objective lip-sync / liveliness check for a rendered avatar clip:
# per-frame mouth opening (MediaPipe landmarks 13/14 over face height) vs the driving audio's loudness,
# blink count (eye aspect), head motion; plus a contact sheet of frames while listening and speaking.
import sys, json, cv2, numpy as np, mediapipe as mp, soundfile as sf
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision
S = '/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad'
coach = sys.argv[1]
vid = f'{S}/avatar2/videos/{coach}-face.mp4'; wav = f'{S}/avatar2/audio/{coach}-coachonly.wav'
tl = json.load(open(f'{S}/avatar2/audio/{coach}-timeline.json'))
det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(base_options=mpt.BaseOptions(model_asset_path=f'{S}/face_landmarker.task'), num_faces=1))
cap = cv2.VideoCapture(vid); fps = cap.get(cv2.CAP_PROP_FPS) or 25
mouth, eye, nose, frames = [], [], [], []
i = 0
while True:
    ok, fr = cap.read()
    if not ok: break
    r = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(fr, cv2.COLOR_BGR2RGB)))
    if r.face_landmarks:
        l = np.array([[p.x, p.y] for p in r.face_landmarks[0]]); fh = np.linalg.norm(l[10] - l[152])
        mouth.append(np.linalg.norm(l[13] - l[14]) / fh)
        eye.append((np.linalg.norm(l[159] - l[145]) + np.linalg.norm(l[386] - l[374])) / (2 * fh))
        nose.append(l[1])
    else:
        mouth.append(np.nan); eye.append(np.nan); nose.append([np.nan, np.nan])
    if i % int(fps) == 0: frames.append((i / fps, fr))
    i += 1
mouth, eye, nose = np.array(mouth), np.array(eye), np.array(nose)
a, sr = sf.read(wav); hop = int(sr / fps)
env = np.array([np.sqrt(np.mean(a[k*hop:(k+1)*hop]**2)) if (k+1)*hop <= len(a) else 0 for k in range(len(mouth))])
ok = ~np.isnan(mouth)
def corr(x, y): return float(np.corrcoef(x, y)[0, 1])
best = max(((corr(mouth[ok][max(0,-s):len(mouth[ok])-max(0,s)], env[ok][max(0,s):len(env[ok])-max(0,-s)]), s) for s in range(-6, 7)))
speaking = env > 0.02
blink_thr = np.nanmedian(eye) * 0.55
blinks = int(np.sum((eye[1:] < blink_thr) & (eye[:-1] >= blink_thr)))
res = {'coach': coach, 'frames': int(len(mouth)), 'fps': fps, 'seconds': round(len(mouth)/fps, 1),
       'mouth_audio_corr_best': round(best[0], 3), 'best_lag_frames': best[1],
       'mouth_open_speaking_mean': round(float(np.nanmean(mouth[speaking])), 4),
       'mouth_open_silent_mean': round(float(np.nanmean(mouth[~speaking])), 4),
       'blinks': blinks, 'blinks_per_min': round(blinks / (len(mouth)/fps) * 60, 1),
       'head_motion_px_std': round(float(np.nanstd(nose[:, 0]) * 896 + np.nanstd(nose[:, 1]) * 1080), 1),
       'face_found_pct': round(float(ok.mean() * 100), 1)}
print(json.dumps(res)); json.dump(res, open(f'{S}/avatar2/eval/{coach}-metrics.json', 'w'), indent=1)
# contact sheet: one frame per second, labelled listening/speaking
thumbs = []
for t, fr in frames[:40]:
    role = next((r for r, a0, a1 in tl if a0 <= t <= a1), 'pause')
    im = cv2.resize(fr, (224, 270)); cv2.putText(im, f'{t:4.1f}s {role}', (6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1)
    thumbs.append(im)
while len(thumbs) % 8: thumbs.append(np.zeros_like(thumbs[0]))
rows = [np.hstack(thumbs[k:k+8]) for k in range(0, len(thumbs), 8)]
cv2.imwrite(f'{S}/avatar2/eval/{coach}-sheet.jpg', np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 80])
