# Fix round 3, Ava follow-ups exactly as run (after ava_r3b.py and before/after headroom_all.py as noted):
#  1. ava-r3b.png: two passes on the blue patch under the left lobe (seeds 131, 132)   -> ava-r3b.png
#  2. after headroom_all.py: crown re-inpaint (seed 141)                                -> ava-final2.png
#  3. pale rim strands on the right/left hair edge (seeds 151, 152)                     -> ava-final3.png
import os, sys, numpy as np, cv2, fl, herofix as hf
R3 = fl.SP + '/fp/r3'
NEG_EAR = 'blue, teal, background, gap, earring, jewelry, grey, white, face, text, blurry'
PR_EAR = 'close-up photo, auburn wavy hair in soft shadow beside the neck, photorealistic'

def ear_pass(out, box, seed, grow):
    H, W = out.shape[:2]; P = hf.segment(out)
    lab = cv2.cvtColor(out, cv2.COLOR_BGR2LAB).astype(np.float32)
    x0, y0, x1, y1 = box
    m = np.zeros((H, W), np.uint8); m[y0:y1, x0:x1] = 1
    m = m * ((lab[..., 2] - 128) < (4 if seed == 131 else 5)).astype(np.uint8)
    m = cv2.dilate(m, np.ones((grow, grow))) * (P[..., 3] < 0.5) * ((P[..., 2] < 0.6) if seed == 132 else 1)
    return hf.sd_inpaint(out, m.astype(np.uint8), PR_EAR, NEG_EAR, seed=seed, work=512, steps=26)

step = sys.argv[1]
if step == 'ear':
    out = cv2.imread(R3 + '/ava-r3b.png')
    out = ear_pass(out, (190, 1070, 340, 1220), 131, 15)
    out = ear_pass(out, (230, 1180, 440, 1320), 132, 17)
    cv2.imwrite(R3 + '/ava-r3b.png', out)
elif step == 'crown':
    im = cv2.imread(R3 + '/ava-final.png'); H, W = im.shape[:2]; P = hf.segment(im)
    f = fl.face(im); x, y, w, h = [int(v) for v in f[:4]]
    m = np.zeros((H, W), np.uint8); m[0:int(y - 0.25 * h), int(x - 0.15 * w):int(x + 1.15 * w)] = 1
    m = m * (P[..., 3] < 0.4)
    out = hf.sd_inpaint(im, m, 'studio portrait photo, smooth rounded top of long auburn wavy hair with a centre parting, plain dark teal studio background, photorealistic',
                        'bun, top knot, ponytail, updo, tuft, grey, white, halo, specks, face, text, blurry, cartoon', seed=141, work=768, steps=26)
    cv2.imwrite(R3 + '/ava-final2.png', out)
elif step == 'edges':
    im = cv2.imread(R3 + '/ava-final2.png'); H, W = im.shape[:2]; P = hf.segment(im)
    hair = (P[..., 1] > 0.5).astype(np.uint8)
    band = ((cv2.dilate(hair, np.ones((27, 27))) - cv2.erode(hair, np.ones((9, 9)))) > 0).astype(np.uint8)
    band = band * (cv2.dilate((P[..., 3] > 0.4).astype(np.uint8), np.ones((41, 41))) == 0)
    lab = cv2.cvtColor(im, cv2.COLOR_BGR2LAB).astype(np.float32); C = np.hypot(lab[..., 1] - 128, lab[..., 2] - 128)
    pale = ((lab[..., 0] > 110) & (C < 25)).astype(np.uint8)
    out = im
    for i, (x0, x1) in enumerate([(1300, W), (0, 480)]):
        m = np.zeros((H, W), np.uint8); m[250:1500, x0:x1] = 1
        mm = cv2.dilate(m * band * pale, np.ones((11, 11))) * m * band
        if mm.sum() > 300:
            out = hf.sd_inpaint(out, mm, 'studio portrait photo, edge of auburn wavy hair, natural strands, plain dark teal studio background, photorealistic',
                                'grey, white, pale, halo, glow, outline, specks, face, text, blurry', seed=151 + i, work=768, steps=26)
    cv2.imwrite(R3 + '/ava-final3.png', out)
