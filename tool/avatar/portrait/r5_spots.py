"""Round 5 spot fixes for Sofía and Diego (non-generative, no geometry change).

sofia: blue-grey wisp above the right crown -> backdrop copied from just
above it; light strip at the bottom-left edge -> its low-frequency lightness
pulled down to the hair next to it (texture kept).
diego: dark tick and dot in the soul patch -> local median; pale vertical
stripe down the chin centre -> its low-frequency lightness matched to the
stubble left and right of it, plus the stubble texture from beside it.
Jaw, lips and outline untouched.

Usage: python r5_spots.py sofia|diego <round-4 hero png> <out png>
"""
import sys, cv2, numpy as np


def seg_mask(shape, p0, p1, r):
    m = np.zeros(shape[:2], np.uint8)
    cv2.line(m, p0, p1, 255, thickness=2 * r)
    return cv2.GaussianBlur(m.astype(np.float32) / 255, (0, 0), 1.5)


def sofia(im):
    out = im.astype(np.float32)
    w = seg_mask(im.shape, (1010, 270), (1040, 256), 7)
    w *= np.clip((277 - np.arange(im.shape[0]))[:, None] / 5.0, 0, 1)
    shifted = np.roll(out, 20, axis=0)          # content 20 px above
    out = out * (1 - w[..., None]) + shifted * w[..., None]
    lab = cv2.cvtColor(np.clip(out, 0, 255).astype(np.uint8), cv2.COLOR_BGR2LAB).astype(np.float32)
    L = lab[..., 0]
    y0, y1, x1 = 2150, im.shape[0], 30
    Ll = cv2.GaussianBlur(L, (0, 0), 6)
    ref = Ll[y0:y1, 30:70].mean(axis=1, keepdims=True)
    excess = np.clip(Ll[y0:y1, :x1] - ref, 0, None)
    fx = np.clip((x1 - np.arange(x1)) / 8.0, 0, 1)[None, :]
    fy = np.clip((np.arange(y1 - y0) / 40.0), 0, 1)[:, None]
    L[y0:y1, :x1] -= excess * fx * fy
    lab[y0:y1, :x1, 2] += (135 - lab[y0:y1, :x1, 2]) * (fx * fy) * 0.7
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def diego(im):
    lab = cv2.cvtColor(im, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = lab[..., 0]
    # tick and dot: pixels much darker than their neighbourhood
    y0, y1, x0, x1 = 1440, 1515, 975, 1035
    sub = np.clip(L[y0:y1, x0:x1], 0, 255).astype(np.uint8)
    med = cv2.medianBlur(sub, 15).astype(np.float32)
    dark = (L[y0:y1, x0:x1] < med - 14).astype(np.uint8)
    dark = cv2.dilate(dark, np.ones((3, 3), np.uint8)).astype(np.float32)
    dark = cv2.GaussianBlur(dark, (0, 0), 1.0)
    for c in range(3):
        ch = lab[y0:y1, x0:x1, c]
        m = cv2.medianBlur(np.clip(ch, 0, 255).astype(np.uint8), 15).astype(np.float32)
        lab[y0:y1, x0:x1, c] = ch + dark * (m - ch)
    # tick: darker than the soul patch left and right of it
    fix_band(L, 1448, 1505, 986, 1016, sign=-1)
    # pale stripe: lighter than the stubble left and right of it
    fix_band(L, 1520, 1665, 960, 1030, sign=1)
    # ... and give the smooth seam the stubble texture of the band beside it
    y0, y1, x0, x1 = 1525, 1660, 980, 1008
    hf = L - cv2.GaussianBlur(L, (0, 0), 2.5)
    t = np.linspace(0, 1, x1 - x0)[None, :]
    fx = np.sin(np.pi * t) ** 0.7
    fy = np.clip(np.minimum(np.arange(y1 - y0), np.arange(y1 - y0)[::-1]) / 10.0, 0, 1)[:, None]
    donor = hf[y0:y1, x0 + 32:x1 + 32]
    L[y0:y1, x0:x1] += (donor - 0.5 * hf[y0:y1, x0:x1]) * fx * fy * 0.8
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def fix_band(L, y0, y1, x0, x1, sign):
    """Match the low-frequency lightness of a vertical band to a linear
    blend of the columns just left and right of it (only the excess, sign=1,
    or the deficit, sign=-1, is removed; the fine texture stays)."""
    Ll = cv2.GaussianBlur(L, (0, 0), 3 if sign < 0 else 2.5)
    left, right = Ll[y0:y1, x0 - 8:x0].mean(axis=1), Ll[y0:y1, x1:x1 + 8].mean(axis=1)
    t = np.linspace(0, 1, x1 - x0)[None, :]
    expect = left[:, None] * (1 - t) + right[:, None] * t
    excess = np.clip(sign * (Ll[y0:y1, x0:x1] - expect), 0, None)
    fx = np.sin(np.pi * t) ** 0.5
    fy = np.clip(np.minimum(np.arange(y1 - y0), np.arange(y1 - y0)[::-1]) / 10.0, 0, 1)[:, None]
    L[y0:y1, x0:x1] -= sign * excess * fx * fy


if __name__ == "__main__":
    coach, src, dst = sys.argv[1:4]
    im = cv2.imread(src)
    cv2.imwrite(dst, {"sofia": sofia, "diego": diego}[coach](im))
