"""Generate the talking-avatar frame patches for the four coaches.

Usage:
  python tool/avatar/gen_frames.py [--portraits assets/coaches] [--out assets/avatar]
                                   [--review <dir>] [--coaches ava,ethan,sofia,diego]

For each coach it reads the approved portrait `<portraits>/<id>-hero.jpg` and,
with LivePortrait (MIT code and weights; InsightFace replaced by YuNet), renders
mouth shapes (visemes), blinks and a few expressions. Each frame is blended into
the untouched portrait only inside a feathered region (mouth or eyes), so
everything outside that region stays byte-for-byte the approved image. The
region's bounding box is saved as a small JPEG patch plus `manifest.json`; the
app draws the patches over the portrait (lib/avatar/).

Every frame is gated (verify.py): SFace identity vs. the approved reference and
vs. the master, the eye-tone check, and the landmark motion of the region. A
frame that fails is not written, and the script exits non-zero.

No face restoration (GFPGAN/CodeFormer) is used: it changed eye colour before.
"""
import argparse, json, math, os, sys, time
import cv2, numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lp_engine import Engine  # noqa: E402
import verify  # noqa: E402

COACHES = ["ava", "ethan", "sofia", "diego"]

# Mouth shapes. Names must match lib/avatar/viseme.dart (Viseme.asset).
# `rest` has no patch: it is the approved portrait itself. Vowels have a full
# (stressed) and a half (unstressed) opening.
VISEMES = {
    "mbp": dict(lip=0.0, smile=-0.1),               # M, B, P: lips pressed
    "a": dict(lip=0.6),                             # A (father, casa), stressed
    "a2": dict(lip=0.34),                           # A, unstressed / half open
    "e": dict(lip=0.3, grin=8),                     # E (bed, mesa)
    "e2": dict(lip=0.17, grin=6),
    "i": dict(lip=0.15, grin=10),                   # I (see, sí)
    "i2": dict(lip=0.07, grin=8),
    "o": dict(lip=0.45, smile=-0.3, purse=10),      # O (go, oso)
    "o2": dict(lip=0.27, smile=-0.3, purse=8),
    "u": dict(lip=0.12, smile=-0.3, purse=15),      # U / W (you, luna)
    "u2": dict(lip=0.05, smile=-0.3, purse=18),
    "fv": dict(lip=0.05, purse=5),                  # F, V
    "l": dict(lip=0.35, smile=-0.1),                # L
    "th": dict(lip=0.2),                            # TH (and Spanish soft d)
    "cons": dict(lip=0.18, grin=4),                 # T D N S K G R ...
    "sh": dict(lip=0.16, smile=-0.25, purse=6),     # SH CH J (lips forward)
}
# Eye patches: two blink stages and the thinking glance (eyes up and aside).
# Head motion (nods, tilts) is a whole-image transform in the app, not a
# generated frame, so nothing warps the hair, hands or background.
EYES = {
    "blink_half": dict(eye=0.16),
    "blink_closed": dict(eye=0.0),
    "gaze": dict(gaze_x=8, gaze_y=12),
}

# LivePortrait landmark indices (203-point layout): face contour.
CONTOUR = list(range(108, 145))


def regions(face, shape, lmk203=None):
    """Feathered masks (float 0..1, full image size) and their boxes, from YuNet's 5 points.
    The mouth mask is clipped to the face contour, so a hand under the chin
    (or the neck and collar) is never warped."""
    H, W = shape[:2]
    re, le, nose, rm, lm = face[4:6], face[6:8], face[8:10], face[10:12], face[12:14]
    eye_c = (re + le) / 2
    mouth_c = (rm + lm) / 2
    iod = float(np.linalg.norm(le - re))
    roll = math.degrees(math.atan2(le[1] - re[1], le[0] - re[0]))
    down = np.array([-math.sin(math.radians(roll)), math.cos(math.radians(roll))])

    def ellipse(center, axes):
        m = np.zeros((H, W), np.float32)
        cv2.ellipse(m, (int(center[0]), int(center[1])), (int(axes[0]), int(axes[1])), roll, 0, 360, 1.0, -1)
        return m

    def feather(m, f):
        k = int(f) | 1
        return cv2.GaussianBlur(m, (k, k), 0)

    mouth = ellipse(mouth_c + down * 0.25 * iod, (0.95 * iod, 0.72 * iod))
    if lmk203 is not None:
        face_poly = np.zeros((H, W), np.uint8)
        pts = lmk203[CONTOUR].astype(np.int32)
        # Close the contour over the forehead so only the jaw line clips.
        top = np.array([[pts[-1][0], int(eye_c[1] - iod)], [pts[0][0], int(eye_c[1] - iod)]], np.int32)
        cv2.fillPoly(face_poly, [np.vstack([pts, top])], 1)
        # Keep a thin band inside the jaw line for the feather.
        er = max(1, int(0.04 * iod))
        face_poly = cv2.erode(face_poly, np.ones((er, er), np.uint8))
        mouth = mouth * face_poly.astype(np.float32)
    mouth = feather(mouth, 0.3 * iod)
    eyes = feather(ellipse(eye_c - down * 0.05 * iod, (1.05 * iod, 0.36 * iod)), 0.22 * iod)
    out = {}
    for name, m in (("mouth", mouth), ("eyes", eyes)):
        ys, xs = np.where(m > 1.0 / 255)
        box = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
        box = [max(0, box[0]), max(0, box[1]), min(W, box[2]), min(H, box[3])]
        out[name] = (m, box)
    return out


def match_detail(gen, orig, mask):
    """Match the generated region's sharpness and grain to the portrait's:
    an unsharp mask scaled so the fine-detail energy matches, then luma
    noise for any remaining deficit. No face restoration, no colour change."""
    sel = mask > 0.5
    if sel.sum() < 100:
        return gen
    def hf(img):
        g = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY).astype(np.float32)
        return g - cv2.GaussianBlur(g, (0, 0), 1.0)
    so, sg = hf(orig)[sel].std(), hf(gen)[sel].std()
    out = gen.astype(np.float32)
    if sg > 0 and so > sg:
        k = min(2.5, so / sg - 1) * 1.6
        blur = cv2.GaussianBlur(out, (0, 0), 1.0)
        out = out + k * (out - blur)
    sg2 = hf(np.clip(out, 0, 255).astype(np.uint8))[sel].std()
    if so > sg2:
        rng = np.random.default_rng(1234)
        n = rng.normal(0, math.sqrt(so ** 2 - sg2 ** 2) * 0.8, out.shape[:2]).astype(np.float32)
        out = out + n[..., None]
    return np.clip(out, 0, 255).astype(np.uint8)


def blend(orig, gen, mask):
    m = mask[..., None]
    return np.clip(gen.astype(np.float32) * m + orig.astype(np.float32) * (1 - m), 0, 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--portraits", default="assets/coaches")
    ap.add_argument("--out", default="assets/avatar")
    ap.add_argument("--review", default=None, help="also write full frames and a contact sheet here")
    ap.add_argument("--coaches", default=",".join(COACHES))
    ap.add_argument("--quality", type=int, default=88)
    ap.add_argument("--crop-scale", type=float, default=1.9,
                    help="LivePortrait crop size relative to the face (smaller = more pixels on the mouth)")
    args = ap.parse_args()
    coaches = args.coaches.split(",")
    unknown = [c for c in coaches if c not in COACHES]
    if unknown:
        sys.exit(f"unknown coach(es) {unknown}; choose from {COACHES}")

    eng = Engine(crop_scale=args.crop_scale)
    refs = verify.reference_embeddings()
    failures = []
    for coach in coaches:
        t0 = time.time()
        src = os.path.join(args.portraits, f"{coach}-hero.jpg")
        bgr = cv2.imread(src)
        if bgr is None:
            sys.exit(f"missing portrait {src}")
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        st = eng.prepare(rgb)
        reg = regions(st["face"], rgb.shape, st["lmk203"])
        master = verify.analyse(bgr)
        out_dir = os.path.join(args.out, coach)
        os.makedirs(out_dir, exist_ok=True)
        for f in os.listdir(out_dir):
            if f.endswith(".jpg"):
                os.remove(os.path.join(out_dir, f))
        manifest = {
            "coach": coach,
            "source": os.path.basename(src),
            "width": rgb.shape[1],
            "height": rgb.shape[0],
            "generator": "LivePortrait (MIT) + YuNet (MIT); tool/avatar/gen_frames.py",
            "crop_scale": args.crop_scale,
            "frames": {},
        }
        review = {}
        jobs = [(n, kw, "mouth") for n, kw in VISEMES.items()] + \
               [(n, kw, "eyes") for n, kw in EYES.items()]
        for name, kw, region in jobs:
            _, full = eng.render(st, **kw)
            mask, box = reg[region]
            full = match_detail(full, rgb, mask)
            comp = blend(rgb, full, mask)
            comp_bgr = cv2.cvtColor(comp, cv2.COLOR_RGB2BGR)
            res = verify.check_frame(comp_bgr, coach, refs, master, eyes_closed=name.startswith("blink"))
            res["frame"] = name
            if not res["ok"]:
                failures.append(f"{coach}/{name}: {'; '.join(res['notes'])}")
                print("REJECTED", coach, name, res["notes"], flush=True)
                if args.review:
                    os.makedirs(os.path.join(args.review, coach), exist_ok=True)
                    cv2.imwrite(os.path.join(args.review, coach, f"REJECTED-{name}.jpg"), comp_bgr)
                continue
            x0, y0, x1, y1 = box
            cv2.imwrite(os.path.join(out_dir, f"{name}.jpg"), comp_bgr[y0:y1, x0:x1],
                        [cv2.IMWRITE_JPEG_QUALITY, args.quality, cv2.IMWRITE_JPEG_OPTIMIZE, 1])
            manifest["frames"][name] = {"region": region, "rect": [x0, y0, x1 - x0, y1 - y0],
                                        "identity": res["identity"], "master": res["master"]}
            review[name] = comp_bgr
            print(f"{coach}/{name}: id={res['identity']:.3f} master={res['master']:.3f} "
                  f"eye={res.get('eye_shift')}", flush=True)
        with open(os.path.join(out_dir, "manifest.json"), "w") as fh:
            json.dump(manifest, fh, indent=1)
        if args.review:
            rd = os.path.join(args.review, coach)
            os.makedirs(rd, exist_ok=True)
            for n, im in review.items():
                cv2.imwrite(os.path.join(rd, f"{n}.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 92])
            verify.contact_sheet(bgr, review, st["face"], os.path.join(args.review, f"{coach}-sheet.jpg"))
        print(f"{coach}: {len(manifest['frames'])} frames in {time.time() - t0:.0f}s", flush=True)
    if failures:
        print("\nREJECTED FRAMES (not written; the app skips a missing shape):\n  " + "\n  ".join(failures))
        sys.exit(1)
    print("\nall frames passed identity and eye-colour checks")


if __name__ == "__main__":
    main()
