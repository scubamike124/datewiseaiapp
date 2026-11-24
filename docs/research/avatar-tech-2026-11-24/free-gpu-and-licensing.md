# DateWise avatar: free GPU options, newer licensed models, and clean replacements for problem components

Research date: 2026-11-24. This was desk research only. I created no accounts, did not sign in, spent nothing, and ran no models. This report builds on `frameworks.md`, `models.md` and `alternatives.md` (same folder) and does not repeat what they cover.

**Evidence labels used throughout**

- **[LICENCE]**: I read the licence text itself (a LICENSE file, a licence `.txt`, or the licence agreement), fetched today.
- **[CARD]**: from a Hugging Face model-card licence tag or the model card's own licence section, not a separate licence file.
- **[HASH]**: I compared file hashes (LFS sha256) through the Hugging Face API.
- **[CODE]**: I read the source code. The shallow clones are in `avatar-research/repos/`; Ditto is in `/root/ditto`.
- **[README]** or **[VENDOR]**: what the project's README or the vendor's own page claims.
- **[3P]**: a third-party article. Treat it as unconfirmed.

---

## 0. Top findings

1. **FlashHead Lite is not commercially usable as shipped [LICENCE + HASH].**
   - Its `VAE_LTX/diffusion_pytorch_model.safetensors` is byte-identical (sha256 `265ca87c…2010`, 1,676,798,532 bytes) to `Lightricks/LTX-Video/vae/diffusion_pytorch_model.safetensors`. That file was last committed on 2024-12-11 in "Diffusers weights test (#32)", which is the **LTX-Video 0.9** VAE.
   - The governing licence is "LTX Video 0.9 RAIL-M License dated November 22, 2024". Its definition 12 reads: *"'Permitted Purpose' means for academic or research purposes only, and explicitly excludes commercialization"*. Sections 2 and 3 grant copyright and patent rights "only for the Permitted Purpose" ([licence](https://huggingface.co/Lightricks/LTX-Video/blob/main/ltx-video-2b-v0.9.license.txt)).
   - The FlashHead model card calls this licence "Open-RAIL-M", and `models.md` repeated that ("commercial use allowed"). **Both are wrong.** Only LTX **0.9.5** is Open RAIL-M with commercial use. **0.9.6 and later** use the Open Weights License: free under $10M annual revenue, with liquidated damages for larger companies that do not take a commercial licence.
   - The licence defines "Derivatives of the Model" to include models trained on its outputs or by distillation. The Lite DiT, which was trained in LTX latent space, may therefore be caught as well. That is a question for a lawyer.
   - **Conclusion: do not ship Lite. Ship FlashHead Pro (Wan 2.1 VAE, Apache-2.0) or the LeapTalk route below.**
2. **LeapTalk (2026) appears to solve FlashHead's speed and licence problems together [LICENCE + CODE + CARD].**
   - What it is: a LoRA plus an audio projector on the **FlashHead Pro** DiT, decoded with **TAEHV `taew2_1`** (a tiny autoencoder for the Wan 2.1 VAE, MIT [LICENCE]). The inference code defaults to `--model_type pro` [CODE].
   - Speed: 1 inference step per chunk, "up to 200 FPS" on one **H200** [README].
   - Licences: code Apache-2.0 [LICENCE]; weights Apache-2.0 [CARD]. **No LTX component.**
   - Not yet known: performance on consumer GPUs. The web demo uses the paid Doubao cloud for ASR and TTS, so we would swap in our own.
3. **FlashHead weights are now clearer [CARD].** The model card README (updated 2026-11-19) lists:
   - the DiT: Apache-2.0;
   - the Wan VAE: Apache-2.0;
   - the LTX VAE: RAIL-M;
   - wav2vec2: Apache-2.0.
   The repo tag is still `license: other`, and there is still no LICENSE file in the model repo.
   **New caveat:** the training set VividHead is CC-BY-4.0, but its card says it is *"intended for research and non-commercial purposes"* and was collected from *"Web videos and various Open-source videos"*. This is the same kind of training-data question as MuseTalk's HDTF.
4. **Free GPU for real tests.**
   - **The only free option that can serve live WebRTC is Modal's Starter plan** ($30/month of compute, recurring [VENDOR]). That buys about 37 h on an L4 or 27 h on an A10. It needs a Modal account.
   - **Hugging Face ZeroGPU gives clips only.** Daily quota: 2 min anonymous, **5 min with a free account** [VENDOR]. A free account can host ZeroGPU Spaces only once it is **older than 30 days** with a verified email, so a newly created account **cannot duplicate the FlashHead Space for 30 days**.
   - **Kaggle and Colab: offline clips only.** They have no inbound ports. Colab's FAQ bans "creating deepfakes" and web serving. Their T4 GPUs lack native bf16, which FlashHead hard-codes.
5. **InsightFace in Ditto is easy to remove, using code DateWise already has [CODE].**
   - In Ditto, `det_10g.onnx` (SCRFD) and `2d106det.onnx` only seed the first crop for LivePortrait's MIT `landmark203`.
   - DateWise's own `tool/avatar/lp_engine.py` already replaced InsightFace with YuNet (MIT) plus `landmark203`.
   - The same swap in Ditto's `source2info._crop` is about 20 lines, with no retraining.
6. **Face parsing (BiSeNet/CelebAMask-HQ) has no clean "learned" drop-in.** Every public face parser found is trained on CelebAMask-HQ or LaPa, and both datasets are non-commercial [LICENCE]. SegFormer's `nvidia/mit-b5` backbone also carries NVIDIA's own licence. The answer is **MediaPipe Face Landmarker plus Selfie-Multiclass (Apache-2.0 [CARD])**, both already used in DateWise. They generate the paste-back mask with no retraining.

---

## 1. Free GPU resources for testing Mynah, SoulX-FlashHead and OpenAvatarChat

### 1.1 What fits where (VRAM needs, from earlier reports and source)

- **FlashHead Lite:** about 6.6 GB. **Commercially excluded** (finding 1), but fine for a private technical look.
- **FlashHead Pro:** a 1.3B DiT. Fits in 24 GB. Runs at about 10.8 fps on a 4090 [README], so not real time on one consumer card.
- **LeapTalk:** a Pro DiT plus a LoRA plus TAE. Probably under 16 GB (my estimate), but unverified.
- **MuseTalk 1.5:** about 7.7 GB.
- **Constraints that apply on every platform:**
  - FlashHead hard-codes `param_dtype=torch.bfloat16` (`flash_head_pipeline.py:62`) [CODE], so Turing GPUs (T4) need a patch to fp16, which risks overflow.
  - Its attention uses flash-attn 3 or 2 when installed and otherwise falls back to SDPA [CODE].
  - Mynah pins torch 2.5.1+cu121. The FlashHead Space uses torch 2.9.1 [CODE].

### 1.2 Platform table

| Platform | GPU / VRAM | Free hours | Account | FlashHead Lite / Pro / MuseTalk | Live WebRTC? | Commercial-evaluation terms | Source (date) |
|---|---|---|---|---|---|---|---|
| **HF ZeroGPU: use the official `Soul-AILab/SoulX-FlashHead` Space** | Half an NVIDIA RTX Pro 6000 Blackwell, **48 GB** (`large`). A full card, 96 GB, costs 2× quota | **Daily quota:** anonymous 2 min, **free account 5 min**, PRO 40 min. The Space's `@spaces.GPU` uses the default **60 s** per call [CODE], so a free account gets about 5 short clips a day | None for anonymous; HF email account for 5 min | Lite and Pro are both selectable (`choices=["pro","lite"]`, default lite [CODE]). MuseTalk: the official Space shows `RUNTIME_ERROR` [API] | No. Gradio, and a GPU only inside each call | HF ToS allow commercial use of the Hub. Uploading a coach portrait sends it to the Space owner's Space, a privacy question | [ZeroGPU docs](https://huggingface.co/docs/hub/spaces-zerogpu) (fetched 2026-11-24); Space API: RUNNING, `zero-a10g` label, 2026-11-24 |
| **HF ZeroGPU: duplicate the Space into your own account** | Same | Same quotas apply to visitors; hosting itself is free | **Free account in good standing: verified email and account older than 30 days, max 2 ZeroGPU Spaces** | Same | No | Same | [ZeroGPU docs](https://huggingface.co/docs/hub/spaces-zerogpu) "Hosting Limitations" |
| **HF Spaces `cpu-basic`** | 2 vCPU, 16 GB RAM, no GPU | Unlimited (sleeps when idle) | Free account | Not usable for FlashHead or MuseTalk at useful speed | Mynah `cored` only | Same | earlier reports |
| **Kaggle Notebooks** | 2× T4 (16 GB each, Turing). P100 (16 GB, Pascal) reportedly retired 2026-09-15 [3P] | About 30 GPU-h/week, floating and shown in settings [3P]. 12 h max session [3P quoting docs] | Kaggle account (Google or email) **plus phone verification** for GPU and internet [3P] | **MuseTalk: yes (fp16).** Lite: fits in VRAM but needs bf16→fp16 and flash-attn off; slow; not real time. Pro: fits, very slow | **No.** No inbound ports. A tunnel would be a terms risk I could not verify (Kaggle's terms page did not render) | **Not verified.** Kaggle's terms text could not be fetched | [gpuperhour 2026-09-21](https://gpuperhour.com/blog/free-cloud-gpus-and-credits), [aimultiple](https://aimultiple.com/free-cloud-gpu) |
| **Google Colab free** | Usually a T4, 16 GB. Google names none and publishes no limits | Not published; "at most 12 hours"; "access to expensive resources like GPUs is heavily restricted" | Google account | As Kaggle | **No.** The FAQ forbids "web service offerings", "connecting to remote proxies", and (free tier) "bypassing the notebook UI to interact primarily via a web UI" | The FAQ also forbids **"creating deepfakes"**. Our coaches are synthetic faces, but a talking-head job could still be flagged. **Not recommended** | [Colab FAQ](https://research.google.com/colaboratory/faq.html) (fetched 2026-11-24) |
| **Lightning AI Studios** | GPUs not listed on the free plan. T4, L4 and L40S sessions are "unlimited"; A100 and up are capped at 4 h | **5 credits on sign-up, plus 25 with a card ("up to 30")**, "~50 GPU hours on interruptible machines". Third parties say this was one-time from 2026-09, replacing 15 credits/month | Account **plus phone verification** [VENDOR FAQ]. Card optional (adds credits) | L4 24 GB: everything fits | Possibly (Studios can expose ports), not verified | No restriction stated on the page | [lightning.ai/pricing](https://lightning.ai/pricing) (2026-11-24); [usagepricing 2026-09-21](https://www.usagepricing.com/blueprint/activity/lightning-ai-2026-09-21-gpu-rate-card-reprice) [3P] |
| **Modal Starter** | T4 / L4 / A10 / L40S / A100 / H100 | **$30/month free, recurring.** At $/h: T4 0.59, L4 0.80, A10 1.10, L40S 1.95. So **about 37 h L4, 27 h A10, 15 h L40S** | Modal account (sign-in). Card requirement not stated on the page; third parties say none needed [3P] | All fit on L4 or A10. A **real-time** FlashHead Lite or MuseTalk test is feasible (Ada/Ampere, bf16, flash-attn) | **Yes, with work.** Web endpoints and tunnels; WebRTC would need TURN over TCP | Normal commercial platform; credits apply to production use too | [modal.com/pricing](https://modal.com/pricing) (2026-11-24) |
| Modal academic | Same | "up to $10k" | Graduate students, labs and researchers | — | — | **Not applicable** unless the owner has a real academic affiliation | same |
| **RunPod** | Any | **No free tier.** Referral bonus needs a $10 deposit. **Startup Program: Starter $1K (raised under $1M), Venture $5K (VC-backed, under $5M)**. Credits expire after 1 year; existing customers are ineligible | Company application | All | Yes (pods expose ports) | Commercial | [runpod.io/startup-program](https://www.runpod.io/startup-program) (2026-11-24) |
| **Vast.ai** | Marketplace (e.g. a 4090 at about $0.51/h on 2026-11-24 [3P]) | **No free tier. Startup Program: $2,500 credits** ("move workloads to Vast.ai") | Company application | All | Yes | Commercial | [Vast article 2026-02-06](https://vast.ai/article/vast-ai-startup-program) |
| **Paperspace (DigitalOcean) free notebook** | Quadro M4000, 8 GB (Maxwell). Free A4000 and up appear only occasionally | 6 h sessions | Account. Sources disagree on whether a card is needed [3P] | **No.** Maxwell has no bf16 and recent CUDA 12.8 torch builds have dropped it | No | — | [yangmao.ai](https://yangmao.ai/en/compute/paperspace/), [gpuperhour](https://gpuperhour.com/blog/free-cloud-gpus-and-credits) [3P] |
| **Lambda** | — | No free tier or public credit programme found | — | — | — | — | search 2026-11-24 |
| **SageMaker Studio Lab** | — | **Closed to new customers** | — | — | — | — | [gpuperhour](https://gpuperhour.com/blog/free-cloud-gpus-and-credits) [3P] |
| **NVIDIA Inception** | Partner credits, amount unpublished | — | **Incorporated company, under 10 years old, working website, ≥1 founder**. Free, no equity | — | — | — | [nvidia.com/startups](https://www.nvidia.com/en-us/startups/) (2026-11-24) |
| **AWS Activate** | AWS GPUs (e.g. g5/g6) | Founders $1K (some up to $5K); Portfolio up to $200K | Company, pre-Series B, AWS account on a paid tier | — | Yes | Commercial | [gpuperhour](https://gpuperhour.com/blog/free-cloud-gpus-and-credits) [3P] |
| **Google for Startups Cloud** | GCP GPUs. The free trial cannot add GPUs | $2K (MVP), $200K–350K (funded or AI-first) | Company | — | Yes | Commercial | same [3P] |
| **Microsoft for Startups** ("Founders Hub" name retired) | Azure GPU VMs (high-demand GPUs need a support ticket) | Self-service **up to $5,000**; investor-referred from $100K | Company | — | Yes | Commercial | [learn.microsoft.com changes page](https://learn.microsoft.com/en-us/startups/changes-microsoft-for-startups) |

### 1.3 Recommended order and the owner's exact steps (every one is an owner choice: each creates an account)

1. **Quickest look, $0, needs the HF account the owner already authorised.** In-session, the owner declined a credential form, so this is the owner's choice, not an action I take.
   1. Sign in at huggingface.co and verify the email.
   2. Open `huggingface.co/spaces/Soul-AILab/SoulX-FlashHead`.
   3. Choose **"pro"** (the licence-relevant variant; "lite" is fine for comparison only).
   4. Upload a **non-sensitive test face** (not a coach portrait, unless the owner accepts sending it to Soul AI Lab's Space) and a 5–10 s English or Spanish wav.
   5. Budget: about 5 runs a day of up to 60 s GPU each. Result: offline clips that judge lip closure, teeth and head motion.
   6. After 30 days, the same account can **Duplicate this Space** (top-right ⋮ menu) into a Space it owns, so its own inputs stay in its own Space. Still clip-only.
2. **Real-time test, $0, needs a Modal account** (a new account, so the owner must authorise it):
   1. Sign up at modal.com.
   2. Run `pip install modal` and `modal setup` locally.
   3. Deploy a single L4 or A10 container with Mynah's FlashHead worker (or OAC's FlashHead/MuseTalk handler, or LeapTalk). Expose `cored`'s `/offer` through a Modal web endpoint or tunnel, and add a free TURN-over-TCP relay (self-hosted coturn on the same container).
   4. Do not add a payment method, so usage stops at the $30.
   One 2-hour test session costs about $1.60–2.20 of the $30.
3. **Batch clips, $0, Kaggle** (account plus phone verification): a MuseTalk 1.5 notebook on a T4 with internet on, downloading weights from HF. Offline MP4s only.
4. **Production-scale credits** (all need a registered company, so the owner decides): RunPod Starter $1K, Vast $2.5K, Microsoft up to $5K self-serve, AWS Activate $1K, NVIDIA Inception (partner credits). The 4090-class prices on RunPod and Vast make those credits last longest for FlashHead or MuseTalk serving.

---

## 2. Newer commercially licensed alternatives the earlier reports missed (2025–2026)

Checked today: GitHub LICENSE files fetched raw, Hugging Face API licence tags, and READMEs. Nothing was run.

| Model | Released | Code licence | Weights licence | Dependencies (licence) | GPU / real-time claim | Single photo? | Listening / idle | Emotion control | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| **LeapTalk** (zhangrongxiang/LeapTalk, SJTU/HIT) | arXiv 2026; weights 2026-07-29; repo updated 2026-11-17 | **Apache-2.0 [LICENCE]** | **Apache-2.0 [CARD]** (`z-rx/leaptalk`: LoRA, `audio_proj`, `taew2_1.pth`) | FlashHead Pro DiT (Apache-2.0 [CARD]); Wan 2.1 VAE (Apache-2.0 [CARD]); TAEHV (**MIT [LICENCE]**); wav2vec2-base-960h (Apache-2.0 [CARD]); MediaPipe 0.10.35 (Apache-2.0). Training data: VividHead ("research and non-commercial" note). Web demo: Doubao cloud (paid, swap out) | **1 step per chunk, "up to 200 FPS" on one H200** [README]. Consumer-GPU numbers not published | **Yes** | Streaming chunks; no explicit idle mode (silence-driven as in FlashHead) | No | **Best new lead.** A FlashHead-quality single-photo model with no LTX dependency. Benchmark on Modal L4/A10 first |
| **IMTalker** (bigai-nlco/IMTalker, ACM MM) | weights 2025-11-27; training code 2025-12-16 | **Apache-2.0 [LICENCE]** | **MIT [CARD]** (`cbsjtu01/IMTalker`) | wav2vec2-base-960h (Apache-2.0); **face-alignment for cropping** (code BSD-3; S3FD/FAN weight licence not stated). SMIRK and L2CS-Net are training-only. Training data not named in README | **42 FPS audio-driven at 512² on an RTX 4090** [README] | **Yes** | Not described | Head-pose and **eye-gaze** control inputs; no emotion label | **Good real-time single-GPU candidate**, comparable class to Ditto (implicit-motion warping). Swap face-alignment for MediaPipe (cropping only, no retraining). Check the paper's training datasets |
| **Hallo-Live** (fudan-generative-vision) | 2026-06 (ACM MM 2026) | MIT [LICENCE badge/README] | MIT [CARD] | Built on **Ovi** (Apache-2.0 [CARD]) plus Wan and **MMAudio** checkpoints, which are **CC-BY-NC 4.0 [README/CARD]** | 20.4 FPS, 0.94 s latency on **2× H200** [README] | Text-driven joint audio+video. It generates its own voice, so not our TTS | — | Via prompt | **No:** NC audio dependency, 2× H200, wrong input type |
| **NVIDIA Audio2Face-3D** (v3.0 models, SDK, training framework) | open-sourced 2025-09/10 | SDK MIT; training framework Apache-2.0 [GitHub API] | Audio2Face: **NVIDIA Open Model License** (commercial) [CARD]. **Audio2Emotion: commercial but "may only be used in connection with the NVIDIA Audio2Face project" [LICENCE]** | CUDA/TensorRT | Real-time blendshapes | No: drives a **3D rig** (ARKit-style blendshapes), not a photo | Yes, via blendshapes | **Yes: audio-inferred emotion** | Not photoreal from one photo. Useful only if we went 3D |
| **Linly-Talker-Stream** (Kedreamix) | 2026 | Apache-2.0 [LICENCE] | Uses wav2lip (original weights non-commercial), MuseTalk, ER-NeRF, TalkingGaussian | As the engines | WebRTC, full-duplex, barge-in [README] | Per engine | "Listen while speaking" | — | A LiveTalking-style framework; nothing beyond LiveTalking or Mynah |
| **DuplexAvatar** (zzzweakman) | 2026-10 | Apache-2.0 [LICENCE] | — | **FlashHead Lite** (LTX issue); MiniCPM-o 4.5 (own licence, not checked) | 4× H200, 1 session [README] | Yes | **Silence-driven listening motion and interruption pose continuation** [README] | — | **Reference design only** (3 stars). Its listening-continuation idea is worth copying into Mynah |
| **Duix-Mobile / Duix-Avatar** (duixcom) | updated 2026-11 | **DUIX.COM Community License [LICENCE]** | same | — | On-device, "<120 ms on Snapdragon 8 Gen 2" [README] | **No.** Custom avatars need a 15 s–2 min video and contacting Duix | Yes | "emotional cues" [README] | **Excluded: commercial licence needed above 1,000 MAU [LICENCE §2]**, plus "Built with/Powered by DUIX.COM" attribution |
| DyStream, Vach, Avatar Forcing, AVTR-1 (GitHub), RAP, StreamAvatar | 2025–2026 | **No LICENSE file** (checked raw `LICENSE` on 2026-11-24) | AVTR-1 unchanged since 2026-05-31 (community licence plus InsightFace note) | — | Real-time claims | — | DyStream and Avatar Forcing do dyadic listening | — | **Not usable** until licensed. AVTR-1 status unchanged from `alternatives.md` |
| LongCat-Video-Avatar 1.6 ComfyUI and INT8 ports | 2026-11 | — | MIT | — | Offline | — | — | — | Already covered (LongCat). The INT8 port (`TeamAIQ/...-INT8-ConvRot`) may make offline intro and idle clips cheaper |

**Takeaway.** For a photoreal, single-photo, commercially clean real-time engine, the shortlist grows from "FlashHead (Lite blocked)" to:

1. **LeapTalk** (FlashHead Pro + TAEHV, Apache/MIT);
2. **FlashHead Pro**, if 2× GPUs are acceptable;
3. **IMTalker** (42 FPS on a 4090, MIT weights, warping class like Ditto, after swapping out face-alignment);
4. MuseTalk on top of an idle loop, with HDTF caveats.

None of these ships emotion labels. Emotional reactions would come from the idle and gesture clip library (Mynah's "instinct" layer) or from prompt/reference-image choice.

---

## 3. Replacing unclear-licence components

| Problem component | Where | What the licence actually says | Clean replacement (licence; evidence) | Swap difficulty | Retraining? |
|---|---|---|---|---|---|
| **InsightFace SCRFD `det_10g.onnx` + `2d106det.onnx` (buffalo_l)** | Ditto (`ditto_pytorch/aux_models/`, `insightface_det.onnx` / `.engine`); used in `source2info._crop` only to seed the first crop [CODE] | InsightFace README: code MIT, *"models trained with these data are available for non-commercial research purposes only"* [LICENCE text in README] | **YuNet** (OpenCV Zoo, **MIT [LICENCE]**) for box plus 5 points, then Ditto's existing **`landmark203`** (LivePortrait's, MIT [CARD `KlingTeam/LivePortrait`]). Alternative: **MediaPipe BlazeFace short-range / Face Landmarker 478** (Apache-2.0 [CARD `litert-community/...`]). Ditto already ships `blaze_face.onnx`, `face_mesh.onnx` and a `mediapipe_landmark478.py` aux model [CODE] | **Easy.** About 20 lines: replace `insightface_det` + `landmark106` with YuNet/MediaPipe points passed to `crop_image`. DateWise already did exactly this for LivePortrait (`tool/avatar/lp_engine.py`, `docs/legal/ASSET_PROVENANCE.md`) | **No.** Check that crop alignment matches on the 4 coaches |
| InsightFace in Mynah | `deploy/compose/requirements-avatartrain.txt` pins `insightface==1.0.1` for LivePortrait idle baking; the bake runs `--no-flag_do_crop` [CODE]. Mynah's own portrait extraction already uses MediaPipe (`extract_portrait.py`) [CODE] | as above | Remove the pin. Use YuNet/MediaPipe crop (as in DateWise `lp_engine.py`) | **Easy** | No |
| **SCRFD alternatives generally** | — | **Ultralytics YOLO (incl. YOLO11/YOLO26 face forks): AGPL-3.0**, so a network-served model must publish its source; avoid. YOLOv5-face (deepcam-cn): GPL-3.0. RetinaFace (biubug6/Pytorch_Retinaface): code MIT, but weights trained on WIDER FACE, whose image rights are research-oriented. Nearly every open detector (YuNet included) is trained on WIDER FACE | **Preferred: MediaPipe BlazeFace** (Google-trained, Apache-2.0 weights [CARD]). **YuNet** is MIT weights [LICENCE] but WIDER-FACE-trained (a residual dataset question, small for a detector) | — | — |
| **FlashHead Lite LTX VAE** | `VAE_LTX/` = LTX-Video **0.9** VAE [HASH] | **RAIL-M 0.9: academic/research only** [LICENCE]. By version: 0.9 and 0.9.1 are research-only RAIL-M; **0.9.5 is Open RAIL-M (commercial, use-based restrictions)** [LICENCE]; **0.9.6+ is the LTX Open Weights License (free under $10M revenue; at or above $10M you must buy a licence or owe double fees as liquidated damages)** [LICENCE] | **(a) FlashHead Pro + Wan 2.1 VAE** (Apache-2.0 [CARD]), but slow (10.8 fps on a 4090). **(b) LeapTalk: Pro DiT + LoRA + TAEHV `taew2_1`** (MIT/Apache), real-time claim. (c) LTX 0.9.5 VAE (Open RAIL-M) is a different VAE, so the Lite DiT would need retraining in its latent space. (d) A TAE distilled from LTX 0.9 counts as a "Derivative" under RAIL-M, so it is **not** a way out | (a) a config switch; (b) a drop-in (published weights); (c) hard | (a) No; (b) No (already trained); (c) **Yes** |
| **FlashHead DiT weights** ("license: other") | `Soul-AILab/SoulX-FlashHead-1_3B` | Model card README (2026-11-19) states DiT Apache-2.0 [CARD text]; no LICENSE file. Training data VividHead: CC-BY-4.0 but "intended for research and non-commercial purposes", from web videos [CARD] | Nothing else matches it. Ask Soul AI Lab to add a LICENSE file and confirm commercial use in writing (a free email, owner's choice) | — | — |
| **MuseTalk face parsing: BiSeNet `79999_iter.pth`** | MuseTalk `download_weights.sh` (gdown); Mynah `workers/avatar/faceparse` (used only in `mode="face"` for lip-sync engines; **FlashHead uses `mode="full"`, no parser** [CODE]) | Code MIT (zllrunning). **CelebAMask-HQ: "available for non-commercial research purposes only… not … exploit for any commercial purposes, any portion of … derived data"** [LICENCE README] | **MediaPipe Face Landmarker** (478 points; build a jaw/lower-face polygon mask) plus **Selfie-Multiclass** (face-skin/hair/clothes classes); both Apache-2.0 [CARD], already in DateWise (`face_landmarker.task`, `selfie_multiclass.tflite` in scratchpad). **Do not use SegFormer face parsers:** `jonathandinu/face-parsing` says *"RESTRICTED to non-commercial research and educational purposes"* (CelebAMask-HQ), and the `nvidia/mit-b5` backbone carries NVIDIA's own licence ("other" [CARD]). **LaPa** dataset: non-commercial only [LICENCE README] | **Easy–moderate.** Parsing only builds the paste-back blend mask (`blending.py`, `get_image_prepare_material`). Rewrite one function; tune feathering to avoid seams | **No** |
| **MuseTalk weights: HDTF notice** | `TMElyralab/MuseTalk` NOTICE | Weights MIT [CARD + NOTICE], but *"trained on the HDTF and private dataset. Please, communicate with the HDTF owner about commercialization"* [NOTICE]. HDTF itself is **CC-BY-4.0 for its annotations** [LICENCE README], but the videos are third-party YouTube uploads it only links to, so the owners of the underlying footage are the real rights holders | No drop-in. Options: accept as a residual training-data risk (common industry practice, owner and legal decision); or retrain MuseTalk on licensed or own-recorded footage (MuseTalk training code exists; a large job); or prefer FlashHead Pro/LeapTalk, which carries a similar VividHead question | — | Only if we retrain |
| **MuseTalk face detection: S3FD** (vendored `face_detection/sfd`, weights from adrianbulat.com) | MuseTalk preprocessing [CODE] | face-alignment code BSD-3; **S3FD weight licence not stated** (WIDER FACE-trained) | **MediaPipe BlazeFace** or **YuNet** box, converted to MuseTalk's bbox convention | **Moderate.** Preprocessing only; must reproduce bbox size and position so `bbox_shift` behaves the same | No |
| **DWPose `dw-ll_ucoco_384` (mmpose RTMPose-L)** | MuseTalk `preprocessing.py`; OAC uses the ONNX version [CODE] | Weights **Apache-2.0 [CARD `yzd-v/DWPose`]**; mmpose Apache-2.0. Trained on COCO-WholeBody plus UBody (UBody terms not verified) | Fine to keep (Apache). If removing it for simplicity: **MediaPipe Face Landmarker** points mapped to the 68 face points MuseTalk uses | Moderate (landmark index mapping) | No |
| **face-alignment (S3FD + FAN)** | IMTalker cropping; Vivora swaps mmpose for it | code BSD-3; weights unstated | MediaPipe Face Landmarker | Easy–moderate | No |
| LivePortrait weights | Mynah idle bake; DateWise `tool/avatar` | **MIT [CARD]** (already accepted in DateWise ASSET_PROVENANCE) | keep | — | — |
| wav2vec2-base-960h, whisper-tiny, sd-vae-ft-mse, TAEHV, Wan 2.1 VAE | FlashHead, LeapTalk, IMTalker, MuseTalk | Apache-2.0 / Apache-2.0 tag (code MIT) / MIT / MIT / Apache-2.0 [CARD/LICENCE] | keep | — | — |
| **MMAudio** (in Ovi/Hallo-Live) | — | **CC-BY-NC 4.0 checkpoints [CARD + README]** | Avoid Ovi-based models | — | — |
| **NVIDIA Audio2Emotion** | — | Commercial, but **only with the Audio2Face project** [LICENCE §2.4] | Use only inside the Audio2Face pipeline | — | — |
| wav2lipLS (Mynah), wav2lip256 (LiveTalking) | — | Self-trained or undisclosed data | Don't use; prefer FlashHead Pro/LeapTalk or MuseTalk | — | — |

### Corrections to earlier reports

- `models.md` table: "LTX-Video-0.9 VAE (Lite) Open RAIL-M (commercial use allowed…)" is **wrong**. The licence is research-only RAIL-M (finding 1).
- `frameworks.md`: "Exact LTX version embedded is not stated" is now **resolved**: it is v0.9 [HASH]. Its $10M-threshold remark applies only to 0.9.6+, not to this VAE.
- `frameworks.md` / `models.md`: "FlashHead weights: no licence" is now **partly resolved**. The model card states DiT Apache-2.0, but there is still no LICENSE file, and there is the new VividHead "non-commercial" note.

---

## 4. Sources (all accessed 2026-11-24)

**Licences and hashes**

- https://huggingface.co/Lightricks/LTX-Video/blob/main/ltx-video-2b-v0.9.license.txt
- https://huggingface.co/Lightricks/LTX-Video/blob/main/ltx-video-2b-v0.9.1.license.txt
- https://huggingface.co/Lightricks/LTX-Video/blob/main/ltx-video-2b-v0.9.5.license.txt
- https://huggingface.co/Lightricks/LTX-Video/blob/main/LTX-Video-Open-Weights-License-0.X.txt
- HF API `paths-info` for `Lightricks/LTX-Video` `vae/` (commit 05be24f, 2024-12-11) and the `tree` listings of both repos
- https://huggingface.co/Soul-AILab/SoulX-FlashHead-1_3B (README "Component Licenses")
- https://huggingface.co/datasets/Soul-AILab/VividHead
- https://github.com/deepinsight/insightface (README "License")
- https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet (LICENSE)
- https://github.com/madebyollin/taehv (LICENSE, README)
- https://github.com/switchablenorms/CelebAMask-HQ
- https://huggingface.co/jonathandinu/face-parsing
- https://github.com/MRzzm/HDTF
- https://github.com/JDAI-CV/lapa-dataset
- https://huggingface.co/TMElyralab/MuseTalk (NOTICE)
- https://huggingface.co/yzd-v/DWPose
- https://huggingface.co/litert-community (MediaPipe model cards, Apache-2.0 tags)
- https://huggingface.co/hkchengrex/MMAudio
- https://huggingface.co/nvidia/Audio2Emotion-v3.0/blob/main/LICENSE
- https://huggingface.co/nvidia/Audio2Face-3D-v3.0
- https://github.com/duixcom/Duix-Mobile/blob/main/LICENSE

**New models**

- https://github.com/zhangrongxiang/LeapTalk , https://huggingface.co/z-rx/leaptalk , https://zhangrongxiang.github.io/leaptalk-page/
- https://github.com/bigai-nlco/IMTalker , https://huggingface.co/cbsjtu01/IMTalker
- https://github.com/fudan-generative-vision/Hallo-Live
- https://github.com/Kedreamix/Linly-Talker-Stream
- https://github.com/zzzweakman/DuplexAvatar
- https://github.com/NVIDIA/Audio2Face-3D-SDK

**Free GPU**

- https://huggingface.co/docs/hub/spaces-zerogpu
- https://research.google.com/colaboratory/faq.html
- https://lightning.ai/pricing
- https://modal.com/pricing
- https://www.runpod.io/startup-program
- https://vast.ai/article/vast-ai-startup-program
- https://www.nvidia.com/en-us/startups/
- https://learn.microsoft.com/en-us/startups/changes-microsoft-for-startups
- https://gpuperhour.com/blog/free-cloud-gpus-and-credits (2026-09-21) [3P]
- https://aimultiple.com/free-cloud-gpu [3P]
- https://www.usagepricing.com/blueprint/activity/lightning-ai-2026-09-21-gpu-rate-card-reprice [3P]
- https://yangmao.ai/en/compute/paperspace/ [3P]

**Code read locally**

- `avatar-research/repos/{SoulX-FlashHead,honwee_mynah,TMElyralab_MuseTalk,HumanAIGC-Engineering_OpenAvatarChat}`
- `/root/ditto/repo/core/atomic_components/source2info.py`
- `datewiseaiapp/tool/avatar/lp_engine.py`
- `datewiseaiapp/docs/legal/ASSET_PROVENANCE.md`

**Not verified**

- Kaggle's terms (page did not render)
- Kaggle's P100 retirement (third-party only)
- Lightning's free GPU types and current credit model
- Modal's card requirement
- LeapTalk and IMTalker VRAM and fps on consumer GPUs
- IMTalker's training datasets
- UBody's licence
- S3FD/FAN weight licences
