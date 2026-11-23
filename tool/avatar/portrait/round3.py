# Fix round 3: local repairs, starting from 9b58790 (Ava, Sofia) and fa7da02 (Ethan, Diego).
# Every generated region is a hair/backdrop/neck region with the face masked; the explicit boxes below are
# full-resolution hero pixels.
import sys, numpy as np, cv2, fl, herofix as hf
from lp_engine import Engine
R3 = fl.SP + '/fp/r3'
NEG = 'face, eyes, earrings, hoop, ring, jewelry, metal, grey, gray, white, halo, glow, blob, specks, text, watermark, blurry, cartoon, painting'
BG = {'ava': 'dark teal', 'ethan': 'dark slate blue', 'sofia': 'dark terracotta', 'diego': 'dark olive green'}
HAIR = {'ava': 'auburn wavy hair', 'ethan': 'short tousled curly light brown hair', 'sofia': 'long dark brown wavy hair',
        'diego': 'short curly black hair'}
eng = Engine()

def P_of(img):
    return hf.segment(img)

def box(shape, x0, y0, x1, y1):
    m = np.zeros(shape[:2], np.uint8); m[max(0, y0):y1, max(0, x0):x1] = 1; return m

def not_face(P, grow=9):
    return (cv2.dilate((P[..., 3] > 0.45).astype(np.uint8), np.ones((grow, grow))) == 0).astype(np.uint8)

def sd(img, m, c, what=None, seed=1, work=512, extra_neg=''):
    pr = f'studio portrait photo, {what or HAIR[c]}, plain {BG[c]} studio background, soft light, photorealistic'
    return hf.sd_inpaint(img, m.astype(np.uint8), pr, NEG + extra_neg, seed=seed, work=work, steps=26)

def run(c):
    im = cv2.imread(f'{R3}/{c}-base.jpg'); P = P_of(im); f = fl.face(im); x, y, w, h = [int(v) for v in f[:4]]
    nf = not_face(P)
    out = im
    if c == 'sofia':
        # only the three reviewed grey patches, narrow masks (grey pixels + 4 px), hair prompt
        gm, _ = hf.grey_mask(im, P, f[:4])
        for i, (x0, y0, x1, y1) in enumerate([(70, 1280, 190, 1570), (1730, 1520, 1856, 1680), (0, 2160, 110, 2472)]):
            m = gm * box(im.shape, x0, y0, x1, y1)
            m = cv2.dilate(m, np.ones((9, 9))) * nf
            if m.sum() > 50:
                out = sd(out, m, c, seed=50 + i)
        L = eng.prepare(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))['lmk203']
        lm = cv2.GaussianBlur(hf.lips_mask(L, out.shape), (0, 0), 2)
        out = hf.lab_edit(out, lm, da=-2, db=1, ladd=3, cmul=0.82)
        out = hf.degloss_lips(out, hf.lips_mask(L, out.shape), strength=0.5, outline=0.6)
    if c == 'ava':
        # hoops: remove each hoop below the lobe (the stud at the piercing stays), clean hair around it
        ear = (P[..., 5] > 0.15).astype(np.uint8); ear[:y + int(0.45 * h), :] = 0
        n, lab, st, _ = cv2.connectedComponentsWithStats(cv2.dilate(ear, np.ones((9, 9))))
        skin = cv2.dilate(((P[..., 3] > 0.5) | (P[..., 2] > 0.5)).astype(np.uint8), np.ones((5, 5)))
        for i in range(1, n):
            if st[i, 4] < 300: continue
            bx, by, bw, bh = st[i, :4]
            m = box(im.shape, bx - 25, by + 18, bx + bw + 25, by + bh + 30)
            # the hoop itself and anything metallic/grey in its box, but not the jaw/neck skin
            lab_ = cv2.cvtColor(out, cv2.COLOR_BGR2LAB).astype(np.float32); C = np.hypot(lab_[..., 1] - 128, lab_[..., 2] - 128)
            m = m * (((C < 18) | (cv2.dilate((lab == i).astype(np.uint8), np.ones((15, 15))) > 0)) & (skin == 0))
            m = cv2.dilate(m.astype(np.uint8), np.ones((7, 7))) * (1 - skin)
            out = sd(out, m, c, what='auburn wavy hair falling past the neck, no earrings', seed=60 + i)
        # crown blob and the pale rim strands along the outline (narrow outer band only)
        P2 = P_of(out); hair = (P2[..., 1] > 0.5).astype(np.uint8)
        band = ((cv2.dilate(hair, np.ones((31, 31))) - cv2.erode(hair, np.ones((15, 15)))) > 0).astype(np.uint8) * not_face(P2, 31)
        crown = box(im.shape, 760, 0, 1020, 90) * (P2[..., 3] < 0.4)
        out = sd(out, np.maximum(crown, band * box(im.shape, 600, 0, 1300, 120)), c, seed=71, work=512)
        right = band * box(im.shape, 1350, 150, im.shape[1], 1400)
        out = sd(out, right, c, seed=72, work=768)
        L = eng.prepare(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))['lmk203']
        lmm = hf.lips_mask(L, out.shape)
        lab_ = cv2.cvtColor(out, cv2.COLOR_BGR2LAB).astype(np.float32); a = lab_[..., 1] - 128
        am = np.median(a[lmm > 0.5])
        green = cv2.GaussianBlur(((a < am - 6) & (lmm > 0.5)).astype(np.float32), (0, 0), 2) * cv2.GaussianBlur(lmm, (0, 0), 2)
        lab_[..., 1] = 128 + a + green * (am - a) * 0.9
        out = cv2.cvtColor(np.clip(lab_, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
        out = hf.degloss_lips(out, lmm, strength=0.45, outline=0.3)
        out = hf.soft_liner(out, L, amount=0.4)
    if c == 'ethan':
        out = sd(out, box(im.shape, 520, 530, 660, 650) * nf, c, seed=81)                       # orange disc at the left temple
        right = box(im.shape, 1230, 330, 1520, 720) * not_face(P, 25) * (P[..., 2] < 0.4)       # ghost curls, right temple
        out = sd(out, right, c, seed=82)
    if c == 'diego':
        # forehead smudge where the loop was: hairline + forehead skin texture, small area
        out = sd(out, box(im.shape, 585, 410, 730, 520), c, what='dark hairline over smooth forehead skin', seed=91,
                 extra_neg=', hair loop, line, smudge')
        out = sd(out, box(im.shape, 1480, 380, 1600, 500) * nf, c, seed=92)                    # wire loop, right side
        crown = box(im.shape, 650, 0, 1250, 170) * (P[..., 1] > 0.2)
        out = sd(out, cv2.dilate(crown, np.ones((9, 9))), c, seed=93, work=768)                # mottled crown
        # neck seam: band across the protected/generated neck boundary, below the chin and jaw
        ys = y + h + int(0.12 * h)
        neck = box(im.shape, x, ys - 60, x + w, ys + 60) * (P[..., 2] > 0.4) * nf
        out = sd(out, neck, c, what='smooth neck skin, soft natural shading', seed=94, extra_neg=', seam, line')
        # chin: low-frequency light/dark split (source artefact); equalise only the large-scale shading,
        # leaving the stubble detail and the jaw geometry as they are
        cb = (x + int(0.32 * w), y + int(0.72 * h), x + int(0.68 * w), y + int(1.0 * h))
        sub = out[cb[1]:cb[3], cb[0]:cb[2]].astype(np.float32)
        low = cv2.GaussianBlur(sub, (0, 0), 25); low2 = cv2.GaussianBlur(sub, (0, 0), 70)
        wgt = np.zeros(sub.shape[:2], np.float32); cv2.ellipse(wgt, (sub.shape[1] // 2, sub.shape[0] // 2),
                                                               (sub.shape[1] // 2 - 6, sub.shape[0] // 2 - 6), 0, 0, 360, 1, -1)
        wgt = cv2.GaussianBlur(wgt, (0, 0), 12)[..., None] * 0.8
        out = out.copy(); out[cb[1]:cb[3], cb[0]:cb[2]] = np.clip(sub + wgt * (low2 - low), 0, 255).astype(np.uint8)
    cv2.imwrite(f'{R3}/{c}-r3.png', out)
    print(c, 'done', flush=True)

for c in sys.argv[1].split(','):
    run(c)
