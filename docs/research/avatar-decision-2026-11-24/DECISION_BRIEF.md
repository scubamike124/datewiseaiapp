# AVATAR REPLACEMENT DECISION BRIEF: DateWise AI

Date: 2026-11-24. Desk research only. No account opened, no sign-in, no spend. Companion files: REQUIREMENTS_MATRIX.md, COSTS.md, costs.json (from costs.py), INTEGRATION_PLAN.md.

## 1. One-page summary

**Situation.** If the independent review fails the on-device frame-based avatar, the engine is replaced, not the app. The replacement must work inside DateWise: Flutter on iPhone, a Worker that mints sessions only for a verified StoreKit entitlement, no vendor key in the app, no new native-only code (AGENTS.md), US/CA/MX/ES, four coaches (EN and es-MX), AI operating cost within $4-5 per subscriber per month.

**Ranked recommendation**

| Rank | Option | Role | Cost at 60 min (all-in, list) | Why | Main unknown |
|---|---|---|---|---|---|
| 1 | **Simli** (audio-in, via our Worker) | **Pilot first** | **$1.85** | Only credible API that fits the budget up to 120 min ($3.87); plain WebRTC + token, no native SDK; own faces from $10; we keep our LLM, prompts and caps; enterprise has zero data retention and a 99.95% SLA | Quality on our portraits and in es-MX; privacy and acceptable-use terms unread |
| 2 | **Anam** | Quality benchmark, premium capped tier | $10.83 (enterprise hint $0.04/min: $3.63) | Best quality claims; own image on the Free plan ($0 test); SOC 2 Type II, DPA, no-training statement | Price: only fits at 15-21 min on list, or after an enterprise quote; JS-only SDK so a WebView page |
| 3 | **bitHuman** | Cost and privacy hedge, second wave | cloud $4.32; on-device $0.95 | Cheapest credible; on-device keeps media on the phone | On-device is a native Swift SDK on iPhone 16 Pro+ only (needs a White Glove plugin later, not allowed in v1 Flutter); cloud is borderline |

Not recommended now: HeyGen LiveAvatar LITE ($7.62, $99 floor, unresolved consent rules for fictional faces; FULL $11.40 sends the whole conversation to the vendor), Tavus ($21.15), D-ID (no official streaming price found; about $43 on third-party derivation), and every self-hosted open option (MuseTalk, IMTalker, FlashHead/Mynah, OpenAvatarChat, LeapTalk, Live Avatar/FlashTalk). The open options are cheap per minute but need a warm-GPU floor of about $1,300/month, unresolved licences (FlashHead weights "license: other"; MuseTalk training-data notice) and ops work, and our own CPU tests of MuseTalk and IMTalker did not show a clear win over the current avatar. LivePortrait is a renderer we already use offline, not a conversational engine. Keep the open route as a scale hedge (not before roughly 5,000-7,000 subscribers per COST_AUDIT B1).

**The one option to pilot first: Simli,** run alongside a $0 Anam Free test of the same portrait so the owner sees the quality ceiling next to the budget option. Reason: it is the only option that is both plausibly good enough to test and affordable at every usage level the owner cares about, and it works with the architecture DateWise already has.

**Exact cost at the five usage levels** (per subscriber per month, voice = our neural TTS placeholder $0.027/speech-min, text = existing Llama model, list price before free allowance)

| Minutes | Simli | Anam (list $0.16) | Anam (Pro $0.11) | bitHuman cloud | bitHuman on-device |
|---|---|---|---|---|---|
| 15 | $0.46 | $2.71 | $1.96 | $1.08 | $0.24 |
| 30 | $0.93 | $5.42 | $3.92 | $2.16 | $0.48 |
| 60 | **$1.85** | $10.83 | $7.83 | $4.32 | $0.95 |
| 120 | $3.87 | $21.82 | $15.82 | $8.79 | $2.06 |
| 300 | $9.68 (over budget) | $54.56 | $39.56 | $21.98 | $5.16 |

Remaining revenue per subscriber at 60 min with Simli: $14.63 (US/CA/MX, 15%), $11.72 (30%), $11.77 (Spain, 15%), $9.36 (Spain, 30%). At 300 minutes Simli leaves $6.80 / $3.90 / $3.94 / $1.54, so a cap is required.

**Hard cap (recommended):** 60 included premium-avatar minutes per month (Simli; 30 if bitHuman cloud, 15-30 if Anam at list), enforced in the Worker with 10-minute tokens and a 45-60 s idle close; after the cap, on any vendor error or offline, the existing on-device avatar and system voice take over silently. Detail in COSTS.md section 6.

**What the owner must approve (nothing has been done)**

1. Permission to create vendor accounts (Anam Free first; Simli Hobby).
2. Permission to upload ONE approved coach portrait (Ava) to those vendors for the test (it leaves our control; the rest of the coaches only after the gates pass).
3. Spend: **$10 once** (Simli Hobby, one month, cancel after; required because the Simli Free plan has template faces only). Total pilot cash cost: $10. If the owner wants strictly $0: Anam Free only, plus Simli Free with a stock face to judge latency.
4. Workers Paid ($5/month) before any neural-voice pilot beyond a few turns: TTS draws on the same neuron pool as chat (COSTS.md s5; today's account is on the free 10,000 neurons/day and no paid fallback is enabled).
5. Voice: accept that the live avatar uses a neural Worker voice instead of the system voice (product change, with its cost).
6. Privacy/legal copy (INTEGRATION_PLAN s8) and a second 5.1.2(i) consent naming the vendor.

**Exact cheapest first step:** the owner (not Claude) signs up for **Anam Free** (no card, 30 min, own image, 3-minute sessions) and uploads the Ava portrait, then I send the vendor questions in INTEGRATION_PLAN s6 to Anam and Simli before anything else is uploaded. Next, **$10** buys Simli Hobby for the same portrait. Both are judged against the on-device avatar on the same eight scripted EN/es-MX lines using the existing identity and lip-sync scripts. Decision rule: proceed to the 5-6 day in-app pilot only if the vendor is clearly preferred in a blind owner rating, passes the identity and iris gates and the vendor's written privacy answers are acceptable.

**Verification status.** Verified today from vendor pages: Simli, Anam, LiveAvatar, bitHuman, Tavus, LiveKit prices and limits. Not verified (gaps, not yeses): every vendor's lip-sync accuracy and Spanish lip quality, Simli/Tavus/D-ID/bitHuman-cloud privacy terms, acceptable-use for dating coaching and fictional faces, D-ID streaming price, Simli time-to-create, hosted-vendor time-to-first-frame in our pipeline.

## 2. Corrections to earlier notes

- `docs/avatar/PAID_PROVIDER_BAKEOFF.md` assumed $6.99 net per subscriber (the old $9.99 price). At $19.99 it is $16.48 / $13.57 (US) and $13.62 / $11.22 (Spain).
- It treated LiveAvatar's consent requirement as settled; the sources conflict (LiveAvatar FAQ lists a consent recording, HeyGen developer docs say photo avatars need none). Ask in writing.
- It priced Simli at about $0.05/min [T]. The vendor's own page today says $0.01 (Hobby) / $0.0095 (Pro).
- It put the cap at 30 min; with Simli's actual price 60 minutes fits comfortably, 30 stays right for the dearer options.
- The earlier cost notes omitted neural voice, transport and the Spain VAT effect; COSTS.md includes them.

## 3. Why the best demo may not be the best choice

1. **Demos use stock faces.** Vendor homepages and the free tiers of Simli, Tavus and LiveAvatar show templates or stock avatars. Our four coaches are portraits upscaled from small references; an image-to-avatar step can soften them, drift the face or recolour eyes, which the owner has ruled out. A demo says nothing about identity.
2. **The most lifelike option is the one we cannot afford.** Anam and Tavus lead on realism claims, at $10.83 and $21.15 per subscriber at 60 minutes against a $4-5 budget. A feature that loses money on the active users is worse than a plainer one with a cap.
3. **Quality claims are vendor-run.** Anam's latency study, HeyGen's "under 300 ms" and Tavus's 134 ms are the vendors' own numbers; the one independent comparison in our notes put LiveAvatar's median time-to-first-frame near 4.7 s. We have no measured lip-sync or Spanish-lip result for any hosted vendor.
4. **Demos are English on good Wi-Fi with the vendor's own voice.** DateWise needs es-MX, cellular, and our own TTS audio fed in; lip quality on non-English phonemes is the usual weak point and is UNVERIFIED for all of them.
5. **A demo is not an iPhone app.** The hard parts are the audio session (WebRTC or WebView next to on-device speech recognition and speech synthesis), backgrounding, Bluetooth, the StoreKit-gated token and the fallback. The best-looking vendor with a JS-only SDK costs more integration days than a plainer one with a token and WebRTC.
6. **Switching to a live vendor changes the voice.** Today the coach speaks with free system voices; a lip-synced vendor face needs our audio, so we pay for a neural voice and the voice research must pass first.
7. **The open-source demos are the weakest evidence.** They run on a 4090 with a licence or training-data caveat; our own CPU tests of MuseTalk and IMTalker showed soft mouths, artifacts and no clear win over the current avatar.
8. **The existing avatar has real advantages the review may not weigh:** $0 per minute, works offline, nothing leaves the phone, identity exactly the approved portrait. If the review fails it on realism, a vendor replacement is also a privacy and cost regression; the pilot gates exist to prove the trade is worth it.

## 4. Sources (fetched or searched 2026-11-24)

- Simli pricing: https://www.simli.com/pricing ; docs index: https://docs.simli.com/llms.txt ; Flutter community client: https://pub.dev/packages/simli_client ; Pipecat integration: https://docs.pipecat.ai/api-reference/server/services/video/simli
- Anam pricing: https://anam.ai/pricing ; docs: https://anam.ai/docs/introduction ; governance: https://anam.ai/ai-governance ; ZDR: https://anam.ai/blog/zero-data-retention ; DPA: https://anam.ai/data-processing
- bitHuman pricing: https://www.bithuman.ai/pricing
- HeyGen LiveAvatar credits: https://docs.liveavatar.com/docs/faq/credits ; FAQ: https://help.heygen.com/en/articles/12758866-liveavatar-faq ; consent: https://developers.heygen.com/docs/avatar-consent ; biometric notice: https://www.heygen.com/biometric-privacy-notice ; moderation: https://www.heygen.com/moderation-policy
- Tavus pricing: https://www.tavus.io/pricing
- D-ID: https://docs.d-id.com/docs/livekit ; third-party pricing: https://www.activepieces.com/blog/d-id-pricing-2026-every-plan-cost-and-limit ; LiveKit plugin: https://docs.livekit.io/agents/models/avatar/plugins/did
- LiveKit Cloud pricing: https://livekit.com/pricing
- Prior research (same day): `wt-research/docs/research/avatar-tech-2026-11-24/` (frameworks, models, alternatives, free-gpu-and-licensing, costs-capacity, COST_AUDIT, calc/model.py, musetalk-cpu, imtalker-cpu); `datewiseaiapp/docs/business/AI_COST_MODEL.md`; `docs/avatar/PAID_PROVIDER_BAKEOFF.md`; app code `lib/avatar/`, `lib/services/voice_service.dart`, `backend/worker.js`, `backend/apple_jws.js`, `backend/cost_guard.js`.
