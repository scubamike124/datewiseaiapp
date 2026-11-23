# DateWise AI: AI usage cost model and subscription profitability

Status: Phase 1 audit (read-only) plus the evaluation of price points. Nothing here changes the price,
StoreKit, the paywall or entitlements. The configured price stays **$9.99/month, Apple IAP only**.

Every figure is labelled:
- **MEASURED**: read from an official price page (URL and date below) or from the code at a named commit.
- **ASSUMPTION**: an estimate, with the reasoning given. Replace these with real usage figures once the cost guard's
  count-only logs exist (see Phase 2).

Prices were checked on **2026-11-22**. The tables are produced by `docs/business/ai_cost_model.mjs`
(`node docs/business/ai_cost_model.mjs`). Change an assumption there and re-run it; do not edit the numbers by hand.

## 1. What the code actually calls

| Item | Finding | Label |
|---|---|---|
| Chat model (chat-v6 code, commit `f5b0401`, `backend/worker.js`; **not deployed**, see the next rows) | `@cf/meta/llama-3.3-70b-instruct-fp8-fast` (`CHAT_MODEL = TEXT_MODEL`), streamed, `max_tokens: 800` | MEASURED (code) |
| Photo coach (same Worker) | `@cf/meta/llama-3.2-11b-vision-instruct`, plus Llama 3.3 as a JSON converter fallback. The v2 app sends no photos: `lib/` on `claude/datewise-v2-app` has no `imageBase64` sender, and `storage_service.dart` only purges v1 photo data. **The live App Store build does use it.** That is v1 1.0.2 on `main`, whose `lib/services/backend_ai_service.dart` posts `imageBase64` (single photo) and `images` (rank and compare) with `tier`/`mode`. Its chat sends `messages` with its own system prompt and no `coachId`. The photo coach keeps costing money for as long as 1.0.2 is installed. chat-v7 keeps both v1 paths while `LEGACY_CLIENTS=1`. 1.0.2 never sends a StoreKit token, so its requests are counted per network (IPv4 address or IPv6 /64) and draw on the anonymous budget slice (section 9, "v1 capacity") | MEASURED (code) |
| Branch `claude/datewise-v2-app` (base of this work) | Still holds the older chat-v5 worker with `@cf/meta/llama-3.1-8b-instruct-fp8`, which Workers AI retired on 2026-11-20 (HTTP 410). | MEASURED (code) |
| **Production Worker (as of 2026-11-23)** | Still **chat-v5**: it calls the retired `@cf/meta/llama-3.1-8b-instruct-fp8`, so every chat request fails with **502** (Workers AI 410). chat-v6 (`f5b0401`) was approved for deploy but is **not live**; neither is chat-v7. The costs below describe the chat-v6/v7 code once deployed, not today's production | MEASURED (infrastructure check, 2026-11-23) |
| Chat input caps (chat-v6) | 24 turns, 24,000 characters of history (newest kept), each message cut to 6,000 characters, plus the system message. The worst case is about 30,000 characters of input | MEASURED (code) |
| System prompt size | 1,921 to 2,004 characters per coach (measured by running `CoachPersona.systemPrompt` for all four coaches), plus about 200 to 400 for the profile line | MEASURED (code run) |
| Branch `origin/claude/worker-model-fallback` (chat-v8, not deployed) | Ordered `CHAT_MODELS` list. The default is Llama 3.3 70B, then `@cf/google/gemma-4-26b-a4b-it`. It also knows `@cf/qwen/qwen3.8-27b` and `@cf/deepseek-ai/deepseek-v4.1-flash-1017`, which is `paidOnly`. All four are **Workers AI** models on the same `env.AI` binding | MEASURED (code) |
| Other AI providers | None. There is no OpenAI, Gemini, Anthropic, Groq or other key or `fetch` to an AI host in `worker.js` on `f5b0401`, `claude/datewise-v2-app` or `claude/worker-model-fallback`. Only `backend/README.md` still describes an old Gemini design. That file is stale documentation, not code | MEASURED (code, `git grep`) |
| Keys in the app | None. The app only knows the Worker's public HTTPS URL (`lib/services/backend_ai_service.dart`, `ai_config.dart`) | MEASURED (code) |
| Voice | Text-to-speech: `flutter_tts` (`lib/services/voice_service.dart`), which uses iOS AVSpeechSynthesizer on the device. Speech-to-text: `speech_to_text` with `onDevice: true` (`lib/services/speech_service.dart`, line 136), which uses SFSpeechRecognizer on the device. No audio is sent to the Worker, and no Workers AI audio model (Whisper, MeloTTS, Aura) is called anywhere, so **speech processing costs $0**. Voice is **not free per turn**, though. Every spoken turn is sent to the Worker as an ordinary chat message (`lib/screens/chat_screen.dart` `_finishListening` → `_send`), and the coach's spoken answer is that chat reply read aloud (`_voice.speak`, line 113). **A voice turn costs exactly what a typed message costs.** The chat-v7 guard counts every message the same way, whatever its source, so voice cannot get around the caps | MEASURED (code) |

### Audit: could any paid fallback ever bill?

| Path | Can it bill? | Label |
|---|---|---|
| Workers AI on the **Workers Free** plan | **No.** Above 10,000 neurons a day, calls fail with an error. Cloudflare says Workers Free is "N/A - Upgrade to Workers Paid" | MEASURED (pricing page) |
| Workers AI on **Workers Paid** | **Yes.** Every neuron above 10,000 a day is billed at $0.011 per 1,000, with no cap by default. This applies to every model above, the fallbacks included | MEASURED |
| `deepseek-v4.1-flash-1017` (chat-v8 `paidOnly`) | Only on Workers Paid or with prepaid AI Gateway credits. On Free it errors and chat-v8 moves to the next model | MEASURED |
| AI Gateway unified billing | Only if someone buys credits and routes the binding through a gateway. No code does this today | MEASURED (code) |
| `.github/workflows/coach-monitor.yml` (chat-v8 branch, hourly once on `main`) | It sends 48 real chat requests a day, about 3,800 neurons a day: **about 38% of the free daily allowance** (the token figures are an ASSUMPTION). On Paid that is about $1.25 a month | MEASURED (code); cost is an ASSUMPTION |
| `.github/workflows/model-eval.yml` (chat-v8 branch) | It runs 4 models x 4 coaches x 3 scenarios = 48 real calls on every PR that touches `backend/`, via the Cloudflare REST API with the account token. These use the same account allowance or bill. It is not on `claude/datewise-v2-app`, so this PR does not trigger it | MEASURED (code) |
| Voice | Speech processing makes no server call. Each spoken turn is one chat request, billed like a typed message (above) | MEASURED (code) |

**Conclusion:** the only way money can be spent is Workers AI usage on a Workers Paid account. Moving to
Workers Paid ($5/month) is itself a spending increase that needs the owner's authorization. The cost guard's
default global budget (Phase 2) is the free 10,000 neurons a day, so it spends $0 until the owner raises it.

## 2. Pricing sources (checked 2026-11-22)

| Fact | Value | Source | Label |
|---|---|---|---|
| Workers AI price | $0.011 per 1,000 neurons | https://developers.cloudflare.com/workers-ai/platform/pricing/ | MEASURED |
| Free allowance | 10,000 neurons a day on Free and Paid, reset at 00:00 UTC. On Free, usage above it fails with an error | same | MEASURED |
| Llama 3.3 70B fp8-fast | $0.293 per M input tokens (26,668 neurons) and $2.253 per M output tokens (204,805 neurons) | same | MEASURED |
| Llama 3.2 11B Vision | $0.049 per M input (4,410 neurons) and $0.676 per M output (61,493 neurons) | same | MEASURED |
| Gemma 4 26B A4B | $0.100 per M input (9,091 neurons) and $0.300 per M output (27,273 neurons) | same | MEASURED |
| Qwen 3.8 27B | $0.450 per M input (40,909 neurons) and $3.200 per M output (290,909 neurons) | same | MEASURED |
| DeepSeek V4.1 Flash | $0.300 per M input (27,273 neurons) and $1.200 per M output (109,091 neurons). Needs Workers Paid or AI Gateway credits | same | MEASURED |
| Workers AI rate limit | Text generation: 300 requests a minute, unless the model requires Workers Paid | https://developers.cloudflare.com/workers-ai/platform/limits/ | MEASURED |
| Workers Free | 100,000 requests a day and 10 ms of CPU per invocation | https://developers.cloudflare.com/workers/platform/pricing/ | MEASURED |
| Workers Paid | $5 a month minimum. Includes 10 M requests a month (+$0.30 per M) and 30 M CPU-ms (+$0.02 per M) | same | MEASURED |
| Workers KV, Free | 100,000 reads a day, 1,000 writes a day, 1 GB | same (Workers KV section) | MEASURED |
| Workers KV, Paid | 10 M reads a month (+$0.50 per M) and 1 M writes a month (+$5 per M) | same | MEASURED |
| Durable Objects, Free | SQLite-backed only. 100,000 requests a day, 13,000 GB-s a day, 5 M rows read a day, 100,000 rows written a day, 5 GB total | https://developers.cloudflare.com/durable-objects/platform/pricing/ | MEASURED |
| Durable Objects, Paid | 1 M requests a month (+$0.15 per M), 400,000 GB-s (+$12.50 per M GB-s), 25 B rows read, 50 M rows written (+$1 per M), 5 GB-month (+$0.20 per GB-month) | same | MEASURED |
| D1, Free and Paid | Free: 5 M rows read a day, 100,000 rows written a day, 5 GB. Paid: 25 B rows read and 50 M rows written a month included, +$0.75 per GB-month | https://developers.cloudflare.com/d1/platform/pricing/ | MEASURED |
| Rate Limiting binding | Approximate and counted per Cloudflare location. The page states no price or plan restriction | https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/ | MEASURED (no price shown); free availability is an ASSUMPTION |
| Apple Small Business Program | 15% commission for developers with up to $1 M of proceeds in the prior calendar year | https://developer.apple.com/app-store/small-business-program/ | MEASURED |
| Apple standard subscription rate | 70% of the price in a subscriber's first year, 85% after one year of paid service. Small Business Program members get 85% from the start. Proceeds are after applicable taxes | https://developer.apple.com/app-store/subscriptions/ ("85% net revenue after one year") | MEASURED |
| Apple Developer Program | 99 USD a membership year, about $8.25 a month | https://developer.apple.com/programs/whats-included/ | MEASURED |
| Billing retry and grace period | The App Store retries a failed renewal for up to 60 days. The optional Billing Grace Period for monthly plans is 3, 16 or 28 days | https://developer.apple.com/documentation/storekit/reducing-involuntary-subscriber-churn | MEASURED |
| Refunds | Apple publishes no rate. **Assumed 3% of proceeds are reversed** | none | ASSUMPTION |
| Taxes | The model uses the US price, so commission applies to $9.99. In VAT countries, proceeds are calculated on the price minus VAT (about 17% less in most EU countries) | Apple subscriptions page ("minus applicable taxes") | MEASURED rule; mix is an ASSUMPTION |
| Hosting (site, legal pages) | Cloudflare Pages and Netlify free tiers, already in use. The domain fee is not counted | `netlify.toml`, worker CORS list | ASSUMPTION ($0) |

## 3. Usage assumptions

| Profile | Messages | Input tokens per message | Output tokens per message | Voice | Label |
|---|---|---|---|---|---|
| Light | 3 a day x 20 days = 60 a month | 1,200 (a 2,000-character system prompt plus a short history, about 4 characters per token) | 250 | counted as chat turns: about 2 turns per voice minute | ASSUMPTION |
| Typical | 10 a day x 25 days = 250 a month | 2,000 | 300 | counted as chat turns: about 2 turns per voice minute | ASSUMPTION |
| Heavy | 40 a day x 30 days = 1,200 a month | 3,500 (long conversations) | 400 | counted as chat turns: about 2 turns per voice minute | ASSUMPTION |
| Worst case per request, chat-v6 | n/a | about 7,500 for English (30,000 characters). Up to the model's 24k context for text that tokenizes badly | 800 (the `max_tokens` cap) | n/a | MEASURED caps; token ratio is an ASSUMPTION |
| Worst case per request, chat-v7 guard | n/a | 6,000 estimated tokens (`MAX_INPUT_TOKENS`, estimated as UTF-8 bytes / 3, which over-counts) | 800 (`MAX_OUTPUT_TOKENS`) | n/a | MEASURED (new code) |

Other inputs to the model: commission of 15% (Small Business Program) or 30% (the standard first-year rate), 3% refunds,
Workers Paid $5 whenever usage exceeds 10,000 neurons a day, the Apple Developer Program $8.25 a month,
4 Durable Object requests per chat message (the guard design), and 5 ms of CPU per request (ASSUMPTION).

## 4. Cost per customer at $9.99 (the configured price)

| Model | Usage | Tokens in/out per msg (ASSUMPTION) | Msgs/month (ASSUMPTION) | $/msg | Neurons/msg | AI $/subscriber/month (list price, before free allowance) |
|---|---|---|---|---|---|---|
| Llama 3.3 70B fp8-fast | light (3 msgs/day x 20 days) | 1200 / 250 | 60 | $0.00091 | 83.2 | $0.05 |
| Llama 3.3 70B fp8-fast | typical (10 msgs/day x 25 days) | 2000 / 300 | 250 | $0.00126 | 114.8 | $0.32 |
| Llama 3.3 70B fp8-fast | heavy (40 msgs/day x 30 days) | 3500 / 400 | 1200 | $0.00193 | 175.3 | $2.31 |
| Gemma 4 26B | light (3 msgs/day x 20 days) | 1200 / 250 | 60 | $0.00019 | 17.7 | $0.01 |
| Gemma 4 26B | typical (10 msgs/day x 25 days) | 2000 / 300 | 250 | $0.00029 | 26.4 | $0.07 |
| Gemma 4 26B | heavy (40 msgs/day x 30 days) | 3500 / 400 | 1200 | $0.00047 | 42.7 | $0.56 |

All rows: AI cost = tokens x MEASURED list price; usage = ASSUMPTION. Voice is included in the message counts. At about 2 turns per voice minute (ASSUMPTION: about 10 s speaking, then about 20 s of the reply read aloud), one voice minute costs about 2 typical messages: **$0.0025 on Llama 3.3** ($0.0006 on Gemma 4). Ten voice minutes a day for 25 days is about 500 turns, $0.63 a month. The cost per customer
including infrastructure, for 100 to 5,000 subscribers, is the "Cost/customer" column in section 5: about $0.06 (light),
$0.32 (typical) and $2.32 (heavy) a month on Llama 3.3. At 100 subscribers the fixed $5 Workers Paid fee adds about
$0.05 a subscriber.

### Capacity on the free allowance only (no Workers Paid)
- Llama 3.3 70B fp8-fast, light: 120 msgs/day for the whole service, about 60 subscribers.
- Llama 3.3 70B fp8-fast, typical: 87 msgs/day for the whole service, about 10 subscribers.
- Llama 3.3 70B fp8-fast, heavy: 57 msgs/day for the whole service, about 1 subscribers.
- Gemma 4 26B, light: 564 msgs/day for the whole service, about 282 subscribers.
- Gemma 4 26B, typical: 379 msgs/day for the whole service, about 45 subscribers.
- Gemma 4 26B, heavy: 234 msgs/day for the whole service, about 5 subscribers.

Result: **the free allowance alone supports about 10 typical subscribers on Llama 3.3 (about 45 on Gemma 4).** At
100 or more subscribers, Workers Paid ($5 a month plus neurons) is required. That is a spending increase the owner
must approve first (MEASURED prices; usage is an ASSUMPTION).

## 5. Price-point scenarios

Evaluation only. $9.99 stays the configured price, and StoreKit, the paywall and entitlements are unchanged.
Model: Llama 3.3 70B fp8-fast (the chat-v6/v7 chat model, MEASURED; production still runs chat-v5, which fails with 502). Every row is derived from MEASURED prices and
ASSUMPTION usage and refunds. "Infra" is Workers Paid $5 (needed in **every** row below, because even 100 light
subscribers use about 25,000 neurons a day, above the free 10,000) plus Worker and Durable Object overage. Profit also
subtracts the Apple Developer Program fee ($8.25 a month).

#### $9.99 / month
Monthly net profit = subscribers x price x (1 - commission) x (1 - 3% refunds) - AI (Llama 3.3, after the 10k neurons/day free allowance) - infrastructure (Workers Paid $5 when needed + overage) - Apple Developer Program $8.25. All results are derived from MEASURED prices and the ASSUMPTION usage profiles above.

| Subscribers | Usage | Net proceeds @15% | Net proceeds @30% | AI cost | Infra | Cost/customer | Profit @15% | Profit @30% | Margin @30% |
|---|---|---|---|---|---|---|---|---|---|
| 100 | light | $823.68 | $678.32 | $2.19 | $5.00 | $0.154 | $808.23 | $662.88 | 97.7% |
| 100 | typical | $823.68 | $678.32 | $28.26 | $5.00 | $0.415 | $782.16 | $636.81 | 93.9% |
| 100 | heavy | $823.68 | $678.32 | $228.04 | $5.00 | $2.413 | $582.38 | $437.03 | 64.4% |
| 500 | light | $4118.38 | $3391.61 | $24.16 | $5.00 | $0.075 | $4080.97 | $3354.20 | 98.9% |
| 500 | typical | $4118.38 | $3391.61 | $154.52 | $5.00 | $0.336 | $3950.61 | $3223.84 | 95.1% |
| 500 | heavy | $4118.38 | $3391.61 | $1153.42 | $5.21 | $2.334 | $2951.50 | $2224.73 | 65.6% |
| 1000 | light | $8236.75 | $6783.21 | $51.61 | $5.00 | $0.065 | $8171.89 | $6718.35 | 99.0% |
| 1000 | typical | $8236.75 | $6783.21 | $312.34 | $5.00 | $0.326 | $7911.17 | $6457.62 | 95.2% |
| 1000 | heavy | $8236.75 | $6783.21 | $2310.13 | $5.57 | $2.324 | $5912.80 | $4459.26 | 65.7% |
| 5000 | light | $41183.78 | $33916.05 | $271.27 | $5.03 | $0.057 | $40899.23 | $33631.50 | 99.2% |
| 5000 | typical | $41183.78 | $33916.05 | $1574.89 | $5.60 | $0.318 | $39595.03 | $32327.31 | 95.3% |
| 5000 | heavy | $41183.78 | $33916.05 | $11563.86 | $8.45 | $2.316 | $29603.22 | $22335.49 | 65.9% |

#### $14.99 / month
Monthly net profit = subscribers x price x (1 - commission) x (1 - 3% refunds) - AI (Llama 3.3, after the 10k neurons/day free allowance) - infrastructure (Workers Paid $5 when needed + overage) - Apple Developer Program $8.25. All results are derived from MEASURED prices and the ASSUMPTION usage profiles above.

| Subscribers | Usage | Net proceeds @15% | Net proceeds @30% | AI cost | Infra | Cost/customer | Profit @15% | Profit @30% | Margin @30% |
|---|---|---|---|---|---|---|---|---|---|
| 100 | light | $1235.93 | $1017.82 | $2.19 | $5.00 | $0.154 | $1220.48 | $1002.38 | 98.5% |
| 100 | typical | $1235.93 | $1017.82 | $28.26 | $5.00 | $0.415 | $1194.41 | $976.31 | 95.9% |
| 100 | heavy | $1235.93 | $1017.82 | $228.04 | $5.00 | $2.413 | $994.63 | $776.53 | 76.3% |
| 500 | light | $6179.63 | $5089.10 | $24.16 | $5.00 | $0.075 | $6142.22 | $5051.70 | 99.3% |
| 500 | typical | $6179.63 | $5089.10 | $154.52 | $5.00 | $0.336 | $6011.86 | $4921.34 | 96.7% |
| 500 | heavy | $6179.63 | $5089.10 | $1153.42 | $5.21 | $2.334 | $5012.75 | $3922.23 | 77.1% |
| 1000 | light | $12359.25 | $10178.21 | $51.61 | $5.00 | $0.065 | $12294.39 | $10113.35 | 99.4% |
| 1000 | typical | $12359.25 | $10178.21 | $312.34 | $5.00 | $0.326 | $12033.67 | $9852.62 | 96.8% |
| 1000 | heavy | $12359.25 | $10178.21 | $2310.13 | $5.57 | $2.324 | $10035.30 | $7854.26 | 77.2% |
| 5000 | light | $61796.28 | $50891.05 | $271.27 | $5.03 | $0.057 | $61511.73 | $50606.50 | 99.4% |
| 5000 | typical | $61796.28 | $50891.05 | $1574.89 | $5.60 | $0.318 | $60207.53 | $49302.31 | 96.9% |
| 5000 | heavy | $61796.28 | $50891.05 | $11563.86 | $8.45 | $2.316 | $50215.71 | $39310.49 | 77.2% |

#### $19.99 / month
Monthly net profit = subscribers x price x (1 - commission) x (1 - 3% refunds) - AI (Llama 3.3, after the 10k neurons/day free allowance) - infrastructure (Workers Paid $5 when needed + overage) - Apple Developer Program $8.25. All results are derived from MEASURED prices and the ASSUMPTION usage profiles above.

| Subscribers | Usage | Net proceeds @15% | Net proceeds @30% | AI cost | Infra | Cost/customer | Profit @15% | Profit @30% | Margin @30% |
|---|---|---|---|---|---|---|---|---|---|
| 100 | light | $1648.18 | $1357.32 | $2.19 | $5.00 | $0.154 | $1632.73 | $1341.88 | 98.9% |
| 100 | typical | $1648.18 | $1357.32 | $28.26 | $5.00 | $0.415 | $1606.66 | $1315.81 | 96.9% |
| 100 | heavy | $1648.18 | $1357.32 | $228.04 | $5.00 | $2.413 | $1406.88 | $1116.03 | 82.2% |
| 500 | light | $8240.88 | $6786.60 | $24.16 | $5.00 | $0.075 | $8203.47 | $6749.20 | 99.4% |
| 500 | typical | $8240.88 | $6786.60 | $154.52 | $5.00 | $0.336 | $8073.11 | $6618.84 | 97.5% |
| 500 | heavy | $8240.88 | $6786.60 | $1153.42 | $5.21 | $2.334 | $7074.00 | $5619.73 | 82.8% |
| 1000 | light | $16481.76 | $13573.21 | $51.61 | $5.00 | $0.065 | $16416.89 | $13508.35 | 99.5% |
| 1000 | typical | $16481.76 | $13573.21 | $312.34 | $5.00 | $0.326 | $16156.17 | $13247.62 | 97.6% |
| 1000 | heavy | $16481.76 | $13573.21 | $2310.13 | $5.57 | $2.324 | $14157.80 | $11249.26 | 82.9% |
| 5000 | light | $82408.77 | $67866.05 | $271.27 | $5.03 | $0.057 | $82124.23 | $67581.50 | 99.6% |
| 5000 | typical | $82408.77 | $67866.05 | $1574.89 | $5.60 | $0.318 | $80820.03 | $66277.31 | 97.7% |
| 5000 | heavy | $82408.77 | $67866.05 | $11563.86 | $8.45 | $2.316 | $70828.21 | $56285.49 | 82.9% |

#### $24.99 / month
Monthly net profit = subscribers x price x (1 - commission) x (1 - 3% refunds) - AI (Llama 3.3, after the 10k neurons/day free allowance) - infrastructure (Workers Paid $5 when needed + overage) - Apple Developer Program $8.25. All results are derived from MEASURED prices and the ASSUMPTION usage profiles above.

| Subscribers | Usage | Net proceeds @15% | Net proceeds @30% | AI cost | Infra | Cost/customer | Profit @15% | Profit @30% | Margin @30% |
|---|---|---|---|---|---|---|---|---|---|
| 100 | light | $2060.43 | $1696.82 | $2.19 | $5.00 | $0.154 | $2044.98 | $1681.38 | 99.1% |
| 100 | typical | $2060.43 | $1696.82 | $28.26 | $5.00 | $0.415 | $2018.91 | $1655.31 | 97.6% |
| 100 | heavy | $2060.43 | $1696.82 | $228.04 | $5.00 | $2.413 | $1819.13 | $1455.53 | 85.8% |
| 500 | light | $10302.13 | $8484.10 | $24.16 | $5.00 | $0.075 | $10264.72 | $8446.70 | 99.6% |
| 500 | typical | $10302.13 | $8484.10 | $154.52 | $5.00 | $0.336 | $10134.36 | $8316.34 | 98.0% |
| 500 | heavy | $10302.13 | $8484.10 | $1153.42 | $5.21 | $2.334 | $9135.25 | $7317.23 | 86.2% |
| 1000 | light | $20604.26 | $16968.21 | $51.61 | $5.00 | $0.065 | $20539.39 | $16903.35 | 99.6% |
| 1000 | typical | $20604.26 | $16968.21 | $312.34 | $5.00 | $0.326 | $20278.67 | $16642.62 | 98.1% |
| 1000 | heavy | $20604.26 | $16968.21 | $2310.13 | $5.57 | $2.324 | $18280.30 | $14644.26 | 86.3% |
| 5000 | light | $103021.27 | $84841.05 | $271.27 | $5.03 | $0.057 | $102736.73 | $84556.50 | 99.7% |
| 5000 | typical | $103021.27 | $84841.05 | $1574.89 | $5.60 | $0.318 | $101432.53 | $83252.31 | 98.1% |
| 5000 | heavy | $103021.27 | $84841.05 | $11563.86 | $8.45 | $2.316 | $91440.71 | $73260.49 | 86.4% |

### Break-even, affordable AI cost and allowances per price point
| Price | Commission | Net per subscriber after refunds | Break-even subscribers (heavy usage, Workers Paid + Apple fee) | Max AI+infra per subscriber at 70% gross margin | Sustainable msgs/month at worst-case $0.00356/msg | Sustainable msgs/month at heavy $0.00193/msg with 1.5x safety | Voice-only equivalent, minutes/month (2 turns/min, ASSUMPTION) |
|---|---|---|---|---|---|---|---|
| $9.99 | 15% | $8.24 | 3 | $2.47 | 694 | 855 | 347 to 427 |
| $9.99 | 30% | $6.78 | 3 | $2.03 | 571 | 704 | 285 to 352 |
| $14.99 | 15% | $12.36 | 2 | $3.71 | 1041 | 1282 | 520 to 641 |
| $14.99 | 30% | $10.18 | 2 | $3.05 | 857 | 1056 | 428 to 528 |
| $19.99 | 15% | $16.48 | 1 | $4.94 | 1388 | 1710 | 694 to 855 |
| $19.99 | 30% | $13.57 | 2 | $4.07 | 1143 | 1408 | 571 to 704 |
| $24.99 | 15% | $20.60 | 1 | $6.18 | 1736 | 2138 | 868 to 1069 |
| $24.99 | 30% | $16.97 | 1 | $5.09 | 1429 | 1761 | 714 to 880 |

Worst-case capped message: $0.00356 (6,000 input + 800 output tokens). Heavy message: $0.00193.

Notes:
- **Break-even** counts the fixed $13.25 a month (Workers Paid $5 + Apple $8.25) against heavy-user contribution. It is
  1 to 3 subscribers at every price point. Below about 10 typical subscribers, the free allowance covers AI and the $5 plan
  is not needed, but the Apple fee still is (MEASURED prices; usage is an ASSUMPTION).
- **Target margin:** 70% gross margin after commission and refunds. AI plus infrastructure may use at most 30% of net
  proceeds. This target is an ASSUMPTION the owner can change.
- **Sustainable allowances:** the "worst-case" column assumes every message is the largest allowed request (6,000 in,
  800 out). The "heavy" column uses the heavy profile with a 1.5x safety factor. Voice allowance: voice turns
  **share the message allowance**. Speech recognition and synthesis are free (on the device, MEASURED), but each
  spoken turn is a chat message. At about 2 turns per voice minute (ASSUMPTION), the sustainable message figures
  in the table above equal about half as many voice minutes. For example, 600 to 700 messages at $9.99 is about 300 to 350 voice
  minutes a month if a subscriber only talks. It is described as fair use, never "unlimited".
- Recommended allowance at $9.99 (published as fair use, not as a number): about 600 to 700 messages a month is
  sustainable at 70% margin even at 30% commission. The hard anti-abuse cap of 1,500 a month only guarantees no loss on
  any one subscriber. At $14.99 the sustainable figure is about 850 to 1,050, at $19.99 about 1,150 to 1,400, and at
  $24.99 about 1,430 to 1,760.

## 6. Worst-case monthly exposure

- uncapped request (24k tokens in, 800 out): $0.00883/msg; 1 req/5 s for 30 days = $4579.75; at the account's Workers AI rate limit (300 req/min) = $114493.82/month.
- capped request (6k in, 800 out): $0.00356/msg; 1 req/5 s for 30 days = $1845.71; at the account's Workers AI rate limit (300 req/min) = $46142.78/month.
- With guard defaults (150/day, 1,500/month): one subscriber at worst-case capped size = $5.34/month.

- **chat-v6 (approved, not yet deployed; production is chat-v5 and returns 502):** the Worker has no per-user limit and no budget. On Workers Free the platform's 10,000 neurons a day is the
  only ceiling: $0 is spent, and the service stops for everyone once it is used up, after about 87 typical messages a day.
  On Workers Paid, one script with any valid request shape can spend thousands of dollars a month (rows above). MEASURED (code + price).
- **With the chat-v7 guard:** spending is capped at `DAILY_NEURON_BUDGET` for the whole service ($0 extra at the
  default). One subscriber is capped at 1,500 messages a month, or $5.34 at worst. A forged token fails the signature
  check and gets nothing. A copied, valid token shares the caps of the subscriber it belongs to.

## 7. Recommended fair-use policy (customer-friendly, provisional)

The owner's instruction: do not impose restrictive limits before real costs are known. So every limit is a
wrangler variable. The defaults are generous and **provisional**, and the global budget breaker is the main protection.

Policy text, for the support page and App Store description. It does not say "unlimited":
> DateWise Premium includes generous everyday coaching for personal use. To keep the service fast and fair for
> everyone, very high automated or shared use may be paused until the next day. You will see a notice before you
> reach the daily limit. Spoken and typed messages count the same.

Shipped wording (2.0.0) states the actual numbers: up to 150 coach replies a day and 1,500 a month, at most 12 a minute
and 2 at a time; a notice near a limit; chat pauses until the next day (00:00 UTC) or month. It appears on the paywall
(`paywallFairUse`), in the Terms of Use ("Fair use") and in the App Store description and review notes. The numbers come
from `lib/config/fair_use.dart`, and `test/fair_use_test.dart` fails if they differ from `backend/wrangler.toml`, so
change both together.

| Limit (wrangler var) | Provisional default | Why | Label |
|---|---|---|---|
| `DAILY_MESSAGE_LIMIT` | 150 a subscriber a day | Almost 4x the heavy profile (40). Nobody chatting by hand reaches it | ASSUMPTION (policy) |
| `SOFT_NOTICE_PERCENT` | 80, so the notice starts at 120 | Warns before the hard stop | ASSUMPTION (policy) |
| `MONTHLY_MESSAGE_LIMIT` | 1,500 a subscriber a month | Worst case at full request size is $5.34, which stays below the $6.78 net per subscriber at 30% commission, so one subscriber can never cost more than they pay | derived from MEASURED prices |
| `MAX_INPUT_TOKENS` | 6,000 estimated (oldest turns trimmed first) | Limits a single request to $0.00356 | MEASURED (price) |
| `MAX_OUTPUT_TOKENS` | 800 | Same as chat-v6 | MEASURED (code) |
| `PER_MINUTE_LIMIT` | 12 a subscriber | A person types more slowly than this; scripts do not | ASSUMPTION |
| `MAX_CONCURRENT` | 2 a subscriber | Two devices on one Apple ID | ASSUMPTION |
| `IP_PER_MINUTE_LIMIT` | 60 an IP | Blunts floods and forged-token probing. Generous because carrier NAT puts many users behind one IP | ASSUMPTION |
| `ANON_DAILY_LIMIT` | 60 a day per IPv4 address or IPv6 /64 (hashed) | Only for the v1 App Store build (no coachId, no token) while `REQUIRE_SUBSCRIPTION=0`. A v2 request (coachId or token) without a valid token always gets 403 `SUBSCRIPTION_REQUIRED` | ASSUMPTION |
| `ANON_NEURON_BUDGET` | 20% of the daily budget (2,000) | Token-less traffic shares only this slice, so it cannot use up the subscribers' budget | ASSUMPTION |
| `SANDBOX_DAILY_LIMIT` | 20 a day | For TestFlight and App Review Sandbox transactions. A missing or `Xcode` environment is refused | ASSUMPTION |
| `LEGACY_CLIENTS` | 1 | Keeps the v1 chat and photo paths. Set it to 0 60 to 90 days after v2 ships: v1 chat then gets an in-chat "please update" reply (HTTP 200 SSE, EN/ES, no model call), the v1 photo coach a 426 `APP_UPDATE_REQUIRED` | n/a |
| `LEGACY_MAX_INPUT_TOKENS` / `LEGACY_MAX_OUTPUT_TOKENS` | 3,000 / 500 | Per-request caps on the token-less v1 chat only, so posing as v1 buys short prompts and replies | ASSUMPTION |
| `SANDBOX_NEURON_BUDGET` | 10% of the daily budget (1,000) | TestFlight / App Review slice. **Pre-launch on Workers Free:** set it to 6,000 for the App Review window (about 50 typical Llama replies a day, at least 18 at the worst-case request size; more than one reviewer's 20-a-day Sandbox cap at typical size), then back to 1,000 after approval. On Workers Paid: 35,000 (Llama) or 10,000 (Gemma). The `wrangler.toml` default stays 1,000; changing it is the owner's deploy-time setting (release checklist A4) | ASSUMPTION |
| `FAIL_OPEN_PER_SUBSCRIBER` / `FAIL_OPEN_PER_ISOLATE` / `FAIL_OPEN_MAX_MINUTES` | 0 / 0 (off: fail closed) / 15 | Opt-in: messages a verified Production subscriber may still send while a Durable Object call throws. If enabled, 3 / 10 recommended, with the required dedicated `FAILOPEN_LIMITER` binding (per Cloudflare location; no fallback to `RATE_LIMITER`) and the legacy per-request caps. Exposure math in SUBSCRIPTION_RESILIENCE.md §4 | ASSUMPTION |
| `DAILY_NEURON_BUDGET` | **10,000** | The free allowance, so $0 of spending. Raise it only with the owner's approval and Workers Paid. Suggested start once approved, with v1 still served (typical usage, 2x peak day, Sandbox slice, in-flight headroom, divided by 0.8 for the anonymous slice): **Llama 285,000 / Gemma 70,000** at 100 subscribers, 1,245,000 / 290,000 at 500, 2,440,000 / 565,000 at 1,000, 12,020,000 / 2,765,000 at 5,000 (`WORKERS_PAID_EVALUATION.md` section 5, PR #30) | ASSUMPTION, derived from MEASURED prices |
| `MONTHLY_NEURON_BUDGET` | unset (off) | An optional second ceiling | n/a |

How the slices combine (MEASURED, `backend/cost_guard.js` `budget()`): every request counts against
`DAILY_NEURON_BUDGET`. Sandbox requests are also capped by `SANDBOX_NEURON_BUDGET`, and token-less v1 requests by
`ANON_NEURON_BUDGET`. The slices are ceilings inside the total, not reservations: with Sandbox at 6,000 and the
anonymous slice at 2,000, at least 2,000 of the free 10,000 stays for Production subscribers, and v1 traffic cannot use
the Sandbox's room. Production traffic has no slice of its own and can use any unspent room, so the large Sandbox slice
is safe only before launch, when there are no Production subscribers.

Heavy-user protection: the per-subscriber hard caps above. Safety margin: the global breaker trips at the configured
budget no matter how many subscribers there are. Requests whose worst-case reservation would exceed the budget are refused
before any model call.

When real numbers exist (from the guard's count-only logs: messages, estimated neurons, outcome), tighten or loosen:
- If the 95th percentile subscriber stays under 600 messages a month at $9.99, keep 1,500 as the anti-abuse cap.
- If blended AI cost per subscriber exceeds $2.03 (70% margin at 30% commission), consider Gemma 4 as primary.
  It is about 4.8x cheaper per message (MEASURED price), subject to a quality check with the chat-v8 model eval.

## 8. Storage and verification choices (summary; details in the Phase 2 PR)

- **Counters: Durable Objects (SQLite-backed).** They are available on Workers Free (100,000 requests a day), and every
  object processes its requests one at a time, so increment-and-check is atomic under concurrency. KV is eventually
  consistent and allows only 1,000 writes a day on Free, so it cannot count. D1 could count atomically, but a single
  database serializes every user. Per-subscriber objects plus one global budget object scale better. MEASURED (pricing pages).
- **Identity without accounts:** a salted SHA-256 hash of the StoreKit 2 `originalTransactionId`, read from the App
  Store-signed transaction JWS, which the Worker verifies offline against the pinned Apple Root CA - G3. The ID is
  the same across renewals, reinstalls, restores and devices on one Apple ID, so deleting the app or resetting local
  storage resets nothing on the server. MEASURED (Apple docs: `originalID` "Identify one or more renewals for the same subscription").
- **Cost of the guard itself:** 4 Durable Object requests per message, $0 on Free up to about 25,000 messages a day.
  On Paid it is $2.55 a month at 5,000 heavy subscribers. Included in the tables above.

## 9. chat-v7 (Phase 2, not deployed)

- `backend/cost_guard.js`: the guard and the `UsageGuard` Durable Object.
- `backend/apple_jws.js`: offline StoreKit 2 JWS verification.
- `backend/coach_prompts.js`: server-side coach system prompts. Client system messages are dropped, so the Worker is
  no longer a general-purpose model proxy.
- v1 compatibility: only a chat request with **neither a `coachId` nor a StoreKit token** keeps the chat-v6 behaviour,
  with the client's own system prompt. That request comes from App Store 1.0.2, which never sends the token. Any
  request that carries `X-DateWise-Entitlement` gets the server prompt, using the default coach when no `coachId` is
  given, and is counted on that subscriber. A request with a `coachId` but no valid token gets 403
  `SUBSCRIPTION_REQUIRED` whatever `REQUIRE_SUBSCRIPTION` says (that switch only governs the v1 requests). The v1 requests are counted per network bucket and share the anonymous budget
  slice. The photo coach reserves its worst case (one vision call per photo plus two 70B converter passes) and is
  settled with the measured usage, overage included. Both v1 paths close with `LEGACY_CLIENTS=0`.
- **v1 capacity (a rollout decision for the owner).** All 1.0.2 users together share `ANON_NEURON_BUDGET`, which is
  2,000 neurons a day by default (20% of the free 10,000). The figures:

  | Item | Neurons | Label |
  |---|---|---|
  | One typical v1 chat message (2,000 tokens in, 300 out) | about 115, so about **17 messages a day for all v1 users together** | MEASURED price; the tokens are an ASSUMPTION |
  | Reserved while a v1 chat message runs (800 output tokens) | about 196, so about 10 at once | MEASURED (code) |
  | One v1 photo analysis | about 30 (quick) to 58 (deep), or about 167 with the 70B converter pass, so about 12 to 65 a day | MEASURED price; the tokens are an ASSUMPTION |

  Once the slice is used up, 1.0.2 users see the busy notice (`SERVICE_BUDGET_EXHAUSTED`) until 00:00 UTC. The v2
  subscribers keep the other 8,000 neurons. The owner's options:
  - **(a)** Keep the default and ship v2 quickly.
  - **(b)** Raise `ANON_NEURON_BUDGET`, up to the whole daily budget. That removes the subscribers' protection.
  - **(c)** Raise `DAILY_NEURON_BUDGET` on Workers Paid; the anonymous slice grows with it only if `ANON_NEURON_BUDGET` is also raised or set to `-1` (20% of the total; `wrangler.toml` pins it at 2,000). 20% of the 285,000 Llama start at 100 subscribers is 57,000, about 490 typical v1 messages a day; ASSUMPTION).
  - **(d)** Set `LEGACY_CLIENTS=0` **60 to 90 days after v2 ships** (recommended rollout). 1.0.2 then gets a normal
    HTTP 200 streamed reply in its own format saying "DateWise has a new version. Please update the app in the App Store
    to keep chatting with your coach." (Spanish when the request looks Spanish), which v1 displays in the chat; no model
    call and no budget. A 426 would only show v1's generic outage text. See `docs/qa/SUBSCRIPTION_RESILIENCE.md` §2.

  Today, 1.0.2 already shares the whole free 10,000 neurons with no limit at all.
- Refund replay while App Store Server Notifications are off: a refunded transaction's older signed copy keeps
  passing the offline check until the Worker sees the revoked version, or until `expiresDate` (at most one month for this
  monthly plan, plus the leeway). That copy is still bound by that subscriber's caps. Turning on `ASSN_ENABLED` (free;
  it needs only the URL in App Store Connect) closes this gap as soon as Apple sends `REFUND` or `REVOKE`.
  `REFUND_REVERSED` reinstates the transaction.
- `ID_HASH_SALT` (secret): rotating it resets every counter and the revoked list. Without it, a public default salt is
  used and the logs leave out `who`.
- Every limit is a variable in `backend/wrangler.toml`.
- chat-v7 deploys **only** through the reviewed workflow `.github/workflows/deploy-worker.yml`, with the owner's
  approval in the `production-worker` environment (`docs/launch/WORKER_DEPLOY_RUNBOOK.md`). An owner-internal redeploy
  tool outside this repo uploads a single pinned file and cannot deploy it. chat-v6 (`f5b0401`) is the approved v1
  stop-gap (not yet live: production is still chat-v5 as of 2026-11-23).

Once deployed, the count-only usage logs (`event: usage`) give measured messages per subscriber and neurons per
message. Replace the ASSUMPTION rows in section 3 with them and re-run `ai_cost_model.mjs`.
