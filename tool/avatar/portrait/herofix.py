import os
# Fix round 2: local repairs on the finished heroes. Never touches the face core except the explicitly
# listed cosmetic edits (lip colour/gloss, eyeliner wing) and thin source artefacts (Diego).
import sys, os, numpy as np, cv2, torch
SP = os.environ.get('DW_PORTRAIT_WORK', os.path.expanduser('~/dw-portrait-work'))
os.environ['AVATAR_TOOLS'] = SP + '/avatar-tools'
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fl, seg
from style import lab_edit
IN = SP + '/fp/hf'; OUT = SP + '/fp/hf/out'; os.makedirs(OUT, exist_ok=True)

def segment(img):
    H, W = img.shape[:2]; s = min(1.0, 1280 / max(H, W))
    small = cv2.resize(img, (int(W * s), int(H * s)), interpolation=cv2.INTER_AREA)
    P = seg.segment(small)
    return np.stack([cv2.resize(P[..., i], (W, H), interpolation=cv2.INTER_LINEAR) for i in range(6)], -1)

def nblur(img, w, sig):
    num = cv2.GaussianBlur(img * w[..., None], (0, 0), sig); den = cv2.GaussianBlur(w, (0, 0), sig)[..., None]
    return num / np.maximum(den, 1e-4), den[..., 0]

def decontaminate(img, P, face_box):
    """Hair-edge halos and grey gaps: pixels that mix hair with the old light-grey backdrop are re-mixed
    with the new backdrop (closed-form matting along the hair->grey line, foreground colour decontaminated)."""
    f = img.astype(np.float32); H, W = img.shape[:2]
    hair, bgp, face, clothes = P[..., 1], P[..., 0], P[..., 3], P[..., 4]
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB).astype(np.float32); L = lab[..., 0]; C = np.hypot(lab[..., 1] - 128, lab[..., 2] - 128)
    # new backdrop field B (smooth), from sure backdrop far from the hair
    sure_bg = ((bgp > 0.9) & (cv2.dilate((hair > 0.3).astype(np.uint8), np.ones((61, 61))) == 0)).astype(np.float32)
    B, _ = nblur(f, sure_bg, W / 12)
    # local hair colour F
    sure_hair = cv2.erode((hair > 0.9).astype(np.uint8), np.ones((9, 9))).astype(np.float32)
    F, fden = nblur(f, sure_hair, 18)
    F2, _ = nblur(f, sure_hair, 60)
    F = np.where(fden[..., None] > 0.05, F, F2)
    # the old grey: light, low-chroma pixels near the hair that are not skin, clothing or the new backdrop
    density = cv2.GaussianBlur((hair > 0.5).astype(np.float32), (0, 0), 10)
    near = cv2.dilate((hair > 0.3).astype(np.uint8), np.ones((81, 81))) > 0
    facecore = cv2.dilate((face > 0.4).astype(np.uint8), np.ones((15, 15))) > 0
    x, y, w, h = face_box
    facecore[int(y):int(y + h), int(x):int(x + w)] = True
    dB = np.linalg.norm(f - B, axis=-1)
    greyish = near & ~facecore & (clothes < 0.5) & (C < 14) & (L > np.percentile(L[sure_hair > 0], 75) + 18) & (dB > 25)
    if greyish.sum() < 50:
        return img, np.zeros((H, W), np.float32)
    G = np.median(f[greyish], axis=0)
    band = near & ~facecore & (clothes < 0.5) & (density < 0.97)
    d = G[None, None] - F; dd = np.maximum((d * d).sum(-1), 1.0)
    t = np.clip(((f - F) * d).sum(-1) / dd, 0, 1)        # share of the old grey in the pixel
    # only where the pixel actually sits on the hair->grey line (not a hair highlight of another hue)
    off = np.linalg.norm(f - (F + t[..., None] * d), axis=-1)
    t = t * np.clip(1 - (off - 18) / 25, 0, 1) * band
    t = cv2.GaussianBlur(t, (0, 0), 0.8)
    a = 1 - t
    Fd = np.clip((f - t[..., None] * G[None, None]) / np.maximum(a, 0.15)[..., None], 0, 255)
    Fd = np.where(a[..., None] > 0.15, Fd, F)
    out = a[..., None] * Fd + t[..., None] * B
    return np.clip(out, 0, 255).astype(np.uint8), t

def wire_loops(img, P, B=None):
    """Thin dark wire-like strands lying over the backdrop (upscaler artefacts): blend them into the backdrop."""
    f = img.astype(np.float32); bgp = P[..., 0]
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)
    bh = cv2.morphologyEx(g, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))) - g
    m = ((bh > 25) & (bgp > 0.45)).astype(np.uint8)
    m = cv2.dilate(m, np.ones((3, 3)))
    fill = cv2.inpaint(img, m, 5, cv2.INPAINT_TELEA)
    w = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 1.2)[..., None]
    return np.clip(f * (1 - w) + fill.astype(np.float32) * w, 0, 255).astype(np.uint8)

_pipe = None
def sd_inpaint(img, mask, prompt, neg, seed=1, work=512, steps=24):
    """SD 1.5 inpainting on a native-resolution crop (no upscale) around the mask; composite with a feather."""
    global _pipe
    from PIL import Image
    if _pipe is None:
        from diffusers import StableDiffusionInpaintPipeline, DPMSolverMultistepScheduler
        _pipe = StableDiffusionInpaintPipeline.from_pretrained(SP + '/fp/sd-inpaint', variant='fp16', torch_dtype=torch.float32,
                                                               safety_checker=None, feature_extractor=None, requires_safety_checker=False)
        _pipe.scheduler = DPMSolverMultistepScheduler.from_config(_pipe.scheduler.config, use_karras_sigmas=True)
        _pipe.set_progress_bar_config(disable=True)
    H, W = img.shape[:2]
    ys, xs = np.where(mask > 0)
    cx, cy = (xs.min() + xs.max()) // 2, (ys.min() + ys.max()) // 2
    span = max(xs.max() - xs.min(), ys.max() - ys.min()) + 160
    side = int(max(work, span)); side = min(side, W, H)
    x0 = int(np.clip(cx - side // 2, 0, W - side)); y0 = int(np.clip(cy - side // 2, 0, H - side))
    crop = img[y0:y0 + side, x0:x0 + side]; mc = mask[y0:y0 + side, x0:x0 + side]
    s = work / side
    ci = cv2.resize(crop, (work, work), interpolation=cv2.INTER_AREA)
    mi = cv2.resize(mc, (work, work), interpolation=cv2.INTER_NEAREST)
    mi = cv2.dilate((mi > 0).astype(np.uint8) * 255, np.ones((5, 5)))  # the pipeline expects 0/255
    r = _pipe(prompt=prompt, negative_prompt=neg, image=Image.fromarray(cv2.cvtColor(ci, cv2.COLOR_BGR2RGB)),
              mask_image=Image.fromarray(mi), width=work, height=work, num_inference_steps=steps, guidance_scale=7.0,
              generator=torch.Generator().manual_seed(seed)).images[0]
    gen = cv2.resize(cv2.cvtColor(np.array(r), cv2.COLOR_RGB2BGR), (side, side), interpolation=cv2.INTER_LANCZOS4)
    if s < 1:  # match grain of the native-resolution surroundings a little
        gen = np.clip(gen.astype(np.float32) + np.random.default_rng(seed).normal(0, 1.5, gen.shape[:2])[..., None], 0, 255).astype(np.uint8)
    w = cv2.GaussianBlur(cv2.dilate(mc, np.ones((9, 9))).astype(np.float32), (0, 0), 3)[..., None]
    w = np.clip(w * 1.2, 0, 1)
    out = img.copy()
    out[y0:y0 + side, x0:x0 + side] = np.clip(crop.astype(np.float32) * (1 - w) + gen.astype(np.float32) * w, 0, 255).astype(np.uint8)
    return out

def lips_mask(lmk, shape, grow=0):
    m = np.zeros(shape[:2], np.float32)
    cv2.fillPoly(m, [cv2.convexHull(lmk[48:96].astype(np.int32))], 1.0)
    if grow: m = cv2.dilate(m, np.ones((grow, grow)))
    return m

def degloss_lips(img, lm, strength=0.5, outline=0.6):
    """Less gloss (compress the brightest lip highlights) and a softer lip-liner edge."""
    f = img.astype(np.float32); inner = cv2.erode(lm, np.ones((5, 5)))
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB).astype(np.float32); L = lab[..., 0]
    p = np.percentile(L[inner > 0.5], 80)
    L2 = np.where(L > p, p + (L - p) * (1 - strength), L)
    lab[..., 0] = L * (1 - inner) + L2 * inner
    out = cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR).astype(np.float32)
    ring = (cv2.dilate(lm, np.ones((7, 7))) - cv2.erode(lm, np.ones((7, 7)))).astype(np.float32)
    ring = cv2.GaussianBlur(ring, (0, 0), 2) * outline
    soft = cv2.GaussianBlur(out, (0, 0), 2.5)
    return np.clip(out * (1 - ring[..., None]) + soft * ring[..., None], 0, 255).astype(np.uint8)

def soft_liner(img, lmk, amount=0.45):
    """Lighter eyeliner on both eyes evenly: lift very dark pixels in a ring just outside each eye outline
    (never inside the eye opening). Both rings are built first and applied once."""
    H, W = img.shape[:2]
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB).astype(np.float32); L = lab[..., 0]
    ring = np.zeros((H, W), bool)
    for idx in (range(0, 24), range(24, 48)):
        pts = lmk[list(idx)].astype(np.int32)
        e = np.zeros((H, W), np.uint8); cv2.fillPoly(e, [cv2.convexHull(pts)], 1)
        ew = int(np.ptp(pts[:, 0]))
        k = max(9, int(0.22 * ew)) | 1
        ring |= (cv2.dilate(e, np.ones((k, k))) > 0) & (cv2.dilate(e, np.ones((5, 5))) == 0)
    dark = ring & (L < 80)
    m = cv2.GaussianBlur(dark.astype(np.float32), (0, 0), 1.5) * amount
    lab[..., 0] = L + m * (110 - L) * 0.5
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def grey_mask(img, P, face_box, extra_light=18):
    """Old light-grey backdrop left inside or around the hair: light, low-chroma pixels near the hair that are
    not face, skin, clothing or the new backdrop."""
    H, W = img.shape[:2]; f = img.astype(np.float32)
    hair, bgp, face, body, clothes = P[..., 1], P[..., 0], P[..., 3], P[..., 2], P[..., 4]
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB).astype(np.float32); L = lab[..., 0]; C = np.hypot(lab[..., 1] - 128, lab[..., 2] - 128)
    sure_bg = ((bgp > 0.9) & (cv2.dilate((hair > 0.3).astype(np.uint8), np.ones((61, 61))) == 0)).astype(np.float32)
    B, _ = nblur(f, sure_bg, W / 12)
    sure_hair = cv2.erode((hair > 0.9).astype(np.uint8), np.ones((9, 9))) > 0
    Lh = np.percentile(L[sure_hair], 85) if sure_hair.any() else 120
    near = cv2.dilate((hair > 0.3).astype(np.uint8), np.ones((61, 61))) > 0
    skin = cv2.dilate(((face > 0.4) | (body > 0.5)).astype(np.uint8), np.ones((11, 11))) > 0
    x, y, w, h = [int(v) for v in face_box]
    skin[y:y + h, x:x + w] = True
    dB = np.linalg.norm(f - B, axis=-1)
    m = near & ~skin & (clothes < 0.5) & (((C < 6) & (L > Lh + 10)) | ((C < 16) & (L > max(Lh + extra_light, 150)))) & (dB > 30)
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, np.ones((2, 2)))
    return cv2.dilate(m, np.ones((5, 5))), B

def fix_patches(img, P, face_box, prompt, neg, seed=1, big=1500):
    m, B = grey_mask(img, P, face_box)
    n, lab, st, cen = cv2.connectedComponentsWithStats(m)
    small = np.zeros_like(m); large = np.zeros_like(m)
    for i in range(1, n):
        (large if st[i, 4] >= big else small)[lab == i] = 1
    out = img
    if small.any():
        out = cv2.inpaint(out, small, 7, cv2.INPAINT_TELEA)
    # large patches: SD inpaint, one crop per cluster of nearby patches
    if large.any():
        cl = cv2.dilate(large, np.ones((301, 301)))
        k, lab2 = cv2.connectedComponents(cl)
        for j in range(1, k):
            mj = (large > 0) & (lab2 == j)
            out = sd_inpaint(out, mj.astype(np.uint8), prompt, neg, seed=seed + j)
    return out, m

def regrey(img, P, face_box, grow=9):
    """The grey patches are the old light backdrop seen between or around hair strands. Each pixel is
    modelled as hair + t * old grey; the grey share is swapped for the new backdrop: out = I + t (B - G)."""
    f = img.astype(np.float32); H, W = img.shape[:2]
    m, B = grey_mask(img, P, face_box)
    region = cv2.dilate(m, np.ones((grow, grow))) > 0
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB).astype(np.float32); L = lab[..., 0]; C = np.hypot(lab[..., 1] - 128, lab[..., 2] - 128)
    G = np.median(f[m > 0], axis=0) if m.any() else np.array([180, 180, 180], np.float32)
    LG = float(np.median(L[m > 0])) if m.any() else 180.0
    sure_hair = cv2.erode((P[..., 1] > 0.9).astype(np.uint8), np.ones((9, 9))).astype(np.float32)
    Lh = cv2.GaussianBlur(L * sure_hair, (0, 0), 25) / np.maximum(cv2.GaussianBlur(sure_hair, (0, 0), 25), 1e-4)
    t = np.clip((L - Lh) / np.maximum(LG - Lh, 10), 0, 1) * np.clip((22 - C) / 10, 0, 1) * region
    t = cv2.GaussianBlur(t, (0, 0), 1.0)
    out = f + t[..., None] * (B - G[None, None])
    return np.clip(out, 0, 255).astype(np.uint8), t

def patch_fill(img, P, face_box, detail=0.5):
    """Grey patches inside/around the hair: Navier-Stokes fill from the surrounding hair plus hair texture
    (high-pass) borrowed from nearby offsets. No generation; the face is excluded by grey_mask."""
    m, B = grey_mask(img, P, face_box)
    mm = cv2.dilate(m, np.ones((7, 7)))
    if not mm.any():
        return img, mm
    fill = cv2.inpaint(img, mm, 15, cv2.INPAINT_NS).astype(np.float32)
    g = img.astype(np.float32); hp = g - cv2.GaussianBlur(g, (0, 0), 3)
    best = np.zeros_like(g); taken = np.zeros(mm.shape, bool)
    for dx, dy in [(60, 0), (-60, 0), (0, 60), (0, -60), (90, 40), (-90, -40), (120, 0), (-120, 0)]:
        sh = np.roll(np.roll(hp, dy, 0), dx, 1); ok = np.roll(np.roll(mm, dy, 0), dx, 1) == 0
        use = ok & ~taken
        best = np.where(use[..., None], sh, best); taken |= use
    fill = fill + detail * best * (mm > 0)[..., None]
    w = cv2.GaussianBlur(mm.astype(np.float32), (0, 0), 2)[..., None]
    return np.clip(g * (1 - w) + fill * w, 0, 255).astype(np.uint8), mm

def add_headroom(img, px, seed=3):
    """Shift the picture down by px (same size): the new top band continues the studio backdrop (the smooth
    colour of the top rows, with matching fine grain); the same number of rows is cropped from the bottom
    (clothing). Used where the hair touched the top edge."""
    H, W = img.shape[:2]
    top = img[:40].astype(np.float32).mean(axis=0)                 # per-column backdrop colour
    top = cv2.GaussianBlur(top[None], (0, 0), 25)[0]
    band = np.repeat(top[None], px, axis=0)
    band += np.random.default_rng(seed).normal(0, 1.4, band.shape[:2])[..., None]
    out = np.vstack([np.clip(band, 0, 255).astype(np.uint8), img[:H - px]])
    # soften the join
    j = np.clip(np.arange(-20, 20) / 40 + 0.5, 0, 1)
    seg_ = out[px - 20:px + 20].astype(np.float32)
    blend = band[-1][None] * (1 - j[:, None, None]) + seg_ * j[:, None, None]
    # keep the original rows where they are clearly hair (not backdrop): only blend backdrop-like rows
    out[px - 20:px + 20] = np.clip(blend, 0, 255).astype(np.uint8)
    return out
