# Final verdict: frame-based on-device avatar (2026-11-24). Simulation only; I have NOT heard any audio and cannot play video.
Evidence: ffmpeg stills (2 fps tiles, 6 fps mouth grids at 380x190 px, crops/<coach>-mouth-{A,B}.jpg, crops/ava-tile.jpg), the four sheets, silencedetect/ebur128, mouth-metrics.json, prior reviews.

## Scores (1-10; A shipping / B round-2). In speaking stills A and B are near-identical at phone size.
| | Ava | Ethan | Sofia | Diego |
|---|---|---|---|---|
| Face/identity | 8/8 | 9/9 | 7/7 | 9/9 |
| Eye colour | 7/7 (left reads grey-hazel, unfixed) | 8/8 | 9/9 | 8/8 |
| Mouth realism | 6/6.5 | 6/6.5 | 6.5/7 | 5.5/6 |
| Lip-sync timing/rate | 6.5 | 7 | 6.5 | 7 |
| Blink | 5/6 (A: wink-like half blink; B reduces it but blink sheet frame still looks one-sided) | 7 | 7 | 5/6 (squint, flat closed lids) |
| Head/breath motion | 5 | 5 | 5 | 5 |
| Listening | 4 | 4 | 4 | 4 |
| Thinking | 5 | 5 | 5 | 5 |
| Expression | 2 | 2 | 2 | 2 |
| Transitions | 7 | 7 | 7 | 7 |
| Phone impression | 5.5 | 6 | 5.5 | 5.5 |
B vs A: B is slightly better (parted-teeth cavity no longer a ribbon at phone size, o/o2 pout widened, Ava wedge/tail gone, eye fixes on Ethan/Diego gaze). Not enough to change the category.

## What I saw
- Mouth: calm now (4.9-5.8 shape changes/s average, worst second 8; Ava's short closing line 7.1). Better than old 7-10/s. Shapes seen: closed smile, wide-smile teeth (dominant, repeated), small o-pout (Ava/Diego look like a kiss), a few open-vowel shapes (Sofia and Diego show a dark open mouth with teeth; Sofia's lower teeth row reads grey/gapped; Diego's teeth uneven with a visible gap). The same 4-5 mouth poses cycle; there are no true visemes, so lip sync is "mouth opens when loud", not accurate speech shapes. Pop between poses is a hard 1-frame swap of the mouth patch (no tween), visible as flicker of the mouth at 24 fps; skin seams themselves invisible.
- Listening: face is a still photo with a constant closed smile, slight drift and blinks (3-6 s). No brow, cheek, nod, gaze or smile change in any tile (ava-tile.jpg rows 1-2). This is the "frozen/looped" listening the owner dislikes; it reads as a held photograph.
- Thinking: gaze patch to the side plus "..." bubble; ok but the face stays smiling; one frame swap.
- Expression: none. Same smile in every state, including the sad/nervous user topics.
- Blink: half-blink frames read as winks/squints on Ava and Diego in the blink column of the sheets; closed lids flat. Hard on a phone because blinks are the one thing that moves the upper face.
- Audio (research recordings, measured, not heard): loudness -26.7 to -28.6 LUFS, peaks -4.3 to -8.8 dBFS (no clipping). Sentence gaps 0.28-0.78 s detected (380 ms by design); a 3 s silent thinking/listening gap (5-8 s) before the reply. Pacing in the demo is the recordings' own; the real iOS voice (robotic/rushed on build 203) is untested here. Only a human ear can judge naturalness, rush and robotic quality.

## Versus hosted products (REQUIREMENTS_MATRIX only; all vendor claims, none tested by us)
Anam: expressive photo avatars, Raven perception (emotion, listening) claimed; Tavus/Phoenix-4: 40 fps, 134 ms audio-to-video; Simli: "mouth region on a mostly static face" per description (so also limited); bitHuman Expression 2 variant. None has verified lip-sync or Spanish quality; pilot required. Our engine cannot match perception-driven listening/emotion by design.

## Premium test
A paying $19.99/mo customer on a phone: the portraits are attractive (identity 7-9) and the mouth is now calm, but the whole experience is "beautiful photograph with a mouth that changes pose and a smile that never changes". Listening, which is most of a conversation, is dead. I rate overall 5.5/10, not premium. Not "cheap" thanks to the portraits.

## What the engine can never deliver (frame swapping)
Emotional reactions/micro-expressions, true visemes (a few fixed mouth poses), smooth jaw/lip interpolation, brow/cheek/head response, gaze following, speech-timed head motion, natural listening, new expressions without more hand-made frames per coach (4 coaches x per emotion).

## DECISION
FAIL for premium as the primary avatar: stop developing the frame-based engine and start the replacement pilot (Anam/Simli/bitHuman, with our portraits, es-MX lines, real device). Before deciding finally, human check of the real iOS voice and the video by the owner. The existing avatar IS acceptable as the FALLBACK (use B frames: revert nothing except keep Diego o/o2 production as in B; Ava blink_half remains flagged) and as the offline/failure mode. Code/config-only tweaks worth doing regardless (not rebuilding faces): tween/hold mouth poses >=120 ms, longer listening idle (brow-free subtle head drift/nod on pauses), blink using full closed only.
