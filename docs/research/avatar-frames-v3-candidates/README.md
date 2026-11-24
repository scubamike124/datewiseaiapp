# Round-2 candidate avatar frames (NOT approved, NOT in production)

Complete drop-in sets for assets/avatar/<coach>/ with manifest.json. Production images are unchanged and need the
owner's approval first. regate.py: 76/76 pass, no gate loosened. See REPORT.md (per-frame method, gate numbers,
remaining weaknesses). Each coach folder has contact-full.jpg, contact-phone.jpg and contact-jaw.jpg
(jaw 0 / 0.5 / 1.0 composited with a port of AvatarPainter._drawJaw).
Gaze frames are synthesised from the approved rest portrait (iris shifted sideways), so eye colour is the approved brown.
