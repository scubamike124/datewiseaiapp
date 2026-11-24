# Coach portrait candidates (2026-11-24, overnight). NOT approved, NOT in the app.

Three candidates per coach, ranked after independent visual reviews (reviews/). The owner picks one per coach;
production portraits are unchanged until then. `candidates/comparison-sheet.jpg` shows all twelve.

**How they were made ($0, no accounts):** RealVisXL V5.0 Lightning (SG161222, CreativeML OpenRAIL++-M, commercial
use allowed with the licence's use restrictions), run on CPU in the session container (gen_all.py, gen_v2.py,
gen_v3.py, gen_v3s.py hold the exact prompts, seeds and settings).

**Retouching, disclosed:** 
- Irises darkened to dark brown on every final (iris.py: MediaPipe Face Landmarker iris landmarks, Apache-2.0; only
  pixels inside the iris and eyelids change; catchlights kept).
- A light de-sharpen (Gaussian blend) on Ethan, Diego and Sofía to remove the over-sharpened look; skin texture kept.
- Diego #1: an AI-invented logo on the polo was painted out (OpenCV inpaint).
- Ava #1 and #3: cropped to remove a hand and smeared arms.

**Open issues the reviewers raised:** Ava wears a casual sweater in all three; Ethan still shows some deep crow's
feet; Sofía #1 has a tiny stud earring and #2 a small drop earring and fine chain; Diego #2 has small blemishes on
the earlobe; none of these was retouched further.

These are synthetic people. If one is adopted, keep the generation record (this folder) with the app's assets.
