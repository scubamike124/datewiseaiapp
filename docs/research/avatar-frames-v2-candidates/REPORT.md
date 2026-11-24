# Candidate mouth frames v2 (2026-11-24)

Candidate only. Production frames in assets/avatar and assets/coaches were not touched. Each folder is a complete drop-in set (same filenames, rects and manifest.json; unchanged frames are byte-identical copies). Changed frames need owner re-approval.

Gate: `AVATAR_TOOLS=<yunet/sface dir> python3 tool/avatar/regate.py --frames <this folder>` -> **76/76 pass** (output in regate.txt). Gates untouched (identity >= 0.45, master >= 0.75, iris 5/15). Eyes were not edited, so the mouth frames have iris shift 0.0/0.0 (blink/gaze frames are the original files; Diego gaze still 4.4/8.5).

Border check: changed pixels at the patch edge differ from the approved file by <= 8 grey levels (JPEG re-encode noise; Sofia <= 15 on a dark hair edge), so seams are unchanged.

Method (CPU only, no generative model, no accounts; the SDXL route was not used because it was not needed and memory was shared with the IMTalker job): bite-line detection, remap warp, procedural cavity and tongue, LAB teeth tone/gap repair, optical-flow morph, compositing. Scripts: scripts/ (gen_a.py, gen_misc.py, ov.py, ov_o.py, fv.py, ava_fix.py, sheets.py). Contact sheets: <coach>/contact-full.jpg (1:1 pixels) and <coach>/contact-phone.jpg (390 pt stage at 2x), before row / after row.

## Changed frames

| Coach | Frame | identity | master | iris dab/dL | method |
|---|---|---|---|---|---|
| ava | a | 0.680 | 0.833 | 0.0 / 0.0 | warp: lower teeth/lip dropped 15 px at the bite line (tapered to corners, fades to 0 over the lower lip), dark red-brown cavity + small tongue drawn in the gap, scalloped tooth edges; teeth: thin dark gaps closed, ivory tint, corner/edge shading; also removed the orange/red lower-lip blotch (a* capped to the lip, smoothed) |
| ava | a2 | 0.743 | 0.879 | 0.0 / 0.0 | same as a, 11 px drop |
| ava | l | 0.727 | 0.867 | 0.0 / 0.0 | same, 9 px drop, tongue tip high behind the upper teeth |
| ava | o | 0.762 | 0.900 | 0.0 / 0.0 | flow-morph 40-80% toward the approved rest face, 1.2-1.28x horizontal widening of the lips, rest skin (smile lines, moustache) kept outside a feathered ellipse around the lips |
| ava | o2 | 0.783 | 0.910 | 0.0 / 0.0 | same as o |
| ava | fv | 0.726 | 0.917 | 0.0 / 0.0 | lower lip opened 8 px, upper-incisor strip (the coach's own a-frame teeth, tinted, with soft interdental lines) placed on the lower lip |
| ethan | a | 0.831 | 0.925 | 0.0 / 0.0 | warp: lower teeth/lip dropped 15 px at the bite line (tapered to corners, fades to 0 over the lower lip), dark red-brown cavity + small tongue drawn in the gap, scalloped tooth edges; teeth: thin dark gaps closed, ivory tint, corner/edge shading |
| ethan | a2 | 0.842 | 0.932 | 0.0 / 0.0 | same as a, 11 px drop |
| ethan | l | 0.823 | 0.921 | 0.0 / 0.0 | same, 9 px drop, tongue tip high behind the upper teeth |
| ethan | o | 0.871 | 0.955 | 0.0 / 0.0 | flow-morph 40-80% toward the approved rest face, 1.2-1.28x horizontal widening of the lips, rest skin (smile lines, moustache) kept outside a feathered ellipse around the lips |
| ethan | o2 | 0.875 | 0.956 | 0.0 / 0.0 | same as o |
| sofia | a | 0.538 | 0.803 | 0.0 / 0.0 | warp: lower teeth/lip dropped 15 px at the bite line (tapered to corners, fades to 0 over the lower lip), dark red-brown cavity + small tongue drawn in the gap, scalloped tooth edges; teeth: thin dark gaps closed, ivory tint, corner/edge shading |
| sofia | a2 | 0.576 | 0.818 | 0.0 / 0.0 | same as a, 11 px drop |
| sofia | l | 0.578 | 0.826 | 0.0 / 0.0 | same, 9 px drop, tongue tip high behind the upper teeth |
| sofia | o | 0.723 | 0.919 | 0.0 / 0.0 | flow-morph 40-80% toward the approved rest face, 1.2-1.28x horizontal widening of the lips, rest skin (smile lines, moustache) kept outside a feathered ellipse around the lips |
| sofia | o2 | 0.724 | 0.942 | 0.0 / 0.0 | same as o |
| sofia | fv | 0.677 | 0.933 | 0.0 / 0.0 | lower lip opened 8 px, upper-incisor strip (the coach's own a-frame teeth, tinted, with soft interdental lines) placed on the lower lip |
| sofia | i2 | 0.662 | 0.915 | 0.0 / 0.0 | subtle interdental lines + per-tooth edge shading + ivory tint on the existing teeth band |
| sofia | sh | 0.650 | 0.899 | 0.0 / 0.0 | same as i2 |
| diego | a | 0.758 | 0.867 | 0.0 / 0.0 | warp: lower teeth/lip dropped 15 px at the bite line (tapered to corners, fades to 0 over the lower lip), dark red-brown cavity + small tongue drawn in the gap, scalloped tooth edges; teeth: thin dark gaps closed, ivory tint, corner/edge shading |
| diego | a2 | 0.777 | 0.885 | 0.0 / 0.0 | same as a, 11 px drop |
| diego | l | 0.769 | 0.881 | 0.0 / 0.0 | same, 9 px drop, tongue tip high behind the upper teeth |
| diego | o | 0.853 | 0.948 | 0.0 / 0.0 | flow-morph 40-80% toward the approved rest face, 1.2-1.28x horizontal widening of the lips, rest skin (smile lines, moustache) kept outside a feathered ellipse around the lips |
| diego | o2 | 0.867 | 0.933 | 0.0 / 0.0 | same as o |

Worst per coach (all 19 frames): identity ava 0.645, ethan 0.824, sofia 0.539, diego 0.758; master min 0.80/0.90/0.80/0.87. Sofia a/a2/l identity (0.54-0.58) is about unchanged from the approved frames (0.54).

## Not changed

u, u2, e, e2, i, mbp, cons, th and the blink/gaze frames (u/u2 stay near rest on Ava and Sofia as before: only fv was asked to show /f/). Eyes untouched. Ethan and Diego fv/i2/sh unchanged.

## Remaining weaknesses (honest)

- Cavity is procedural: a dark red-brown lens with a soft tongue, clean at 390 pt and acceptable at 1:1, but flatter than a photo. Ethan a2/l read as a thin, flat dark bar; Sofia/Ava a2/l are a thin dark line with a hint of tongue.
- Ava a/a2: small dark wedge remnants at the upper-left mouth corner (original bite-line shadow, lightened to dark brown, not removed). Sofia a: the original dark gap/spot is gone but one corner is still dark.
- Teeth are the renderer's own teeth, toned and cleaned, not new teeth: Diego's upper teeth keep their slight irregularity (intended), Ethan keeps two pale rounded lateral teeth. No coach-source grin teeth were pasted (alignment/identity risk); only the fv strip reuses the coach's a-frame teeth.
- o/o2: softer and wider, with smile lines restored from the approved still, but Ava keeps a thin lip-corner tail at the upper left (present in the original o) and Diego's soul patch is lost under the lip in o (as in the original). Not verified in motion against the animator.
- fv: shows 4-6 upper teeth on the lower lip for Ava/Sofia; teeth look slightly bright against the lips on Ava. u/u2 remain near-identical to rest (not requested).
- Not verified: playback with the app compositor (jaw-drop warp on top of a 15 px gap) and GPU filtering; the jaw warp could deepen the cavity beyond what was designed. Needs an on-device or flutter-test render before approval.
