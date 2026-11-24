# COMPARISON: natural voice options for DateWise AI (2026-11-24)

Desk work plus free measurements. Nothing was listened to by a human and no vendor account was opened. "Source" dates are all 2026-11-24 (pages read that day). "Not verified" means I did not find it on an official page this session.

## 0. What customers hear today
App code, not research recordings: `lib/services/voice_service.dart` uses `flutter_tts` (AVSpeechSynthesizer) with per-coach pitch/rate (lines 74-80: Ava 0.98/0.54, Ethan 0.91/0.49, Sofia 1.10/0.46, Diego 0.88/0.45). The native PCM path (`DW_AVATAR_AUDIO_PATH`, voice_service.dart:124) is off by default and still synthesises with Apple voices (AppDelegate.swift:188-194). The Chatterbox/Kokoro files are research only (voice-verify REPORT section 0).

## 1. System voices (a)
| Question | Finding | Source |
|---|---|---|
| Quality ceiling | Default-quality voices sound "much much worse" than Enhanced/Premium (developer report); Premium/Enhanced are 100 MB+ downloads. Even Premium is a pre-neural-era concatenative/older-neural class voice, not a 2026 expressive model. My judgment, not measured: tuning rate/pauses fixes "too fast" but not "robotic" | https://developer.apple.com/forums/thread/758460 ; https://support.apple.com/en-bn/111798 |
| Siri voices | Not offered to third-party apps through AVSpeechSynthesisVoice (the full Siri list is not obtainable) | https://developer.apple.com/forums/thread/676726 |
| Can the app download them? | No API to download Premium/Enhanced or even to detect which are downloadable; users must go to Settings > Accessibility > Spoken Content > Voices. The app can only guide (it already shows a tip) | https://developer.apple.com/forums/thread/787779 ; https://developer.apple.com/forums/thread/758460 |
| How many users have them? | No public statistic found. Assume a minority: it needs a manual, hidden download. State as unknown | none |
| Mexican Spanish | Paulina (es-MX) reported present on iOS 17 and missing on some iOS 18/26 devices; Mexican Siri-neural Spoken Content voices reported "more robotic after iOS 18". Anecdotal | https://developer.apple.com/forums/thread/764438 ; https://discussions-cn-prz.apple.com/thread/255452659 |
| Personal Voice | Not usable (user's own voice, not a coach persona) | task brief |

## 2. Self-hosted open source (b)
| | Kokoro-82M (Apache-2.0) | Chatterbox (MIT) |
|---|---|---|
| English voices | 20 American voices. Grades from the model card: af_heart A, af_bella A-, af_nicole B-, am_michael C+, am_fenrir C+, am_puck C+ (others D to F+) | zero-shot clone from a reference clip (research used Kokoro voices as references) |
| Spanish voices | Exactly 3: ef_dora (F), em_alex (M), em_santa (M). No accent documented anywhere on the model card; espeak-ng "es" default is Spain Spanish. I do NOT claim Mexican. The existing REPORT.md reached the same verdict ("assumed, not evidenced") | Multilingual model; accent comes from the reference clip; no es-MX option |
| Known defects (research, not mine) | Spanish questions come out flat (README notes) | Perth watermark; v1 gaps and mispronunciations fixed in v2; Sofia muffled above 3.2 kHz; Sofia/Diego ECAPA 0.53 (too alike) |
| Naturalness evidence | Artificial Analysis Speech Arena snapshot: Kokoro 82M v1.0 Elo about 1055, 5th among open-weights; same arena snapshots show ElevenLabs v3 about 1173, Cartesia Sonic 3.5 about 1203, OpenAI TTS-1 about 1101 (snapshots from mixed dates, May-June 2026; English-centred) | no arena figure found |
| Speed measured here | 0.73 CPU-s per audio-s per vCPU (1 thread; host loaded). Wall time with 4 threads under load average 13 was 2 to 7x real time, i.e. not usable for judging; 1-thread wall RTF 1.0 to 1.3. A first sentence (about 3 s of audio) therefore takes about 2 s on 1 vCPU. Samples: `samples/` | `samples/kokoro_cpu_time.json`, `kokoro_bench.json` |
| Hosting cost | CPU: about $0.0007/min marginal + $40/month floor (ASSUMPTION server). GPU 4090 community $0.34/h = $248/month (costs-capacity.md); real-time factor on GPU not measured | Needs a GPU for real time; $248/month floor; RTF not measured |
| Streaming | Yields per sentence chunk (the KPipeline generator); app would receive sentence-sized files | Not streaming-native |
| Verdict | Free of vendor risk but Spanish is the weak point (no documented Mexican voice, 1 female, 2 male, flat questions) and ops burden is yours | Heavier, slower, same Spanish accent question; not for v1 |

Sources: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md ; https://artificialanalysis.ai/text-to-speech/leaderboard (via search snapshots) ; /home/user/wt-research/docs/research/voice-verify-2026-11-24/REPORT.md ; avatar-voice-2026-11-24/voices/README.md.

## 3. Hosted options (c)
Naturalness evidence is the weakest column: the only independent source I found is the Artificial Analysis arena (English-centred, snapshots disagree, nothing found for Aura-2, Azure or Polly). Everything else is vendor claim. A listening test with a native Mexican ear is the real decider.

| | Mexican Spanish | English voices | Pace / pauses | Emotion | 4 distinct voices | Latency / streaming | $/1k chars | $/min (900 ch) |
|---|---|---|---|---|---|---|---|---|
| **Workers AI Aura-2** (Deepgram model on the Worker's existing `env.AI`) | Deepgram labels Mexican: sirio (M), javier (M), luciano (M), valerio (M), estrella (F), olivia (F). The Workers AI model page lists 10 speakers: of these sirio, estrella, javier are Mexican; aquila and selena Latin American. So F=estrella, M=sirio/javier | 41 (Deepgram) / 40 (Workers AI list), e.g. thalia, apollo, orion, luna | No rate or SSML parameter in the Workers AI schema; "context-aware pacing" from the text; pauses via punctuation. Weak control | Inferred from text, no style switch | Yes: 2 ES (1F+2M Mexican) and many EN | Real-time capable per the page; no latency figure published there; output a ReadableStream (mp3/linear16/opus...) | $0.030 | $0.027 |
| Deepgram Aura-2 direct | same 6 Mexican voices | 41 | not verified | not verified | yes | vendor says real time | $0.030 PAYG / $0.027 Growth | $0.027 / $0.0243 |
| **Azure Neural** | es-MX is a real locale: Dalia, Jorge (styles cheerful, sad, whispering, excited, chat), plus Beatriz, Candela, Carlota, Larissa, Nuria, Renata, Cecilio, Gerardo, Liberto, Luciano, Pelayo, Yago | Jenny, Aria, Guy, Davis, Jason, Ava, Andrew... many with styles | Full SSML: prosody rate, `<break>`, styles with degree | Yes (mstts:express-as) | Yes, plenty | streaming synthesis; visemes on standard voices (README, not re-verified) | $0.015 | $0.0135 |
| **Azure Neural HD** (DragonHD, MAI-Voice-2) | es-MX Ximena (F), Tristan (M) DragonHD; Valeria (F), Alejo (M) MAI-Voice-2 with styles (happy, sad, whispering...) | 30+ DragonHD (Ava, Andrew, Emma, Jenny, Davis...), MAI Ethan, Harper, Olivia | SSML (styles only on MAI/standard; DragonHD lists none) | MAI yes | yes | Flash variants exist | $0.022 | $0.0198 |
| Google Chirp 3 HD | **es-US and es-ES only, es-MX not listed** | en-US, 30 voices | speaking_rate 0.25-2.0, [pause] tags; SSML not in streaming | limited | yes | streaming PCM/Opus | $0.030 | $0.027 |
| Google Neural2 | es-US (es-MX not verified) | many | SSML prosody | limited | yes | sync | $0.016 | $0.0144 |
| Amazon Polly | es-MX: **Mia (F), Andres (M)** only, both Neural and Generative (Mia Standard) | many (Matthew, Joanna, Ruth, Stephen...) | SSML | Newscaster only (Joanna, Matthew) | exactly 2 ES, enough for 2 ES coaches | sync/streaming | Neural $0.016, Generative $0.030 | $0.0144 / $0.027 |
| OpenAI gpt-4o-mini-tts | No locale selector; accent steered by instructions text, not guaranteed Mexican | built-in voices (count not verified) | speed param + instructions ("speak slowly") | instructions-steerable | yes but same voices for both languages | streaming | token billing ($0.60/M in, $12/M out), OpenAI says about 1.5 cents/min | about $0.015 |
| ElevenLabs | Multilingual v2 / Flash v2.5 support "Spanish (Spain, Mexico)" per docs; voice library accents not verified; **Voice Library voices cannot be used via API on the Free plan** | huge library | pause/speed controls not found on the docs page I read; not verified | v3 audio tags (not verified) | yes | Flash v2.5 about 100 ms (docs) | Flash $0.04, v2 $0.08 | $0.036 / $0.072 |
| Cartesia Sonic | 44 languages; Mexican accent not verified | yes | speed/emotion params claimed, not verified | claimed | yes | under 90 ms first audio (vendor), word timestamps (README) | credits: 1 per char; $38-65/M overage | $0.034-0.059 (Startup plan $0.0353) |
| Hume, PlayHT | shut down per owner's research README (not re-verified) | | | | | | | |

### Free tier and commercial terms
Azure F0 0.5M neural chars/month; Google 1M (Chirp/Neural2); Polly 1M Neural + 100k Generative first 12 months; Deepgram $200 credit; ElevenLabs Free is not commercial (Starter $6 first plan with licence) and gives 10k credits; Cartesia Free 20k, Pro $5 with commercial licence; Workers AI 10k neurons/day (2,727 neurons per 1k Aura-2 chars).

### Privacy and data handling
| Vendor | What I verified | DPA / region |
|---|---|---|
| Workers AI Aura-2 | Model page: "Cloudflare-hosted and has zero data retention" (https://developers.cloudflare.com/workers-ai/models/aura-2-es/). The reply text already goes to the same Cloudflare account for the chat model | Not verified; Cloudflare DPA to read |
| Azure | "Microsoft doesn't retain or store the text" for real-time synthesis; output audio not stored (https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/speech-service/text-to-speech/data-privacy-security); DPA applies | Region selectable |
| Google, Polly, ElevenLabs, Cartesia, OpenAI | Not verified this session. Read each DPA / zero-retention terms before use | |

What DateWise must tell users (not legal advice): the coach's reply text is sent to a third-party processor to make audio; add it to the privacy policy and App Store privacy details, give an in-app on/off with plain wording (default off or ask once), and mark the voice as AI-generated. Note the chat text already goes to Cloudflare, so with Workers AI Aura-2 no new processor is added; any other vendor adds one.

### Sources (all read 2026-11-24)
- https://developers.cloudflare.com/workers-ai/platform/pricing/ ; /models/aura-2-es/ ; /models/aura-2-en/
- https://developers.deepgram.com/docs/tts-models ; https://deepgram.com/pricing
- https://prices.azure.com/api/retail/prices (Neural $15/1M, Neural HD $22/1M meters, eastus); https://azure.microsoft.com/en-us/pricing/details/speech/ (F0 0.5M); https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts
- https://cloud.google.com/text-to-speech/pricing ; https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd
- https://aws.amazon.com/polly/pricing/ ; https://docs.aws.amazon.com/polly/latest/dg/available-voices.html
- https://elevenlabs.io/pricing/api ; https://elevenlabs.io/pricing ; https://elevenlabs.io/docs/overview/capabilities/text-to-speech
- https://cartesia.ai/pricing ; https://cartesia.ai/product/text-to-speech-tts
- https://developers.openai.com/api/docs/models/gpt-4o-mini-tts ; https://community.openai.com/t/new-tts-api-pricing-and-gotchas/1150616
- https://artificialanalysis.ai/text-to-speech/leaderboard
- Apple threads listed in section 1.

## 4. Mexican accent: what only a native Mexican listener can confirm
No model's Mexican accent is proven by me. Vendor-labelled Mexican: Aura-2 (6 voices), Azure es-MX locale voices, Polly es-MX (Mia, Andres). Not documented: Kokoro, Chatterbox, Google Chirp 3 HD (es-US), OpenAI. Play these (include Mexican markers; the coach script is currently neutral):
1. "Ahorita no tengo prisa, ¿quieres platicar un rato?" (ahorita, platicar)
2. "Qué padre que te animaste a salir; la primera cita es lo más difícil." (qué padre, seseo in cita/difícil)
3. "Mejor pídele un café y pregúntale por su familia, nada de presiones." (rhythm, questions)
4. "¿Y si le mandas un mensaje mañana? Nomás dile que la pasaste bien." (nomás, rising question)
5. "Respira. Los nervios solo significan que te importa." (coda s, no aspiration)
6. "Ya estuvo, ya hiciste lo más difícil. Ahora a disfrutar." (idiom)
Ask: Mexican, neutral Latin American, or Spain? Any [θ] or aspirated s? Real person or robot? Do Sofia and Diego sound like two people?
English test (Ava/Ethan): "Hey, I'm really glad you asked. A first date doesn't need to be perfect. Pick somewhere quiet, ask one real question, and let the silence breathe a little. You've got this." Ask: pace right? pauses natural? warm?
