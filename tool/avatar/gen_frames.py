"""Generate the talking-avatar frame patches for the four coaches.

Usage:
  python tool/avatar/gen_frames.py [--portraits assets/coaches] [--out assets/avatar]
                                   [--review <dir>] [--coaches ava,ethan,sofia,diego]

For each coach it reads the approved portrait `<portraits>/<id>-hero.jpg` and,
with LivePortrait (MIT code and weights; InsightFace replaced by YuNet), renders
mouth shapes (visemes), blinks and a few expressions. Each frame is blended into
the untouched portrait only inside a feathered region (mouth, eyes or head), so
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
# `rest` has no patch: it is the approved portrait itself.
VISEMES = {
    "mbp": dict(lip=0.0, smile=-0.1),               # M, B, P: lips pressed
    "a": dict(lip=0.6),                             # A (father, casa)
    "e": dict(lip=0.3, grin=8),                     # E (bed, mesa)
    "i": dict(lip=0.15, grin=10),                   # I (see, sí)
    "o": dict(lip=0.45, smile=-0.3, purse=10),      # O (go, oso)
    "u": dict(lip=0.12, smile=-0.3, purse=15),      # U / W (you, luna)
    "fv": dict(lip=0.05, purse=5),                  # F, V
    "l": dict(lip=0.35, smile=-0.1),                # L
    "th": dict(lip=0.2),                            # TH (and Spanish soft d)
    "cons": dict(lip=0.18, grin=4),                 # T D N S K G R CH J ...
}
EYES = {
    "blink_half": dict(eye=0.16),
    "blink_closed": dict(eye=0.0),
}
# Whole-head expressions (listening nods, attentive brows, thinking).
EXPRESSIONS = {
    "nod_1": dict(pitch=-2.5),
    "nod_2": dict(pitch=-5.0),
    "attentive": dict(brow=10),
    "think": dict(lip=0.0, gaze_x=8, gaze_y=12, roll=2.5),
}


def regions(face, shape):
    """Feathered masks (float 0..1, full image size) and their boxes, from YuNet's 5 points."""
    H, W = shape[:2]
    re, le, nose, rm, lm = face[4:6], face[6:8], face[8:10], face[10:12], face[12:14]
    eye_c = (re + le) / 2
    mouth_c = (rm + lm) / 2
    iod = float(np.linalg.norm(le - re))
    roll = math.degrees(math.atan2(le[1] - re[1], le[0] - re[0]))
    # Unit vector "down the face" (perpendicular to the eye line).
    down = np.array([-math.sin(math.radians(roll)), math.cos(math.radians(roll))])

    def ellipse_mask(center, axes, feather):
        m = np.zeros((H, W), np.float32)
        cv2.ellipse(m, (int(center[0]), int(center[1])), (int(axes[0]), int(axes[1])), roll, 0, 360, 1.0, -1)
        k = int(feather) | 1
        m = cv2.GaussianBlur(m, (k, k), 0)
        return m

    # Mouth: lips, chin and jaw (an open mouth drops the chin).
    mouth = ellipse_mask(mouth_c + down * 0.28 * iod, (0.95 * iod, 0.78 * iod), 0.35 * iod)
    # Eyes: both eyes and lids, not the brows' upper edge.
    eyes = ellipse_mask(eye_c - down * 0.05 * iod, (1.05 * iod, 0.36 * iod), 0.22 * iod)
    # Head: whole face and hairline.
    head = ellipse_mask(eye_c + down * 0.45 * iod, (1.75 * iod, 2.15 * iod), 0.7 * iod)
    out = {}
    for name, m in (("mouth", mouth), ("eyes", eyes), ("head", head)):
        ys, xs = np.where(m > 1.0 / 255)
        box = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
        box = [max(0, box[0]), max(0, box[1]), min(W, box[2]), min(H, box[3])]
        out[name] = (m, box)
    return out


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
    args = ap.parse_args()

    eng = Engine()
    refs = verify.reference_embeddings()
    failures = []
    for coach in args.coaches.split(","):
        t0 = time.time()
        src = os.path.join(args.portraits, f"{coach}-hero.jpg")
        bgr = cv2.imread(src)
        if bgr is None:
            sys.exit(f"missing portrait {src}")
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        st = eng.prepare(rgb)
        reg = regions(st["face"], rgb.shape)
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
            "frames": {},
        }
        review = {}
        jobs = [(n, kw, "mouth") for n, kw in VISEMES.items()] + \
               [(n, kw, "eyes") for n, kw in EYES.items()] + \
               [(n, kw, "head") for n, kw in EXPRESSIONS.items()]
        for name, kw, region in jobs:
            _, full = eng.render(st, **kw)
            mask, box = reg[region]
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
