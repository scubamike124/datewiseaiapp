"""Write the hero (JPEG q90) and the 1024 px avatar (q92) from a finished hero PNG.

The avatar is a square of 1.9 x the face height centred 0.05 face heights
below the face centre (above it for Diego).

Usage: python export.py <coach> <hero png> <out dir>"""
import sys, os, cv2, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fl
c, src, outdir = sys.argv[1:4]
out = cv2.imread(src); H, W = out.shape[:2]
cv2.imwrite(f'{outdir}/{c}-hero.jpg', out, [cv2.IMWRITE_JPEG_QUALITY, 90])
f = fl.face(out)
off = -0.05 if c == 'diego' else 0.05
cx, cy = f[0] + f[2] / 2, f[1] + f[3] / 2 + off * f[3]; side = int(min(1.9 * f[3], W, H))
x0 = int(np.clip(cx - side / 2, 0, W - side)); y0 = int(np.clip(cy - side / 2, 0, H - side))
cv2.imwrite(f'{outdir}/{c}-avatar.jpg', cv2.resize(out[y0:y0 + side, x0:x0 + side], (1024, 1024), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 92])
print(c, 'face', [round(float(v)) for v in f[:4]], 'crop', x0, y0, side)
