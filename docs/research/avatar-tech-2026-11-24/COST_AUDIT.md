# Independent audit: talking-avatar costs and capacity (DateWise AI)

Audited: `docs/research/avatar-tech-2026-11-24/costs-capacity.md` and `calc/model.py` (worktree `/home/user/wt-research`),
with `frameworks.md`, `models.md`, `alternatives.md` and `/home/user/datewiseaiapp/docs/business/AI_COST_MODEL.md`.
Audit date: 2026-11-24. No accounts created, no money spent. Supporting script: `xover.py` in this folder.

**Bottom line.** The arithmetic is correct and reproducible. The problems are in what the model leaves out and in how
its conclusions follow from it. Three conclusions do not hold: the "~1,000 subscribers" crossover to self-hosting, the
headline per-subscriber costs (no TTS, transport or ops), and a v1 plan that ignores the owner-approved on-device
talking avatar already in the app. Against the owner's goal (photorealistic, interactive, premium, commercially usable,
sustainable), the recommendation leans to the cheapest options. It has no quality bar above Ditto (4/10), and the paid
test does not include a premium benchmark.

---

## 1. Reproduction and formula checks

`python3 -I model.py` runs cleanly. Every figure I checked in sections 0, 3.2, 3.3, 4.2, 4.3 and 8.2 matches the output.

| Check | Hand calculation | Result |
|---|---|---|
| Net revenue | 19.99 × 0.85 × 0.97 = 16.48; 19.99 × 0.70 × 0.97 = 13.57 | Correct (refunds are treated as reversing net proceeds, which is right, since Apple returns its commission on a refund) |
| $/speaking stream-min | 0.34/60/2 = 0.00283; 0.89/60/2 = 0.00742 | Correct |
| $/wall-min, hybrid | × d 0.5 ÷ u 0.5 = 0.00283 / 0.00742 | Correct |
| Per subscriber, Secure 4090, u = 0.5 | 0.00742 × 20/60/150 = $0.15 / $0.45 / $1.11 | Correct |
| Hybrid slots, 99.5th percentile of Bin(S, 0.5) | S = 1,000: 500 + 2.576 × 15.8 ≈ 541; S = 100: 63; S = 10: 9 | Correct |
| GPUs at peak | ceil(9/2) + 1 = 6; ceil(63/2) + 4 = 36; ceil(541/2) + 28 = 299 | Correct |
| Hybrid saving | 10% / 37% / 46% | Correct for d = 0.5 (but see M3) |
| Break-even vs Simli | 248/(0.01 × 60) = 414; 650/0.6 = 1,083 | Arithmetic correct, method wrong (B1) |
| Test budget | 7 h × 0.89 = 6.23 + 0.33 storage = 6.56; + 2.70 = 9.26 | Correct |

Formula caveat: the u = 0.5 per-subscriber figures in 3.2 are lower than the doc's own capacity model at small scale.
At S = 10 (2,400 typical subscribers), the Secure fleet costs $1,559/month autoscaled, which is $0.65 per subscriber,
not the $0.45 the u = 0.5 row implies. Fixed provisioning costs $1.62. At S = 1,000 it costs $0.32, below the u = 0.5 row.

---

## 2. Price and performance spot checks (all fetched 2026-11-24)

| # | Claim in doc | Source checked | Verdict |
|---|---|---|---|
| 1 | RunPod RTX 4090: $0.89 Secure / $0.34 Community; Serverless $1.34; L4 $0.69/$0.44; H100 SXM $4.39/$2.69 | runpod.io/pricing | **Confirmed** |
| 2 | Vast.ai 4090 on-demand median $0.465, min $0.296, n = 64 | Vast public bundles API, single-GPU rentable on-demand | **Confirmed** (median $0.469, min $0.296, n = 64). Interruptible median bid came out $0.367, not $0.34: the query differs slightly; **minor difference** |
| 3 | Modal L4 $0.80, L40S $1.95, A10 $1.10, A100 $2.10/$2.50, H100 $3.95; $30/month Starter credits | modal.com/pricing | **Confirmed** |
| 4 | Lambda A10 $1.29, A100 40 GB $1.99, 80 GB $3.19, H100 PCIe $3.79, SXM $4.69–4.89 | lambda.com/pricing | **Confirmed**, except H100 SXM, which is $4.59–4.89 (8× nodes $4.59): **minor difference** |
| 5 | Simli Hobby $10 / $0.01, Pro $49 / $0.0095, Scale $249 / $0.009, concurrency 2/10/50, enterprise "from $0.005" | simli.com/pricing | **Confirmed**. Not mentioned in the doc: a Free plan with 50 min and 1 session |
| 6 | bitHuman 4 credits/min cloud, 2 on-device, $1 per 100 credits, speaking-only billing on device, caps 3/10/50/200 | bithuman.ai/pricing | **Confirmed**. The page says the 2-credit, speaking-only rate applies "on your own devices **or servers**". The doc treats it as iPhone 16 Pro+ only and misses that a server-side self-hosted bitHuman runtime is an option at about $0.01/wall-min (see M7) |
| 7 | Anam Starter $0.16, Pro $999 incl. 8,000 min, $0.11, enterprise from $0.04; concurrency 1/3/5/10/100+ | anam.ai/pricing | **Confirmed**. Not mentioned in the doc: a Free plan with 30 min/month (3-min conversations) |
| 8 | HeyGen LiveAvatar LITE 1 credit/min, FULL 2; Essential $99/1,110 credits | docs.liveavatar.com credits FAQ | **Confirmed**. Business overage is $0.09/credit; the doc's $0.079 is the included-credit rate. **Minor** |
| 9 | Tavus Builder $0.35, Business $0.26, concurrency 3/15, 30 s minimum | tavus.io/pricing | **Confirmed** (newer table; the page still carries an older conflicting table, as the doc says). Not mentioned in the doc: a free plan with 20 min |
| 10 | MuseTalk 4090 72 fps (LiveTalking), 3090 45, 3080 Ti 42; both inferfps and finalfps must be ≥25 | github.com/lipku/LiveTalking | **Confirmed** as published. It is a single-stream throughput figure, not a concurrency measurement (see M1) |
| 11 | MuseTalk "30fps+ on V100", 256×256 face region | github.com/TMElyralab/MuseTalk | **Confirmed**. The README says the model may be used commercially but the test data is non-commercial. The HDTF licence question stays open, as the doc says |
| 12 | LiveKit cost for the "Simli/bitHuman via LiveKit" path | livekit.com/pricing | **Not in doc**: agent session $0.01/min after the included minutes, plus WebRTC minutes $0.0004–0.0005 and $0.10–0.12/GB (see M4) |

Unverifiable here: FlashHead Lite 96 fps / 3 streams (vendor claim) against Mynah's measured 1 stream; Anam and Tavus
latency claims (vendor-run). The GCP column is already flagged as unverified in the doc.

---

## 3. Findings ranked by severity

### Blocking (must be fixed before the owner decides on this document)

**B1. The "self-host above ~1,000 subscribers" crossover is wrong. The doc's own capacity model contradicts it.**
The 414 to 1,083 break-even compares *one* warm GPU against Simli. But one 4090 serves only about 2 sessions, which is
about 480 typical subscribers (doc 4.3). Section 8.1 itself asks for at least 2 warm GPUs. Using the doc's own
autoscaled fleet formula (`xover.py`, RunPod Secure 4090, 2 streams, d = 0.5):

| Peak sessions S (typical subs) | Self-host Secure, 2 streams | Self-host Secure, 1 stream | Simli Scale $0.009 | Simli enterprise $0.005 |
|---|---|---|---|---|
| 10 (2,400) | $1,559 | $2,599 | **$1,296** | **$720** |
| 30 (7,200) | $3,378 | $6,497 | $3,888 | **$2,160** |
| 100 (24,000) | $9,356 | $18,192 | $12,960 | **$7,200** |
| 1,000 (240,000) | $77,704 | $154,888 | $129,600 | **$72,000** |

Corrected crossover:
- Against Simli list price: about **5,000–7,000 typical subscribers** with 2 streams per GPU, and **never** with 1 stream.
- Against Simli's enterprise rate: Secure-cloud self-hosting **never** wins at these sizes.
- Only Community Cloud ($0.34) clearly wins. Its hosts are third-party machines handling users' dating-coaching audio,
  which is a GDPR and privacy problem for a Spain-based owner, and the doc itself flags the data-handling issue.
- Adding even modest ops time (say $1,500/month of engineering and on-call) pushes the crossover past ~25,000
  subscribers.

Correction: replace "~1,000 subscribers" with "not before ~5,000–7,000 typical subscribers, and only if the GPU test
shows ≥2 streams per 4090 and Simli enterprise pricing is not available". Self-hosting is a cost hedge at scale, not
a near-term step.

**B2. The headline costs leave out TTS and real-time transport, and those can be bigger than the avatar itself.**
- Today the app's voice is on-device Apple TTS (AI_COST_MODEL §1). A server-rendered lip-synced avatar needs the
  audio on the server. That means either neural TTS on the server, or uploading the device's TTS audio, which adds
  latency and keeps a non-premium voice.
- The doc says self-hosted Kokoro is "about $0", but on the hosted (Simli/bitHuman) path there is no GPU box to run it.
- It recommends "via LiveKit" without pricing it. LiveKit Cloud charges about $0.01 per agent session minute plus
  WebRTC minutes and data, roughly **$0.012/min**.

Corrected full stack per subscriber per month, Simli via LiveKit Cloud with Cartesia TTS ($0.035 per speaking minute, d = 0.5):

| Profile | Doc (text + Simli) | + LiveKit | + hosted TTS | Budget at 70% margin (15% / 30%) |
|---|---|---|---|---|
| Light 20 min | $0.27 | $0.51 | **$0.85** | $4.94 / $4.07 |
| Typical 60 min | $0.93 | $1.65 | **$2.70** | $4.94 / $4.07 |
| Heavy 150 min | $3.82 | $5.62 | **$8.25** | $4.94 / $4.07: **over budget** |

The section 8.2 guardrail ("120 min keeps a heavy user under $4.07") only holds with on-device voice and no LiveKit:
$3.52. With hosted TTS and LiveKit it is **$7.06**, which breaches the 70% margin target. Fix: price the transport (use
Simli's own WebRTC client or self-hosted LiveKit to avoid the $0.01/min), state the voice choice, and size the caps on
the full stack. A cap of about 60 premium-avatar minutes plus the on-device avatar beyond that keeps heavy users inside
budget.

**B3. The v1 plan ignores, and would regress, the talking avatar already in the app.**
- `lib/avatar/` (`talking_avatar.dart`, `lip_sync.dart`, `viseme.dart`, `avatar_frames.dart`) already draws an on-device,
  lip-synced, blinking, breathing coach from owner-approved photo patches. It is used in `chat_screen.dart` and costs
  $0 per subscriber. It shipped in commit de430f7, "Final coach portraits and talking avatars, owner-approved
  2026-11-23".
- The doc's v1 ("loops with closed or neutral lips while the coach speaks") is a step down from that. It also breaks
  the repository's reuse-first rule.
- AI_COST_MODEL §10 still says "a still portrait", which is out of date.

Fix: v1 = the existing on-device talking avatar, plus pre-rendered idle, listening and reaction clips if they add value.
Live server rendering becomes the premium upgrade, and its quality bar is "clearly better than the shipped on-device
avatar".

### Material

**M1. 2 streams per 4090 is optimistic. Plan on 1–1.5 until measured.**
- 72 fps is LiveTalking's single-stream inference rate (`inferfps`, batch 16–20). Two sessions in one process
  time-slice the same GPU, so each gets at most about 36 fps before the other work on the box.
- That other work: whisper-tiny audio features per chunk, face paste-back and blending (CPU/numpy in LiveTalking),
  software H.264 encode per stream (aiortc/PyAV, roughly one CPU core per 512 px stream at 25 fps), Python GIL
  contention between session threads, and WebRTC pacing.
- RunPod 4090 pods often come with few vCPUs. LiveTalking itself says the CPU limits streams.
- The only independent measurement in the pack (Mynah on FlashHead Lite) came in 2.5× below the vendor's claim.
- At 1 stream every self-hosted cost doubles and B1's crossover disappears. The test must use the exact pod
  type/vCPU count planned for production and report `finalfps` (not `inferfps`) over at least 10 minutes per stream.

**M2. 0.5% overflow per instant means visible fallbacks in about 18% of sessions.**
A 20-minute session has about 40 coach turns, and 1 − 0.995^40 ≈ 18%. So nearly one session in five drops to voice
over a loop for at least one turn. For a "premium" product, size at 99.9% or use a per-session reserved slot for paying
users. That reduces the hybrid saving (at S = 100, from 37% to about 33%).

**M3. The duty cycle is under-assumed.**
The doc's own derivation from AI_COST_MODEL gives d ≈ 0.62, but the base case uses 0.5. At d = 0.6 the provisioned
saving is 0% / 28% / 36% (not 10/37/46), and marginal costs rise 24%. Render pre-roll (the model must run ahead of the
audio) and the mouth-close tail push effective GPU time higher still. Use d = 0.6 as the base case.

**M4. Transport, TURN and egress cost is waved away, and the cross-reference is broken.**
Section 3.1 cites "section 6.3" for TURN and bandwidth, but 6.3 is the licence section; no TURN analysis exists.
Corrected estimate at 512 px ≈ 1 Mbps ≈ 7.5 MB/min:
- Cloudflare-style TURN at $0.05/GB: about $0.0004/min.
- Twilio-class TURN at $0.40/GB: about $0.003/min.
- LiveKit Cloud: about $0.012/min.
RunPod has no egress fee, as the doc says. Small for the self-hosted path, but not small for the hosted path (B2).

**M5. VAT is missing from the revenue line.**
AI_COST_MODEL §2 notes that EU proceeds are calculated after VAT. A Spanish subscriber at the equivalent price yields
$13.62 (15%) or **$11.22** (30%), not $16.48 / $13.57. All margins and minute budgets should be shown for the
EU-heavy case, about 17% lower.

**M6. The quality bar favours cheap options over the owner's premium goal.**
- The section 9.3 decision rule accepts MuseTalk if lip closure is "above Ditto", which is a 4/10 baseline.
- MuseTalk is a 256 px mouth inpaint with soft teeth and jitter reported. Simli is described as "mouth region on a
  mostly static face". Neither is plainly better than the on-device avatar already shipped.
- The premium vendors (Anam, Tavus, HeyGen FULL) are ruled out on an "all-you-can-talk" 60–150 min assumption. The
  doc never costs a capped premium tier. At about 30 min/month, Anam Pro costs $3.30 and Anam enterprise $1.20, both
  inside the typical budget.
- The real trade-off for the owner is "premium live minutes, capped, on top of the on-device avatar", not
  "cheapest live minutes, uncapped".

**M7. Options are missing or under-weighted.**
- bitHuman's speaking-only $0.02/min rate also applies on the owner's **own servers** (pricing page), not only on an
  iPhone 16 Pro+. That gives a commercially licensed, photoreal, hybrid-billed option at about $0.01/wall-min with no
  HDTF/CelebAMask licence risk.
- Simli enterprise ($0.005) is mentioned but not used in the crossover.

**M8. Engineering, operations and monitoring are not priced.**
Self-hosting needs:
- a session router;
- an autoscaler that runs ahead of the evening peak;
- capacity contingency (RunPod Secure 4090 supply at peak is not guaranteed; 299 GPUs at S = 1,000 is not
  realistic supply);
- health checks, overflow and fps metrics, logs and an on-call path;
- licence clearance (HDTF, CelebAMask-HQ face-parse, InsightFace in Ditto).

For a solo owner this time is the dominant cost below tens of thousands of subscribers. Hosted vendors include it.

**M9. Cold start and the autoscaling assumptions are optimistic.**
The 20–60 s worker load is an estimate. Pod provisioning plus image pull on RunPod is typically minutes. The
"average GPUs = peak ÷ 3 × 1.2" autoscaling assumes capacity can follow the curve. Keep the warm floor (the doc does)
and assume scale-up lead times of 5–15 minutes.

### Minor

- m1. Lambda H100 SXM is $4.59–4.89, not $4.69–4.89. LiveAvatar Business overage is $0.09/credit. Vast interruptible
  median bid is about $0.37 in my query.
- m2. The free tiers (Simli 50 min, Anam 30, Tavus 20, bitHuman 99 credits, LiveAvatar 10 credits) are not mentioned.
  They allow a $0-cash premium quality comparison, though each needs an account, so owner approval first.
- m3. The doc points to `avatar-research/calc/model.py` "in this scratchpad". The durable copy is `calc/model.py` in
  the research folder.
- m4. Plan fees and minimum commitments at small scale (Simli Scale $249, Anam Pro $999, LiveKit Ship $50) are
  mentioned but not in the per-subscriber figures. That is fine at scale but matters in year one.
- m5. Storage for avatar latents and logs, and monitoring SaaS, are omitted. Likely below $20/month. The Apple
  Developer fee of $8.25/month is noted.
- m6. PAR = 3 is reasonable for a two-region audience. Use 4–5 if launch is single-market (Spain or US only).

---

## 4. Is the $6.56 paid GPU test well scoped?

It is cheap and the arithmetic is right, but it only tests the low-cost tier and under-budgets two steps:
1. **No premium benchmark.** Add a side-by-side on the same scripted Spanish and English lines with the shipped
   on-device avatar, Simli, bitHuman and Anam (free tiers, $0 cash, owner approval for accounts). Without this the
   owner cannot judge "premium".
2. **No identity gate.** Check the output against the approved portraits and the brown iris colour (AGENTS.md rule),
   using the existing avatar identity checks.
3. **The load test is too short and under-specified.** Fix the pod's vCPU count, use the production process model
   (threads vs processes vs MPS), run each concurrency level at least 10 min, and report `finalfps` and per-stream CPU.
   Budget 3 h, not 1.5 h.
4. **The iPhone WebRTC + TURN step assumes a client and a TURN server that do not exist yet.** A flutter_webrtc test
   client is engineering work, and TURN needs a provider. Either budget for it or test from a desktop browser first.
5. Decision rule: replace "above Ditto" with "clearly better than the shipped on-device avatar in a blind owner
   rating, and within 0.5 points of the best hosted vendor".

Corrected budget: about $9–12 on Secure Cloud (4090 test with longer load runs) plus $0-cash free-tier vendor trials.
Keep the $25 hard cap.

---

## 5. Corrected recommendation

1. **v1:** ship the existing on-device talking avatar (`lib/avatar/`) with voice, at $0, adding idle, listening and
   reaction clips only where they improve it.
2. **Premium tier:** a capped live avatar (for example 30–60 min/month included, then fall back to the on-device
   avatar). Choose the vendor by blind quality test, not by lowest price. Candidates: bitHuman (cloud, or speaking-only
   on own servers), Simli, and Anam at enterprise rates. Size caps on the full stack (avatar + TTS + transport).
3. **Self-hosting MuseTalk:** treat it as a scale hedge, not before about 5,000–7,000 typical subscribers. Only on Secure
   or datacentre GPUs, only if the test shows ≥2 sustained streams per 4090 and quality beats the hosted pick, and only
   after the HDTF and face-parse licences are cleared.
4. **Show margins at EU VAT and the 30% commission rate.**
