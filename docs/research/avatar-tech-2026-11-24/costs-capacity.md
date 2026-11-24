# DateWise AI talking-avatar coach: costs, capacity and architecture

Desk analysis, 2026-11-24. No accounts were created, no money was spent and no model was run. Every price below is a
list price read on 2026-11-24 from the page cited, unless marked otherwise. Labels:

- **[src]**: read from a cited page or a cited repository file.
- **[est]**: my estimate, with the reasoning stated. A paid GPU test (section 9) should replace these.
- **[calc]**: arithmetic on the two above. The formula is shown.

The numbers are reproducible: `avatar-research/calc/model.py` in this scratchpad (`python3 -I model.py`) prints every
per-minute, per-subscriber and capacity figure in sections 3 to 5.

Inputs carried over from earlier work (dated 2026-11-24 unless noted):
`avatar-research/{frameworks.md, models.md, alternatives.md}` (also at `/home/user/wt-research/docs/research/avatar-tech-2026-11-24/`)
and `/home/user/datewiseaiapp/docs/business/AI_COST_MODEL.md` (prices checked 2026-11-22).

---

## 0. Headline

1. **Revenue per subscriber.** $19.99 × 0.85 × 0.97 = **$16.48** with the Apple Small Business Program (15%), or
   $19.99 × 0.70 × 0.97 = **$13.57** at the standard first-year rate (30%). The 0.97 is the cost model's 3% refund
   assumption. AI_COST_MODEL.md says the owner **must join** the Small Business Program to get 15%. It is not
   assumed to be in place, so both rates are shown.
2. **The 70% margin budget** (the cost model's target) allows $4.94 (15%) or $4.07 (30%) of AI plus infrastructure per
   subscriber per month. Text AI already uses $0.07 (light), $0.33 (typical) or $2.32 (heavy) of that.
3. **Self-hosted MuseTalk 1.5 + LiveTalking with a prerecorded idle loop** is the cheapest live-video option per
   minute. The GPU costs **$0.0028 per speaking stream-minute** on a RunPod community RTX 4090 ($0.34/h ÷ 60 ÷ 2
   streams), or **$0.0074** on RunPod Secure Cloud ($0.89/h). At 50% speaking duty and 50% fleet utilisation that is
   **$0.0028–0.0074 per wall-clock avatar minute**. A typical subscriber (60 min) costs **$0.17–0.45 a month**, and margin
   with text AI stays **above 94%**.
4. **Simli** ($0.009–0.01/min) costs about the same as self-hosting at small scale, and needs no always-on GPU.
   A self-hosted warm GPU (floor of $248/month community, $650/month secure) only beats Simli above **about 414–1,083
   typical subscribers**.
5. **The premium hosted vendors lose money on heavy users at list price.** Anam ($0.11–0.16/min), HeyGen LiveAvatar
   (LITE $0.08–0.095, FULL $0.16–0.19) and Tavus ($0.26–0.35) all do. Tavus also loses money on a *typical* user,
   except Business at 15% commission, which leaves a 3% margin. At a
   70% margin, the avatar minutes a typical subscriber can have are: Anam Pro 34–42, LiveAvatar LITE 39–49, Tavus
   14–18. For comparison: bitHuman cloud 94–115, Simli 375–462, self-hosted MuseTalk 505–623.
6. **The hybrid design saves GPUs only at scale.** With a prerecorded idle loop, the GPU renders only while the coach
   speaks. Provisioned GPUs fall by **10% at 10, 37% at 100 and 46% at 1,000 simultaneous sessions** (50% duty cycle,
   99.5th-percentile sizing). At under about 10 simultaneous sessions it saves almost nothing, because you still need a
   slot for every session that might speak at the same moment.
7. **Recommendation.**
   - v1 ships with pre-rendered clips (idle, listening and reaction loops) plus voice, at $0 marginal cost.
   - In parallel, run a test of about $6–12 on paid GPUs with MuseTalk + LiveTalking over a Ditto loop, plus FlashHead
     Lite, to replace the [est] numbers.
   - Then choose Simli or bitHuman (hosted, via LiveKit) below about 1,000 subscribers, and self-hosted MuseTalk above
     that.
   - Guardrails: every option needs a per-user avatar-minute allowance and a fallback to voice plus loop.

---

## 1. GPU prices (2026-11-24)

### 1.1 Price table ($ per GPU-hour)

| GPU | RunPod Pod Secure / Community [src] | RunPod Serverless [src] | Vast.ai on-demand median (min) [src] | Vast.ai interruptible median bid (min) [src] | Modal [src] | Lambda [src] | AWS us-east-1 on-demand / spot avg [src] | GCP us-central1 [src, partial] |
|---|---|---|---|---|---|---|---|---|
| **RTX 4090 24 GB** | $0.89 / **$0.34** | $1.34 | $0.465 ($0.296), n=64 | **$0.34** ($0.186) | not offered | not offered | not offered | not offered |
| **L4 24 GB** | $0.69 / $0.44 | $0.75 (24 GB tier, shared with A5000/3090) | $0.30 ($0.10), n=14 | $0.20 ($0.03) | $0.80 ($0.000222/s) | not offered | g6.xlarge **$0.805** / $0.642 | g2-standard-4 **$0.707**; spot $0.28–0.62 (sources conflict) |
| **L40S 48 GB** | $1.09 / $0.79 | $1.89 (48 GB tier) | $0.80 ($0.535), n=10 | $0.43 ($0.27) | $1.95 ($0.000542/s) | not offered | g6e.xlarge **$1.861** / $1.633 | not checked |
| **A10G / A10 24 GB** | not listed (A40: $0.59 / $0.35) | not listed (A40 tier $1.22) | A10 $0.24, n=3 | none | A10 $1.10 ($0.000306/s) | A10 $1.29 | g5.xlarge (A10G) **$1.006** / $0.842 | n/a |
| **A100 80 GB** | PCIe $2.09 / $1.19; SXM $2.19 / $1.39 | $2.99 | SXM4 $0.80 ($0.40), n=25; PCIe $0.73 | $0.40 / $0.40 | $2.50 (40 GB: $2.10) | 80 GB $3.19; 40 GB $1.99 | p4d.24xlarge $21.96 / 8 = **$2.74**; spot $1.85 | a2-highgpu-1g (A100 40 GB) $3.67 |
| **H100 80 GB** | PCIe $2.89 / $1.99; SXM $4.39 / $2.69 | $5.89 | SXM $4.05 ($2.48), n=3 | $1.67 ($0.65) | $3.95 ($0.001097/s) | PCIe $3.79; SXM $4.69–4.89 | p5.4xlarge (1 GPU) **$6.88** / $4.48 | A3-High spot $2.591/GPU |
| 2× RTX 5090 (FlashHead Pro) | not checked | not checked | $1.35 per 2-GPU box ($0.78), n=56 | $1.05 ($0.65) | — | — | — | — |

Sources (all fetched 2026-11-24):
- RunPod Pods and Serverless: https://www.runpod.io/pricing . RunPod shows no spot price. Serverless "flex" workers
  bill per second including cold start and idle time; the default idle timeout is 5 s. Active (always-on) worker
  discounts are by sales inquiry: https://docs.runpod.io/serverless/pricing . RunPod's own docs say there are no
  ingress or egress fees for Pods: https://docs.runpod.io/pods/pricing .
- Vast.ai: the public offers API, `https://console.vast.ai/api/v0/bundles/` queried 2026-11-24 for single-GPU,
  rentable offers. "dph_total" was used for on-demand and "min_bid" for interruptible. These are marketplace snapshots,
  so prices move hourly and sample sizes for L40S, A10 and H100 are small. https://vast.ai/pricing says interruptible is
  "50%+ cheaper".
- Modal: https://modal.com/pricing (per-second prices; Starter plan $0 base with **$30/month of free credits**).
- Lambda: https://lambda.com/pricing (self-serve instance prices per GPU-hour, before tax).
- AWS: on-demand and spot average/min for us-east-1 Linux, from the instances.vantage.sh dataset
  (https://instances.vantage.sh/aws/ec2/g5.xlarge , `/g6.xlarge`, `/g6e.xlarge`, `/p4d.24xlarge`, `/p5.4xlarge`),
  downloaded 2026-11-24. The spot figures may lag AWS's live spot feed.
- GCP: the official pages (https://cloud.google.com/products/compute/pricing/accelerator-optimized ,
  https://cloud.google.com/spot-vms/pricing) did not render for the fetch tool. The g2-standard-4 $0.7068 figure is
  corroborated by https://calculator.holori.com/gcp/vm/g2-standard-4 . The spot figure for g2 conflicts between
  sources ($0.28–0.62). **Treat the GCP column as unverified.**

### 1.2 What this means for the choice of GPU

- **The RTX 4090 is the price/performance leader** for these models, at $0.34–0.89/h. It exists only on marketplace
  and community clouds (RunPod, Vast). Those offer weaker SLAs, and community hosts are third-party machines, which
  is a data-handling consideration for user audio.
- **The cheapest datacenter-grade option is the L4** (AWS g6 $0.80, GCP g2 $0.71, Modal $0.80). It renders MuseTalk at
  about 30 fps, so roughly one stream per L4. **A10G** (AWS g5 $1.01) is similar.
- **H100 and A100 are poor value for these small models.** You pay 3–8× a 4090 for perhaps 1.5–2× the throughput
  [est]. MIG slices (section 4) do not change that.
- **Interruptible and spot capacity can kill a live WebRTC session mid-sentence.** Use it only for overflow or
  offline pre-rendering, never for the base fleet.

---

## 2. Streams per GPU (the 25 fps requirement)

A live stream needs **≥25 fps sustained**. LiveTalking's README says both `inferfps` and `finalfps` must be ≥25 to
count as real time [src: https://github.com/lipku/LiveTalking , section 6]. Formula: streams = floor(published fps ÷ 25),
then reduced for headroom (face blending, video encode and TTS on the same box).

| Candidate | Published throughput [src] | Streams per GPU used in this model | Notes |
|---|---|---|---|
| (a) **MuseTalk 1.5 via LiveTalking** | **RTX 4090: 72 fps**; 3090: 45; 3080 Ti: 42 (LiveTalking README §6). V100: "30fps+" (MuseTalk README). A10G and L4: "~30 FPS" (Vivora README instance table, `repos/sur950_vivora/README.md` l.205–211; that is Vivora's claim, not a cited measurement) | **4090: 2** (72/25 = 2.88, rounded down for headroom). **L4/A10G: 1**. L40S ≈ 2, A100 ≈ 2, H100 ≈ 3–4 [est; no published figure] | LiveTalking: "idle sessions scale with CPU, simultaneously speaking sessions scale with GPU". Each stream's video encode uses CPU. Mynah measured MuseTalk at 7.6 GB VRAM resident, so 3 fit in 24 GB by memory |
| (b) **SoulX-FlashHead Lite** via Mynah or OpenAvatarChat | Soul README: "**96 FPS, or 3-concurrent real-time (25+ FPS) streaming on single RTX4090**". Mynah measured: "**1.56× realtime on a 4090, i.e. one GPU ≈ one concurrent visitor**" (39 fps, half-body 720×1280, Mynah README "Capacity & scaling", 2026-10-11). OAC ships `concurrent_limit: 1` | **Base: 1 per 4090** (Mynah measurement). Optimistic: 3 (Soul claim) | The two claims differ 2.5×; the test in section 9 settles it. Via OAC the GPU stays busy while idle (it runs FlashHead on "breathing-patterned noise"), so there is no hybrid saving |
| (c) **SoulX-FlashHead Pro** | Soul README: "**10.8 FPS on single RTX4090, or real-time (25+ FPS) on two RTX5090**" with SageAttention. Users report under 20 fps on 2× 5090 (issue #27) and low fps on 2× L40S (#24) | **1 stream per 2× RTX 5090** (vendor claim). **Possibly 0 real-time streams** (user reports). H100: 1 [est, unverified] | 10.8/25 = 0.43 of a stream per 4090. It needs sequence parallelism across 2 GPUs, which is the opposite of sharing |
| (d) Hosted APIs | n/a (vendor's GPUs) | n/a | Billed per minute. Concurrency is capped by plan (section 3) |
| (e) Pre-rendered clips only | Offline. FlashHead Pro at 10.8 fps on a 4090 renders 1 min of video in 2.3 min | n/a | One-off cost per coach, $0 per subscriber |

---

## 3. Cost per candidate: per minute, per hour, per subscriber, margin

### 3.1 Formulas and assumptions

- **Speaking duty cycle d = 0.5** [est]: the share of wall-clock avatar time during which the coach talks (section 5.1).
  Sensitivity is in section 5.
- **Self-hosted, hybrid** (idle and listening = prerecorded loop, no GPU):
  `$/wall-min = ($/GPU-h ÷ 60 ÷ streams) × d ÷ u`
- **Self-hosted, non-hybrid** (GPU renders all the time, e.g. OAC FlashHead): the same formula with d = 1.
- **u = fleet utilisation**: the average share of provisioned speaking slots in use. u = 1.0 is the pure marginal cost.
  u = 0.5 is a realistic, well-autoscaled fleet [est]. Section 4 derives u from real capacity at 10/100/1,000 sessions.
- **Hosted**: `$/wall-min` = vendor list rate. Vendors bill connected session time, idle included, except bitHuman
  on-device, which bills speaking seconds only (bitHuman pricing page).
- **Usage profiles** (from the brief): light 20, typical 60, heavy 150 avatar minutes a month.
- **Text AI per subscriber** (AI_COST_MODEL.md §5, $19.99 table, 1,000 subscribers, Llama 3.3 70B, infrastructure
  included): light $0.065, typical $0.326, heavy $2.324. This is conservative: 150 avatar minutes is about 300 chat
  turns at 2 turns/min, but the heavy text profile assumes 1,200 messages.
- **Margin** = (net − text AI − avatar) ÷ net, with net = $16.48 (15%) or $13.57 (30%). Not included: the Apple
  Developer fee ($8.25/month fixed), voice TTS (self-hosted Kokoro/Chatterbox on the same GPU box is about $0;
  hosted TTS adds $0.027–0.036/min, per AI_COST_MODEL.md §10), TURN and bandwidth (section 6.3, under $0.01/min).

### 3.2 Self-hosted candidates

| Candidate / GPU / price | Streams | $/speaking stream-min | $/h per stream | $/wall-min (u=1 → u=0.5) | Light 20 min | Typical 60 min | Heavy 150 min | Margin with text AI @15% / @30% (typical; heavy), u=0.5 |
|---|---|---|---|---|---|---|---|---|
| (a) MuseTalk+LiveTalking, 4090 RunPod Community $0.34 | 2 | $0.0028 | $0.17 | $0.0014 → **$0.0028** | $0.03–0.06 | **$0.09–0.17** | $0.21–0.43 | 97.0/96.3%; 83.3/79.7% |
| (a) same, 4090 RunPod Secure $0.89 | 2 | $0.0074 | $0.445 | $0.0037 → **$0.0074** | $0.07–0.15 | **$0.22–0.45** | $0.56–1.11 | 95.3/94.3%; 79.1/74.7% |
| (a) same, 4090 RunPod Serverless $1.34 | 2 | $0.0112 | $0.67 | $0.0056 → $0.0112 | $0.11–0.22 | $0.34–0.67 | $0.84–1.68 | 94.0/92.7%; 75.7/70.5% |
| (a) same, L4 AWS g6 $0.805 | 1 | $0.0134 | $0.805 | $0.0067 → $0.0134 | $0.13–0.27 | $0.40–0.80 | $1.01–2.01 | 93.1/91.7%; 73.7/68.1% |
| (b) FlashHead Lite+Mynah, 4090 Secure, 1 stream (measured) | 1 | $0.0148 | $0.89 | $0.0074 → $0.0148 | $0.15–0.30 | $0.45–0.89 | $1.11–2.23 | 92.6/91.0%; 72.4/66.5% |
| (b) same, 3 streams (Soul's claim) | 3 | $0.0049 | $0.30 | $0.0025 → $0.0049 | $0.05–0.10 | $0.15–0.30 | $0.37–0.74 | 96.2/95.4%; 81.4/77.4% |
| (b) FlashHead Lite+**OAC** (GPU busy while idle), 4090 Secure | 1 | $0.0148 | $0.89 | $0.0148 → $0.0297 | $0.30–0.59 | $0.89–1.78 | $2.23–4.45 | 87.2/84.5%; 58.9/50.1% |
| (c) FlashHead Pro, 2× 5090 Vast median $1.35 | 1 | $0.0225 | $1.35 | $0.0113 → $0.0225 | $0.23–0.45 | $0.68–1.35 | $1.69–3.38 | 89.8/87.7%; 65.4/58.0% |
| (c) FlashHead Pro, H100 SXM RunPod Community $2.69 [est 1 stream] | 1 | $0.0448 | $2.69 | $0.0224 → $0.0448 | $0.45–0.90 | $1.34–2.69 | $3.36–6.72 | 81.7/77.8%; 45.1/33.3% |

Worked example, row 1: $0.34 ÷ 60 ÷ 2 = $0.00283 per speaking stream-minute. × d 0.5 ÷ u 0.5 = $0.00283 per wall
minute. × 60 min = $0.17. Total with text AI: $0.17 + $0.326 = $0.50. Margin @15% = (16.48 − 0.50) ÷ 16.48 = 97.0%.

These figures exclude the **fixed always-on floor** (section 4.3): one warm 4090 is $248/month (Community) or
$650/month (Secure), whether or not anyone uses it.

### 3.3 Hosted candidates (list price, 2026-11-24)

| Vendor / plan [src] | $/wall-min | $/h | Light 20 | Typical 60 | Heavy 150 | Margin @15% / @30%: typical; heavy | Plan concurrency cap [src] |
|---|---|---|---|---|---|---|---|
| **bitHuman** cloud (4 credits/min, $1 per 100 credits) | $0.04 | $2.40 | $0.80 | $2.40 | $6.00 | 83.5/79.9%; 49.5/38.7% | Creator ($20) 3, Pro ($99) 10, Business ($299) 50, Enterprise ($999) 200 |
| **bitHuman** on-device (2 credits/min, speaking seconds only; × d 0.5) | $0.01 | $0.60 | $0.20 | $0.60 | $1.50 | 94.4/93.2%; 76.8/71.8% | No cap on self-hosted sessions (Creator+). **Native Swift SDK on iPhone 16 Pro+**, so under AGENTS.md it is not allowed in the v1 Flutter app (section 7) |
| **Simli** Hobby / Scale | $0.010 / $0.009 | $0.60 / $0.54 | $0.20 | $0.60 / $0.54 | $1.50 / $1.35 | 94.4–94.7/93.2–93.6%; 76.8–77.7/71.8–72.9% | Hobby ($10) 2, Pro ($49) 10, Scale ($249) 50, Enterprise "far higher". Enterprise rate "as low as $0.005" |
| **Anam** Starter / Pro / enterprise floor | $0.16 / $0.11 / from $0.04 | $9.60 / $6.60 / $2.40 | $3.20 / $2.20 / $0.80 | $9.60 / $6.60 / $2.40 | $24.00 / $16.50 / $6.00 | Pro: 58.0/49.0%; **−14/−39%** | Starter 1, Explorer 3, Growth 5, Pro ($999) 10, Enterprise 100+. Per-second billing |
| **HeyGen LiveAvatar** LITE (1 credit/min) Essential overage / Business included | $0.095 / $0.079 | $5.70 / $4.75 | $1.90 / $1.58 | $5.70 / $4.75 | $14.25 / $11.88 | Business: 69.2/62.6%; 13.8/**−4.6%** | Not stated; contact support for volume |
| **HeyGen LiveAvatar** FULL (2 credits/min), Essential overage | $0.19 | $11.40 | $3.80 | $11.40 | $28.50 | 28.9/13.6%; **−87/−127%** | as above |
| **Tavus** CVI Builder / Business | $0.35 / $0.26 (30 s minimum per conversation) | $21.00 / $15.60 | $7.00 / $5.20 | $21.00 / $15.60 | $52.50 / $39.00 | Business: 3.4/**−17%**; **−151/−205%** | Builder 3, Growth 10, Business 15 |

Sources (fetched 2026-11-24): https://www.bithuman.ai/pricing , https://www.simli.com/pricing , https://anam.ai/pricing ,
https://docs.liveavatar.com/docs/faq/credits , https://www.tavus.io/pricing (that page carries two conflicting price
sets; the newer "Pricing Built to Scale" set is used).

**Price changes since alternatives.md.** The LiveAvatar credits page now lists Essential at $99 for 1,110 credits and
Business at $475 for 6,010, which gives LITE $0.08–0.095/min. Alternatives.md derived ~$0.13 from a $19 Starter plan.
The "$0.01/min enterprise" figure is still contact-sales only.

**Plan fees matter at small scale.** For example, Anam Pro at $999/month includes 8,000 minutes and allows only 10
concurrent sessions. 100 or more simultaneous sessions require an enterprise contract at every vendor except bitHuman
Enterprise (200 cloud sessions).

### 3.4 Floor: pre-rendered clips only, no live video (e)

- **One-off render cost** [calc]: 4 coaches × 30 clips × 10 s = 1,200 s of video = 30,000 frames.
  - FlashHead Pro at 10.8 fps on a 4090: 30,000 ÷ 10.8 = 46 min, × $0.34/h = **$0.26**. On Secure Cloud: $0.69.
  - A 14B offline model such as LongCat-Video-Avatar 1.6 (MIT) at an assumed 50–100× slower [est] would take about
    40–80 GPU-hours, or **$14–70** on a 4090 or A100 at marketplace rates.
- **Hosting** [est]: 1,200 s at 2 Mbps is about 300 MB. That fits the Cloudflare R2 free tier (10 GB, zero egress) and
  costs $0 per subscriber.
- **Margin**: text AI only, which is the cost model's 82.9–99.5%.
- **Limit**: the mouth does not follow the live LLM answer. Clips can only do idle, listening, nods, reactions and
  fixed greetings. While the coach speaks, the app shows a loop with closed or neutral lips, or the existing Ditto or
  still portrait.

---

## 4. Capacity for 10, 100 and 1,000 simultaneous customers

### 4.1 Assumptions

- "Simultaneous" means concurrent avatar sessions at the daily peak.
- **Peak-to-average ratio (PAR) = 3** [est]. Consumer evening use is concentrated. Spain (UTC+1) peaks 6–9 h before
  the Americas (UTC−5 to −8), which flattens the global curve, so 3 is between a single-time-zone curve (4–5) and a
  flat one (1.5–2). At very small scale, Poisson bursts make the effective PAR higher.
- **Subscribers that a given peak implies**: subscribers = S × 43,200 ÷ (minutes per month × PAR), where 43,200 is the
  minutes in a 30-day month. For typical use (60 min): S × 240. So 10 simultaneous ≈ **2,400** typical subscribers,
  100 ≈ **24,000** and 1,000 ≈ **240,000**. For light use multiply by 3; for heavy use by 0.4.
- **Hybrid speaking slots needed**: the 99.5th percentile of Binomial(S, d = 0.5). Sessions start speaking
  independently, so at most 0.5% of instants have more speakers than slots. That gives **9 slots for 10 sessions
  (−10%), 63 for 100 (−37%), 541 for 1,000 (−46%)**.
- **GPUs at peak** = ceil(slots ÷ streams per GPU) + spare, where spare = max(1, 10%).
- **Fixed** = peak GPUs × $/h × 730 h. This is provisioning for peak, 24/7.
- **Autoscaled** = average GPUs × $/h × 730, with average GPUs = max(floor, peak ÷ PAR × 1.2). The 1.2 is a warm buffer;
  the floor is 1 GPU, or 2 at 100+ sessions.

### 4.2 Results (monthly cost; $ per typical subscriber = monthly cost ÷ subscribers implied above)

| Candidate | S = 10: GPUs at peak / fixed / autoscaled | S = 100 | S = 1,000 | $/typical subscriber (fixed → autoscaled), S = 1,000 |
|---|---|---|---|---|
| (a) MuseTalk, 4090 Community $0.34 | 6 / $1,489 / $596 | 36 / $8,935 / $3,574 | 299 / $74,212 / $29,685 | $0.31 → **$0.12** |
| (a) MuseTalk, 4090 Secure $0.89 | 6 / $3,898 / $1,559 | 36 / $23,389 / $9,356 | 299 / $194,260 / $77,704 | $0.81 → **$0.32** |
| (a) MuseTalk, 4090 Serverless $1.34 | 6 / $5,869 / $2,348 | 36 / $35,215 / $14,086 | 299 / $292,482 / $116,993 | $1.22 → $0.49 |
| (b) FlashHead Lite+Mynah, 4090 Secure, 1 stream | 10 / $6,497 / $2,599 | 70 / $45,479 / $18,192 | 596 / $387,221 / $154,888 | $1.61 → $0.65 |
| (b) FlashHead Lite+OAC (no hybrid) | 11 / $7,147 / $2,859 | 110 / $71,467 / $28,587 | 1,100 / $714,670 / $285,868 | $2.98 → $1.19 |
| (c) FlashHead Pro, 2× 5090 $1.35 | 10 boxes / $9,855 / $3,942 | 70 / $68,985 / $27,594 | 596 / $587,358 / $234,943 | $2.45 → $0.98 |
| Simli Scale $0.009 (minutes = S ÷ PAR × 43,200) | 144,000 min: $1,296 | 1.44 M min: $12,960 | 14.4 M min: $129,600 | $0.54 (enterprise $0.005 → $0.30) |
| bitHuman cloud $0.04 | $5,760 | $57,600 | $576,000 | $2.40 |
| Anam Pro $0.11 | $15,840 | $158,400 | $1,584,000 | $6.60 |
| LiveAvatar LITE $0.079 | $11,405 | $114,048 | $1,140,480 | $4.75 |
| Tavus Business $0.26 | $37,440 | $374,400 | $3,744,000 | $15.60 |

All self-hosted options cost a small fraction of revenue at every scale: at S = 1,000, 240,000 typical subscribers
bring in $3.26–3.96 M a month. The choice between them turns on quality and operational risk, not cost. The hosted
premium vendors cost 30–115% of net revenue at typical use.

### 4.3 Small scale (the realistic first year)

- **One warm GPU floor**: 4090 Community $0.34 × 730 = **$248/month**. Secure: $650. RunPod Serverless active worker:
  $1.34 × 730 = $978. Modal L4: $0.80 × 730 = $584. AWS g6: $588.
- **Capacity of one 4090 (2 speaking slots)**: about 2 simultaneous sessions with no risk. With 3 sessions, the chance
  that all 3 speak at once is 12.5% at d = 0.5 [calc], which is too high without a fallback. So **~2 sessions ≈ 480
  typical subscribers** (2 × 240). This is why the hybrid saving is negligible at small scale.
- **Break-even against Simli at $0.01/min** [calc] = floor ÷ ($0.01 × minutes): 414 typical subscribers on Community
  ($248), 1,083 on Secure ($650). For heavy users: 165 / 433.
- **Below about 400–1,000 subscribers, Simli (or bitHuman cloud) costs less than keeping a GPU warm.** Above that,
  self-hosting is cheaper per minute, provided its quality passes.

### 4.4 Cold start

| Path | Cold start | Source |
|---|---|---|
| Modal container | "boot in about one second", plus your imports and model load. `scaledown_window` defaults to 60 s (range 2 s – 20 min); `min_containers` and `buffer_containers` keep warm capacity | https://modal.com/docs/guide/cold-start [src] |
| Modal GPU memory snapshot (alpha/experimental) | Parakeet ~20 s → ~2 s (2025-07-30); Ministral 3B median ~118 s → ~12 s (2025-12-02). The docs say "3–10× faster" for init-heavy functions, and warn it may not help when weight loading dominates | https://modal.com/blog/gpu-mem-snapshots , https://modal.com/blog/mistral-3 [src] |
| Modal WebRTC example (A100) | Cached cold start "about 15–20 seconds"; first run several minutes (model download, TensorRT build) | https://modal.com/docs/examples/webrtc_yolo [src] |
| RunPod Serverless | Billed from worker start, including cold start (mostly model loading). FlashBoot and model caching "reduce" cold start, but the docs give no figure | https://docs.runpod.io/serverless/pricing [src] |
| MuseTalk + LiveTalking worker | Load the UNet, VAE, whisper-tiny and face models (a few GB), plus each coach's precomputed avatar latents: **~20–60 s** [est] | est |

**Conclusion: cold start is far too long to start a GPU when a user opens the app.** Users expect a reply in under 1–2 s.
Keep at least one warm GPU (or `min_containers=1`) during service hours. Scale up ahead of the evening peak (scheduled
plus queue-based), not on demand. While capacity is coming up, show the voice-plus-loop fallback (section 8).

---

## 5. Shared GPU processing, batching, MPS/MIG, autoscaling, queueing

### 5.1 Speaking duty cycle

- The brief puts the coach's talk time at 40–60% of wall time.
- AI_COST_MODEL.md assumes ~10 s of user speech and ~20 s of reply per turn. Adding ~1–2 s of LLM and TTS latency gives
  20 ÷ 32 ≈ **62%**.
- I use **d = 0.5** as the base case.

| d | Marginal GPU saving (1 − d) | Provisioned saving, S = 10 / 100 / 1,000 (99.5th percentile) [calc] |
|---|---|---|
| 0.40 | 60% | 20% / 47% / 56% |
| 0.50 | 50% | 10% / 37% / 46% |
| 0.60 | 40% | 0% / 28% / 36% |
| 0.67 | 33% | 0% / 21% / 29% |

The marginal saving appears in per-second billing and in u (section 3). Provisioned capacity saves less, because GPUs
must cover the moments when many sessions speak together.

### 5.2 Batching multiple streams per GPU

| Model | Batched inference? | Evidence |
|---|---|---|
| MuseTalk 1.5 | **Frames within one stream only**: `--batch_size` default 20 (`scripts/realtime_inference.py` l.331, UNet run "batch by batch" l.257–277) [src, repo]. No cross-session batching documented | In LiveTalking, each session runs its own inference loop on a shared GPU (time-slicing). 72 fps on a 4090 ≈ 2 streams |
| LiveTalking | "Supports multi-concurrency"; the GPU limits speaking sessions, the CPU limits idle ones (README §6). No `max_session` figure | [src] |
| FlashHead Lite | Soul README claims "3-concurrent real-time" on a 4090; the mechanism is not described. OAC ships `concurrent_limit: 1`; in Mynah one worker = one session | [src]. Conflict, needs a test |
| FlashHead Pro | Sequence-parallel across 2 GPUs (xfuser); no batching | [src] |
| Hosted vendors | Opaque; bills per minute | — |

Cross-stream batching could raise MuseTalk throughput meaningfully. The UNet is small, and VAE decode at 256² batches
well. Building it, however, means writing a scheduler that collects frames from N sessions every 40 ms. That is new
code, so it is last in the reuse order. Measure the gain with the test first.

### 5.3 MPS and MIG

- **CUDA MPS** runs on any Volta-or-newer GPU, including 4090, L4, L40S and A10G. It lets 2–3 worker processes (one
  per session, as in Mynah) share the GPU concurrently without context-switch overhead. That is useful exactly for
  "2 × MuseTalk on a 24 GB card" (Mynah's "Pool" profile, 17–20 GB). Memory isolation is limited, so one crashing
  process can affect the others. [general NVIDIA documentation; not re-fetched]
- **MIG** exists only on datacenter GPUs (A100, H100/H200, A30), not on the 4090, L4, L40S or A10G. An A100 80 GB
  splits into up to 7 × 1g.10gb slices, each with ~1/7 of the compute. That is roughly 10 fps of MuseTalk per slice
  [est], below real time. 2–3 slices per stream would be needed, so MIG gives isolation but no cheaper streams. The
  A100 at $1.19–2.74/h with ~2–3 streams [est] still loses to a 4090 at $0.34–0.89 with 2 streams.

### 5.4 Autoscaling options

| Option | Fit for long-lived WebRTC sessions | Cost model | Notes |
|---|---|---|---|
| **RunPod Pods + own router** | Good. A thin router assigns `/offer` to a worker with a free slot (Mynah: "a thin router in front of `/offer` … is straightforward") | Per-second Pod billing; scale by API | Cheapest ($0.34–0.89 for a 4090). You run the scaler yourself |
| **RunPod Serverless** | Weak. It is a job/queue model; a 10–30 min WebRTC session is a single very long job. Flex workers stop 5 s after the last job | $1.34/h for a 4090, about 1.5–4× Pod prices | Good for the offline clip renders |
| **Modal** | Workable. It has a WebRTC example with `POST /offer`, plus `min_containers`, `buffer_containers` and snapshots. No 4090: L4 $0.80, L40S $1.95 | Per second | **$30/month free credits** on Starter = ~37 L4-hours. That is a $0-cash test path, but it needs a new account (owner approval) |
| **KServe (Knative)** | Scale-to-zero, request-concurrency autoscaling; needs your own Kubernetes plus GPU nodes, and node scale-up takes minutes | Infrastructure only | Overkill below hundreds of GPUs |
| **Ray Serve** | Fractional GPUs (`num_gpus: 0.5` packs 2 replicas per GPU) and replica autoscaling; stateful WebRTC needs a custom ingress | Infrastructure only | Good fit if the fleet grows past ~20 GPUs |

### 5.5 Queueing

- With hybrid sizing at the 99.5th percentile, about 0.5% of speaking-turn starts find no free slot.
- Waiting does not help: a turn lasts 10–20 s, so a queued turn would be late. On overflow, play the coach's audio over
  the idle or "talking" loop (voice-only mode) for that turn. Never block the reply.
- Count overflows. If they exceed ~1% of turns, add a GPU.

---

## 6. Hybrid design: prerecorded loops + live speaking

### 6.1 Design

- **Idle, listening and reactions.** Per coach, pre-render 10–20 s of idle and listening loops (breathing, blinks,
  small nods) and short reaction clips (smile, concern, laugh, thinking, encouraging nod). Select them from the coach
  LLM's sentiment tag or a cheap classifier.
  - Mynah already ships this as its "instinct" layer: gesture clips such as shy, laugh and wink, chosen while the LLM
    composes. Mynah's idle "costs no GPU: silence is a baked loop replayed by cored" [src].
  - LiveTalking plays the avatar's source-video loop while silent [src].
- **Speaking.** The GPU renders only while TTS audio plays.
  - MuseTalk inpaints just the mouth over the *same* loop frames, so the head, eyes and blinks continue unchanged.
  - FlashHead generates the whole head, so its frames must be blended into and out of the loop.

### 6.2 Seams and how products handle them

| Risk | Where it bites | Mitigation |
|---|---|---|
| Pose and lighting jump at the loop ↔ live switch | FlashHead (whole head generated) switching to or from a LivePortrait or Ditto loop | Start live generation from the loop frame currently shown (use it as the condition image). End on a neutral key pose. Crossfade 3–6 frames (120–240 ms). Insert an "inhale / start-talking" micro-clip that also hides the 0.4–1.1 s render latency |
| Mouth state discontinuity | MuseTalk at speech start and end (inpainted open mouth ↔ loop's closed mouth) | Fade the inpaint mask in and out over 2–4 frames. Pad TTS audio with ~100 ms of silence so the model closes the mouth itself |
| Jaw and chin seam, lip colour drift | MuseTalk (README admits identity drift; issues #389 jitter, #335 blur) | The loop source must be mouth-closed with a low-motion head. Smooth the bounding box (`extra_margin`). Optionally run GFPGAN on the mouth crop (check its licence) |
| Visible loop repetition | All loop designs | Ping-pong (mirror) loops. Several loops with random entry points. Reaction clips interleaved |
| Reaction clip does not return to rest | Sentiment clips | Author every clip to start and end on the same neutral frame |
| Audio/video desync while streaming | FlashHead (issue #83); LiveTalking fixed an 80 ms lip lag (Aug 2026) | Measure in the test. A/V sync tolerance is about ±45 ms (ITU-R BT.1359) |

How products differ:
- **Rendered all the time**: Tavus, Anam, HeyGen and OAC render idle frames live. That is why they bill per connected
  minute and why their listening behaviour looks continuous; Tavus Raven adds perception.
- **Loop plus live**: Mynah and LiveTalking.
- **bitHuman on-device**: bills only speaking seconds, so its idle is local animation.
- **Gemini Live Avatar**: reportedly idle is free (third-party source in alternatives.md).

### 6.3 Licence trap in the loop pre-render

The recommended loop source (models.md) is **Ditto**. Ditto's code is Apache-2.0, but its TensorRT bundle lists
`insightface_det.onnx`, and InsightFace models are non-commercial (alternatives.md). Mynah's LivePortrait bake pins
`insightface==1.0.1`, bypassed with `--no-flag_do_crop`. Before rendering commercial loops:
- confirm no InsightFace model is executed (swap in MediaPipe, Apache-2.0); or
- render the loops with a clean model, such as LongCat-Video-Avatar 1.6 (MIT) or FlashHead Pro (Apache code, weights
  need a written grant).

---

## 7. Comparison table

TTFF is the time to first frame after the user's turn ends. Self-hosted figures come from the frameworks' own
measurements on an RTX 4090; hosted ones are vendor claims or vendor-run benchmarks. Add DateWise's own pipeline on
top: Workers AI LLM time to first token ~0.3–0.8 s [est], and TTS first chunk ~0.2–0.5 s for Kokoro or Chatterbox [est].

| Option | TTFF / latency | Visual quality (published, not our test) | Voice (Chatterbox, Kokoro or hosted TTS) | iPhone: decode, battery, bandwidth | Commercial licence status | $/typical subscriber (60 min) |
|---|---|---|---|---|---|---|
| **(a) MuseTalk 1.5 + LiveTalking + loop** | Mynah measured 0.40–0.72 s turn end → first lip-synced audio (MuseTalk 512); engine compute 0.24–0.48 s | 256 px mouth inpaint, soft teeth, jitter reported; head and eyes from the loop (as good as the loop) | Any audio we feed it (whisper-tiny features, language-agnostic) | WebRTC H.264, hardware decode (VideoToolbox via flutter_webrtc). 512 px ≈ 0.5–1 Mbps ≈ 4–7.5 MB/min [est]; 720 p ≈ 1.5–2.5 Mbps ≈ 11–19 MB/min [est]. Battery like a receive-only video call [est] | Code MIT/Apache. Weights MIT, **but trained on HDTF** ("talk to HDTF owner about commercialization") and the face-parse weights come from CelebAMask-HQ (non-commercial dataset). Avoid wav2lip256 | **$0.17–0.45** (+ $248–650/month floor) |
| (b) FlashHead Lite (Mynah) | 0.86–1.15 s (Mynah measured, half-body) | Single-portrait head motion; Sync-C 4.21 (vs Ditto 3.57); **blurry or vanishing teeth** (#21) | Any audio (wav2vec2 English-pretrained; Spanish untested) | Same; 720×1280 half-body ≈ 2 Mbps [est] | Weights `license: other`, informal "of course you can"; LTX VAE terms (free under $10 M revenue if ≥0.9.6). **Needs a written grant** | $0.45–0.89 (1 stream) / $0.15–0.30 (3) |
| (c) FlashHead Pro | Not published for streaming; ≥1–2 s [est, 33-frame chunks] | Best open lip sync measured here (Sync-C 5.73); 512² | Any audio | Same | Apache code + Wan VAE; weights as above | $0.68–1.35 (if real time is achieved at all) |
| bitHuman cloud / on-device | 25 fps on device (vendor) | Essence 2 photoreal from one portrait (vendor) | BYO audio (LiveKit plugin) | Cloud: WebRTC as above. On-device: no video bandwidth, but the iPhone GPU renders (higher battery use [est]), **iPhone 16 Pro+ only**, native Swift SDK (not allowed in the v1 Flutter app under AGENTS.md) | Commercial ToS; likeness and training terms not stated | $2.40 cloud / $0.60 device |
| Simli | Not published | Mouth region on a mostly static face (alternatives.md) | BYO audio | WebRTC (LiveKit/Pipecat) | Commercial ToS; ZDR enterprise only | $0.54–0.60 |
| Anam Cara-4.1 | 1.24 s reply, ~150 ms server render (vendor study) | Leads vendor-run comparisons | 70+ languages; BYO via LiveKit | WebRTC | Commercial ToS; ZDR enterprise only | $6.60–9.60 (enterprise ≥ $2.40) |
| HeyGen LiveAvatar LITE | Median ~4.7 s TTFF (Anam's benchmark); <300 ms claimed by HeyGen | HeyGen photo avatar | LITE = bring your own STT/LLM/TTS | WebRTC | Commercial ToS; LITE keeps no session data | $4.75–5.70 |
| Tavus Phoenix-4.5 | 134 ms audio-to-video (third party) | Highest perception/listening (Raven); 1080p 40 fps | 42+ languages | WebRTC (Daily) | Commercial ToS | $15.60–21.00 |
| (e) Clips only | 0 s (local playback) | As good as the offline render; no live lip sync | On-device Apple voice (today) or any TTS | Local MP4 loops, ~300 MB library downloaded once [est], minimal battery | Depends on the render model (section 6.3) | **$0** |

---

## 8. Recommendation and guardrails

### 8.1 Path

1. **v1: clips plus voice (the floor).** Ship pre-rendered idle, listening and reaction loops plus the existing voice.
   This costs $0 per subscriber, needs no GPU fleet, and is consistent with AGENTS.md (no new native feature).
   The loops play in shared app code.
2. **Run the paid GPU test** (section 9) once the owner approves.
   - It replaces every [est] here: streams per 4090 for MuseTalk and FlashHead Lite, TTFF, seam quality, iPhone data
     use.
   - It also gives a side-by-side quality check against Ditto (currently scored 4/10).
3. **Live speaking, below ~1,000 subscribers: hosted.** Use **Simli** ($0.009–0.01/min) or **bitHuman cloud** ($0.04)
   via LiveKit, after a quality check of each with our own portraits. That needs accounts, so owner approval comes first.
   No GPU floor is needed.
4. **Live speaking, above ~1,000 subscribers: self-hosted.** Move to MuseTalk + LiveTalking over a clean idle loop on
   RunPod 4090 Pods, with an own router and at least 2 warm GPUs. That is about $0.12–0.32 per typical subscriber at
   S = 1,000, autoscaled. Do this only if the test shows acceptable quality, and only after the HDTF and face-parse
   licence questions are cleared.
5. **Do not use Anam, HeyGen FULL or Tavus at list price** for an all-you-can-talk subscription.
   - They are viable only as a capped premium feature (≤ 15–40 min/month) or at enterprise rates. Anam from $0.04
     would mean ≤ 94–115 min.
   - **Use FlashHead Pro only for offline clip rendering** until it runs in real time on one GPU.

### 8.2 Guardrails (every option)

| Guardrail | Value | Why [calc] |
|---|---|---|
| Included avatar minutes per month | **120 min** (soft notice at 100) | Heavy-text subscriber + 120 Simli min = $2.32 + $1.20 = $3.52 < $4.07 (70% margin at 30%) |
| Hard avatar cap per month | **300 min** (self-hosted or Simli); **30 min** if the vendor is Anam, LiveAvatar or Tavus | 300 × $0.0074 (MuseTalk Secure, u = 0.5) = $2.22; 300 × $0.01 (Simli) = $3.00 |
| Per-day / per-session caps | 30 min a day; 20 min per session, with an idle disconnect after 60 s of silence | Stops a forgotten open session from billing (hosted vendors bill idle time) |
| Fallback 1 | Voice + idle/listening loop (clips) | $0. Used when the cap is reached, on overflow (no free slot), during cold start, or when the network is under ~0.5 Mbps |
| Fallback 2 | Voice + still portrait | $0. Used for low battery, Low Power Mode or cellular data saver |
| Global budget breaker | Mirror chat-v7's `DAILY_NEURON_BUDGET`: a `DAILY_AVATAR_MINUTES` / GPU-hour budget in the Worker; past it, everyone gets fallback 1 | Same pattern as AI_COST_MODEL.md §7 |
| Counting | Count connected avatar minutes server-side, keyed by the same hashed `originalTransactionId` | Reuses the existing guard. No new identity system |
| Spot/interruptible | Never for live sessions | A preempted host drops calls mid-sentence |

---

## 9. Small paid GPU test (needs owner approval; not run)

### 9.1 What it would prove

1. Real speaking streams per GPU for MuseTalk + LiveTalking and FlashHead Lite (1 vs 3 per 4090).
2. TTFF, end to end, with our TTS.
3. m/b/p lip closure in English and Mexican Spanish versus Ditto.
4. Loop ↔ live seam quality.
5. iPhone WebRTC data use (MB/min) and battery over cellular with TURN.

### 9.2 Plan (RunPod RTX 4090; Secure Cloud prices for safety, Community in brackets)

| Step | Hours | Price | Cost |
|---|---|---|---|
| Set up LiveTalking + MuseTalk 1.5; build 4 coach avatars from pre-rendered idle loops (made beforehand on the CPU or Ditto) | 1.5 | $0.89 ($0.34) | $1.34 ($0.51) |
| Load test: 1, 2, 3, 4 concurrent speaking streams; log `inferfps`/`finalfps`, VRAM, CPU encode load; TTFF over 50 turns | 1.5 | $0.89 | $1.34 ($0.51) |
| FlashHead Lite via Mynah on the same pod: 1 vs 2 vs 3 streams; TTFF; seams against its baked loop | 1.5 | $0.89 | $1.34 ($0.51) |
| iPhone test over Wi-Fi and cellular with TURN: MB/min at 512 px and 720p, battery drain over 20 min | 1.0 | $0.89 | $0.89 ($0.34) |
| Buffer (debugging, downloads) | 1.5 | $0.89 | $1.34 ($0.51) |
| **Subtotal, 4090** | **7.0** | | **$6.23 ($2.38)** |
| Optional: FlashHead Pro on 2× RTX 5090 (Vast median, on-demand), fps check only | 2.0 | $1.35 | $2.70 |
| Storage: 100 GB volume for ~1 day ($0.10/GB-month ÷ 30) | | | $0.33 |
| **Total** | | | **$6.56 without Pro, $9.26 with Pro** (Community: $2.71 / $5.41) |

Notes:
- Set a hard cap of $25. RunPod's default account spend limit is $80/hour (docs), so set a lower one.
- A minimum credit top-up may apply on RunPod or Vast; check before buying.
- Alternative with $0 cash: Modal Starter's $30/month free credits cover ~37 L4-hours or ~15 L40S-hours. There is no
  4090, so it would measure the L4 path (about 1 MuseTalk stream). It still needs a new account, which needs owner
  approval.
- Use test audio and non-sensitive or approved coach portraits only. Community-cloud hosts are third-party machines.

### 9.3 Decision rule after the test

- If MuseTalk sustains **≥2 streams at ≥25 fps** on a 4090, TTFF is ≤1.0 s, and the owner rates lip closure above
  Ditto, the self-hosted numbers here stand.
- If it holds only 1 stream, double every self-hosted MuseTalk cost. Typical then becomes $0.34–0.90 per subscriber,
  which is still viable.
- If quality fails, go hosted (Simli or bitHuman) behind the same caps.
