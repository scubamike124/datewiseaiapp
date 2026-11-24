# Fix round 3 follow-up for Diego (after round3.py): chin light/dark split and the neck seam.
import numpy as np, cv2, fl, herofix as hf
R3 = fl.SP + '/fp/r3'
im = cv2.imread(R3 + '/diego-r3.png'); f = fl.face(im); x, y, w, h = [int(v) for v in f[:4]]
# chin: equalise mid-frequency shading (sigma 7 vs 35) inside an ellipse; stubble detail and geometry unchanged
cb = (x + int(0.36 * w), y + int(0.74 * h), x + int(0.64 * w), y + int(1.02 * h))
sub = im[cb[1]:cb[3], cb[0]:cb[2]].astype(np.float32)
d = cv2.GaussianBlur(sub, (0, 0), 35) - cv2.GaussianBlur(sub, (0, 0), 7)
wgt = np.zeros(sub.shape[:2], np.float32)
cv2.ellipse(wgt, (sub.shape[1] // 2, sub.shape[0] // 2), (sub.shape[1] // 2 - 8, sub.shape[0] // 2 - 8), 0, 0, 360, 1, -1)
wgt = cv2.GaussianBlur(wgt, (0, 0), 10)[..., None] * 0.85
out = im.copy(); out[cb[1]:cb[3], cb[0]:cb[2]] = np.clip(sub + wgt * d, 0, 255).astype(np.uint8)
cv2.imwrite(R3 + '/diego-r3b.png', out)
# neck seam: strongest horizontal edge in the neck (rows 1540-1700), SD band +-40 px over neck skin only
g = cv2.GaussianBlur(cv2.cvtColor(out, cv2.COLOR_BGR2GRAY).astype(np.float32), (0, 0), 2)
row = 1540 + int(np.argmax(np.abs(np.diff(g, axis=0))[1540:1700, 800:1200].mean(1)))
P = hf.segment(out)
m = np.zeros(g.shape, np.uint8); m[row - 40:row + 40, 620:1380] = 1
m = m * (P[..., 2] > 0.4) * (P[..., 3] < 0.4)
out = hf.sd_inpaint(out, m.astype(np.uint8), 'studio portrait photo, smooth neck skin, soft natural shading, photorealistic',
                    'seam, line, stripe, face, text, blurry', seed=96, work=512, steps=26)
cv2.imwrite(R3 + '/diego-r3c.png', out)
