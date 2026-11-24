# DateWise AI avatars: before / after SIMULATION videos

All outputs are SIMULATIONS (host `flutter test` renders of the app's own animation code), not device recordings. Nothing was committed or pushed; production assets were not modified (both worktrees were temporary and are removed).

## Files
- `<coach>-<en|es>-before-after.mp4` (8 files): 15 s, 2286x1040 (two 369 pt stages at 3x), 30 fps, 450 frames, AAC audio. BEFORE left, AFTER right, each labelled. SIMULATION banner, state caption per side (LISTENING / THINKING / SPEAKING / IDLE), current mouth shape, jaw value and active patches, time and progress bar. Window per clip: listening (user's turn, ~0-1.9 s for Ava EN; nods, blinks, breathing), thinking before the coach speaks, then the coach speaking.
- `<coach>-sheet.jpg` (4 files): still contact sheet, before | after for every mouth frame whose JPEG changed (plus `rest` as an unchanged reference). Each patch is pasted on the approved portrait as the app does. Changed frames: Ava a, a2, o, o2, fv, l; Ethan a, a2, o, o2, l; Sofia a, a2, i2, o, o2, fv, l, sh; Diego a, a2, o, o2, l. Blink, gaze, mbp, cons, e, e2, i, u, u2, th frames were byte-identical, except i2 and sh for Sofia (listed).
- `scripts/`: `sim_render_ba_test.dart` (renderer), `encode_ba.py`, `sheet_ba.py`, `run_all.sh`.

## How
- Renderer: the earlier QA `sim_render_test.dart` (AvatarFrames, AvatarAnimator, LipSyncDriver fed with loudness levels like the iOS native-audio path, AvatarPainter), changed to: stage 369 pt wide (iPhone 15 393 pt minus 12 pt padding each side), `CoachStageAvatar.stageHeight`, the same clip + caption fade (`fadeStart` 0.85, `AppColors.surface`) that `render_framing_test.dart` and the chat screen use, a fixed animator seed (12345) on both sides, and identical jobs (same audio window, timeline, text, loudness) as `ondevice-qa/jobs/`. Frames at 3x, 30 fps.
- BEFORE: detached worktree at dd3eac5 (PR branch just before 26396da): approved assets/avatar frames, old animator, stage height width/2 (185 pt rendered; 184.5 exact), overscan 1.0.
- AFTER: worktree at 26396da (gaze hold into speech, no blink while thinking) with `git merge 8d5753c` (framing candidate; merged cleanly, no conflicts), plus the 4 coaches' avatar-frames-v2 JPGs and manifest.json copied over assets/avatar/<coach>/ in that worktree only (the extra `contact-*.jpg` files in v2 were NOT copied). Stage height 0.6 x width = 221 pt, overscan 1.2 (set via QA_K=1.2, matching `CoachStageAvatar.portraitOverscan`).
- Shorter BEFORE stage is top-aligned and padded with the surface colour, with thin outlines marking each stage's bounds.
- Audio: Ava and Ethan EN, Sofia and Diego ES use their own recording. Cross-language clips (Ava ES, Ethan ES, Sofia EN, Diego EN) use the same-gender partner's recording (Sofia for Ava, Diego for Ethan, Ava for Sofia, Ethan for Diego); the on-screen line says "CROSS-LANGUAGE TEST AUDIO". The mouth shapes there are driven by loudness plus the target-language text, so lip-text correspondence is only approximate.

## Verification
ffprobe on all 8 MP4s: 15.0 s video, 450 frames, 15.0 s audio. Frames at several timestamps from each coach were viewed: patches (blink, gaze, mouth) sit correctly on the face in the new framing for all four coaches in the frames inspected; no misalignment seen.

## Caveats and honest notes
- Not a device recording: no iOS compositing, real TTS timing or Flutter widget tree (the OverflowBox/ClipRect in CoachStageAvatar is reproduced as a canvas clip + scaled paint, same as the repo's framing tool).
- Mouth timing comes from the loudness-only path; word-marker path (iOS 17) not simulated.
- Because the animator changed in 26396da, the same seed does not give identical blink timing on both sides; the difference in eye behaviour is partly the intended fix and partly different random draws.
- In the AFTER thinking segment the `mbp` (lips closed) patch shows alongside gaze for Ava at ~2.2 s; I did not investigate why (it is the app animator output at 26396da, not something the render script adds, but not verified further).
