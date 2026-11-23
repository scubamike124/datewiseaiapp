import os
"""DateWise portrait intake: accept the owner's 8 high-res coach portraits only if they keep the approved identities.

Usage: python portrait_intake.py <incoming_dir> [--apply] [--app <flutter_repo_dir>]
  incoming_dir holds {ava,ethan,sofia,diego}-{hero,avatar}.{jpg,jpeg,png}
  Without --apply it only reports. With --apply, accepted files are written (sRGB JPEG, q=92) to
  dw-concepts/img/<coach>-<slot>.jpg, which the mockups (and the app's assets/coaches/) use.

Checks per file:
  1. Resolution: hero >= 1024 px wide and >= 1400 px tall, portrait orientation; avatar >= 1024 px on the short side.
  2. Exactly one face (YuNet, MIT), large enough (>= 300 px) for lip-sync.
  3. Identity: SFace (Apache-2.0) cosine similarity to the approved reference crop from ref-003 must be >= 0.45
     (OpenCV's same-person threshold is 0.363; we demand more), AND it must be higher for its own coach than for
     any other coach (no swapped faces).
  4. Eye colour: mean iris hue/brightness near the detected eye landmarks compared with the reference; a large shift
     is flagged for manual review (the earlier face-restoration attempt turned brown eyes blue).
  5. Avatar only: head roll (tilt) <= 8 degrees, for lip-sync tools.
Nothing is altered: accepted images are only re-encoded.
"""
import sys, os, json, math, numpy as np, cv2

HERE = os.path.dirname(os.path.abspath(__file__))
S = os.path.dirname(HERE)
# Approved identity crops (the same files the avatar frame gate uses) and OpenCV Zoo models from the
# avatar tool cache (tool/avatar/setup.sh), unless overridden.
REF_DIR = os.environ.get("DW_REF_DIR", os.path.join(HERE, "..", "refs"))
REF = {c: os.path.join(REF_DIR, f"crop-{c}.png") for c in ["ava", "ethan", "sofia", "diego"]}
MODELS = os.path.join(os.environ.get("AVATAR_TOOLS", os.path.expanduser("~/.cache/datewise-avatar-tools")), "models")
OUT = os.environ.get("DW_INTAKE_OUT", os.path.join(S, "dw-concepts", "img"))
det = cv2.FaceDetectorYN.create(os.path.join(MODELS, "yunet.onnx"), "", (320, 320), 0.8, 0.3, 5000)
rec = cv2.FaceRecognizerSF.create(os.path.join(MODELS, "sface.onnx"), "")


def faces(img, max_side=1600):
    h, w = img.shape[:2]
    scale = 1.0
    if max(h, w) > max_side:  # detect on a smaller copy, map back
        scale = max_side / max(h, w)
        small = cv2.resize(img, (int(w * scale), int(h * scale)))
    else:
        small = img
    det.setInputSize((small.shape[1], small.shape[0]))
    _, f = det.detect(small)
    if f is None:
        return []
    f = f.copy()
    f[:, :14] /= scale
    return list(f)


def embed(img, face):
    return rec.feature(rec.alignCrop(img, face))


def eye_tone(img, face):
    out = []
    for ex, ey in [(face[4], face[5]), (face[6], face[7])]:
        r = max(3, int(face[2] * 0.035))
        patch = img[int(ey) - r:int(ey) + r, int(ex) - r:int(ex) + r]
        if patch.size:
            hsv = cv2.cvtColor(patch, cv2.COLOR_BGR2HSV).reshape(-1, 3).astype(float)
            dark = hsv[hsv[:, 2] < np.percentile(hsv[:, 2], 60)]  # iris/pupil, not the white
            out.append(dark.mean(axis=0) if len(dark) else hsv.mean(axis=0))
    return np.mean(out, axis=0) if out else None


def ref_data():
    d = {}
    for c, p in REF.items():
        img = cv2.imread(p)
        big = cv2.resize(img, (img.shape[1] * 3, img.shape[0] * 3), interpolation=cv2.INTER_CUBIC)
        f = max(faces(big), key=lambda x: x[2] * x[3])
        d[c] = (embed(big, f), eye_tone(big, f))
    return d


def check(path, coach, slot, refs):
    img = cv2.imread(path)
    r = {"file": os.path.basename(path), "coach": coach, "slot": slot, "ok": True, "notes": []}
    if img is None:
        return {**r, "ok": False, "notes": ["unreadable image"]}
    h, w = img.shape[:2]
    r["size"] = f"{w}x{h}"
    if slot == "hero" and not (w >= 1024 and h >= 1400 and h > w):
        r["ok"] = False; r["notes"].append("hero must be portrait, at least 1024x1400")
    if slot == "avatar" and min(w, h) < 1024:
        r["ok"] = False; r["notes"].append("avatar must be at least 1024 px on the short side")
    fs = faces(img)
    if not fs:  # YuNet misses very large faces (about 700 px and up): retry on a smaller copy (detection only, same thresholds)
        fs = faces(img, 1280) or faces(img, 1024)
    if len(fs) != 1:
        r["ok"] = False; r["notes"].append(f"expected exactly one face, found {len(fs)}")
        if not fs:
            return r
    f = max(fs, key=lambda x: x[2] * x[3])
    if f[3] < 300:
        r["ok"] = False; r["notes"].append(f"face too small for lip-sync ({int(f[3])} px tall)")
    e = embed(img, f)
    sims = {c: float(rec.match(e, refs[c][0], cv2.FaceRecognizerSF_FR_COSINE)) for c in refs}
    r["similarity"] = {c: round(s, 3) for c, s in sims.items()}
    if sims[coach] < 0.45:
        r["ok"] = False; r["notes"].append(f"identity mismatch: similarity to approved {coach} is {sims[coach]:.2f} (< 0.45)")
    best = max(sims, key=sims.get)
    if best != coach:
        r["ok"] = False; r["notes"].append(f"face is closer to {best} than to {coach}")
    tone, rtone = eye_tone(img, f), refs[coach][1]
    if tone is not None and rtone is not None:
        dh = min(abs(tone[0] - rtone[0]), 180 - abs(tone[0] - rtone[0]))
        dv = abs(tone[2] - rtone[2])
        r["eye_shift"] = {"hue": round(dh, 1), "brightness": round(dv, 1)}
        if dh > 25 or dv > 45:
            r["ok"] = False; r["notes"].append("eye colour differs from the approved reference; review by eye")
    if slot == "avatar":
        roll = math.degrees(math.atan2(f[7] - f[5], f[6] - f[4]))
        r["head_roll_deg"] = round(roll, 1)
        if abs(roll) > 8:
            r["ok"] = False; r["notes"].append(f"head tilted {roll:.0f} degrees; lip-sync master should be level")
    return r


def main():
    src = sys.argv[1]
    apply = "--apply" in sys.argv
    refs = ref_data()
    results = []
    for coach in REF:
        for slot in ["hero", "avatar"]:
            cand = [os.path.join(src, f"{coach}-{slot}.{x}") for x in ("jpg", "jpeg", "png", "JPG", "PNG")]
            p = next((c for c in cand if os.path.exists(c)), None)
            if not p:
                results.append({"coach": coach, "slot": slot, "ok": False, "notes": ["missing"]}); continue
            r = check(p, coach, slot, refs)
            if r["ok"] and apply:
                dst = os.path.join(OUT, f"{coach}-{slot}.jpg")
                cv2.imwrite(dst, cv2.imread(p), [cv2.IMWRITE_JPEG_QUALITY, 92])
                r["written"] = dst
                if "--app" in sys.argv:
                    app = sys.argv[sys.argv.index("--app") + 1]
                    adst = os.path.join(app, "assets", "coaches", f"{coach}-{slot}.jpg")
                    os.makedirs(os.path.dirname(adst), exist_ok=True)
                    cv2.imwrite(adst, cv2.imread(p), [cv2.IMWRITE_JPEG_QUALITY, 90])
                    r["written_app"] = adst
            results.append(r)
    print(json.dumps(results, indent=1, ensure_ascii=False))
    print(f"\n{sum(r['ok'] for r in results)}/8 accepted" + ("" if apply else " (report only; use --apply to install)"))


if __name__ == "__main__":
    main()
