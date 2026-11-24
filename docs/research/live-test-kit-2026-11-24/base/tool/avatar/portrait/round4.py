# Fix round 4 (non-generative): smooth headroom band, Ava right-edge revert + jaw specks, Diego chin/neck revert,
# Sofia blue speck. Inputs: round-3 finals (with the 150 px headroom) and the round-3 bases (9b58790 / fa7da02).
import sys, numpy as np, cv2, fl, herofix as hf
R3 = fl.SP + '/fp/r3'; PX = 150
SRC = {'ava': 'ava-final3', 'ethan': 'ethan-final', 'sofia': 'sofia-final', 'diego': 'diego-final'}

def shifted_base(c, shape):
    b = cv2.imread(f'{R3}/{c}-base.jpg'); H, W = shape[:2]
    out = np.zeros_like(b); out[PX:] = b[:H - PX]
    return out

def smooth_band(img, P, rows=270, fade=70, seed=4):
    """Backdrop above the head: a smooth continuation of the backdrop below (normalised large-sigma blur of
    real backdrop pixels, rows PX..700), with fine grain matched to the backdrop. Replaces backdrop pixels only,
    fading out over `fade` rows below `rows - fade`, so there is no seam and no column streaks."""
    H, W = img.shape[:2]; f = img.astype(np.float32)
    bg = (P[..., 0] > 0.6).astype(np.float32)
    src = bg.copy(); src[:PX + 20] = 0; src[700:] = 0
    num = cv2.GaussianBlur(f * src[..., None], (0, 0), 120); den = cv2.GaussianBlur(src, (0, 0), 120)[..., None]
    field = num / np.maximum(den, 1e-3)
    field = cv2.GaussianBlur(field, (0, 0), 25)
    hp = (f - cv2.GaussianBlur(f, (0, 0), 2))[300:700][bg[300:700] > 0]
    sd = float(np.std(hp.mean(-1))) if hp.size else 1.5
    noise = np.random.default_rng(seed).normal(0, sd, (H, W)).astype(np.float32)[..., None]
    w = np.ones(H, np.float32); w[rows - fade:rows] = np.linspace(1, 0, fade); w[rows:] = 0
    m = cv2.GaussianBlur(P[..., 0], (0, 0), 1.5) * w[:, None]
    m = np.clip((m - 0.2) / 0.6, 0, 1)[..., None]
    out = f * (1 - m) + (field + noise) * m
    return np.clip(out, 0, 255).astype(np.uint8)

for c in [c for c in sys.argv[1].split(',') if c in SRC]:
    im = cv2.imread(f'{R3}/{SRC[c]}.png'); H, W = im.shape[:2]
    out = im.copy()
    if c == 'ava':
        base = shifted_base(c, im.shape).astype(np.float32)
        # right hair edge: back to the round-1 pixels wherever round 3 changed them (no SD glyphs), except the
        # removed hoop area (that must not come back)
        diff = cv2.GaussianBlur(np.abs(out.astype(np.float32) - base).mean(-1), (0, 0), 3)
        reg = np.zeros((H, W), np.float32); reg[PX + 100:PX + 1350, 1300:W] = 1
        P0 = hf.segment(cv2.imread(f'{R3}/{c}-base.jpg'))
        hoop = np.zeros((H, W), np.uint8); hoop[PX:] = ((P0[..., 5] > 0.15).astype(np.uint8))[:H - PX]
        hoop[:PX + 900] = 0
        hoop = cv2.dilate(hoop, np.ones((61, 61)))
        m = ((diff > 8) * reg * (1 - hoop)).astype(np.float32)
        m = cv2.GaussianBlur(cv2.dilate(m, np.ones((9, 9))), (0, 0), 3)[..., None]
        out = np.clip(out * (1 - m) + base * m, 0, 255).astype(np.uint8)
        # orange specks at the right jaw edge (left from the hoop): small saturated orange blobs outside the face
        P = hf.segment(out)
        lab = cv2.cvtColor(out, cv2.COLOR_BGR2LAB).astype(np.float32); a, b = lab[..., 1] - 128, lab[..., 2] - 128
        box = np.zeros((H, W), np.uint8); box[PX + 950:PX + 1350, 1250:1500] = 1
        L = lab[..., 0]; Lloc = cv2.medianBlur(L.astype(np.uint8), 31).astype(np.float32)
        sp = ((b > 18) & (a > 6) & (L > Lloc + 25) & (P[..., 3] < 0.6) & (box > 0)).astype(np.uint8)   # small bright orange dots on dark hair
        n, lab_, st, _ = cv2.connectedComponentsWithStats(sp); keep = np.zeros_like(sp)
        for i in range(1, n):
            if st[i, 4] < 400: keep[lab_ == i] = 1
        keep = cv2.dilate(keep, np.ones((7, 7)))
        out = cv2.inpaint(out, keep, 6, cv2.INPAINT_TELEA)
        print('ava edge px', int((m[..., 0] > 0.5).sum()), 'specks', int(keep.sum()))
    if c == 'diego':
        base = shifted_base(c, im.shape).astype(np.float32)
        f = fl.face(out); x, y, w, h = [int(v) for v in f[:4]]
        m = np.zeros((H, W), np.float32); m[y + int(0.68 * h):min(H, PX + 1720), x + int(0.2 * w):x + int(0.8 * w)] = 1
        m = cv2.GaussianBlur(m, (0, 0), 12)[..., None]
        out = np.clip(out * (1 - m) + base * m, 0, 255).astype(np.uint8)
        print('diego chin/neck reverted to round 2')
    if c == 'sofia':
        P = hf.segment(out)
        lab = cv2.cvtColor(out, cv2.COLOR_BGR2LAB).astype(np.float32); b = lab[..., 2] - 128
        L = lab[..., 0]
        sp = ((b < -4) & (L > 100) & (P[..., 3] < 0.4)).astype(np.uint8); sp[PX + 350:] = 0   # light blue specks only, not the blue-black hair
        n, lab_, st, _ = cv2.connectedComponentsWithStats(sp); keep = np.zeros_like(sp)
        for i in range(1, n):
            if st[i, 4] < 600: keep[lab_ == i] = 1
        keep = cv2.dilate(keep, np.ones((7, 7)))
        out = cv2.inpaint(out, keep, 6, cv2.INPAINT_TELEA)
        print('sofia blue speck px', int(keep.sum()))
    P = hf.segment(out)
    out = smooth_band(out, P)
    cv2.imwrite(f'{R3}/{c}-r4.png', out); print(c, 'done', flush=True)

# Follow-up (explicit spots, round 4): two orange hoop dots at Ava's right jaw edge and the light-blue speck
# above Sofia's crown, both found by eye on the review crops; filled with OpenCV Telea from the surroundings.
def spot_fix(c, spots, box=None):
    out = cv2.imread(f'{R3}/{c}-r4.png'); H, W = out.shape[:2]
    m = np.zeros((H, W), np.uint8)
    for (x, y, r) in spots:
        cv2.circle(m, (x, y), r, 1, -1)
    if box is not None:
        x0, y0, x1, y1 = box
        lab = cv2.cvtColor(out, cv2.COLOR_BGR2LAB).astype(np.float32)
        sub = np.zeros((H, W), np.uint8); sub[y0:y1, x0:x1] = 1
        m |= (sub & ((lab[..., 2] - 128) < 0)).astype(np.uint8)
        m = cv2.dilate(m, np.ones((5, 5)))
    out = cv2.inpaint(out, m, 7, cv2.INPAINT_TELEA)
    cv2.imwrite(f'{R3}/{c}-r4.png', out)
    return int(m.sum())
if len(sys.argv) > 2 and sys.argv[2] == 'spots':
    print('ava spots', spot_fix('ava', [(1280, 1261, 11), (1224, 1427, 11)]))
    print('sofia speck', spot_fix('sofia', [], box=(880, 215, 975, 275)))
if len(sys.argv) > 2 and sys.argv[2] == 'speck2':
    out = cv2.imread(f'{R3}/sofia-r4.png'); H, W = out.shape[:2]
    g = cv2.cvtColor(out, cv2.COLOR_BGR2GRAY).astype(np.float32); loc = cv2.medianBlur(g.astype(np.uint8), 41).astype(np.float32)
    m = np.zeros((H, W), np.uint8); m[200:280, 880:990] = ((g - loc) > 10)[200:280, 880:990]
    m = cv2.dilate(m, np.ones((7, 7)))
    out = cv2.inpaint(out, m, 7, cv2.INPAINT_TELEA); cv2.imwrite(f'{R3}/sofia-r4.png', out); print('sofia speck2', int(m.sum()))
