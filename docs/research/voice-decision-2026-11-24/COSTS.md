# COSTS: voice cost per subscriber per month

Reproduce: `python3 costs.py` (writes costs.json; the tables below are its output). Prices are list prices read 2026-11-24 (sources in COMPARISON.md). MEASURED = read from an official page or run here; ASSUMPTION = mine, editable at the top of costs.py.

## Math
- Speech: 900 characters per minute (150 wpm English, 140 wpm Spanish, about 6 characters per word incl. space). $/min = price per character x 900. Aura-2: $0.030 per 1k x 0.9 = $0.027. Azure Neural: $15 per 1M x 900 = $0.0135. ElevenLabs Flash: $0.04 per 1k x 0.9 = $0.036.
- Net revenue per subscriber: $19.99 x 0.85 = $16.99 (Apple 15%) or x 0.70 = $13.99 (Apple 30%). The 3% refund assumption of AI_COST_MODEL.md is not deducted.
- Text AI (Llama 3.3 70B, AI_COST_MODEL.md section 4): $0.00126 per typical message, 2 chat turns per voice minute (that model's ASSUMPTION), floor $0.32 (typical profile): text = max($0.32, 2 x minutes x $0.00126) = $0.32 up to 120 min, $0.76 at 300 min. A heavy text user costs $2.31 in that model: subtract about $2 of headroom from every row if the voice user is also a heavy typist.
- Budget: $4 to $5 TOTAL AI per subscriber (voice + text + avatar). Avatar placeholder: $0 and $1.50, both shown (cell format "avatar0/avatar1.50"; F = within $4, f = within $5 only, X = over $5).
- Self-hosted Kokoro: MEASURED 0.73 CPU-seconds per audio-second per vCPU (this machine, 1 thread, but the host was loaded, load average 13 on 4 cores, so conservative). A 4-vCPU server at $40/month (ASSUMPTION; Hetzner dedicated-vCPU plans start at EUR 36.99, hetzner.com/cloud, 2026-11-24) gives 4 x 730 x 60 x 25% duty / 0.73 = about 60,000 audio-minutes a month: $0.0007/min marginal. The $40 floor is paid from subscriber 1 and peak concurrency, not average load, sets the server count. GPU rows (Kokoro/Chatterbox on a 4090, $0.34/h community = $248/month always-on, costs-capacity.md) are not computed per minute because no GPU was available to measure real-time factor.

## Fixed fees, free tiers, minimum commitments, licences
| Option | Free tier (service-wide, not per subscriber) | Fixed / minimum | Licence note |
|---|---|---|---|
| System voice | n/a | none | Apple |
| Workers AI Aura-2 | 10,000 neurons/day shared with chat = about 3,600 chars/day (about 4 audio-min/day) | Workers Paid $5/month is needed anyway above about 10 typical subscribers (AI_COST_MODEL.md) | Deepgram terms, hosted by Cloudflare |
| Deepgram direct | $200 one-off credit, no card | none on PAYG | Deepgram terms |
| Azure Neural / HD | F0: 0.5M neural chars/month (about 555 min); HD not in free tier per the pricing page | none on PAYG; commitment tiers (80M chars $960/month for Neural) only pay off at huge volume | Microsoft |
| Google | Chirp 3 HD 1M chars/month; Neural2 1M | none | Google |
| Polly | Neural 1M, Generative 100k, first 12 months only | none | AWS |
| OpenAI | none | none | OpenAI |
| ElevenLabs | Free 10k credits/month, NOT commercial; Starter $6 is the first plan with the commercial licence (75k chars = 83 min) | at 1,000 subscribers x 60 min = 60M chars: Business tier territory; use PAYG list price as the model does | ElevenLabs terms |
| Cartesia | Free 20k credits; Pro $5 = 100k credits (111 min), commercial included | Startup $49/month = 1.25M credits (1,389 min) | Cartesia terms |
| Kokoro | none | server $40/month floor (CPU) | Apache-2.0 |
| Chatterbox | none | GPU $248/month floor | MIT (Perth watermark stays on) |

## Tables (output of costs.py)

Kokoro CPU-seconds per audio-second used: 0.732

| Option | $/min | 15 min | 30 min | 60 min | 120 min | 300 min |
|---|---|---|---|---|---|---|
| System voice (today) | $0.0000 | $0.00 | $0.00 | $0.00 | $0.00 | $0.00 |
| CF Workers AI Aura-2 (en+es) | $0.0270 | $0.40 | $0.81 | $1.62 | $3.24 | $8.10 |
| Deepgram Aura-2 direct | $0.0243 | $0.36 | $0.73 | $1.46 | $2.92 | $7.29 |
| Azure Neural (Dalia/Jorge, Jenny/Guy) | $0.0135 | $0.20 | $0.40 | $0.81 | $1.62 | $4.05 |
| Azure Neural HD (DragonHD/MAI) | $0.0198 | $0.30 | $0.59 | $1.19 | $2.38 | $5.94 |
| Google Chirp 3 HD (es-US, no es-MX) | $0.0270 | $0.40 | $0.81 | $1.62 | $3.24 | $8.10 |
| Google Neural2 | $0.0144 | $0.22 | $0.43 | $0.86 | $1.73 | $4.32 |
| Amazon Polly Neural (Mia/Andres) | $0.0144 | $0.22 | $0.43 | $0.86 | $1.73 | $4.32 |
| Amazon Polly Generative (Mia/Andres) | $0.0270 | $0.40 | $0.81 | $1.62 | $3.24 | $8.10 |
| OpenAI gpt-4o-mini-tts | $0.0150 | $0.22 | $0.45 | $0.90 | $1.80 | $4.50 |
| ElevenLabs Flash v2.5 (API list) | $0.0360 | $0.54 | $1.08 | $2.16 | $4.32 | $10.80 |
| ElevenLabs Multilingual v2 | $0.0720 | $1.08 | $2.16 | $4.32 | $8.64 | $21.60 |
| Cartesia Sonic (Startup plan rate) | $0.0353 | $0.53 | $1.06 | $2.12 | $4.23 | $10.58 |
| Kokoro-82M self-hosted, CPU | $0.0007 | $0.01 | $0.02 | $0.04 | $0.08 | $0.20 |
| Kokoro-82M self-hosted, 4090 GPU | n/m | n/m | n/m | n/m | n/m | n/m |
| Chatterbox (MIT) self-hosted, 4090 | n/m | n/m | n/m | n/m | n/m | n/m |

Remaining revenue per subscriber per month after Apple and voice (before text AI), 15% / 30% Apple:
| Option | 15 min | 30 min | 60 min | 120 min | 300 min |
|---|---|---|---|---|---|
| System voice (today) | 16.99 / 13.99 | 16.99 / 13.99 | 16.99 / 13.99 | 16.99 / 13.99 | 16.99 / 13.99 |
| CF Workers AI Aura-2 (en+es) | 16.59 / 13.59 | 16.18 / 13.18 | 15.37 / 12.37 | 13.75 / 10.75 | 8.89 / 5.89 |
| Deepgram Aura-2 direct | 16.63 / 13.63 | 16.26 / 13.26 | 15.53 / 12.53 | 14.08 / 11.08 | 9.70 / 6.70 |
| Azure Neural (Dalia/Jorge, Jenny/Guy) | 16.79 / 13.79 | 16.59 / 13.59 | 16.18 / 13.18 | 15.37 / 12.37 | 12.94 / 9.94 |
| Azure Neural HD (DragonHD/MAI) | 16.69 / 13.70 | 16.40 / 13.40 | 15.80 / 12.80 | 14.62 / 11.62 | 11.05 / 8.05 |
| Google Chirp 3 HD (es-US, no es-MX) | 16.59 / 13.59 | 16.18 / 13.18 | 15.37 / 12.37 | 13.75 / 10.75 | 8.89 / 5.89 |
| Google Neural2 | 16.78 / 13.78 | 16.56 / 13.56 | 16.13 / 13.13 | 15.26 / 12.26 | 12.67 / 9.67 |
| Amazon Polly Neural (Mia/Andres) | 16.78 / 13.78 | 16.56 / 13.56 | 16.13 / 13.13 | 15.26 / 12.26 | 12.67 / 9.67 |
| Amazon Polly Generative (Mia/Andres) | 16.59 / 13.59 | 16.18 / 13.18 | 15.37 / 12.37 | 13.75 / 10.75 | 8.89 / 5.89 |
| OpenAI gpt-4o-mini-tts | 16.77 / 13.77 | 16.54 / 13.54 | 16.09 / 13.09 | 15.19 / 12.19 | 12.49 / 9.49 |
| ElevenLabs Flash v2.5 (API list) | 16.45 / 13.45 | 15.91 / 12.91 | 14.83 / 11.83 | 12.67 / 9.67 | 6.19 / 3.19 |
| ElevenLabs Multilingual v2 | 15.91 / 12.91 | 14.83 / 11.83 | 12.67 / 9.67 | 8.35 / 5.35 | -4.61 / -7.61 |
| Cartesia Sonic (Startup plan rate) | 16.46 / 13.46 | 15.93 / 12.93 | 14.87 / 11.88 | 12.76 / 9.76 | 6.41 / 3.41 |
| Kokoro-82M self-hosted, CPU | 16.98 / 13.98 | 16.97 / 13.97 | 16.95 / 13.95 | 16.91 / 13.91 | 16.79 / 13.79 |
| Kokoro-82M self-hosted, 4090 GPU | n/m | n/m | n/m | n/m | n/m |
| Chatterbox (MIT) self-hosted, 4090 | n/m | n/m | n/m | n/m | n/m |

Text AI per subscriber (typical rate; floor $0.32): 15 min: $0.32, 30 min: $0.32, 60 min: $0.32, 120 min: $0.32, 300 min: $0.76

Total AI (voice + text) per subscriber; avatar $0 | $1.50; F = fits $4 budget, f = fits $5 only, X = over $5
| Option | 15 min | 30 min | 60 min | 120 min | 300 min |
|---|---|---|---|---|---|
| System voice (today) | 0.32 F/1.82 F | 0.32 F/1.82 F | 0.32 F/1.82 F | 0.32 F/1.82 F | 0.76 F/2.26 F |
| CF Workers AI Aura-2 (en+es) | 0.72 F/2.23 F | 1.13 F/2.63 F | 1.94 F/3.44 F | 3.56 F/5.06 X | 8.86 X/10.36 X |
| Deepgram Aura-2 direct | 0.68 F/2.18 F | 1.05 F/2.55 F | 1.78 F/3.28 F | 3.24 F/4.74 f | 8.05 X/9.55 X |
| Azure Neural (Dalia/Jorge, Jenny/Guy) | 0.52 F/2.02 F | 0.72 F/2.23 F | 1.13 F/2.63 F | 1.94 F/3.44 F | 4.81 f/6.31 X |
| Azure Neural HD (DragonHD/MAI) | 0.62 F/2.12 F | 0.91 F/2.41 F | 1.51 F/3.01 F | 2.70 F/4.20 f | 6.70 X/8.20 X |
| Google Chirp 3 HD (es-US, no es-MX) | 0.72 F/2.23 F | 1.13 F/2.63 F | 1.94 F/3.44 F | 3.56 F/5.06 X | 8.86 X/10.36 X |
| Google Neural2 | 0.54 F/2.04 F | 0.75 F/2.25 F | 1.18 F/2.68 F | 2.05 F/3.55 F | 5.08 X/6.58 X |
| Amazon Polly Neural (Mia/Andres) | 0.54 F/2.04 F | 0.75 F/2.25 F | 1.18 F/2.68 F | 2.05 F/3.55 F | 5.08 X/6.58 X |
| Amazon Polly Generative (Mia/Andres) | 0.72 F/2.23 F | 1.13 F/2.63 F | 1.94 F/3.44 F | 3.56 F/5.06 X | 8.86 X/10.36 X |
| OpenAI gpt-4o-mini-tts | 0.54 F/2.04 F | 0.77 F/2.27 F | 1.22 F/2.72 F | 2.12 F/3.62 F | 5.26 X/6.76 X |
| ElevenLabs Flash v2.5 (API list) | 0.86 F/2.36 F | 1.40 F/2.90 F | 2.48 F/3.98 F | 4.64 f/6.14 X | 11.56 X/13.06 X |
| ElevenLabs Multilingual v2 | 1.40 F/2.90 F | 2.48 F/3.98 F | 4.64 f/6.14 X | 8.96 X/10.46 X | 22.36 X/23.86 X |
| Cartesia Sonic (Startup plan rate) | 0.85 F/2.35 F | 1.38 F/2.88 F | 2.44 F/3.94 F | 4.55 f/6.05 X | 11.34 X/12.84 X |
| Kokoro-82M self-hosted, CPU | 0.33 F/1.83 F | 0.34 F/1.84 F | 0.36 F/1.86 F | 0.40 F/1.90 F | 0.96 F/2.46 F |

