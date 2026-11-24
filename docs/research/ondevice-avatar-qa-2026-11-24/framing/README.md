# Framing candidate: eyebrows visible on the iPhone stage

Candidate branch `claude/avatar-framing-candidate` (SHA 8d5753c), NOT merged, awaiting owner approval.
Only `lib/avatar/coach_stage_avatar.dart` changes (stage height W/2 -> 0.6*W, clamped 150-250; portrait box 1.2x the
stage height, clipped at the bottom). No image asset is touched. On an iPhone 15 the stage is about 37 pt taller.

| (% of stage height, iPhone 15) | Before | After |
|---|---|---|
| Eye-patch top (brow line) | -5 to -13 (brows cut off) | 6 to 13 (brows visible) |
| Eye centre | 7-12 | 26-31 |
| Mouth | 55 | 66 |
| Chin | cropped | about 88 (partly faded) |

`framing-compare.jpg`: before (left) and after (right) for Ava, Ethan, Diego, Sofía at 3x.
A new test pins that the brows and chin stay inside the stage for all four coaches at iPhone SE, 15 and 15 Pro Max widths.
