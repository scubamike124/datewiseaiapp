# Integrated avatar demos (SIMULATION)

Label on every video: DEMONSTRATION VOICE (research recording), NOT the voice customers hear; SIMULATION of the app's animation, not a device recording.

## Files
- `<coach>-integrated-demo.mp4` (ava, ethan, sofia, diego): 25-30 s, 1632x2024, 24 fps, AAC audio. Left A = SHIPPING (assets/avatar at PR head), right B = CANDIDATE (round-2 frames, avatar-frames-v3). Same audio, timeline and animator seed on both sides. State captions: LISTENING (You are speaking... user turn), THINKING, SPEAKING (sentence count, 380 ms gaps), pause/idle.
- `<coach>-sheet.jpg`: phone-size (393 pt) stills, row A and row B, columns listening / thinking / speaking / blink.
- `mouth-metrics.json`, `jobs/` (timelines, audio), `scripts/` (prep.py, compose.py, metrics.py, sheet.py, run_all.sh). The Dart renderer (test/zz_demo_test.dart) lived only in the temporary worktree and was deleted with it by mistake; it can be re-created on request.

## What was rendered
- Worktree at PR head 45390c9 (detached), removed afterwards. Nothing committed or pushed. B = v3 jpg + manifest.json copied over assets/avatar/<coach>/ in that worktree only (contact-*.jpg and regate files not copied).
- The REAL app: `DateWiseApp` chat tab in voice mode (header, session timer, captions button, stage with full face, caption subtitle, message list, hold-to-talk dock, tab bar), 393x852 pt, 59 pt top / 34 pt bottom safe areas, captured at 2x, frame by frame on a simulated clock. Real AvatarFrames, AvatarAnimator, AvatarPainter, TalkingAvatar, LipSyncDriver (loudness path, 120 ms min shape). The hold-to-talk button was pressed by a simulated pointer; user words appear as the speech partial; AppState sent the messages; the reply was delivered by a scripted AI; the chat screen itself called voice.speak() when the reply completed.
- Flow: idle -> user turn 1 (listening, ~4-5 s) -> 0.6 s pause -> thinking 2.0 s -> 3-sentence reply -> idle -> user turn 2 (listening) -> thinking 1.3 s -> closing line (1 sentence; 2 for Ethan and Diego because their last sentence was under 1.8 s).
- Audio: research coach-only recordings cut per sentence (silence gaps matched to the text) and re-assembled with exactly 380 ms between sentences, no time-stretching. User turns are the research user voice, low-passed (muffled) at low level, plus quiet room tone: placeholder, not real user speech. Sentence texts were checked against the app's own SpeechText.chunks: all MATCH.
- Sofia and Diego: Spanish audio and UI (Mexican Spanish); Ava and Ethan English. All native recordings, no cross-language.

## Mouth-shape changes per second (shown shape changes, sampled per 24 fps frame, speaking windows only, rest transitions included; identical for A and B since it comes from the driver and audio, not the frames)
| coach | average | worst 1 s | reply (avg/worst) | closing (avg/worst) |
|---|---|---|---|---|
| Ava | 4.85 | 8 | 4.04 / 8 | 7.14 / 8 |
| Ethan | 5.20 | 8 | 5.20 / 8 | 5.22 / 7 |
| Sofia | 5.83 | 8 | 5.57 / 8 | 6.51 / 8 |
| Diego | 5.39 | 8 | 5.43 / 8 | 5.33 / 8 |
Target met overall (average <= 6, worst <= 8 everywhere). Exception: Ava's one-sentence closing line averages 7.14 (3 s window, worst 8).

## Caveats
- Not a device: no iOS audio session, real TTS or latency; the voice is the research recording, and the native-audio loudness events are replayed from it (not measured from iOS).
- Harness changes in the worktree only: TalkingAvatar's animator seed fixed (it is `coachId ^ DateTime.now()` in the app) so A and B blink identically; fake voice/speech services drive the real screen. The session timer uses the real clock, so it shows slightly different values on A and B.
- The thinking caption is the app's own; the thinking look-away glance is visible in stills only as the gaze patch; judge it in the video.
- Starter chips of the first-run chat are visible behind the user bubble because the thread starts fresh.
