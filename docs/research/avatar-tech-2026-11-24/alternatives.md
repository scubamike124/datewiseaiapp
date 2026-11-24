# DateWise AI: newer real-time avatar alternatives (open and hosted)

Research date: 2026-11-24. Scope: alternatives to mynah, vivora, OpenAvatarChat, LiveTalking, MuseTalk, SoulX-FlashHead and Ditto. Those are covered by other researchers. Ditto is in use and was reviewed at 4/10.
Constraints applied: $0 now, no new accounts, commercial licence required for code, weights and dependencies, iPhone/Flutter client, Cloudflare Worker backend, EN + MX-ES, $19.99/month subscription, heavy user about 100 avatar minutes/month.

Method: vendor pricing pages fetched today, Hugging Face API (licence tags, Space runtime and hardware), GitHub raw LICENSE/README/requirements files, arXiv, and web search. Nothing here was run on a GPU or tested live. Every quality statement comes from a vendor or a paper, not from our own test. Vendor prices change often and some pages contradict themselves. Those conflicts are flagged below.

---

## 1. Key findings

1. **No open model gives premium, diffusion-grade realism in real time on hardware we could afford.** The best commercially licensed open real-time models (Alibaba-Quark **Live Avatar**, Apache-2.0; **SoulX-FlashTalk-14B**, Apache-2.0) need **5 x H800 GPUs** (Live Avatar) or **8 x H800 GPUs** (FlashTalk) for real-time speed. That is roughly one 5–8 GPU node per concurrent user, so it cannot work at $19.99/month.
2. **The open models that can run on a single GPU** (AVTR-1, Avatar Forcing, Ditto/FlashHead class) are motion-plus-warping models. Most of them depend on **InsightFace** detectors or landmark models, which are licensed for non-commercial use only, or carry custom licences.
3. **Cost per minute separates the hosted vendors more than realism does.** Assume Apple keeps 15–30% of $19.99, leaving about $14–17. At 100 minutes per heavy user, only about **$0.01–0.06/min** leaves margin. Vendors that fit: Simli ($0.009–0.01), bitHuman ($0.02 on-device, $0.04 cloud), Hedra Live (reported $0.05), and LiveAvatar at enterprise volume (claimed $0.01). Anam ($0.11–0.16), LiveAvatar retail (~$0.13 LITE), LemonSlice ($0.16–0.22), Runway (~$0.20), Tavus ($0.26–0.35) and Gemini Live Avatar (~$0.37–0.39) cost $11–39 per heavy user at list prices.
4. **The Flutter path is LiveKit.** LiveKit Agents has official avatar plugins for 16 vendors: Anam, Avatario, AvatarTalk, Beyond Presence, bitHuman, D-ID, Keyframe, LemonSlice, LiveAvatar, Protoface, Runway, Simli, Spatius, Synthesia, Tavus and TruGen. LiveKit has an official Flutter client SDK (`livekit_client`). In LiveKit Agents, interruption (barge-in) is handled by the agent's VAD and turn detection, which flushes the avatar's audio. Any of these vendors can therefore reach the existing Flutter app without a native-only feature. This is consistent with the AGENTS.md rule.
5. **A free demonstration with our own portrait is not possible today at any vendor without an account.** The one anonymous, quota-free path found is the **official Wan2.2-S2V Hugging Face Space**. It is offline video, not real-time, and it uploads the portrait to Alibaba DashScope. See section 5.

---

## 2. Open models (2025–2026)

Legend: Commercial = whether code, weights and dependencies together allow commercial use today.
Status of each Hugging Face Space checked 2026-11-24 via the HF API.

| Model (date) | Single photo? | Real-time? | GPU needs | Code licence | Weights licence | Problem dependencies | Commercial? | Maturity / notes |
|---|---|---|---|---|---|---|---|---|
| **Alibaba-Quark Live Avatar** (Dec 2025; v1.1 Jan 2026; ECCV'26) | Yes | **Yes, streaming, infinite length.** 20 FPS (paper v3) up to 45 FPS (README v1.1) | **5 x H800/80 GB** for real time. FP8 runs on 48 GB GPUs, but not in real time | Apache-2.0 | Apache-2.0 (LoRA on Wan2.2-S2V-14B, also Apache-2.0) | **`insightface` in requirements.txt** (must replace) | Yes, once InsightFace is swapped out | Research preview. Strongest open real-time quality. No public demo Space |
| **SoulX-FlashTalk-14B** (Soul AI Lab, Jan 2026) | Yes | Claimed "real-time infinite streaming" | **8 x H800** for real time, >64 GB single-GPU offline. A 4090 version is "coming soon" | Apache-2.0 | Apache-2.0 | Chinese wav2vec2 audio encoder (Spanish quality unknown) | Yes | Same lab as FlashHead (already under review). No demo yet |
| **AVTR-1** (Avaturn, 2026) | Yes (portrait) | **Yes.** 25 fps, 5-frame chunks, 84 ms/chunk on L40. Also listens: takes a separate listener audio track | Ampere+ GPU. Real-time on L40/A100/RTX 4060 Ti/3070; L4 below real-time | Renderer: Community License. **Streamer: PolyForm Noncommercial 1.0** | AVTR-1 Community License (commercial allowed under $10M revenue) | **The card says commercial use requires replacing InsightFace** (SCRFD + 2D106). LivePortrait-derived ONNX | **Not yet** (InsightFace + non-commercial streamer) | Closest open match to "listening + talking" on one GPU. Watch for the InsightFace-free release. ZeroGPU Space `shenxq/AVTR` running |
| **Avatar Forcing** (KAIST, Jan 2026, CVPR'26) | Yes | ~500 ms latency. Reacts to the user's audio and motion (nods, laughs) | Single GPU (paper) | **No LICENSE file found** | "follows original authors' terms" (mirror) | Unknown | **Unclear, treat as no** | Repo has minimal inference only. No real-time app included |
| **LongCat-Video-Avatar 1.6** (Meituan, Nov 2026; 1.5 Jun 2026) | Yes (`ai2v`) | **No.** Offline, multi-GPU examples, FP8/INT8 options | Hopper-class recommended | MIT | **MIT** | Whisper-Large audio (1.5+), so multilingual-friendly | **Yes** | Strongest permissively licensed offline model. Good for pre-rendered intro and idle clips. ZeroGPU Space `victor/LongCat-Video-Avatar-1.6` running |
| **EchoMimic V3** (Ant, 2025; weights Jan 2026) | Yes | No (1.3B, Wan-based, offline) | Single 24 GB+ | Apache-2.0 | Apache-2.0 | Check face-crop deps | Likely yes | Upgrade over V2. V2: Apache-2.0, uses MediaPipe (Apache) |
| **InfiniteTalk / MultiTalk** (MeiGen, 2025) | Yes (image-to-video and video dubbing) | No | Wan2.1-14B, 24–80 GB | Apache-2.0 (README) | Apache-2.0 | Chinese wav2vec2 | Yes | Very popular (182k downloads). Offline long-form |
| **OmniAvatar** (2025) | Yes | No | Wan 14B | No LICENSE file found in repo | Apache-2.0 (HF) | — | Probably (check code) | ZeroGPU Space running |
| **FantasyTalking** (AMAP, 2025) | Yes | No | Wan 14B | Apache-2.0 | Apache-2.0 | — | Yes | ZeroGPU Space running |
| **Wan2.2-S2V-14B** (Alibaba, Aug 2025) | Yes | No | 80 GB, or multi-GPU | Apache-2.0 | Apache-2.0 | — | Yes | Base of Live Avatar. **The official Space runs on CPU and calls DashScope, so it is anonymous** |
| **StableAvatar** (2025) | Yes | No | Wan2.1-1.3B | — | MIT | — | Likely | Space in RUNTIME_ERROR |
| **HunyuanVideo-Avatar** (Tencent, May 2025) | Yes | No | 24–80 GB | **Tencent Hunyuan Community Licence** | Same | — | **Restricted.** Not licensed in EU/UK/South Korea; MAU cap | Avoid |
| **Hallo3** (Fudan, 2025) | Yes | No | CogVideoX-5B, 80 GB | MIT | **CogVideoX-5B licence** (derivative) | **InsightFace** | **No/unclear** | Avoid |
| **Sonic** (Tencent/ZJU, 2025) | Yes | No | SVD-based | **CC BY-NC-SA 4.0** | (HF tag AFL-3.0 conflicts) | SVD licence | **No** | Avoid |
| **FLOAT** (DeepBrain, 2025) | Yes | Near real-time (flow matching) | Single GPU | **CC BY-NC-ND 4.0** | Same | face_alignment | **No** | Avoid |
| **KDTalker** (2025) | Yes | Near real-time (LivePortrait renderer) | Single GPU | No LICENSE found | MIT (HF) | dlib; LivePortrait (InsightFace models) | **Unclear** | ZeroGPU Space running |
| **JoyVASA** (JD, 2025) | Yes | Near real-time (LivePortrait renderer) | Single GPU | MIT | MIT | **insightface==0.7.3** | **No** until replaced | |
| **ARTalk** (2025) | Yes (3D Gaussian head) | **Yes**, real-time 3D | Single GPU | MIT | MIT | FLAME head model licence (check) | Check FLAME | Stylised, not photoreal enough for "premium" |
| **LatentSync 1.5 / 1.6** (ByteDance, 2025) | **No, needs a video** (lip re-sync) | No | 8–18 GB | Apache-2.0 | OpenRAIL++ (use-restricted, commercial OK) | **insightface==0.7.3**, MediaPipe | **No** until InsightFace removed | Dubbing tool, not an avatar generator. ZeroGPU Space running |
| **Teller** (2025, CVPR) | Yes | Claimed real-time (autoregressive) | — | **No public code/weights found** | — | — | No | Paper only |
| **INFP** (ByteDance, 2024/25), listening heads | Yes | Real-time claimed | — | **No weights released** | — | — | No | Paper only |
| Papers to watch (no usable release found): **Hallo-Live** (arXiv 2604.23632), **DynaForcing** (2608.17707), **Decoupled Self-Forcing** (2609.10317), Lip Forcing, EfficientSync | | real-time streaming | | | | | | Self-forcing distillation is how open models are reaching real-time on 1–2 GPUs. Re-check in 3–6 months |

**InsightFace warning.** Its pretrained detectors and recognisers (buffalo_l, SCRFD, 2d106) are licensed for non-commercial research only. They appear in Live Avatar, AVTR-1, LatentSync, JoyVASA and Hallo3, and in Ditto's TensorRT bundle (`insightface_det.onnx` is listed in the Ditto model card, even though Ditto's code is Apache-2.0). Replace them with MediaPipe (Apache-2.0) or another permissive detector before any commercial use.

**Self-hosting economics.** The 14B real-time models need 5–8 x H800 per concurrent stream, at very roughly $10–20/hour rented. That works out to $0.17–0.33 per streamed minute with no concurrency sharing, which costs more than Anam and needs a paid GPU account. The models that run on one GPU at 25 fps (AVTR-1 class, Ditto, FlashHead) can cost around $0.01–0.02/min on a rented L40/4090. Their realism, though, is the warping class we already score low.

---

## 3. Hosted real-time APIs

Prices are list prices from the vendor's own page, fetched 2026-11-24 unless noted. "Heavy user" means 100 minutes per month at the overage or effective rate.

| Vendor / model | Own portrait to avatar | Effective $/streamed min | Heavy user/mo | Free tier (all need an account) | Transport / SDKs | Latency (vendor claim) | Spanish | Data / training |
|---|---|---|---|---|---|---|---|---|
| **bitHuman** Essence 2 (photoreal) / Expression 2 | **Yes, one portrait.** Essence 2: 250 credits one-off, minutes to build | **$0.02 on-device/self-hosted** (speaking time only), **$0.04 cloud**, $0.10 all-inclusive voice | **$2–4** | Free: 99 credits/mo, 1 cloud session (not enough to build one Essence avatar). Creator $20/mo = 2,000 credits, includes SDKs | **iOS/Swift package (on-device, iPhone 16 Pro+ / M3+ Mac / M4 iPad)**, Android arm64, Python, WebGPU, LiveKit plugin | 25 FPS on-device | Audio-driven, so language-agnostic (needs a test) | 2025 press release: on-device means no data leaves the device. Cloud terms not stated |
| **Simli** (Trinity) | Yes, on Hobby+ (1 custom/mo Hobby, 5 Pro). Free = templates only | **$0.0095–0.01** ($0.005 enterprise) | **~$1** | Free: 50 min/mo, template faces | WebRTC, JS, Python, **LiveKit**, Pipecat | Low (not published on page) | Audio-driven | ZDR enterprise only. Training policy not on page |
| **Hedra Live Avatars** (with LiveKit, Jul 2025) | Yes (Hedra Character from image) | **~$0.05** (third-party report; Hedra's API page lists 2.5¢/s for batch) | ~$5 (unverified) | Hedra free credits | LiveKit | <100 ms (claim) | Audio-driven | Not checked |
| **HeyGen LiveAvatar** | **Yes, photo avatar** (FAQ) | FULL 2 credits/min, LITE 1 credit/min. Starter $19 = 150 credits gives **~$0.13/min LITE, ~$0.25 FULL**. "$0.01/min" enterprise tier announced 2026-08-25 (contact sales) | **$13 retail; ~$1 enterprise** | Free account plus test credits | Web SDK, API, **LiveKit plugin**. LITE = bring your own STT/LLM/TTS | Median TTFF ~4.7 s in Anam's benchmark; <300 ms claimed by HeyGen | Use LITE with your own Spanish TTS/ASR | **LITE: no session data retained.** FULL keeps transcripts |
| **Anam** Cara-4.1 Express | **Yes, image upload on every plan, including Free** | Starter $0.16, Explorer $0.14, Growth $0.12, Pro $0.11, enterprise from $0.04 | **$11–16** | **Free: 30 min/mo, 3-min sessions, image upload included** | JS SDK, API, **LiveKit plugin (Py/Node)** | 1.24 s reply, ~150 ms server render (own study) | 70+ languages | ZDR enterprise only |
| **Beyond Presence** (bey.dev) | Image-to-Avatar **Scale plan only (€349/mo)** | Speech-to-Video €0.0875–0.175, Agents €0.175–0.35 | €9–17.5 | Free: 2K credits (40 min S2V), stock avatars, 3-min sessions | API, **LiveKit plugin** | — | — | SOC 2 II, GDPR. ZDR enterprise |
| **LemonSlice** | Yes (paid plans) | $0.22 overage (Starter). "As low as $0.048" at volume. +$0.09 if hosted voice. Bills idle time | $16–22 | Free = chat with featured avatars only | API, **LiveKit plugin**, Agora | 471 ms model TTFB, 2.0 s end-to-end (own claim) | 70+ languages | ZDR enterprise |
| **Runway Characters** (GWM-1, Mar 2026) | **Yes, single reference image, no fine-tuning** | 2 credits per 6 s ≈ **$0.20/min** (at $0.01/credit) | ~$20 | Runway Dev account | API, **LiveKit plugin** | Not stated | Not stated | Not checked |
| **Tavus** CVI, Phoenix-4/4.5 | **Image-to-Replica (May 2026)**, one image. Video training still higher fidelity | Builder $0.35, Growth $0.31, Business $0.26 | **$26–35** | Free: 20 min, 16 stock faces only | Daily WebRTC, React, **LiveKit plugin** | 40 fps 1080p; 134 ms A2V (third party). Raven perception (emotion and listening) | 42+ languages | Not on page |
| **Google Gemini Live Avatar** (GA ~Sep 2026, secondary sources) | Custom avatar from one ≥704x1280 portrait, **allowlisted / sales-gated** | ~$0.37–0.39 per *speaking* minute (third-party estimate; idle free) | ~$20–39 | GCP credits (account) | Gemini Enterprise Agent Platform | — | Gemini voices multilingual | Google Cloud terms |
| **D-ID** Agents / V4 Expressive | Yes (photo) | ~$0.35–0.70 streaming (derived from plan allowances) | $35–70 | Trial ~10 streaming min | WebRTC, JS SDK, **LiveKit plugin** | — | Yes | Not checked |
| **Akool** Live Avatar | Yes | 1–1.2 credits per 10 s; $/credit not published. API needs Pro Max ($41/seat/mo) | Unclear | 5-min watermarked 720p free session | API | — | — | Not checked |
| Character.ai AvatarFX / TalkingMachines | n/a | Consumer feature, **no public API** | — | — | — | — | — | Not usable |

**What a trial would require.** Every vendor above needs an account, meaning email sign-up and sometimes a payment card. Uploading our own portraits needs Hobby+ at Simli, Creator+ at bitHuman (250 credits per Essence build exceeds the free 99), Scale at Beyond Presence, and a paid plan at LemonSlice. **Anam is the only one whose Free plan includes image upload** (30 min/mo). LiveAvatar gives free test credits. Before uploading coach portraits, read each vendor's terms on rights to uploaded likeness and on training. None of the pricing pages states a training opt-out. Zero data retention is enterprise-only at Simli, Anam, LemonSlice and Beyond Presence.

---

## 4. Ranking for DateWise

Criteria: premium realism from one portrait, EN + MX-ES lip sync, listening/idle behaviour, a Flutter path (LiveKit), commercial terms, and heavy-user cost well under ~$14.

| Rank | Option | Why | Main risk | Heavy-user cost |
|---|---|---|---|---|
| **1** | **bitHuman Essence 2** (on-device iOS SDK, cloud fallback) | Builds a photoreal avatar from one portrait. Renders **on the iPhone**, so no streaming GPU and no video bandwidth, and works with any Spanish TTS. LiveKit plugin for older phones. Lowest cost of any credible option | Realism is likely below diffusion-class models (needs a side-by-side). On-device needs iPhone 16 Pro+. The Swift SDK is native code, so under AGENTS.md it would need to become a White Glove plugin later. In the Flutter v1 app it would count as a new native feature, so the **cloud/LiveKit path is the compliant v1 route** | $2 (device) / $4 (cloud) |
| **2** | **Anam Cara-4.1** | Leads (vendor-run) realism and latency comparisons. Image upload included even on the Free plan. 70+ languages. LiveKit plugin | $0.11–0.16 list = $11–16 per heavy user. Needs the enterprise rate (from $0.04) to be viable. Comparisons are vendor-run | $11–16 list; ~$4 enterprise |
| **3** | **HeyGen LiveAvatar (LITE mode)** | Photo avatars, strong HeyGen realism. LITE lets us keep our own Spanish STT/LLM/TTS and Cloudflare stack. **No session data retained in LITE**. LiveKit plugin | Retail ~$0.13/min. The $0.01 rate is "contact sales". Slower first frame in Anam's benchmark | $13 retail; ~$1 enterprise |
| **4** | **Simli** | Cheapest by far ($0.01/min). Custom face from photo on the $10 Hobby plan (we would need Pro at $49 for 4 coaches). LiveKit/Pipecat/WebRTC | Mouth-region lip sync on a mostly static face, so less "alive" listening and head motion than Anam or Tavus | ~$1 |
| **5** | **Alibaba-Quark Live Avatar** (open, Apache-2.0), with **LongCat-Video-Avatar 1.6** (MIT) for pre-rendered clips | Best commercially licensed open path to diffusion-grade realism, real-time and infinite length. LongCat 1.6 (MIT, Whisper audio) can pre-render greetings, idle and listening loops now | 5 x H800 per live stream today. Must replace InsightFace. Only viable once distillation brings it to 1–2 GPUs | Not viable live today |

Also considered: **Tavus Phoenix-4.5** probably has the best perception and listening (Raven), but at $0.26–0.35/min it costs more per heavy user than the whole subscription. **AVTR-1** is the best open single-GPU listening model, but cannot be used commercially until the InsightFace-free release and a commercial licence for the streamer. **Runway Characters** and **Gemini Live Avatar** are new in 2026 and look promising, but cost ~$0.20–0.39/min and the Gemini custom avatar is gated.

---

## 5. What can be demonstrated for free right now

| Option | Free now without an account? | Uses our portrait? | Real-time? | Notes |
|---|---|---|---|---|
| **Wan2.2-S2V official HF Space** (`Wan-AI/Wan2.2-S2V`) | **Yes.** Runs on `cpu-basic` and calls Alibaba DashScope with the Space owner's key, so no ZeroGPU quota (status RUNNING 2026-11-24) | Yes | No (offline clip) | **Uploads the portrait and audio to Alibaba Cloud OSS.** Get owner approval before sending coach images. Shows the realism ceiling of the Live Avatar base model |
| ZeroGPU Spaces: `victor/LongCat-Video-Avatar-1.6`, `meituan-longcat/LongCat-Video-Avatar-1.5-Demo`, `alexnasa/OmniAvatar`, `acvlab/FantasyTalking`, `fffiloni/KDTalker`, `fffiloni/LatentSync`, `Soul-AILab/SoulX-FlashHead`, `shenxq/AVTR`, `KlingTeam/LivePortrait` | Runs anonymously, but **anonymous ZeroGPU quota is very small**. 14B video jobs will usually exceed it. An HF login gives more quota (that is an account) | Yes | No (Spaces generate clips) | All RUNNING on `zero-a10g` as of 2026-11-24 |
| `fffiloni/echomimic-v2`, `fffiloni/Meigen-MultiTalk` | Showcase or "duplicate this Space" only (CPU) | — | — | Need your own GPU |
| `YinmingHuang/StableAvatar` | No (RUNTIME_ERROR) | — | — | |
| Vendor homepage demos (Anam, Tavus, LemonSlice featured avatars, Simli) | Stock-avatar demos are advertised. Not verified whether each works without login | **No** (stock faces) | Yes | Fine for judging realism and latency, not for judging our coaches |
| Anam Free / LiveAvatar test credits / Simli Free / Tavus Free / Beyond Presence Free / bitHuman Free | **Need an account** (not allowed now) | Anam Free and LiveAvatar: yes. Others: no | Yes | Best first trial once accounts are approved: **Anam Free** (own portrait, 30 min, $0) |
| Live Avatar / FlashTalk / AVTR-1 self-hosted | Need a GPU (5–8 x H800, or an L40-class card for AVTR-1) | Yes | Yes | Paid compute, so owner approval needed |

---

## 6. Sources (accessed 2026-11-24)

Hosted
- Simli pricing: https://www.simli.com/pricing ; docs: https://docs.simli.com
- Anam pricing: https://anam.ai/pricing ; models: https://anam.ai/docs/introduction/models.md ; latency benchmark (Jul/Oct 2026, vendor-run): https://anam.ai/tools/latency-benchmark
- Tavus pricing: https://www.tavus.io/pricing ; Image-to-Replica (2026-05-14): https://www.tavus.io/blog/introducing-image-to-replica ; Phoenix: https://www.tavus.io/model/phoenix
- HeyGen LiveAvatar FAQ: https://help.heygen.com/en/articles/12758866-liveavatar-faq ; credits: https://docs.liveavatar.com/docs/faq/credits ; $0.01/min enterprise post (2026-08-25): https://youmind.com/de-DE/landing/x-viral-articles/liveavatar-unlimited-concurrency-pricing-drop
- bitHuman pricing: https://www.bithuman.ai/pricing ; SDK/CPU press release: https://sdtimes.com/ai/bithuman-launches-sdk-for-creating-ai-avatars/
- LemonSlice pricing: https://lemonslice.com/pricing ; API: https://lemonslice.com/avatar-api
- Beyond Presence pricing: https://www.beyondpresence.ai/pricing ; FAQ: https://docs.bey.dev/learn/faqs.md
- Runway Characters (2026-03-09): https://runway.com/news/introducing-runway-characters ; product/pricing: https://runwayml.com/product/characters
- Hedra Live Avatars with LiveKit: https://mpost.io/hedra-launches-live-avatars-with-livekit-delivering-real-time-ai-characters-at-ultra-low-latency-and-cost/ ; https://www.hedra.com/pricing
- Gemini Live Avatar (secondary): https://lumichats.com/blog/gemini-3-8-live-avatar-general-availability-september-2026 ; https://cloud.google.com/vertex-ai/generative-ai/pricing
- D-ID pricing (secondary): https://www.activepieces.com/blog/d-id-pricing-2026-every-plan-cost-and-limit
- Akool API pricing: https://www.akool.com/api-pricing ; https://wavespeed.ai/blog/cost-and-billing/akool-pricing-2026/
- LiveKit avatar plugins: https://docs.livekit.io/agents/models/avatar/

Open models
- Live Avatar: https://github.com/Alibaba-Quark/LiveAvatar ; https://huggingface.co/Quark-Vision/Live-Avatar ; arXiv 2512.04677
- SoulX-FlashTalk: https://huggingface.co/Soul-AILab/SoulX-FlashTalk-14B ; https://github.com/Soul-AILab/SoulX-FlashTalk
- AVTR-1: https://huggingface.co/avaturn-live/avtr-1 ; arXiv 2609.22913
- Avatar Forcing: https://github.com/TaekyungKi/AvatarForcing ; arXiv 2601.00664
- LongCat-Video-Avatar 1.6: https://huggingface.co/meituan-longcat/LongCat-Video-Avatar-1.6 ; https://github.com/meituan-longcat/LongCat-Video
- EchoMimic V2/V3: https://github.com/antgroup/echomimic_v2 ; https://github.com/antgroup/echomimic_v3 ; https://huggingface.co/BadToBest/EchoMimicV3
- InfiniteTalk/MultiTalk: https://github.com/MeiGen-AI/InfiniteTalk ; https://huggingface.co/MeiGen-AI/InfiniteTalk
- OmniAvatar: https://huggingface.co/OmniAvatar/OmniAvatar-14B ; FantasyTalking: https://github.com/Fantasy-AMAP/fantasy-talking
- Wan2.2-S2V: https://huggingface.co/Wan-AI/Wan2.2-S2V-14B ; Space: https://huggingface.co/spaces/Wan-AI/Wan2.2-S2V
- StableAvatar: https://huggingface.co/FrancisRing/StableAvatar ; HunyuanVideo-Avatar licence: https://github.com/Tencent-Hunyuan/HunyuanVideo-Avatar/blob/main/LICENSE
- Hallo3: https://github.com/fudan-generative-vision/hallo3 ; Sonic licence: https://github.com/jixiaozhong/Sonic/blob/main/LICENSE ; FLOAT: https://github.com/deepbrainai-research/float
- KDTalker: https://huggingface.co/ChaolongYang/KDTalker ; JoyVASA: https://github.com/jdh-algo/JoyVASA ; ARTalk: https://github.com/xg-chu/ARTalk
- LatentSync: https://github.com/bytedance/LatentSync ; https://huggingface.co/ByteDance/LatentSync-1.6
- Ditto model card (lists insightface_det.onnx): https://huggingface.co/digital-avatar/ditto-talkinghead
- Watch list: arXiv 2604.23632 (Hallo-Live), 2608.17707 (DynaForcing), 2609.10317 (Decoupled Self-Forcing); daily tracker https://github.com/liutaocode/talking-face-arxiv-daily
