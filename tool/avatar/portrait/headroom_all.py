# Headroom for the coach cards: shift each hero down (same size), continue the backdrop, and let SD 1.5
# complete the top of the hair in the new band (face far below the mask).
import sys, numpy as np, cv2, fl, herofix as hf
R3 = fl.SP + '/fp/r3'
SRC = {'ava': 'ava-r3b', 'ethan': 'ethan-r3', 'sofia': 'sofia-r3', 'diego': 'diego-r3c'}
HAIR = {'ava': 'auburn wavy hair', 'ethan': 'short tousled curly light brown hair', 'sofia': 'long dark brown wavy hair', 'diego': 'short curly black hair'}
BG = {'ava': 'dark teal', 'ethan': 'dark slate blue', 'sofia': 'dark terracotta', 'diego': 'dark olive green'}
PX = 150
for c in sys.argv[1].split(','):
    im = cv2.imread(f'{R3}/{SRC[c]}.png'); H, W = im.shape[:2]
    P = hf.segment(im)
    cols = np.where((P[:30, :, 1] > 0.4).any(axis=0))[0]
    out = hf.add_headroom(im, PX)
    if len(cols):
        m = np.zeros((H, W), np.uint8); m[0:PX + 45, max(0, cols.min() - 50):min(W, cols.max() + 50)] = 1
        out = hf.sd_inpaint(out, m, f'studio portrait photo, top of {HAIR[c]}, rounded natural crown, plain {BG[c]} studio background, photorealistic',
                            'cut off, flat top, grey, white, halo, glow, specks, face, text, blurry, cartoon', seed=121, work=768, steps=26)
    cv2.imwrite(f'{R3}/{c}-final.png', out); print(c, 'headroom', PX, 'hair cols', len(cols), flush=True)
