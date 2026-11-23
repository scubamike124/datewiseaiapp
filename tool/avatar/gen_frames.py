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
    # Tuned for masters with closed, relaxed lips (the candidate finals). The
    # earlier values compensated for a broad toothy smile in the source
    # (smile < 0, strong purse); on a neutral mouth they made O/U a pout.
    "mbp": dict(lip=0.0, smile=-0.05),              # M, B, P: lips pressed
    "a": dict(lip=0.5, smile=0.1),                  # A (father, casa), stressed: jaw open, not a shout
    "a2": dict(lip=0.36, smile=0.08),                # A, unstressed / half open
    "e": dict(lip=0.32, grin=4, smile=0.2),         # E (bed, mesa)
    "e2": dict(lip=0.2, grin=3, smile=0.1),
    "i": dict(lip=0.14, grin=6),                    # I (see, si)
    "i2": dict(lip=0.07, grin=4),
    "o": dict(lip=0.14, smile=-0.25, purse=18),     # O (go, oso): rounded, small opening; teeth mostly hidden (review sheets)
    "o2": dict(lip=0.1, smile=-0.2, purse=15),
    "u": dict(lip=0.08, smile=-0.1, purse=11),      # U / W (you, luna)
    "u2": dict(lip=0.04, smile=-0.1, purse=12),
    "fv": dict(lip=0.05, purse=2),                  # F, V
    "l": dict(lip=0.38),                            # L
    "th": dict(lip=0.22),                           # TH (and Spanish soft d)
    "cons": dict(lip=0.2, grin=2),                  # T D N S K G R ...
    "sh": dict(lip=0.14, smile=-0.1, purse=5),      # SH CH J (lips forward)
}
# Per-coach offsets added to every mouth shape, so speech keeps the smile of
# the rest pose (Ava's master smiles softly; without this her visemes lost the
# smile, and the mouth "pumped" between smiling and neutral while she spoke).
COACH_MOUTH = {"ava": dict(smile=0.3)}
# Rounded shapes do not take the smile offset (Ava's smile pulled the lips
# back and showed her upper incisors on O and U); they get extra purse
# instead. Per-coach `a` opening: a little smaller where the full opening
# showed a lopsided mouth or dark gaps between the teeth.
ROUNDED = {"o", "o2", "u", "u2", "sh", "fv"}
COACH_ROUNDED = {"ava": dict(purse=3.0)}
COACH_A = {"ava": 0.44, "ethan": 0.44, "diego": 0.44}
# Per-coach eye-frame overrides. Diego's full glance moved the iris far
# enough that the gate's iris sample caught the lid (chroma 5.1 > 5); a
# slightly smaller glance reads the same and keeps the gate unchanged.
COACH_EYES = {"diego": {"gaze": dict(gaze_x=7, gaze_y=10)}}

# Eye patches: two blink stages and the thinking glance (eyes up and aside).
# Head motion (nods, tilts) is a whole-image transform in the app, not a
# generated frame, so nothing warps the hair, hands or background.
EYES = {
    "blink_half": dict(eye=0.16),   # replaced by a per-eye symmetric render (symmetric_half_blink)
    "blink_closed": dict(eye=0.0),
    "gaze": dict(gaze_x=8, gaze_y=12),
}

# LivePortrait 203-point layout: the two eyes (image left, image right) and the lips.
EYE_L, EYE_R, LIPS = list(range(0, 24)), list(range(24, 48)), list(range(48, 96))


def eye_apertures(eng, rgb, lmk_init):
    """Mean opening of each eye (pixels): eye-outline area / eye width, from
    LivePortrait's landmarks (independent of head tilt)."""
    l = eng.lmk.run(rgb, lmk_init)
    out = []
    for idx in (EYE_L, EYE_R):
        pts = l[idx].astype(np.float32)
        hull = cv2.convexHull(pts)
        width = float(max(np.linalg.norm(p - q) for p in pts for q in pts))
        out.append(float(cv2.contourArea(hull)) / max(width, 1.0))  # mean opening; roll-invariant
    return out


def symmetric_half_blink(eng, st, mask, rgb):
    """A half blink with both eyes equally closed (~45% of their opening).
    One eye-ratio setting closes the two eyes unevenly on a tilted or
    smiling face (it read as a wink), so each eye takes the render whose
    opening is closest to the target, and the two halves are joined at the
    bridge of the nose."""
    open_ap = eye_apertures(eng, rgb, st["lmk203"])
    target = [0.45 * a for a in open_ap]
    renders = []
    for r in (0.05, 0.08, 0.11, 0.14, 0.17, 0.2, 0.24, 0.28):
        _, full = eng.render(st, eye=r)
        renders.append((full, eye_apertures(eng, full, st["lmk203"])))
    pick = [min(renders, key=lambda x: abs(x[1][k] - target[k])) for k in (0, 1)]
    face = st["face"]
    mid = int((face[4] + face[6]) / 2)
    H, W = rgb.shape[:2]
    left = np.zeros((H, W), np.float32)
    left[:, :mid] = 1
    k = int(0.15 * abs(face[6] - face[4])) | 1
    left = cv2.GaussianBlur(left, (k, k), 0)
    full = (pick[0][0].astype(np.float32) * left[..., None] +
            pick[1][0].astype(np.float32) * (1 - left[..., None])).astype(np.uint8)
    got = [pick[0][1][0] / open_ap[0], pick[1][1][1] / open_ap[1]]
    return full, got

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
        # Pull the mask in from the jaw line by the feather's reach, so the
        # feathered edge fades out inside the face: a patch whose jaw moved
        # never blends a second, offset jaw outline over the original one.
        er = max(1, int(0.12 * iod))
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


def teeth_tone(gen, orig, mask):
    """Teeth come out of the renderer grey, cyan or dark. Inside the mouth
    mask, pixels that are teeth in the frame (light, low chroma) but not in
    the portrait are moved toward natural ivory: L* toward 76, a* 1.5,
    b* 9 (the same target for every coach, so no chalk-white dentures).
    Small dark gaps between teeth (inside the teeth area, darker than the
    teeth around them) are filled toward the local tooth colour. Lips, skin
    and everything outside the teeth are untouched. L* is on the 0-100
    scale throughout."""
    lab = cv2.cvtColor(gen, cv2.COLOR_RGB2LAB).astype(np.float32)
    lab0 = cv2.cvtColor(orig, cv2.COLOR_RGB2LAB).astype(np.float32)
    L, a, b = lab[..., 0] * 100 / 255, lab[..., 1] - 128, lab[..., 2] - 128
    L0 = lab0[..., 0] * 100 / 255
    teeth = (L > 50) & (np.hypot(a, b) < 26) & (a < 12) & (mask > 0.3) & (np.abs(L - L0) > 5)
    t8 = teeth.astype(np.uint8)
    # gaps: closed teeth area minus teeth, dark, small
    area = cv2.morphologyEx(t8, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    gaps = (area > 0) & ~teeth & (L < 45) & (mask > 0.3)
    w = cv2.GaussianBlur(teeth.astype(np.float32), (0, 0), 1.2) * 0.85
    L2 = L + w * (76.0 - L) * 0.7
    a2 = a + w * (1.5 - a)
    b2 = b + w * (9.0 - b)
    if gaps.any():
        tw = cv2.GaussianBlur(teeth.astype(np.float32), (0, 0), 3) + 1e-3
        Lt = cv2.GaussianBlur(np.where(teeth, L2, 0).astype(np.float32), (0, 0), 3) / tw
        g = cv2.GaussianBlur(gaps.astype(np.float32), (0, 0), 0.8) * 0.7
        L2 = L2 + g * (Lt * 0.85 - L2)
        a2 = a2 + g * (1.5 - a2)
        b2 = b2 + g * (9.0 - b2)
    lab[..., 0] = np.clip(L2, 0, 100) * 255 / 100
    lab[..., 1] = 128 + a2
    lab[..., 2] = 128 + b2
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2RGB)


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
    ap.add_argument("--max-width", type=int, default=1080,
                    help="frames are made on the portrait scaled to at most this width (decoded-memory budget)")
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
        src_h, src_w = bgr.shape[:2]
        if bgr.shape[1] > args.max_width:
            # The app decodes the portrait at the manifest size (lib/avatar/avatar_frames.dart),
            # so a large final portrait costs no more memory on the voice stage than this.
            h = round(bgr.shape[0] * args.max_width / bgr.shape[1])
            bgr = cv2.resize(bgr, (args.max_width, h), interpolation=cv2.INTER_AREA)
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
            "source_width": src_w,
            "source_height": src_h,
            "generator": "LivePortrait (MIT) + YuNet (MIT); tool/avatar/gen_frames.py",
            "crop_scale": args.crop_scale,
            "frames": {},
        }
        review = {}
        def mouth_kw(n, kw):
            extra = COACH_ROUNDED.get(coach, {}) if n in ROUNDED else COACH_MOUTH.get(coach, {})
            out = {k: kw.get(k, 0.0) + extra.get(k, 0.0) for k in {**kw, **extra}}
            if n == "a" and coach in COACH_A:
                out["lip"] = COACH_A[coach]
            return out
        jobs = [(n, mouth_kw(n, kw), "mouth") for n, kw in VISEMES.items()] + \
               [(n, COACH_EYES.get(coach, {}).get(n, kw), "eyes") for n, kw in EYES.items()]
        lips = st["lmk203"][LIPS]
        manifest["mouth"] = [round(float(lips[:, 0].mean()), 1), round(float(lips[:, 1].mean()), 1)]
        manifest["mouth_width"] = round(float(lips[:, 0].max() - lips[:, 0].min()), 1)
        manifest["chin"] = round(float(st["lmk203"][126][1]), 1)
        for name, kw, region in jobs:
            mask, box = reg[region]
            if name == "blink_half":
                full, got = symmetric_half_blink(eng, st, mask, rgb)
                manifest["blink_half_openings"] = [round(g, 2) for g in got]
                print(f"{coach}/blink_half: eye openings {got[0]:.2f} / {got[1]:.2f} of open", flush=True)
            else:
                _, full = eng.render(st, **kw)
            full = match_detail(full, rgb, mask)
            if region == "mouth":
                full = teeth_tone(full, rgb, mask)
            comp = blend(rgb, full, mask)
            comp_bgr = cv2.cvtColor(comp, cv2.COLOR_RGB2BGR)
            res = verify.check_frame(comp_bgr, coach, refs, master, eyes_closed=name.startswith("blink"),
                                     eyes_moved=name == "gaze")
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
