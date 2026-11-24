# DateWise AI: overnight report (2026-11-24)

Nothing was deployed, merged, purchased or submitted. Spending: **$0**. Production portraits, voices and the app's
live behaviour are unchanged. Everything below is on branches or in draft PRs for your approval.

## Summary

| Area | Status |
|---|---|
| Live coach chat | **Broken today (HTTP 502)**: Cloudflare retired the model used by the deployed chat-v5. The fix (chat-v7) is already on `main`; it needs the 3 Cloudflare secrets and your approval of one deploy run. |
| Portraits | New photoreal candidates for all four coaches, each set reviewed by an independent reviewer. Awaiting your choice. |
| Voices | 13 samples (Kokoro and Chatterbox, free and commercial-use) on identical scripts, with objective checks. Awaiting your ears. |
| Avatar video demos | **Blocked**: needs a GPU or a provider trial account; you asked for no new accounts tonight. |
| App code | 6 fix commits in draft PR #54; CI green; 957 Flutter tests and 110 backend tests passing. |
| TestFlight | Build 2.0.0 (185) is VALID and not expired. Not verified on a device by me. |
| Subscription | `datewise_premium_monthly` unchanged: US$19.99 / CA$24.99 / MX$399.00 / €22.99, no offers, Family Sharing off. Still "Missing metadata" (review screenshot). |

## 1. Completed and verified

- **Backup:** branch `backup/main-2026-11-24` = `b060239` (main before tonight). GitHub refused the tag, so a branch was used.
- **Backend 413 fix (security review M5):** oversized chat requests are refused before parsing. Test added.
- **Spanish review fixes:** gender-neutral Sofía and Diego, a Mexican-Spanish vocabulary rule, 13 wording fixes, and the demo coach no longer promises photo upload. Independent Spanish reviewer: 26 findings; all medium items fixed except the two that need you (below).
- **UI review fixes:** the paywall price column (M1); chat refreshes the store when the server says the subscription was revoked or expired (M2). No critical or high UI findings.
- **Coach safety rules (static review, 16 findings):**
  - crisis lines for self-harm;
  - recognising unnamed abuse and romance scams;
  - no explicit sexual content;
  - never helping anyone pursue minors;
  - "I can't see images";
  - no guaranteed results and no invented life story;
  - privacy and no prompt reveal;
  - no repeat introductions.

  Mirrored in the app. Cost impact: about +14% input per message.
- **Regression:** `flutter test` 957 passed, 0 failed. Backend 110/110. PR #54 CI green: tests, unsigned iOS release build, worker check and staging dry run.
- **Feature audit:** see `REVIEW_FEATURES.md`. Photo upload is removed cleanly, Spanish covers 247/247 strings, and the paywall and App Store text match what exists.
- **Cost model:** `docs/business/AI_COST_MODEL.md` section 10 adds voice and avatar costs for light, average, heavy and extreme users.

## 2. Completed, awaiting your approval

- **Portraits:** see section 6.
- **Voices:** see section 7.
- **Draft PR #54** (`claude/overnight-2026-11-24` → `main`). Do not merge without your OK.
- **Avatar research and voices:** branch `claude/avatar-research` (docs and audio only).

## 3. Blocked by external requirements (exact actions)

1. **Live chat 502:**
   - In GitHub → datewiseaiapp → Settings → Environments → **production-worker**, add environment secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` and `ID_HASH_SALT`.
   - Then Actions → **Deploy coach Worker** → Run workflow on `main`: target `chat-v7-cost-guard`, untick *Dry run*.
   - Approve the deployment when GitHub asks.
2. **Real coach conversations, and the 66-scenario coach test battery:** need chat-v7 live (staging target `chat-v7-staging` is ready and uses about 2,417 test units).
3. **Avatar video demos:**
   - **Open source** (SoulX-FlashHead, MuseTalk/LiveTalking, EchoMimicV3, Ditto) needs a GPU. The anonymous Hugging Face free GPU quota is used up. A free Hugging Face or Kaggle account would unblock it.
   - **Simli, HeyGen, D-ID, Tavus and Anam** need trial accounts.
   - You asked for no new accounts tonight, so no videos were made.
4. **Premium voices** (ElevenLabs, Cartesia, Deepgram Aura-2): need accounts or keys. Deepgram is also on Cloudflare Workers AI once the Cloudflare credentials exist.
5. **Public website preview:** there is no free public host without an account. Cloudflare Pages needs the same Cloudflare token. GitHub Pages on a private repo needs a paid plan. The existing preview is a private Claude page.
6. **Subscription review screenshot:** best taken on your iPhone from TestFlight build 185 on the paywall, after you choose the portraits. The web review build shows a "simulated purchases" line and the old portrait.

## 4. Failed testing / needs work

- **Ethan, Diego and Sofía, round 1 portraits:** the reviewers rejected them for an over-sharpened, aged look, and for jewellery artefacts on Sofía. Round 2 is in section 6.
- **Chatterbox Sofía voice:** one 2.6 s pause and mispronunciations; needs a retake.
- **Kokoro Spanish voices:** questions come out flat.

## 5. Decisions only you can make

1. **Service AI budget (security H1):** the free 10,000-unit daily budget covers about 77–87 replies a day for all users combined, but the app promises 150 a day per user. Options:
   - Workers Paid ($5/month) with a larger budget;
   - a lower per-user cap;
   - a cheaper model.
2. **Crisis and hotline numbers in the coach prompt:** please confirm 988 (US), Línea de la Vida 800 911 2000 (Mexico), 911, and the US domestic violence hotline 1-800-799-7233.
3. **Legal:**
   - Mexican privacy law (ARCO rights, controller name and address) needs a legal review.
   - The hosted Lovable privacy pages need republishing with the Nov 24 text.
4. **After App Review:**
   - set the Sandbox budget back to 1,000 (M2);
   - turn on App Store Server Notifications so refunds are enforced (M1).
5. **Weekly plan:** items only tick off; they don't open a chat. Wiring them up is a small product change, if you want it.

## 6. Portraits

PORTRAITS_SECTION

## 7. Voices

Files: `claude/avatar-research` → `docs/research/avatar-voice-2026-11-24/voices/` (13 MP3s plus README and measurements).

- All 13 are intelligible: Whisper transcripts match the script with 0–7% of words wrong.
- The four coaches are distinct by pitch.
- **Chatterbox** keeps natural question intonation in both languages. Ava, Ethan and Diego are good candidates; Sofía needs a retake.
- **Kokoro** is clear, but its Spanish voices read questions flat.
- Nobody has listened yet: please listen to the 8 samples sent to you and pick a voice per coach.

## 8. Avatar recommendation

- **For v1:** keep the still portrait plus a voice. There is no streaming video cost, and it is the safest for App Review.
- **When animation is wanted**, the cost model favours:
  - **Simli** (about $0.01/min): cheapest hosted, needs a trial account; or
  - a **self-hosted open-source** model (SoulX-FlashHead or Ditto; licences OK) on a rented GPU once there are about 100+ subscribers.
- **HeyGen, Anam and Tavus:** a heavy user costs more than the $13.57–16.48 DateWise keeps per subscriber after Apple's cut.
- **Next step:** with your OK to create one free Hugging Face account, the open-source demos can be made on free GPU time.

## 9. TestFlight

- Build 2.0.0 (185): uploaded 2026-11-23, processing VALID, not expired. Internal group "Owner" exists.
- **Install path:**
  - Open the TestFlight app on your iPhone with the Apple ID that is in the "Owner" group, and install DateWise 2.0.0 (185).
  - If it doesn't appear, go to App Store Connect → DateWise → TestFlight → Internal Testing → Owner, and add build 185 and your Apple ID.
- Chat will fail (502) until the deploy in section 3.1. I did not verify it on a device.

## 10. GitHub

| Item | State |
|---|---|
| PR #54 `claude/overnight-2026-11-24` | Draft, CI green, not merged |
| `claude/avatar-research` | Research docs and voice samples |
| `claude/asc-verify` | Read-only App Store Connect check (run 45334592680) |
| `backup/main-2026-11-24` | Backup of main |
| amberai `claude/wg-subscription-automation` | White Glove, paused, unmerged |

## 11. Costs

$0 tonight. All image, voice and test work ran on this session's own container: no paid APIs, no GPU rental, no accounts.

## 12. Reviewer reports

In this folder:
- `REVIEW_SECURITY.md`
- `REVIEW_SPANISH.md`
- `REVIEW_UI.md`
- `REVIEW_FEATURES.md`
- `REVIEW_PORTRAITS_*.md`
- `../COACH_PROMPT_REVIEW_2026-11-24.md`
- `../../qa/COACH_BATTERY_2026-11-24.json` (not run)

## Your checklist

1. ☐ Pick Ava's portrait (top 3 sent), then Ethan's, Sofía's and Diego's.
2. ☐ Listen to the voices and pick one per coach.
3. ☐ Add the 3 Cloudflare secrets to `production-worker` and approve the chat-v7 deploy (fixes the 502).
4. ☐ Decide the AI budget (Workers Paid $5/month or lower caps).
5. ☐ Confirm the crisis and hotline numbers.
6. ☐ Review PR #54; say "merge" if approved.
7. ☐ Install TestFlight build 185 and test chat after the deploy.
8. ☐ Optional: allow one free Hugging Face account for avatar video demos.
9. ☐ Later: take the paywall screenshot for the subscription review, create the Spanish subscription localizations, and arrange the legal review.
