import sys, numpy as np, cv2, mediapipe as mp
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision
det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(base_options=mpt.BaseOptions(model_asset_path='face_landmarker.task'), num_faces=1))
R_EYE = [33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246]
L_EYE = [263,249,390,373,374,380,381,382,362,398,384,385,386,387,388,466]
for src in sys.argv[1:]:
    bgr = cv2.imread(src); h, w = bgr.shape[:2]
    res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)))
    lm = np.array([[p.x * w, p.y * h] for p in res.face_landmarks[0]])
    mask = np.zeros((h, w), np.float32)
    for c, ring, eye in ((468, range(469, 473), R_EYE), (473, range(474, 478), L_EYE)):
        r = np.mean([np.linalg.norm(lm[i] - lm[c]) for i in ring])
        iris = np.zeros((h, w), np.uint8); cv2.circle(iris, tuple(np.round(lm[c]).astype(int)), int(round(r * 1.02)), 255, -1)
        lid = np.zeros((h, w), np.uint8); cv2.fillPoly(lid, [np.round(lm[eye]).astype(np.int32)], 255)
        mask = np.maximum(mask, (cv2.bitwise_and(iris, lid) / 255.0).astype(np.float32))
    mask = cv2.GaussianBlur(mask, (0, 0), 1.2)
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    L, A, B = lab[..., 0], lab[..., 1], lab[..., 2]
    keep = np.clip((L - 200) / 40, 0, 1)            # leave catchlights alone
    m = mask * (1 - keep)
    tL = L * 0.62; tA = 128 + 0.5 * (A - 128) + 7; tB = 128 + 0.5 * (B - 128) + 12   # dark warm brown, keeps texture
    lab[..., 0] = L * (1 - m) + tL * m; lab[..., 1] = A * (1 - m) + tA * m; lab[..., 2] = B * (1 - m) + tB * m
    out = cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
    cv2.imwrite(src.replace('.png', '-iris.png'), out)
    # close-up check: both eyes, before / after
    x0, x1 = int(min(lm[R_EYE][:, 0].min(), lm[L_EYE][:, 0].min()) - 20), int(max(lm[R_EYE][:, 0].max(), lm[L_EYE][:, 0].max()) + 20)
    y0, y1 = int(lm[[159, 386], 1].min() - 30), int(lm[[145, 374], 1].max() + 30)
    crop = np.vstack([bgr[y0:y1, x0:x1], out[y0:y1, x0:x1]])
    cv2.imwrite(src.replace('.png', '-iris-check.png'), cv2.resize(crop, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC))
    print('ok', src, 'iris r', round(r, 1))
