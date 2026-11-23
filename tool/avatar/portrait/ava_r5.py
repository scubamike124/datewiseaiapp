"""Round 5, Ava right side (non-generative): pale crescent inside the hair
becomes backdrop seen through the hair; light diagonal lines in the teal
backdrop are replaced by the median backdrop; the two jaw-edge specks are
replaced by the hair a few pixels further out (the jaw line is not moved).

Usage: python ava_r5.py <round-4 hero png> <out png>"""
import sys, cv2, numpy as np
src, out = sys.argv[1], sys.argv[2]
im = cv2.imread(src)
lab = cv2.cvtColor(im, cv2.COLOR_BGR2LAB).astype(np.float32)
L, a, b = lab[..., 0] * 100 / 255, lab[..., 1] - 128, lab[..., 2] - 128
H, W = L.shape
roi = np.zeros((H, W), bool)
roi[1240:1430, 1650:1784] = True
crescent = roi & (L > 40) & (np.hypot(a, b) < 22)
crescent = cv2.morphologyEx(crescent.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
n, lb, st, _ = cv2.connectedComponentsWithStats(crescent)
keep = [i for i in range(1, n) if st[i, cv2.CC_STAT_AREA] > 150]
crescent = np.isin(lb, keep)
cm = cv2.dilate(crescent.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))) > 0
teal = (b < -3) & (a < -3) & ~cm
tsel = teal.copy(); tsel[:1300] = False; tsel[1480:] = False; tsel[:, :1680] = False
tL, ta, tb = [float(np.median(ch[tsel])) for ch in (L, a, b)]
w = cv2.GaussianBlur(cm.astype(np.float32), (0, 0), 1.5)
# keep a little of the original light variation so it is not a flat patch
Lsm = cv2.GaussianBlur(L, (0, 0), 6)
Lnew = tL + 0.15 * (Lsm - Lsm[cm].mean()) if cm.any() else L
L = L + w * (Lnew - L); a = a + w * (ta - a); b = b + w * (tb - b)
print("crescent px", int(cm.sum()), "teal", round(tL, 1), round(ta, 1), round(tb, 1))
# light lines in the backdrop
bg = np.zeros((H, W), bool)
for (y0, y1, x0, x1) in [(1340, 1560, 1680, 1784), (1000, 1140, 1690, 1784)]:
    bg[y0:y1, x0:x1] = True
tealnow = (b < -3) & (a < -3)
med = cv2.medianBlur(np.clip(L * 2.55, 0, 255).astype(np.uint8), 21).astype(np.float32) / 2.55
medA = cv2.medianBlur(np.clip(a + 128, 0, 255).astype(np.uint8), 21).astype(np.float32) - 128
line = bg & (medA < -4) & (a < 4) & (L - med > 1.5)
line = cv2.dilate(line.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
line &= bg & (medA < -4) & (a < 4)
for ch_i, ch in enumerate((L, a, b)):
    m = cv2.medianBlur(np.clip(ch * (2.55 if ch_i == 0 else 1) + (0 if ch_i == 0 else 128), 0, 255).astype(np.uint8), 21).astype(np.float32)
    m = m / 2.55 if ch_i == 0 else m - 128
    ch[line] = m[line]
print("line px", int(line.sum()))
lab2 = np.dstack([L * 255 / 100, a + 128, b + 128])
out_im = cv2.cvtColor(np.clip(lab2, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
# jaw specks: skin-coloured bumps outside the jaw line. The jaw edge in the
# speck rows is interpolated from the rows just above and below, and only
# pixels beyond it (on the hair side) are replaced by hair from a few pixels
# further out, so the jaw line itself does not move.
Lo = cv2.cvtColor(out_im, cv2.COLOR_BGR2LAB)[..., 0].astype(np.float32) * 100 / 255
def edge(y, x0, x1):
    row = Lo[y, x0:x1]
    dark = np.nonzero(row < 22)[0]
    return x0 + (dark[0] if len(dark) else x1 - x0)
total = 0
for (x0, y0, x1, y1) in [(1180, 1240, 1320, 1286), (1160, 1405, 1300, 1452)]:
    ea, eb = edge(y0 - 4, x0, x1), edge(y1 + 4, x0, x1)
    for y in range(y0, y1):
        e = ea + (eb - ea) * (y - y0 + 4) / (y1 - y0 + 8)
        xs = np.arange(int(np.ceil(e)) + 1, x1)
        bad = xs[Lo[y, xs] > 20]
        if len(bad):
            shift = 30
            out_im[y, bad] = out_im[y, np.minimum(bad + shift, W - 1)]
            total += len(bad)
print("speck px", total)
cv2.imwrite(out, out_im)
