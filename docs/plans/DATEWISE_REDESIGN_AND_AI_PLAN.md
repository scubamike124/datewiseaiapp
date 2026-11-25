# DateWise redesign and AI integration plan

Written 2026-11-22 for #20. Built on the code in `main` (App Store 1.0.2 build), PR #21 (the four coaches) and PR #17 (backend model fix), and on issues #1–#19. Everything stated as fact below was read from the repository or tested on this branch. Anything that was not is marked **unverified**.

## 1. Where things stand

| Area | State | Evidence |
|---|---|---|
| Four coaches (Emily, James, Isabella, Mateo), picker, bilingual text coaching | **Built**, PR #21, waiting for owner approval to merge (merging deploys the web app) | 35 tests in #21: widget flows and iPhone SE / 15 / 15 Pro Max / iPad / 320×568 at 1.3× text. Green CI. Independent review: APPROVE. |
| Live coaching backend (Cloudflare Worker `datewise-photo-coach`) | **Likely broken in production.** `main` calls `@cf/meta/llama-3.1-8b-instruct-fp8`, which Cloudflare retired on 2026-11-20 (HTTP 410). | PR #17 swaps to `@cf/meta/llama-3.3-70b-instruct-fp8-fast`, with offline tests. The live state is **unverified** from here: the sandbox cannot reach `*.workers.dev`. |
| Coach roster API used by the redesign issues | **Compatible.** This branch adds the names #6–#10 and #13 use: `kCoaches`, `coachById`, `coachesFor`, `displayName`, `gender`, `coach.systemPrompt`. | `test/coaches_test.dart`, "names the redesign issues use". |
| Coaching evaluation data (#18, #19) | Amber's independence test. #18 runs after the 00:00 UTC free-budget reset. | amberai beacon |
| Premium prototype (#4–#10) | Specified, not built | Issues |
| Mode-aware prompts (#13), consent memory (#14), scorer (#12), engine comparison (#16, needs #15) | Specified, not built. Amber's #14 run failed its own test on 2026-11-22. | Issues, amberai runs |
| Voice, video, date concierge | **Not built and not claimed.** No provider chosen or approved. | — |

Overlap resolved: #3 (coach roster) was closed as superseded by #21, so Amber does not build a second, conflicting `lib/models/coach.dart`. #2 (audit document) is covered by this plan and #21. If Amber's run of #2 would only repeat this, it can be closed the same way. That is the owner's call, and is listed in section 5.

## 2. AI integration

### A1. Restore the live coach (owner approval, no cost)
Merge and deploy #17 (chat-v6 at `f5b0401`, using a deploy path from `docs/launch/WORKER_DEPLOY_RUNBOOK.md` §7; release checklist D0). Then check:
1. `GET <worker>/?version` returns `chat-v6`.
2. A chat request streams `data: {"response": …}` lines.
3. In the app, a coach answers.

Until this is done, the App Store app's coach most likely shows "I'm having trouble reaching the DateWise coach right now".

### A2. Close the open proxy (backend change, needs review and an approved deploy)
The Worker forwards whatever `messages` a caller sends, including its own `system` message, to Workers AI on the owner's account (`handleChat` → `sanitizeMessages`). CORS only restricts browsers, so anyone can use it as a free general-purpose LLM and use up the free daily allowance.

Plan, in two reviewed steps:
1. **New contract, old one still accepted** (draft #23). The app sends `{coachId, tier, profile?, messages}`. `profile` is the structured `UserProfile.toJson()`, never free text. The app keeps its own system message so that an older Worker still works.
   - The Worker builds the system prompt itself, with the same coaching rules as the app and drift-checked against `coach.dart` and `persona.dart`, and drops any client `system` message.
   - Only known profile values reach the prompt.
   - Requests without `coachId` (App Store 1.0.2) keep today's behavior. `?version` reports `chat-v7`.
   - This narrows abuse for coach requests but does not close it: user and assistant turns still reach the model.
2. **Remove the old contract once adoption allows.** After an app release that sends `coachId` has reached most users, the Worker rejects requests without one. Add per-IP rate limiting. Cloudflare's Workers rate-limiting binding is one option; whether it is free on this account is **unverified**, so that is an owner decision.

Tests: extend `backend/worker.test.mjs` from #17 with a fake AI binding. Cover: a client system message is ignored when `coachId` is present; an unknown `coachId` gets 400; legacy requests are unchanged.

### A3. Measure coaching quality before changing models
- **Data:** #18 and #19, 24 scenarios across five modes, with coach ids matching #21.
- **Scorer:** #12, deterministic checks: asks before writing, no invented facts, right language, brand-safe, respectful, length.
- **Run:** the current free model (#17's) and one or two other free Workers AI chat models on all 24 scenarios, through the Worker's own prompt. Store the replies and the score report in the repo.
- **Cost:** free-tier Workers AI only. The neuron cost per run is **unverified** until it runs.
- **Then:** pick the model by score, especially Spanish (`rightLanguage`) and `noInventedFacts`, where small models are weakest.

### A4. Better coaching behavior (after A3 has a baseline)
- #13 `coach_policy.dart`: mode-aware instructions and a profile interview that asks before it writes. It now builds on #21's `Coach` (`coach.systemPrompt` exists).
- #14 consent memory: off by default, visible and deletable. Wire it into the prompt only after #13. Re-run A3 after each to show the change in score.

### A5. Voice, video, concierge (owner decisions, paid)
Nothing is integrated. #16, which needs #15 merged, compares text, voice and avatar vendors on price, privacy, policy and Flutter integration. Any paid provider, real likeness or voice, camera or microphone use, or booking partner needs the owner's explicit approval. Until then the UI may show clearly labeled "coming soon" controls only, with camera and microphone off by default (as #9 specifies).

## 3. Redesign

Two visual tracks exist:
- **Live app:** the cream and navy theme. #21 puts the coaches here.
- **Premium prototype:** midnight purple and plum, under `lib/prototype/` with its own entry point `lib/main_prototype.dart` (#4–#10). It never touches the App Store build.

**Recommendation:**
1. Build the prototype exactly as #4–#10 specify, on #21's roster. With this branch, no spec needs changing except two notes:
   - "#3 merged first" now means #21.
   - `CoachLanguage` values are `en` / `es`. The prototype's own `AppLanguage` (#5) maps onto them.
2. Waves:
   - **Wave 1**, in parallel: #4 theme, #5 strings.
   - **Wave 2:** #6 avatar.
   - **Wave 3**, in parallel: #7 onboarding, #8 home, #9 conversation, which uses the real `AIService` and therefore the live coaches.
   - **Wave 4:** #10 app shell.
3. When the owner approves the prototype's look, one PR moves the live app onto the premium theme and screens. It keeps every existing feature: profile tools, photo coach, account, privacy and legal pages.

**Who builds what:**
- Amber takes the small file-scoped issues (#4, #5, #6, #12, #13, #14), one per run, on the free route. That is the point of her independence test.
- Claude takes over an issue only after Amber has stalled on it twice, or on owner request, and says so on the issue.

## 4. Order of work

1. Owner approvals:
   - #17: backend fix; restores live coaching.
   - #21: four coaches; web deploy on merge.
2. A2 step 1 (backend contract with `coachId`), with tests, as its own PR. Deploy only with approval.
3. Amber: #18 tonight, then #19. Then #12 scorer, then the A3 run.
4. Amber: wave 1 (#4, #5), then wave 2 (#6).
5. A4 (#13, #14) once A3 has a baseline.
6. Waves 3–4, then the owner reviews the prototype, then the swap PR.
7. A5 only after owner decisions.

## 5. Owner decisions needed

1. Merge and deploy #17. The live coach is likely down until then.
2. Merge #21. This deploys the web app; the App Store build is unchanged.
3. Approve the A2 backend contract change, and decide whether to add rate limiting.
4. Close #2 as covered by this plan, or keep it as Amber practice.
5. Choose the redesign direction: the premium prototype as specified (recommended), or evolve the live theme.
6. Paid voice and video providers, likeness and voice consent, and booking partners (A5): no work until decided.

### Owner decisions recorded (2026-11-23)

- **No sign-in for v1.** The app keeps no accounts; conversations stay on the device.
- **Booking is a link-out only.** On first-date plans (Home's "Prepare for a date", the weekly plan's "Plan a first
  date", the coaches' "Plan a first date" starters) a compact "Find a table" button under the coach's latest reply
  opens an Apple Maps search for restaurants (`https://maps.apple.com/?q=restaurants`, `restaurantes` in Spanish), on
  tap only. No accounts, no partner APIs, no API costs, no location permission, no chat content sent. iPhone/iPad only;
  hidden on the web and Android. Booking partners (A5) stay undecided.
- **Update 2026-11-25 (reservation planner).** "Find a table" / "Buscar mesa" now also appears when the user's latest
  message asks about a restaurant or reservation, in text chat and the voice conversation, on every platform. It opens a
  "Plan a table" sheet (area, cuisine, budget, date, time, party size) whose results are search links carrying only what
  the user typed: OpenTable (`/s/?covers=&dateTime=&term=`, unverified against OpenTable docs, see
  `lib/app_links.dart`), Google Maps (`/maps/search/?api=1&query=`, documented) and Apple Maps where it exists. DateWise
  still cannot see availability or book; still no accounts, partner APIs, costs or location permission.

## 6. Not claimed

- That the live model answers well in Spanish. This is **unverified** until A1 and A3.
- Any voice, video, avatar, camera, memory or concierge feature.
- Any cost figure for paid providers.
