# Candidate avatar frames v3 (round 2), 2026-11-24

CANDIDATE ONLY. Production assets (assets/avatar, assets/coaches) untouched; nothing committed. Each folder `<coach>/` is a complete drop-in set (same filenames, rects, manifest.json). Unchanged files are byte-identical copies. Extra files per folder: contact-full.jpg (1:1 pixels), contact-phone.jpg (390 pt stage at 2x), regate.txt.
Gate: `AVATAR_TOOLS=.../ondevice-qa/tools python3 tool/avatar/regate.py --portraits assets/coaches --frames <this folder>` -> 76/76 pass (regate.txt; production for comparison: regate-production.txt). No gate loosened. CPU only, no accounts, no SDXL (CPU SDXL is minutes per step and memory is shared, and identity risk; not needed).

## Changed frames
| Coach | Frame | identity prod -> v3 | master prod -> v3 | method |
|---|---|---|---|---|
| ava | a | 0.687 -> 0.663 | 0.826 -> 0.828 | mouth interior re-rendered (see A) |
| ava | a2 | 0.720 -> 0.699 | 0.865 -> 0.858 | same |
| ava | l | 0.716 -> 0.675 | 0.868 -> 0.839 | same, tongue raised |
| ava | o | 0.654 -> 0.620 | 0.868 -> 0.845 | lips only widened 1.22x, tail removed (see B) |
| ava | o2 | 0.637 -> 0.647 | 0.885 -> 0.874 | same |
| ava | blink_half | 0.709 -> 0.699 | 0.890 -> 0.900 | image-left eye rebuilt, see D |
| ethan | a / a2 / l | 0.831/0.843/0.828 -> 0.844/0.854/0.848 | 0.918/0.926/0.916 -> 0.930/0.941/0.932 | see A |
| ethan | o / o2 | 0.815/0.846 -> 0.814/0.848 | 0.904/0.940 -> 0.900/0.937 | production frame, lips only widened 1.24x |
| ethan | gaze | 0.866 -> 0.869 | 0.908 -> 0.915 | iris correction, see D |
| sofia | a / a2 / l | 0.537/0.545/0.562 -> 0.543/0.589/0.585 | 0.798/0.809/0.804 -> 0.809/0.845/0.848 | see A |
| sofia | i2 / sh | 0.648/0.654 -> 0.658/0.655 | 0.910/0.901 -> 0.912/0.899 | see C |
| diego | a / a2 / l | 0.754/0.780/0.771 -> 0.769/0.786/0.772 | 0.864/0.887/0.883 -> 0.881/0.894/0.883 | see A |
| diego | o / o2 | unchanged (production copied) | | per request |
| diego | blink_half | 0.857 -> 0.861 | 0.915 -> 0.912 | image-right eye rebuilt, see D |
| diego | gaze | 0.837 -> 0.844 | 0.900 -> 0.877 | iris correction, see D |

Ava identity dips 0.02-0.04 on a/a2/l/o (all well above the 0.45 gate; worst Ava frame 0.620 vs 0.637 before). Sofia a/a2/l still the lowest identity of any coach (0.54-0.59), but slightly higher than production.

## A. Open vowels a / a2 / l (all four coaches)
Round 1 re-tinted the clenched teeth and drew a lens-shaped cavity. Round 2 re-renders the whole mouth interior (`scripts/paint.py`, `synth.py`):
1. Opening geometry from the production frame (teeth + dark pixels near the teeth, top and bottom lip contour per column, ends extended and tapered). The dark inner lip rim is re-grown with lip colour (inpaint) so there is no black outline; lip thickness and shape outside the opening are the production pixels (lower lip dropped 12 / 8 / 1 px with the round-1 bite-line warp).
2. Upper teeth: individual teeth (central 1.22 : lateral 0.86 : canine 0.80 : premolar 0.58 widths, random +-16 %), rounded incisal edges with per-tooth length differences and slight canine point, soft interdental lines (about 10 %), per-tooth brightness/yellow variation, lip shadow at the top, translucent bluish incisal edge, falloff toward the corners, enamel highlight, grain. 30 % of the luminance structure comes from the production teeth (closing removes dark cracks), so it is not a flat synthetic fill.
3. Lower teeth: the coach's production lower row (warped with the lip) cleaned: dark gaps softened, tone rebuilt, edge pixels re-coloured, top rim light, darker toward the lip, corner falloff. Edge pixels blend over the cavity, so no grey outline.
4. Cavity: graded dark red-brown (darkest just under the upper teeth, lighter toward the tongue, reddish at the corners, no black wedge), tongue with shaded rim, groove, papillae noise and a soft highlight; position depends on the cavity height (raised tip for l).
5. Upper-teeth height is limited to about 0.17 of the teeth span, so the cavity opens under real-sized teeth (round 1 kept the 35 px fused block).
Tooth colour comes from the coach's own smile portraits where available (softsmile ava/ethan/sofia: median Lab ~ L 73-76, a 3-4, b 9-10) and production teeth for Diego. Pasting/warping those smile teeth as a texture was tried and rejected: the source teeth are about 17 px tall and 100 px wide, the warp gave streaky vertical smears (kept in work/tm-*.png). Diego has no usable own-smile portrait (the v3 portraits are a different person), so his colour is from his production teeth.
Ava a/a2: the dark wedge at the upper-left corner is gone (the corner is a soft red-brown gradient).

## B. o / o2
Ava: production frame, lips only widened 1.22x about the lip centroid with a 1.6 px feather (union covers the original lips); the thin tail at the upper-left lip corner is inpainted away (box-limited, plus matching grain). Ethan: same lip-only warp (1.24x) on the production frame, so the moustache/stubble texture is the production texture, not stretched or morphed. Diego: production o/o2 copied unchanged.

## C. Sofia i2 / sh
The existing teeth band keeps its photographic shape; added per-tooth soft shading (convex tooth shading about 7 %, +-2.4 L tooth variation), soft slightly slanted interdental lines (4 %, fading toward the edge), top lip shadow, ivory tint toward the coach's tone (a 0.75 weight), grain. Subtle by design; change is visible at 1:1, small at phone size.

## D. Eyes
Gate numbers (regate eye_shift on the gaze frame; blink frames are not iris-gated):
| Frame | gate dab/dL production -> v3 |
|---|---|
| ethan gaze | 3.1 / 1.8 -> 2.8 / 1.3 |
| diego gaze | 4.4 / 8.5 -> 3.1 / 4.3 |
| ava gaze | 2.1 / 3.9 unchanged (production kept) |
| sofia gaze | 0.1 / 0.9 unchanged (production kept) |
Per-eye iris disc Lab (my measurement: iris disc at hand-located centres, 20-85 percentile band, vs portrait; before -> after dab / dL):
- ethan image-left eye: 4.9 / 4.0 -> 2.3 / 0.7 (grey-brown iris pulled back to the portrait colour); image-right 1.3 / 1.0 (not touched; the reviewer's "lighter right iris" is the same eye the gate and my measurement see as the left one in image coordinates; the right eye already matches within 1.3).
- diego image-left eye: 5.8 / 13.6 -> 0.8 / 7.3 (the disc includes some sclera, so dL stays large); right 2.9 / 4.0 untouched.
- ava gaze left eye 3.5 / 3.9, right 1.4 / 2.6; sofia left 2.3 / 3.8, right 6.1 / 6.1. I tried iris-class Lab shifts on these (k 0.4-1.4, left/right/both, with/without lightness): the gate's own window metric got worse every time (Ava 2.1/3.9 -> 2.3-2.7/4.4-5.2; Sofia ab 0.1 -> 0.2-0.4, L improved to 0.1-0.4), so by the "never worsen" rule I kept the production gaze for Ava and Sofia. The Ava left-eye grey cast the reviewer saw is therefore NOT fixed. The gate window includes lashes and liner, so it is a noisy proxy; a mask-based fix needs a real iris segmentation (not done).
- Iris correction method: shift Lab of iris-class pixels (L 5-46, chroma > 0.6, soft disc 1.1 r around the located centre) by the per-eye difference to the portrait iris, 3 iterations damped 0.9, limits +-5 L, +-4 a/b. No change to eye shape, highlights or lids.
blink_half (symmetric): the production frame is kept for the eye that already reads right and the other eye is rebuilt by lid descent from the approved portrait: the lid skin region of production blink_closed is compressed down to a lid margin halfway (t) between the portrait's upper liner line and the closed lash line, composited over the portrait eye (rows below the lid stay the portrait's open eye), a soft dark lash line is added on the margin. Ava: image-left eye, t 0.5; Diego: image-right eye, t 0.62. Both eyes now close by a similar amount (wink gone). Ethan/Sofia blink_half were not flagged and are unchanged. blink_closed unchanged on all four (reviewer: flat/muddy; not addressed).

## Honest remaining weaknesses
- The open-vowel interiors are still rendered, not photographic: teeth edges are clean, tongues are smooth pink blobs with noise, the lower teeth row is a little flat/greyer than the upper. At 390 pt they read as a real open mouth; at 1:1 an attentive reviewer will see a synthetic look. A generative inpaint (SDXL/LivePortrait with a real mouth reference) or a photographic teeth/tongue library would be the next step.
- Open-vowel frames now show the cavity much more strongly than round 1 (bigger opening; upper teeth shorter than production); the app's jaw-drop warp on top of D px has not been run through render_demo_test.dart or the flutter compositor, so the combined opening may be too large on loud vowels. Needs an app render before approval.
- Ethan a2/a left end of the upper teeth has a slightly abrupt end; Ava a left-most tooth is a little uneven; Diego upper teeth look slightly toothy/arched.
- Ava identity on a/a2/l/o dropped 0.02-0.04 versus production (gate still passes). Sofia a identity unchanged (0.54).
- Ava gaze left-eye and Sofia gaze right-eye iris differences from the portrait are not corrected (see D). Ava gaze still widens the eyes and loses the lid shimmer (shape not changed per instruction).
- Ava blink_half left eye is closed a little more than the right (both read as the same blink, no wink); lid skin is flatter than the production eye (no shimmer); a tiny lash tick may remain at the inner corner.
- Ethan/Ava o: the o shape is a lip-only widening of the production pout: less pout, not a new viseme. Diego o/o2 unchanged, so the production moustache is kept.
- fv, u, e, i and viseme coverage, blink_closed, listening behaviour: not touched.

## Files
`<coach>/` drop-in sets; scripts in `scripts/` (paint.py, synth.py, render.py, sofia_i.py, lipo.py, lid.py, eyefix*.py, eyesweep.py, gen_open.py, gen_misc3.py, gen_eyes.py, sheets3.py); experiments in `work/`.


# ROUND 2b UPDATE (supersedes earlier numbers/claims where they differ)
Final per-frame regate numbers: see regate.txt (76/76 pass, no gate loosened); production in regate-production.txt.

## 1. Gaze frames: synthesised from the approved rest portrait (all four coaches)
`scripts/gazesyn.py`, `gen_gaze.py`. Per eye: iris+pupil+catchlight layer (core of the dark iris disc after a morphological opening that removes liner/lashes, plus catchlight) taken from the rest portrait, the old iris area inpainted from its surroundings (sclera / liner shadow), the layer pasted shifted 5-6 px sideways and clipped by the eye-opening mask, with a soft upper-lid shadow on the moved iris. Lids, lashes, liner, shimmer and eye shape are the rest portrait's, so eyes do not widen and shimmer is kept; iris colour is the approved colour by construction, both eyes. Same patch rect/size/geometry. Direction: Ava/Ethan/Diego +5 px (image right), Sofia -6 px (image left; +x gave a worse gate for her). Vertical shift was dropped (narrow eyes made lid-crossing bumps).
Gate eye_shift (ab / L), production -> v3: Ava 2.1/3.9 -> 0.3/0.6; Ethan 3.1/1.8 -> 0.7/0.1; Diego 4.4/8.5 -> 0.4/0.5; Sofia 0.1/0.9 -> 0.1/0.8. Identity/master of the gaze frames rise (Ava 0.70/0.82 -> 0.76/0.98, Ethan 0.87/0.91 -> 0.91/0.99, Sofia 0.67/0.80 -> 0.72/0.99, Diego 0.84/0.90 -> 0.88/0.99). All four look brown, natural and left/right matched at 1:1 and phone size (work/gaze-final.png). Weakness: it is a small look-away (5-6 px), not up-and-aside; the catchlight moves with the iris; Sofia looks the other way from the others. The earlier disc-correction gaze frames are discarded.

## 2. Ava identity
Kept the candidate where there is a clear visual gain: a/a2/l (clenched teeth -> open mouth) 0.687/0.720/0.716 -> 0.659/0.702/0.675. Ava o/o2 is now the production frame with ONLY the lip-corner tail removed (the widening was dropped; the earlier lipmask also wrongly picked the black corner triangle for Ava and the dark moustache for Ethan, now fixed with an ellipse-limited lip mask): o 0.654 -> 0.618 (dropped, but the visible gain is the removed tail, which the reviewer flagged), o2 0.637 -> 0.645. blink_half 0.709 -> 0.699 (symmetric blink is the gain). Worst Ava frame 0.618 (o), gate 0.45. Ethan o/o2 widening is kept (0.830/0.838, above production 0.815/0.846 on o).

## 3. App compositor check (jaw mesh)
render_demo_test.dart needs the repo's assets and a job set and cannot take another frames folder without changing the repo, so I ported AvatarPainter._drawJaw exactly (8x12 mesh, jawDrop 0.12 of mouth width, lineV/peakV smoothstep, sin(pi u) falloff, triangle-by-triangle affine textured, scripts/jaw.py) and composited each candidate and production frame on the hero at jaw 0, 0.5, 1.0 (jawsheets.py): <coach>/contact-jaw.jpg, rows prod/cand for a, a2, l, o. Findings: displacement is zero on the patch border (border max diff vs portrait <= 13/20/30/14 grey levels for ava/ethan/sofia/diego, JPEG noise; the first run showed 100-128 on Ava/Ethan o, caused by my lip warp touching the black corner / moustache, fixed); no tearing, no gap or teeth smear where the mesh stretches the cavity; lower teeth stretch about 25 % at jaw 1 and read as a wide open mouth. Because the opening at jaw 1 was large I reduced the cavity: a drop 12 -> 8 px, a2 8 -> 5 px (l stays 1). Not run: the real Flutter painter (GPU filtering, FilterQuality.medium), only the geometric port.

## Remaining weaknesses (updated)
- Open-vowel interiors are still rendered, not photographic (see above); lower teeth flatter than upper; Ethan a2 left end of the upper row still abrupt.
- Ava a/a2/l/o identity 0.62-0.70 (lower than production, passes the gate); Sofia a identity 0.531 (production 0.537) is the lowest of any frame.
- Gaze is a sideways glance only (no upward component); Sofia's goes the opposite way.
- Ava blink_half left eye closes slightly more than the right; lash tick possible at inner corner.
- Jaw simulation is a Python port, not the Flutter render; needs one on-device/flutter check before approval.
