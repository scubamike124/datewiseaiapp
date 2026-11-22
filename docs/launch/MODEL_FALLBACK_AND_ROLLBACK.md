# Chat models: primary and fallback, monitoring, rollback

Applies to `backend/worker.js` chat-v8 (stacked on #23 and #17).

## How it works
- The Worker tries the models in **`CHAT_MODELS`** order: the primary first, then the fallbacks. A model that errors before replying is skipped: retired, overloaded, or not available on the account's plan. The next model answers.
- Every model's stream is converted to the app's format (`data: {"response": …}`). Reasoning text is never forwarded.
- Each reply carries the header **`X-DateWise-Model`**, naming the model that answered.
- The default list, when the variable is not set, is `@cf/meta/llama-3.3-70b-instruct-fp8-fast,@cf/google/gemma-4-26b-a4b-it`.
- Known models, with list prices per 1M tokens (in/out), from developers.cloudflare.com/workers-ai/models on 2026-11-22:

| Model id | Price in/out | Free plan | Notes |
|---|---|---|---|
| `@cf/meta/llama-3.3-70b-instruct-fp8-fast` | $0.293 / $2.253 | yes | 24k context; the app's #17 baseline |
| `@cf/google/gemma-4-26b-a4b-it` | $0.10 / $0.30 | yes | cheapest; 256k context |
| `@cf/qwen/qwen3.8-27b` | $0.45 / $3.20 | yes | called with `reasoning_effort: low` (the default is xhigh: slower and costlier) |
| `@cf/deepseek-ai/deepseek-v4.1-flash-1017` | $0.30 / $1.20 | **no**: needs Workers Paid or AI Gateway credits | called with `reasoning_effort: none` |

Workers Free includes 10,000 neurons a day, about $0.11. At 1,500 input and 300 output tokens per message, that is roughly:

| Model | Messages per day on the free allowance | Per 1,000 messages |
|---|---|---|
| Gemma 4 | ~450 | $0.24 |
| DeepSeek V4.1 Flash (paid plan) | — | $0.81 |
| Llama 3.3 | ~100 | $1.12 |
| Qwen 3.8 | ~65 | $1.64 |

Real usage depends on prompt length.

## Choosing the primary: real responses
`Chat model comparison` (`.github/workflows/model-eval.yml`) runs `backend/eval/model-eval.mjs`:
- **What it tests:** every model × the four coaches × 3 scenarios, using the Worker's own prompts. The scenarios are a profile request with no information, a question in the other language, and a manipulation request.
- **What it reports:** success, latency, reply language, brand safety, length, "asks first", estimated cost, and every reply for human review.
- **When it runs:** automatically on PRs that touch `backend/`, or by hand.
- **What it needs:** the same two repository secrets as the deploy (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`). Without them it reports "Skipped".

## Monitoring
- `Coach monitor` (`.github/workflows/coach-monitor.yml`, from `main`, hourly) sends one English (Emily) and one Spanish (Mateo) test message. On failure it opens or updates a `coach-down` issue that includes the rollback steps.
- Worker logs carry `model_error`, `model_fallback` and `chat_unavailable` events, with no user content. See the dashboard's real-time logs, or enable `[observability]`.
- `GET /?health` shows the deployed version, the model order and the protection switches.

## Rollback
1. **Model problem (instant, no deploy).** In the Cloudflare dashboard, open Workers & Pages → `datewise-photo-coach` → Settings → Variables. Set `CHAT_MODELS` to a working order, for example only `@cf/google/gemma-4-26b-a4b-it`. Check `/?health`.
2. **Code problem.** Actions → **Deploy coach backend** → "Use workflow from": pick the previous branch or tag → type `deploy`. Or paste the previous `worker.js` in the dashboard.
