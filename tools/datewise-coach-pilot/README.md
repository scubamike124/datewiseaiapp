# DateWise coach pilot — owner-approved handoff

Serve the player from this directory with `python3 -m http.server 8000 --directory dist`. Open http://localhost:8000. The player, portraits and clips are self-hosted. The default ten-second Ava clip is the approved reference for natural mouth closure.

| Coach | Language | Voice sample | Approved pacing |
| --- | --- | --- | --- |
| Ava | English | Kokoro af_heart for the additional opening line | Keep the reference and opening line as supplied |
| Ethan | English | Kokoro am_michael | Original |
| Diego | Spanish | Kokoro em_alex | 85% of original tempo |
| Sofía | Spanish | Kokoro ef_dora | 85% of original tempo |

The final Spanish MP4s already include the slowdown. Use normal playback speed. For new lines, supply original-speed voice audio; the renderer applies the Spanish adjustment once before animation. The intended audience includes Mexican Spanish speakers; the team has not independently certified the accents.

## For Claude

Use the included DateWise portraits and the approved clips when integrating the four-coach selector into the app. Keep the existing coach identities and Ava's relaxed expression. The owner wants DateWise characters in a DateWise player. This pilot has prerecorded dialogue; live replies and native iPhone performance still need separate implementation and verification. No vendor credentials are needed for playback.

See render/README.md for render-host setup. New outputs are registered in dist/ava/lines.json. Media checks covered H.264/AAC decoding, matching audio/video durations and visible mouth closure. The owner accepted the final pacing of the four-coach pilot.
