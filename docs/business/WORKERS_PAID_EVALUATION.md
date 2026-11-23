# Workers Paid evaluation for DateWise AI

Date: 2026-11-23. Nothing here was bought, activated or deployed. The account stays on its current plan,
and the configured price stays $9.99; $19.99 is a proposed price for this analysis only.

Updated 2026-11-23 for the base branch `claude/datewise-v2-app` at `be57af7` (cost guard with budget slices,
legacy per-request caps, opt-in fail-open). Figures that depend on the guard are read from `backend/cost_guard.js`
and `backend/wrangler.toml` at that commit.

Labels: **MEASURED** = read from an official page (URL below) or from code at a named file.
**ASSUMPTION** = an estimate, to be replaced with real usage.

Sources: Cloudflare's documentation at the URLs below, read on 2026-11-23 from its published source
(`github.com/cloudflare/cloudflare-docs`, commit `1c6e632`, 2026-11-22). developers.cloudflare.com itself
is not reachable from this session's network, so each figure was read from the page's source file. Prices
were the same as those `docs/business/AI_COST_MODEL.md` read on 2026-11-22.

## 1. What the $5 Workers Paid plan includes (MEASURED)

https://developers.cloudflare.com/workers/platform/pricing/

| Item | Workers Paid (Standard) | Overage | Workers Free, for comparison |
|---|---|---|---|
| Subscription | **$5 a month minimum per account** | | $0 |
| Worker requests | 10 million a month | +$0.30 per million | 100,000 a day |
| Worker CPU time | 30 million CPU-ms a month; up to 5 min per invocation (default 30 s) | +$0.02 per million CPU-ms | 10 ms per invocation |
| Duration, egress, bandwidth | no charge | | |
| Workers KV | 10 M reads, 1 M writes, 1 M deletes, 1 M lists a month, 1 GB | +$0.50 per M reads; +$5.00 per M writes, deletes or lists; +$0.50 per GB-month | 100,000 reads, 1,000 writes a day, 1 GB |
| Durable Objects requests | 1 million a month | +$0.15 per million | 100,000 a day |
| Durable Objects duration | 400,000 GB-s a month (billed at 128 MB per active object) | +$12.50 per million GB-s | 13,000 GB-s a day |
| Durable Objects SQLite storage | 25 billion rows read, 50 million rows written, 5 GB-month | +$0.001 per M rows read, +$1.00 per M rows written, +$0.20 per GB-month | 5 M rows read, 100,000 rows written a day, 5 GB |
| Workers Logs | 20 million events a month | +$0.60 per million (Cloudflare Observability pricing from 2026-12-01) | 200,000 a day |

Durable Objects: https://developers.cloudflare.com/durable-objects/platform/pricing/. KV: the Workers pricing
page, "Workers KV" section. Workers Logs: same page. The DateWise cost guard uses one SQLite-backed Durable Object
class (`UsageGuard`, `backend/wrangler.toml`) and **no KV** (MEASURED, code).

**Rate Limiting binding** (`[[ratelimits]]` in `backend/wrangler.toml`): the page
(https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) states no price and no plan
restriction. Its counts are "approximate and apply separately in each Cloudflare location" (MEASURED). That it
is free is an ASSUMPTION.

## 2. Workers AI on Workers Paid (MEASURED)

https://developers.cloudflare.com/workers-ai/platform/pricing/ and https://developers.cloudflare.com/workers-ai/platform/limits/

- Price: **$0.011 per 1,000 neurons.** Workers AI is **not** part of the $5; it is billed on top.
- Free allocation: **10,000 neurons a day, on Free and on Paid.** "On Workers Paid, you will be charged at
  $0.011 / 1,000 Neurons for any usage above the free allocation of 10,000 Neurons per day." It resets at
  00:00 UTC. So the free allocation **still applies on Paid** (about $3.30 a month of free inference).
- On Workers Free, usage above 10,000 neurons a day fails with an error ("N/A - Upgrade to Workers Paid").
  On Paid it is billed, **with no limit by default**.
- Per-model prices for the two chat candidates: Llama 3.3 70B fp8-fast $0.293 / $2.253 per M input / output
  tokens (26,668 / 204,805 neurons); Gemma 4 26B A4B (`@cf/google/gemma-4-26b-a4b-it`) $0.100 / $0.300
  (9,091 / 27,273 neurons).
- Rate limit: text generation, **300 requests a minute** per account, except models that require Workers Paid
  (20 a minute; 50 with prepaid AI Gateway credits). Neither chat candidate requires Paid.

## 3. Spending ceilings: is there a hard cap for Workers AI?

**No.** Cloudflare offers no enforceable spending cap for Workers AI usage on Workers Paid. What exists:

| Control | Where | What it does at the threshold | Covers Workers AI? | Hard cap? | Source (MEASURED) |
|---|---|---|---|---|---|
| **Workers spending limit** | Billing > Spend Management | Blocks new invocations of every Worker on the account (error 1103) until the limit is raised or the billing period ends | **No.** It counts only Workers requests and CPU after included usage. "A Workers limit does not include Durable Objects, Workers AI, Workers KV, R2, or other products" | A blocking limit, but "not an exact maximum bill", and not for AI | https://developers.cloudflare.com/billing/manage/spend-management/ and https://developers.cloudflare.com/workers/platform/spend-management/ |
| **Durable Objects spending limit** | same | Blocks Durable Object operations (stored data keeps billing) | No | Blocking, approximate, DO only | https://developers.cloudflare.com/durable-objects/platform/spend-management/ |
| **Spend-policy email alerts** | same, or the `cf` CLI | Emails at 80% and 100% of a threshold | No (Workers and DO only) | **Alert only** | https://developers.cloudflare.com/billing/manage/spend-management/cli/ |
| **Budget alerts** | Billing > Billable Usage | One email when account-wide usage-based spend crosses a dollar threshold; "informational only. They do not pause or limit usage". Pay-as-you-go accounts only | Yes, as part of account-wide spend | **Alert only** | https://developers.cloudflare.com/billing/manage/budget-alerts/ |
| **Threshold billing** | automatic | Charges a mid-cycle invoice once usage reaches a level | Yes | **No**, it is a payment trigger | https://developers.cloudflare.com/billing/threshold-billing/ |
| **AI Gateway spend limits** (Beta) | AI Gateway > Settings > Spend limits | Returns 429 for requests routed through the gateway once a dollar budget for a rolling or fixed window is reached; up to 20 rules, by model, provider or metadata (for example a user id) | Yes, for requests routed through the gateway ("per-user and per-model budgets for Workers AI") | **Blocking but soft**: "eventually consistent ... a burst of concurrent requests can briefly exceed the limit"; cost is "a best-effort estimation". Requests that skip the gateway are not counted | https://developers.cloudflare.com/ai-gateway/features/spend-limits/ |
| **AI Gateway rate limiting** | AI Gateway > Settings | 429 above N requests per fixed or sliding window, for the whole gateway | Yes, through the gateway | A request-count limit, not a dollar cap | https://developers.cloudflare.com/ai-gateway/features/rate-limiting/ |
| **Workers AI rate limits** | platform | 300 text-generation requests a minute per account | Yes | Throughput only. At 300 a minute, worst-case capped Llama requests could cost about $46,000 a month (AI_COST_MODEL.md section 6) | https://developers.cloudflare.com/workers-ai/platform/limits/ |
| **Prepaid AI Gateway credits** (Unified Billing) | AI Gateway | Workers AI requests through the gateway deduct from a prepaid balance | Yes, through the gateway | Close to one, but "in rare instances, your credit balance may go negative" and the card is charged; 5% fee on credits; costs money up front | https://developers.cloudflare.com/ai-gateway/features/unified-billing/, https://developers.cloudflare.com/ai-gateway/reference/pricing/ |

Distinction: **alerts** (spend-policy emails, budget alerts) only notify. **Blocking limits** exist for Workers
compute, Durable Objects and AI Gateway, and Cloudflare says of each that metering delays can let spend exceed
them. None of them caps Workers AI called directly through the `env.AI` binding, which is how `backend/worker.js`
calls it today.

**Conclusion: the cost guard's own global breaker (`DAILY_NEURON_BUDGET` in `backend/cost_guard.js`) is
required on Workers Paid.** It is the only control that is strict, sits in front of every Workers AI call, and
counts in neurons before the call is made (the guard reserves each request's worst case and settles the
measured amount after). Keep `MONTHLY_NEURON_BUDGET` available as a second ceiling.

What the breaker does at `be57af7` (MEASURED, code):

- **One total, with slices inside it.** `DAILY_NEURON_BUDGET` counts every AI call. Token-less v1 traffic may
  use at most `ANON_NEURON_BUDGET` (default 20% of the total) and Sandbox (TestFlight, App Review) at most
  `SANDBOX_NEURON_BUDGET` (default 10%; `wrangler.toml` sets it to a fixed **1,000**). The slices are caps, not
  reservations: what they do not use stays available to subscribers, but on a bad day they can take their full
  share, so the total must cover subscribers **plus** both slices (section 5).
- **Legacy per-request caps.** The token-less v1 chat is cut to `LEGACY_MAX_INPUT_TOKENS` **3,000** in and
  `LEGACY_MAX_OUTPUT_TOKENS` **500** out (v2 subscribers keep 6,000 / 800). A worst-case v1 request is 182 neurons
  on Llama and 41 on Gemma, against 324 and 76 for a worst-case v2 request.
- **Fails closed by default.** If the Durable Object throws, chat is refused. Fail-open is **opt-in**:
  `FAIL_OPEN_PER_SUBSCRIBER` and `FAIL_OPEN_PER_ISOLATE` are both **0** by default. If the owner turns it on
  (3 and 10 recommended, at most `FAIL_OPEN_MAX_MINUTES` 15 per isolate per outage, only verified Production
  tokens, only with the dedicated `FAILOPEN_LIMITER` binding), those messages skip the breaker and use the legacy
  caps. Its exposure is bounded and small (`docs/qa/SUBSCRIPTION_RESILIENCE.md`, section 4); it does not change
  the budget figures below.

### A second, independent limit with AI Gateway (free)

AI Gateway's core features, including analytics, caching and rate limiting, are free on all plans (MEASURED,
https://developers.cloudflare.com/ai-gateway/reference/pricing/). Spend limits are not listed as a paid feature
(that they cost nothing is an ASSUMPTION; the feature is in Beta). Routing the Worker's calls through a
gateway would add a limit that is independent of the Durable Object guard:

- Code: `env.AI.run(model, input, { gateway: { id: 'datewise' } })`
  (https://developers.cloudflare.com/ai-gateway/usage/worker-binding-methods/). This is a one-line change in
  `worker.js`, which another agent owns, so it is not made here.
- Settings, in the dashboard: a gateway **rate limit** a little above peak traffic (for example 120 requests per
  minute, sliding), and a **spend limit** per day equal to the dollar value of `DAILY_NEURON_BUDGET` minus the
  free allocation, plus 20% (so it only fires if the guard fails).
- Keep **Workers AI billing on Standard billing** (the default), so no credits are bought.
- Gateways created after 2026-09-24 store logs in Workers Logs (20 M events a month included on Paid). Turn log
  collection off, or keep it within the included amount, so the gateway adds no cost and stores no chat text.
- Optionally add a **budget alert** (email) at, for example, $25 of usage-based spend, so the owner hears about
  unexpected spend from any product.

The gateway limit is soft (eventually consistent) and only sees gateway traffic; the guard stays the primary
breaker.

## 4. Costs at $19.99 a month

Produced by `node docs/business/ai_cost_model.mjs --workers-paid`, which extends the existing cost model (same
prices, the same light / typical / heavy usage profiles as `AI_COST_MODEL.md` section 3, all ASSUMPTION). Usage
profiles: light = 60 messages a month (1,200 tokens in / 250 out), typical = 250 (2,000 / 300), heavy = 1,200
(3,500 / 400). Voice turns count as messages. The free 10,000 neurons a day is deducted, assuming usage is
spread evenly over 30 days (ASSUMPTION). Apple commission: 15% (Small Business Program) and 30% (standard,
first year) (MEASURED, AI_COST_MODEL.md section 2). Refunds: 3% (ASSUMPTION).

### Profit and loss at $19.99 a month on Workers Paid

Net = subscribers x $19.99 x (1 - commission) x (1 - 3% refunds, ASSUMPTION). Costs: Workers Paid $5 (MEASURED) plus Worker requests and CPU over the included 10 M requests and 30 M CPU-ms (MEASURED prices); Durable Objects over the included 1 M requests, 400,000 GB-s and 50 M rows written (MEASURED prices; 4 guard requests per message from the code, GB-s and rows per message ASSUMPTION); AI after the free 10,000 neurons a day (MEASURED price, usage ASSUMPTION); Apple Developer Program $8.25 a month (MEASURED). Margin = profit / net.

#### Llama 3.3 70B fp8-fast

| Subs | Usage | Gross | Apple 15% | Apple 30% | Refunds (3%) | Net @15% | Net @30% | Workers ($5 + requests) | Durable Objects | AI | Apple dev | Profit @15% | Margin @15% | Profit @30% | Margin @30% |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100 | light | $1999.00 | $299.85 | $599.70 | $50.97 / $41.98 | $1648.18 | $1357.32 | $5.00 | $0.00 | $2.19 | $8.25 | $1632.73 | 99.1% | $1341.88 | 98.9% |
| 100 | typical | $1999.00 | $299.85 | $599.70 | $50.97 / $41.98 | $1648.18 | $1357.32 | $5.00 | $0.00 | $28.26 | $8.25 | $1606.66 | 97.5% | $1315.81 | 96.9% |
| 100 | heavy | $1999.00 | $299.85 | $599.70 | $50.97 / $41.98 | $1648.18 | $1357.32 | $5.00 | $0.00 | $228.04 | $8.25 | $1406.88 | 85.4% | $1116.03 | 82.2% |
| 500 | light | $9995.00 | $1499.25 | $2998.50 | $254.87 / $209.89 | $8240.88 | $6786.60 | $5.00 | $0.00 | $24.16 | $8.25 | $8203.47 | 99.5% | $6749.20 | 99.4% |
| 500 | typical | $9995.00 | $1499.25 | $2998.50 | $254.87 / $209.89 | $8240.88 | $6786.60 | $5.00 | $0.00 | $154.52 | $8.25 | $8073.11 | 98.0% | $6618.84 | 97.5% |
| 500 | heavy | $9995.00 | $1499.25 | $2998.50 | $254.87 / $209.89 | $8240.88 | $6786.60 | $5.00 | $0.21 | $1153.42 | $8.25 | $7074.00 | 85.8% | $5619.73 | 82.8% |
| 1000 | light | $19990.00 | $2998.50 | $5997.00 | $509.75 / $419.79 | $16481.76 | $13573.21 | $5.00 | $0.00 | $51.61 | $8.25 | $16416.89 | 99.6% | $13508.35 | 99.5% |
| 1000 | typical | $19990.00 | $2998.50 | $5997.00 | $509.75 / $419.79 | $16481.76 | $13573.21 | $5.00 | $0.00 | $312.34 | $8.25 | $16156.17 | 98.0% | $13247.62 | 97.6% |
| 1000 | heavy | $19990.00 | $2998.50 | $5997.00 | $509.75 / $419.79 | $16481.76 | $13573.21 | $5.00 | $0.57 | $2310.13 | $8.25 | $14157.80 | 85.9% | $11249.26 | 82.9% |
| 5000 | light | $99950.00 | $14992.50 | $29985.00 | $2548.72 / $2098.95 | $82408.77 | $67866.05 | $5.00 | $0.03 | $271.27 | $8.25 | $82124.23 | 99.7% | $67581.50 | 99.6% |
| 5000 | typical | $99950.00 | $14992.50 | $29985.00 | $2548.72 / $2098.95 | $82408.77 | $67866.05 | $5.00 | $0.60 | $1574.89 | $8.25 | $80820.03 | 98.1% | $66277.31 | 97.7% |
| 5000 | heavy | $99950.00 | $14992.50 | $29985.00 | $2548.72 / $2098.95 | $82408.77 | $67866.05 | $5.00 | $3.45 | $11563.86 | $8.25 | $70828.21 | 85.9% | $56285.49 | 82.9% |

#### Gemma 4 26B

| Subs | Usage | Gross | Apple 15% | Apple 30% | Refunds (3%) | Net @15% | Net @30% | Workers ($5 + requests) | Durable Objects | AI | Apple dev | Profit @15% | Margin @15% | Profit @30% | Margin @30% |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 100 | light | $1999.00 | $299.85 | $599.70 | $50.97 / $41.98 | $1648.18 | $1357.32 | $5.00 | $0.00 | $0.00 | $8.25 | $1634.93 | 99.2% | $1344.07 | 99.0% |
| 100 | typical | $1999.00 | $299.85 | $599.70 | $50.97 / $41.98 | $1648.18 | $1357.32 | $5.00 | $0.00 | $3.95 | $8.25 | $1630.98 | 99.0% | $1340.12 | 98.7% |
| 100 | heavy | $1999.00 | $299.85 | $599.70 | $50.97 / $41.98 | $1648.18 | $1357.32 | $5.00 | $0.00 | $53.10 | $8.25 | $1581.82 | 96.0% | $1290.97 | 95.1% |
| 500 | light | $9995.00 | $1499.25 | $2998.50 | $254.87 / $209.89 | $8240.88 | $6786.60 | $5.00 | $0.00 | $2.55 | $8.25 | $8225.08 | 99.8% | $6770.80 | 99.8% |
| 500 | typical | $9995.00 | $1499.25 | $2998.50 | $254.87 / $209.89 | $8240.88 | $6786.60 | $5.00 | $0.00 | $32.95 | $8.25 | $8194.68 | 99.4% | $6740.40 | 99.3% |
| 500 | heavy | $9995.00 | $1499.25 | $2998.50 | $254.87 / $209.89 | $8240.88 | $6786.60 | $5.00 | $0.21 | $278.70 | $8.25 | $7948.71 | 96.5% | $6494.44 | 95.7% |
| 1000 | light | $19990.00 | $2998.50 | $5997.00 | $509.75 / $419.79 | $16481.76 | $13573.21 | $5.00 | $0.00 | $8.40 | $8.25 | $16460.10 | 99.9% | $13551.56 | 99.8% |
| 1000 | typical | $19990.00 | $2998.50 | $5997.00 | $509.75 / $419.79 | $16481.76 | $13573.21 | $5.00 | $0.00 | $69.20 | $8.25 | $16399.30 | 99.5% | $13490.76 | 99.4% |
| 1000 | heavy | $19990.00 | $2998.50 | $5997.00 | $509.75 / $419.79 | $16481.76 | $13573.21 | $5.00 | $0.57 | $560.71 | $8.25 | $15907.23 | 96.5% | $12998.68 | 95.8% |
| 5000 | light | $99950.00 | $14992.50 | $29985.00 | $2548.72 / $2098.95 | $82408.77 | $67866.05 | $5.00 | $0.03 | $55.20 | $8.25 | $82340.29 | 99.9% | $67797.57 | 99.9% |
| 5000 | typical | $99950.00 | $14992.50 | $29985.00 | $2548.72 / $2098.95 | $82408.77 | $67866.05 | $5.00 | $0.60 | $359.20 | $8.25 | $82035.72 | 99.5% | $67493.00 | 99.5% |
| 5000 | heavy | $99950.00 | $14992.50 | $29985.00 | $2548.72 / $2098.95 | $82408.77 | $67866.05 | $5.00 | $3.45 | $2816.73 | $8.25 | $79575.35 | 96.6% | $65032.62 | 95.8% |

Refunds column: the 3% of proceeds lost at 15% / at 30% commission.

### DAILY_NEURON_BUDGET needed per scenario (subscriber traffic only)

This table sizes subscriber demand alone. The budget to configure also has to hold the v1 and Sandbox slices; use section 5.

Average day = monthly neurons / 30. Peak day = 2x the average (ASSUMPTION). Recommended budget = the peak day rounded up to 5,000, never below the free 10,000. "Most the breaker allows" = the AI bill if the whole budget were used every day for 30 days: the ceiling the breaker enforces.

| Model | Subs | Usage | Messages / month | Neurons / month | Average day | Peak day | Recommended DAILY_NEURON_BUDGET | Most the breaker allows / month | Guard DO requests / month |
|---|---|---|---|---|---|---|---|---|---|
| Llama 3.3 70B fp8-fast | 100 | light | 6,000 | 499,217 | 16,641 | 33,281 | 35,000 | $8.25 | 24,000 |
| Llama 3.3 70B fp8-fast | 100 | typical | 25,000 | 2,869,438 | 95,648 | 191,296 | 195,000 | $61.05 | 100,000 |
| Llama 3.3 70B fp8-fast | 100 | heavy | 120,000 | 21,031,200 | 701,040 | 1,402,080 | 1,405,000 | $460.35 | 480,000 |
| Llama 3.3 70B fp8-fast | 500 | light | 30,000 | 2,496,086 | 83,203 | 166,406 | 170,000 | $52.80 | 120,000 |
| Llama 3.3 70B fp8-fast | 500 | typical | 125,000 | 14,347,188 | 478,240 | 956,479 | 960,000 | $313.50 | 500,000 |
| Llama 3.3 70B fp8-fast | 500 | heavy | 600,000 | 105,156,000 | 3,505,200 | 7,010,400 | 7,015,000 | $2311.65 | 2,400,000 |
| Llama 3.3 70B fp8-fast | 1000 | light | 60,000 | 4,992,171 | 166,406 | 332,811 | 335,000 | $107.25 | 240,000 |
| Llama 3.3 70B fp8-fast | 1000 | typical | 250,000 | 28,694,375 | 956,479 | 1,912,958 | 1,915,000 | $628.65 | 1,000,000 |
| Llama 3.3 70B fp8-fast | 1000 | heavy | 1,200,000 | 210,312,000 | 7,010,400 | 14,020,800 | 14,025,000 | $4624.95 | 4,800,000 |
| Llama 3.3 70B fp8-fast | 5000 | light | 300,000 | 24,960,855 | 832,029 | 1,664,057 | 1,665,000 | $546.15 | 1,200,000 |
| Llama 3.3 70B fp8-fast | 5000 | typical | 1,250,000 | 143,471,875 | 4,782,396 | 9,564,792 | 9,565,000 | $3153.15 | 5,000,000 |
| Llama 3.3 70B fp8-fast | 5000 | heavy | 6,000,000 | 1,051,560,000 | 35,052,000 | 70,104,000 | 70,105,000 | $23131.35 | 24,000,000 |
| Gemma 4 26B | 100 | light | 6,000 | 106,365 | 3,545 | 7,091 | 10,000 | $0.00 | 24,000 |
| Gemma 4 26B | 100 | typical | 25,000 | 659,098 | 21,970 | 43,940 | 45,000 | $11.55 | 100,000 |
| Gemma 4 26B | 100 | heavy | 120,000 | 5,127,324 | 170,911 | 341,822 | 345,000 | $110.55 | 480,000 |
| Gemma 4 26B | 500 | light | 30,000 | 531,824 | 17,727 | 35,455 | 40,000 | $9.90 | 120,000 |
| Gemma 4 26B | 500 | typical | 125,000 | 3,295,488 | 109,850 | 219,699 | 220,000 | $69.30 | 500,000 |
| Gemma 4 26B | 500 | heavy | 600,000 | 25,636,620 | 854,554 | 1,709,108 | 1,710,000 | $561.00 | 2,400,000 |
| Gemma 4 26B | 1000 | light | 60,000 | 1,063,647 | 35,455 | 70,910 | 75,000 | $21.45 | 240,000 |
| Gemma 4 26B | 1000 | typical | 250,000 | 6,590,975 | 219,699 | 439,398 | 440,000 | $141.90 | 1,000,000 |
| Gemma 4 26B | 1000 | heavy | 1,200,000 | 51,273,240 | 1,709,108 | 3,418,216 | 3,420,000 | $1125.30 | 4,800,000 |
| Gemma 4 26B | 5000 | light | 300,000 | 5,318,235 | 177,275 | 354,549 | 355,000 | $113.85 | 1,200,000 |
| Gemma 4 26B | 5000 | typical | 1,250,000 | 32,954,875 | 1,098,496 | 2,196,992 | 2,200,000 | $722.70 | 5,000,000 |
| Gemma 4 26B | 5000 | heavy | 6,000,000 | 256,366,200 | 8,545,540 | 17,091,080 | 17,095,000 | $5638.05 | 24,000,000 |

### Sustainable allowance per subscriber at $19.99

AI + infrastructure may use at most 30% of net (70% margin target, ASSUMPTION, as in AI_COST_MODEL.md section 5).

| Model | Commission | Net per subscriber | Max AI per subscriber | $ per worst-case capped message (6,000 in / 800 out) | Messages / month at worst case | $ per heavy message | Messages / month at heavy x 1.5 safety | One subscriber at the 1,500 / month cap, worst case |
|---|---|---|---|---|---|---|---|---|
| Llama 3.3 70B fp8-fast | 15% | $16.48 | $4.94 | $0.00356 | 1,388 | $0.00193 | 1,710 | $5.34 |
| Llama 3.3 70B fp8-fast | 30% | $13.57 | $4.07 | $0.00356 | 1,143 | $0.00193 | 1,408 | $5.34 |
| Gemma 4 26B | 15% | $16.48 | $4.94 | $0.00084 | 5,886 | $0.00047 | 7,013 | $1.26 |
| Gemma 4 26B | 30% | $13.57 | $4.07 | $0.00084 | 4,847 | $0.00047 | 5,775 | $1.26 |

### What the tables say

- Every scenario is profitable at $19.99. The lowest margin is Llama 3.3 with heavy users at 30% commission:
  about 82% of net. With Gemma 4 every margin is above 95%. (Derived from MEASURED prices and ASSUMPTION usage.)
- The $5 plan, Worker requests and Durable Objects are small: at most $8.45 a month together, even at 5,000
  heavy subscribers (24 M guard requests a month). AI is the cost that grows.
- At 5,000 heavy subscribers AI costs about $11,564 a month on Llama and $2,817 on Gemma: Gemma is about 4.1x
  cheaper per heavy message ($0.00047 vs $0.00193).
- One subscriber can never cost more than they pay: at the guard's 1,500 messages a month and worst-case request
  size (6,000 tokens in, 800 out), Llama costs $5.34 and Gemma $1.26, against $13.57 net at 30% commission.

## 5. Recommended DAILY_NEURON_BUDGET and allowances

Usage, peak factor, tester count and in-flight share are ASSUMPTION; prices, caps and slice rules are MEASURED
(`backend/cost_guard.js`, `backend/wrangler.toml` at `be57af7`). Every budget below is derived from both, so treat
it as an ASSUMPTION until the guard's count-only logs give measured daily neurons. Produced by
`node docs/business/ai_cost_model.mjs --workers-paid`.

**How it is sized.** The breaker refuses a call when `spent + reservation > DAILY_NEURON_BUDGET`. The total must
hold, on the busiest day:

1. subscriber traffic at 2x the average day (ASSUMPTION);
2. the Sandbox slice, so App Review and TestFlight never starve subscribers or get refused themselves;
3. a little headroom for in-flight reservations (each call reserves input + the 800-token output cap until it
   settles);
4. while v1 1.0.2 is still served (`LEGACY_CLIENTS=1`), the anonymous slice, which is 20% of the total, so the
   sum of 1 to 3 is divided by 0.8. After `LEGACY_CLIENTS=0`, v1 chat makes no model call and that slice goes
   unused.

### Recommended DAILY_NEURON_BUDGET (v1 still served, `LEGACY_CLIENTS=1`)

| Subscribers | Llama 3.3: start (typical usage) | Llama 3.3: 25% heavy users | Llama 3.3: all heavy (upper bound) | Gemma 4: start (typical usage) | Gemma 4: 25% heavy users | Gemma 4: all heavy (upper bound) |
|---|---|---|---|---|---|---|
| 100 | **285,000** ($91 / month max) | 665,000 ($216) | 1,800,000 ($591) | **70,000** ($20) | 165,000 ($51) | 440,000 ($142) |
| 500 | **1,245,000** ($408) | 3,135,000 ($1,031) | 8,810,000 ($2,904) | **290,000** ($92) | 755,000 ($246) | 2,150,000 ($706) |
| 1,000 | **2,440,000** ($802) | 6,225,000 ($2,051) | 17,575,000 ($5,796) | **565,000** ($183) | 1,495,000 ($490) | 4,290,000 ($1,412) |
| 5,000 | **12,020,000** ($3,963) | 30,940,000 ($10,207) | 87,695,000 ($28,936) | **2,765,000** ($909) | 7,420,000 ($2,445) | 21,385,000 ($7,054) |

All ASSUMPTION (derived). "$ / month max" is the most AI can cost in 30 days with that budget, after the free
10,000 neurons a day; it is a ceiling, not a forecast (the forecast is the AI column in section 4). Once v1 is
retired, the budgets drop by about 20% (the "v1 off" columns below).

Usage profiles (ASSUMPTION, `AI_COST_MODEL.md` section 3): typical = 250 messages a month (2,000 tokens in,
300 out), heavy = 1,200 (3,500 / 400). Heavy users stay within the hard caps (150 a day, 1,500 a month), so even
the all-heavy column is profitable at $19.99 (section 4); it is shown as the upper bound a realistic user base
could need, not as a starting value.

**Recommendation (ASSUMPTION; the owner decides).**

- **Start** at the "typical" column for the subscriber count you have, and review the guard's logs weekly. Move
  toward the "25% heavy" column when the busiest day reaches about 60% of the budget. Never configure the
  all-heavy column without measured demand: it is the ceiling a wholly heavy user base would need.
- **Sandbox slice on Workers Paid:** set `SANDBOX_NEURON_BUDGET` to **35,000** on Llama or **10,000** on Gemma
  (5 testers x 20 a day x a worst-case request; ASSUMPTION). The fixed `1000` in `wrangler.toml` is sized for the
  free 10,000 a day; on Llama it fits only about 7 typical Sandbox messages a day in total (each reserves about
  217 neurons and settles at about 115), on Gemma about 37 (MEASURED caps and prices, typical size ASSUMPTION).
  Keep it at 1,000 while the account stays on Workers Free.
- **Retiring v1** (`LEGACY_CLIENTS=0`) lowers the budget needed by about 20%; the anonymous slice then has nothing
  to pay for.
- **Model switch:** the budget is in neurons, so it must be changed together with the model. Gemma needs about
  a quarter of Llama's budget for the same traffic. A budget sized for Gemma would trip early on Llama.
- **Rule of thumb** (typical usage, v1 served): about **2,400 to 2,850 neurons per subscriber per day on Llama**
  and **550 to 700 on Gemma**, the higher figure at 100 subscribers because the Sandbox slice is fixed.
- Stay on Workers Free with `DAILY_NEURON_BUDGET = 10000` (the current value, $0) until real usage regularly
  reaches about 8,000 neurons a day.
- After moving to Workers Paid (the owner's decision), set `MONTHLY_NEURON_BUDGET` to about 30 x the average day
  x 1.25 as a second ceiling.
- When the breaker trips, chat stops for everyone until 00:00 UTC (`SERVICE_BUDGET_EXHAUSTED`). The 2x peak factor
  is there so that it trips only under abuse or a bug, never on a busy day.
- Add the AI Gateway rate and spend limits from section 3 as an independent second layer, and a Cloudflare budget
  alert by email.

What the breaker protects against (MEASURED caps x MEASURED prices): without it, each subscriber could use up to
150 worst-case requests a day, 48,578 neurons on Llama or 11,455 on Gemma (the 1,500-a-month cap still limits each
one to $5.34 or $1.26 a month). If every one of 5,000 subscribers did that on the same day, it would be about 243
million neurons on Llama (about $2,670 that day); the breaker refuses everything above the budget instead.

### Full table

Subscriber peak day = subscribers x monthly neurons / 30 x 2 (usage and peak ASSUMPTION, prices MEASURED). Sandbox slice = 5 testers (ASSUMPTION) x SANDBOX_DAILY_LIMIT 20 (MEASURED) x a worst-case v2 request (6,000 in / 800 out, MEASURED caps), rounded up. In-flight headroom = 1% of subscribers (at least 2, ASSUMPTION) each holding a worst-case reservation. v1 on (LEGACY_CLIENTS=1): token-less traffic may take its whole ANON_NEURON_BUDGET slice, 20% of the total (MEASURED default), so budget = (peak + sandbox + in-flight) / 0.8. v1 off: budget = peak + sandbox + in-flight. Rounded up to 5,000. "$ / month max" = the most the breaker lets AI cost in 30 days after the free 10,000 a day.

| Model | Subs | Usage | Subscriber peak day | Sandbox slice | In-flight headroom | DAILY_NEURON_BUDGET, v1 on | $ / month max, v1 on | DAILY_NEURON_BUDGET, v1 off | $ / month max, v1 off |
|---|---|---|---|---|---|---|---|---|---|
| Llama 3.3 70B fp8-fast | 100 | typical (all) | 191,296 | 35,000 | 648 | **285,000** | $91 | 230,000 | $73 |
| Llama 3.3 70B fp8-fast | 100 | 25% heavy, 75% typical | 493,992 | 35,000 | 648 | **665,000** | $216 | 530,000 | $172 |
| Llama 3.3 70B fp8-fast | 100 | heavy (all) | 1,402,080 | 35,000 | 648 | **1,800,000** | $591 | 1,440,000 | $472 |
| Llama 3.3 70B fp8-fast | 500 | typical (all) | 956,479 | 35,000 | 1,619 | **1,245,000** | $408 | 995,000 | $325 |
| Llama 3.3 70B fp8-fast | 500 | 25% heavy, 75% typical | 2,469,959 | 35,000 | 1,619 | **3,135,000** | $1,031 | 2,510,000 | $825 |
| Llama 3.3 70B fp8-fast | 500 | heavy (all) | 7,010,400 | 35,000 | 1,619 | **8,810,000** | $2,904 | 7,050,000 | $2,323 |
| Llama 3.3 70B fp8-fast | 1,000 | typical (all) | 1,912,958 | 35,000 | 3,239 | **2,440,000** | $802 | 1,955,000 | $642 |
| Llama 3.3 70B fp8-fast | 1,000 | 25% heavy, 75% typical | 4,939,919 | 35,000 | 3,239 | **6,225,000** | $2,051 | 4,980,000 | $1,640 |
| Llama 3.3 70B fp8-fast | 1,000 | heavy (all) | 14,020,800 | 35,000 | 3,239 | **17,575,000** | $5,796 | 14,060,000 | $4,637 |
| Llama 3.3 70B fp8-fast | 5,000 | typical (all) | 9,564,792 | 35,000 | 16,193 | **12,020,000** | $3,963 | 9,620,000 | $3,171 |
| Llama 3.3 70B fp8-fast | 5,000 | 25% heavy, 75% typical | 24,699,594 | 35,000 | 16,193 | **30,940,000** | $10,207 | 24,755,000 | $8,166 |
| Llama 3.3 70B fp8-fast | 5,000 | heavy (all) | 70,104,000 | 35,000 | 16,193 | **87,695,000** | $28,936 | 70,160,000 | $23,150 |
| Gemma 4 26B | 100 | typical (all) | 43,940 | 10,000 | 153 | **70,000** | $20 | 55,000 | $15 |
| Gemma 4 26B | 100 | 25% heavy, 75% typical | 118,410 | 10,000 | 153 | **165,000** | $51 | 130,000 | $40 |
| Gemma 4 26B | 100 | heavy (all) | 341,822 | 10,000 | 153 | **440,000** | $142 | 355,000 | $114 |
| Gemma 4 26B | 500 | typical (all) | 219,699 | 10,000 | 382 | **290,000** | $92 | 235,000 | $74 |
| Gemma 4 26B | 500 | 25% heavy, 75% typical | 592,051 | 10,000 | 382 | **755,000** | $246 | 605,000 | $196 |
| Gemma 4 26B | 500 | heavy (all) | 1,709,108 | 10,000 | 382 | **2,150,000** | $706 | 1,720,000 | $564 |
| Gemma 4 26B | 1,000 | typical (all) | 439,398 | 10,000 | 764 | **565,000** | $183 | 455,000 | $147 |
| Gemma 4 26B | 1,000 | 25% heavy, 75% typical | 1,184,103 | 10,000 | 764 | **1,495,000** | $490 | 1,195,000 | $391 |
| Gemma 4 26B | 1,000 | heavy (all) | 3,418,216 | 10,000 | 764 | **4,290,000** | $1,412 | 3,430,000 | $1,129 |
| Gemma 4 26B | 5,000 | typical (all) | 2,196,992 | 10,000 | 3,818 | **2,765,000** | $909 | 2,215,000 | $728 |
| Gemma 4 26B | 5,000 | 25% heavy, 75% typical | 5,920,514 | 10,000 | 3,818 | **7,420,000** | $2,445 | 5,935,000 | $1,955 |
| Gemma 4 26B | 5,000 | heavy (all) | 17,091,080 | 10,000 | 3,818 | **21,385,000** | $7,054 | 17,105,000 | $5,641 |

Per-request worst cases (MEASURED caps x MEASURED prices):
- Llama 3.3 70B fp8-fast: v2 request 6,000 / 800 tokens = 323.9 neurons; v1 (legacy) request 3,000 / 500 = 182.4 neurons; one subscriber at 150 a day, all worst case = 48,578 neurons a day.
- Gemma 4 26B: v2 request 6,000 / 800 tokens = 76.4 neurons; v1 (legacy) request 3,000 / 500 = 40.9 neurons; one subscriber at 150 a day, all worst case = 11,455 neurons a day.

**Allowances at $19.99.** Keep the hard anti-abuse caps as they are (`DAILY_MESSAGE_LIMIT` 150,
`MONTHLY_MESSAGE_LIMIT` 1,500, `MAX_INPUT_TOKENS` 6,000, `MAX_OUTPUT_TOKENS` 800); they already guarantee no loss
on any one subscriber with either model. The token-less v1 path keeps its smaller caps (3,000 in, 500 out). For the published fair-use level (at the 70% margin target, ASSUMPTION):

| Model | Sustainable messages a month (worst case to heavy x 1.5) | Voice equivalent, minutes a month (2 turns a minute, ASSUMPTION) | Recommendation |
|---|---|---|---|
| Llama 3.3 70B | 1,143 to 1,408 at 30% commission; 1,388 to 1,710 at 15% | about 570 to 700 | Fair use about 1,150 messages a month; the 1,500 cap stays the hard stop |
| Gemma 4 26B | 4,847 to 5,775 at 30%; 5,886 to 7,013 at 15% | more than 2,400 | AI cost no longer limits the allowance; the 1,500 cap (or a higher one, if the owner wants) is the binding limit |

Describe the allowance as generous fair use, never as "unlimited" (AI_COST_MODEL.md section 7).

## 6. Summary

- Workers Paid costs $5 a month and includes enough Worker requests, CPU and Durable Object usage for 5,000
  subscribers. Workers AI is billed on top at $0.011 per 1,000 neurons, after the 10,000 free neurons a day that
  still apply on Paid.
- **Hard cap for Workers AI spend: no.** There are alerts (budget alerts, spend-policy emails), blocking limits
  that do not cover Workers AI (Workers and Durable Objects spending limits), and AI Gateway's spend and rate
  limits, which block only requests sent through a gateway and are eventually consistent.
- **The guard's `DAILY_NEURON_BUDGET` breaker is required.** AI Gateway (free core features) can add a second,
  independent rate and spend limit in front of Workers AI. That needs a one-line change in `worker.js` and
  dashboard settings, and no purchase.
- At $19.99, margins are about 82% to 99% on Llama and 95% to 99.9% on Gemma for 100 to 5,000 subscribers.
- Recommended starting `DAILY_NEURON_BUDGET` on Workers Paid, with v1 still served: Llama 285,000 / 1,245,000 /
  2,440,000 / 12,020,000 and Gemma 70,000 / 290,000 / 565,000 / 2,765,000 for 100 / 500 / 1,000 / 5,000
  subscribers (ASSUMPTION; section 5 has the heavy-usage figures). Raise `SANDBOX_NEURON_BUDGET` with it.
  Fail-open stays off unless the owner opts in.
