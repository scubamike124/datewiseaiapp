import sys, numpy as np, cv2, fl, herofix as hf
from lp_engine import Engine
NEG = ("face, eyes, skin, earrings, jewelry, hands, text, watermark, deformed, blurry, cartoon, painting, grey patches, white spots")
BGN = {'ava': 'dark teal', 'ethan': 'dark slate blue', 'sofia': 'dark terracotta', 'diego': 'dark olive green'}
HAIR = {'ava': 'auburn wavy hair', 'ethan': 'curly light brown hair', 'sofia': 'long dark brown wavy hair', 'diego': 'short curly black hair'}
eng = Engine()
def lmk(img):
    return eng.prepare(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))['lmk203']
for c in sys.argv[1].split(','):
    im = cv2.imread(hf.IN + f'/{c}-hero.jpg'); P = np.load(fl.SP + f'/fp/hf/{c}-P.npy').astype(np.float32); f = fl.face(im)
    prompt = f'photo, {HAIR[c]}, plain {BGN[c]} studio background, soft light, photorealistic'
    out = im
    if c == 'ava':
        # hoops -> small studs: remove the hoop (accessory class below the earlobes), keep the stud on the lobe
        ear = (P[..., 5] > 0.3).astype(np.uint8); ear[:int(f[1] + 0.45 * f[3]), :] = 0
        skin = cv2.dilate(((P[..., 3] > 0.5) | (P[..., 2] > 0.5)).astype(np.uint8), np.ones((25, 25)))
        ear = cv2.dilate(ear, np.ones((15, 15))) & (1 - skin)
        n, lab, st, _ = cv2.connectedComponentsWithStats(ear)
        for i in range(1, n):
            if st[i, 4] > 300:
                out = hf.sd_inpaint(out, (lab == i).astype(np.uint8), f'photo, {HAIR[c]} falling over the neck, no earrings, plain {BGN[c]} studio background, photorealistic', NEG + ', hoop', seed=20 + i)
        print(c, 'hoops removed', n - 1, flush=True)
    out, m = hf.patch_fill(out, P, f[:4])
    print(c, 'patches', int(m.sum()), flush=True)
    out = hf.wire_loops(out, P)
    L = lmk(out)
    if c == 'sofia':
        lm = cv2.GaussianBlur(hf.lips_mask(L, out.shape), (0, 0), 2)
        out = hf.lab_edit(out, lm, da=-2, db=1, ladd=3, cmul=0.82)
        out = hf.degloss_lips(out, hf.lips_mask(L, out.shape), strength=0.5, outline=0.6)
    if c == 'ava':
        lmm = hf.lips_mask(L, out.shape)
        lab = cv2.cvtColor(out, cv2.COLOR_BGR2LAB).astype(np.float32); a = lab[..., 1] - 128
        am = np.median(a[lmm > 0.5])
        green = cv2.GaussianBlur(((a < am - 6) & (lmm > 0.5)).astype(np.float32), (0, 0), 2) * cv2.GaussianBlur(lmm, (0, 0), 2)
        lab[..., 1] = 128 + a + green * (am - a) * 0.9      # cupid's bow back to the lip colour
        out = cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
        out = hf.degloss_lips(out, lmm, strength=0.45, outline=0.3)
        out = hf.soft_liner(out, L, amount=0.45)
    if c == 'diego':
        # chin seam (thin dark vertical line from the source) and small dark forehead specks: inpaint, same geometry
        g = cv2.cvtColor(out, cv2.COLOR_BGR2GRAY).astype(np.float32)
        bh = cv2.morphologyEx(g, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))) - g
        x, y, w, h = f[:4]
        chin = np.zeros(g.shape, np.uint8); chin[int(y + 0.78 * h):int(y + 1.02 * h), int(x + 0.38 * w):int(x + 0.62 * w)] = 1
        line = ((bh > 22) & (chin > 0)).astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(line); keep = np.zeros_like(line)
        for i in range(1, n):
            if st[i, 3] > 40 and st[i, 2] < 0.4 * st[i, 3]: keep[lab == i] = 1   # tall and thin
        fh = np.zeros(g.shape, np.uint8); fh[int(y - 0.05 * h):int(y + 0.22 * h), int(x + 0.1 * w):int(x + 0.9 * w)] = 1
        skin = (P[..., 3] > 0.6).astype(np.uint8)
        sp = ((bh > 20) & (fh > 0) & (skin > 0)).astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(sp)
        for i in range(1, n):
            if st[i, 4] < 150: keep[lab == i] = 1   # specks, not brows or hairline
        m = cv2.dilate(keep, np.ones((5, 5)))
        fill = cv2.inpaint(out, m, 6, cv2.INPAINT_TELEA)
        w8 = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 1.5)[..., None] * 0.85
        out = np.clip(out * (1 - w8) + fill * w8, 0, 255).astype(np.uint8)
        print(c, 'chin/speck px', int(keep.sum()), flush=True)
    cv2.imwrite(hf.OUT + f'/{c}-hero.png', out)
    print(c, 'done', flush=True)
