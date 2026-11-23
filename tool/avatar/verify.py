"""Identity and eye-colour gate for generated avatar frames.

The same checks as the portrait intake (YuNet MIT detector, SFace Apache-2.0
recogniser, iris-tone comparison), applied to every generated frame:
  * identity: SFace cosine similarity to the approved reference crop of the
    coach >= 0.45, and higher than to any other coach (no swapped faces);
  * master: similarity to the portrait the frame was generated from >= 0.75
    (an open mouth or a nod lowers SFace similarity a little; identity is
    still decided by the approved reference above);
  * eye colour: the iris colour (CIELAB a*/b* chroma and lightness of the
    iris band of each eye region, sampled at the master's eye points;
    at the frame's own points for the gaze frame, which moves the irises)
    within 5 / 15 of the master's, so a
    brown-to-blue or green change is rejected (skipped for blink frames,
    where the eyes are shut). Lab chroma is used instead of HSV hue, which
    is unstable for dark, low-saturation irises.
References: tool/avatar/refs/crop-<coach>.png, the approved identity crops
(the same ones the portrait intake check uses).
"""
import os, numpy as np, cv2

TOOLS = os.environ.get("AVATAR_TOOLS", os.path.expanduser("~/.cache/datewise-avatar-tools"))
COACHES = ["ava", "ethan", "sofia", "diego"]
ID_MIN, MASTER_MIN, AB_MAX, L_MAX = 0.45, 0.75, 5.0, 15.0

_det = cv2.FaceDetectorYN.create(os.path.join(TOOLS, "models", "yunet.onnx"), "", (320, 320), 0.8, 0.3, 5000)
_rec = cv2.FaceRecognizerSF.create(os.path.join(TOOLS, "models", "sface.onnx"), "")


DETECT_MAX = 1280  # YuNet misses very large faces: detect on a copy at most this big, map back


def faces(img):
    h, w = img.shape[:2]
    scale = min(1.0, DETECT_MAX / max(h, w))
    small = img if scale == 1.0 else cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    _det.setInputSize((small.shape[1], small.shape[0]))
    _, f = _det.detect(small)
    if f is None:
        return []
    f = f.copy()
    f[:, :14] /= scale
    return list(f)


def eye_tone(img, face):
    """Mean CIELAB (L, a, b) of the iris band (10th-50th lightness percentile) around each eye."""
    iod = float(np.hypot(face[6] - face[4], face[7] - face[5]))
    r = max(3, int(0.10 * iod))
    out = []
    for ex, ey in [(face[4], face[5]), (face[6], face[7])]:
        patch = img[max(0, int(ey) - r):int(ey) + r, max(0, int(ex) - r):int(ex) + r]
        if patch.size:
            lab = cv2.cvtColor(patch, cv2.COLOR_BGR2LAB).reshape(-1, 3).astype(float)
            lab[:, 0] *= 100 / 255.0
            lab[:, 1:] -= 128
            lo, hi = np.percentile(lab[:, 0], [10, 50])
            dark = lab[(lab[:, 0] >= lo) & (lab[:, 0] <= hi)]  # iris: not pupil/lashes, not sclera/skin
            out.append(dark.mean(axis=0))
    return np.mean(out, axis=0) if out else None


def analyse(img):
    fs = faces(img)
    if not fs:
        return None
    f = max(fs, key=lambda x: x[2] * x[3])
    return dict(face=f, emb=_rec.feature(_rec.alignCrop(img, f)), tone=eye_tone(img, f), count=len(fs))


def reference_embeddings():
    refs = {}
    for c in COACHES:
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "refs", f"crop-{c}.png")
        img = cv2.imread(p)
        if img is None:
            raise SystemExit(f"missing approved reference {p} (see tool/avatar/README.md)")
        big = cv2.resize(img, (img.shape[1] * 3, img.shape[0] * 3), interpolation=cv2.INTER_CUBIC)
        refs[c] = analyse(big)["emb"]
    return refs


def check_frame(img, coach, refs, master, eyes_closed=False, eyes_moved=False):
    r = {"ok": True, "notes": []}
    a = analyse(img)
    if a is None or a["count"] != 1:
        return {"ok": False, "notes": ["expected exactly one face"], "identity": 0, "master": 0}
    sims = {c: float(_rec.match(a["emb"], e, cv2.FaceRecognizerSF_FR_COSINE)) for c, e in refs.items()}
    r["identity"] = round(sims[coach], 3)
    r["master"] = round(float(_rec.match(a["emb"], master["emb"], cv2.FaceRecognizerSF_FR_COSINE)), 3)
    if sims[coach] < ID_MIN:
        r["ok"] = False; r["notes"].append(f"identity {sims[coach]:.2f} < {ID_MIN}")
    if max(sims, key=sims.get) != coach:
        r["ok"] = False; r["notes"].append(f"closer to {max(sims, key=sims.get)} than to {coach}")
    if r["master"] < MASTER_MIN:
        r["ok"] = False; r["notes"].append(f"similarity to master {r['master']:.2f} < {MASTER_MIN}")
    if not eyes_closed and master["tone"] is not None:
        # Measured at the master's eye points: a frame is the master with a
        # patch blended in, so the eyes are where they were. YuNet's points
        # can jump by 20-30 px on an open-mouth frame (the face box changes),
        # which sampled lids and lashes instead of the iris and read as a
        # colour shift on unchanged pixels.
        # A gaze frame moves the irises, so it is sampled at its own points.
        t, m = (a["tone"] if eyes_moved else eye_tone(img, master["face"])), master["tone"]
        dab = float(np.hypot(t[1] - m[1], t[2] - m[2]))
        dl = float(abs(t[0] - m[0]))
        r["eye_shift"] = {"ab": round(dab, 1), "L": round(dl, 1)}
        if dab > AB_MAX or dl > L_MAX:
            r["ok"] = False; r["notes"].append(f"eye colour shifted (chroma {dab:.1f}, lightness {dl:.1f})")
    return r


def contact_sheet(master_bgr, frames, face, path, tile=260):
    x, y, w, h = [int(v) for v in face[:4]]
    def crop(im):
        c = im[max(0, y - int(.15 * h)):y + int(1.2 * h), max(0, x - int(.15 * w)):x + int(1.15 * w)]
        return cv2.resize(c, (tile, int(tile * c.shape[0] / c.shape[1])))
    tiles = [("master", crop(master_bgr))] + [(n, crop(im)) for n, im in frames.items()]
    th = max(t.shape[0] for _, t in tiles)
    out = []
    for n, t in tiles:
        t = cv2.copyMakeBorder(t, 0, th - t.shape[0], 0, 0, cv2.BORDER_CONSTANT)
        cv2.putText(t, n, (6, 22), cv2.FONT_HERSHEY_SIMPLEX, .6, (0, 0, 0), 4)
        cv2.putText(t, n, (6, 22), cv2.FONT_HERSHEY_SIMPLEX, .6, (255, 255, 255), 1)
        out.append(t)
    cols = 6
    while len(out) % cols:
        out.append(np.zeros_like(out[0]))
    rows = [np.hstack(out[i:i + cols]) for i in range(0, len(out), cols)]
    cv2.imwrite(path, np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 85])
