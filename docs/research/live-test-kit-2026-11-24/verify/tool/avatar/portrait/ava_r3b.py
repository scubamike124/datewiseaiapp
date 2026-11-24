import numpy as np, cv2, fl, herofix as hf
from lp_engine import Engine
R3 = fl.SP + '/fp/r3'
base = cv2.imread(R3 + '/ava-base.jpg'); out = cv2.imread(R3 + '/ava-r3.png')
eng = Engine()
L = eng.prepare(cv2.cvtColor(base, cv2.COLOR_BGR2RGB))['lmk203']
# undo the eyeliner edit (it greyed the lashes): restore both eye regions from 9b58790
H, W = base.shape[:2]; ring = np.zeros((H, W), np.uint8)
for idx in (range(0, 24), range(24, 48)):
    cv2.fillPoly(ring, [cv2.convexHull(L[list(idx)].astype(np.int32))], 1)
ring = cv2.GaussianBlur(cv2.dilate(ring, np.ones((61, 61))).astype(np.float32), (0, 0), 6)[..., None]
out = np.clip(out * (1 - ring) + base.astype(np.float32) * ring, 0, 255).astype(np.uint8)
NEG = 'earring, hoop, ring, jewelry, metal, blue, teal, background, gap, grey, white, pink, blob, face, text, blurry'
P = hf.segment(out); f = fl.face(out); x, y, w, h = [int(v) for v in f[:4]]
# left ear: the patch under the lobe (where the hoop was) -> hair in shadow, no background colour
m = np.zeros((H, W), np.uint8); m[1060:1290, 250:420] = 1
m = m * (cv2.dilate((P[..., 3] > 0.5).astype(np.uint8), np.ones((7, 7))) == 0)
out = hf.sd_inpaint(out, m, 'close-up photo, auburn wavy hair in soft shadow beside the neck, photorealistic', NEG, seed=111, work=512, steps=26)
# crown: thin band at the very top over the parting
m = np.zeros((H, W), np.uint8); m[0:70, 760:1040] = 1
m = m * (P[..., 3] < 0.4)
out = hf.sd_inpaint(out, m, 'close-up photo, top of auburn hair, smooth parting, photorealistic', NEG.replace('teal, background, ', ''), seed=112, work=512, steps=26)
cv2.imwrite(R3 + '/ava-r3b.png', out); print('ava r3b done')
