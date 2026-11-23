# DateWise: moving the coach backend to its own Cloudflare account

Status: **plan only**, written 2026-11-23. Nothing has been migrated, bought, created or changed. Every step marked **Owner** needs the owner, and nothing here is approved yet.

Labels:
- **MEASURED**: read from code at a named commit, from a live read-only request, or from Cloudflare's published pricing as recorded in `docs/business/WORKERS_PAID_EVALUATION.md` (branch `claude/datewise-model-eval`).
- **ASSUMPTION**: an estimate.
- **UNKNOWN**: needs the owner's dashboard.

Code references are to `claude/datewise-v2-app` @ `9c0aea1` unless noted.

## 1. Why

The DateWise coach Worker runs on the owner's general Cloudflare account, which also runs the owner's other projects. Workers AI has one free allowance per account (10,000 neurons a day) and one bill per account, so DateWise customers share both with every other project on that account that uses Workers AI.
- On the Free plan, any project can use up the allowance, and the DateWise coach then fails with HTTP 502.
- On Workers Paid, any project's overage lands on the same invoice.

DateWise's cost guard (`DAILY_NEURON_BUDGET`) counts only DateWise's own calls, so it can't prevent either case. A dedicated account gives DateWise its own allowance, bill, limits and access list.

## 2. What DateWise uses on the shared account today

| Resource | Today | Source | Needed in the new account? |
|---|---|---|---|
| Worker `datewise-photo-coach` | Live. Public `?version` = `chat-v5` (2026-11-23, read-only GET); its chat model is retired, so chat returns HTTP 502 | MEASURED | Yes: the v2 Worker (chat-v7-cost-guard) |
| workers.dev URL | `https://datewise-photo-coach.scubamike124.workers.dev` (account subdomain `scubamike124`) | `lib/services/ai_config.dart:14`; `main:lib/services/ai_config.dart:29` | A new subdomain. See section 3 |
| Workers AI binding `AI` | The only binding declared for the live code (`main:backend/wrangler.toml`) | MEASURED (config) | Yes |
| Durable Object `USAGE_GUARD` (class `UsageGuard`, SQLite) + migration tag `v1-usage-guard` (`new_sqlite_classes`) | **Not on production yet** (chat-v7 has never been deployed) | `backend/wrangler.toml` @ 9c0aea1 | Yes. It is created by the first `wrangler deploy` |
| Rate limiting binding `RATE_LIMITER` (`[[ratelimits]]`, `namespace_id = "740219"`, 60 per 60 s) | Not on production yet | same | Yes. The ID must be unique per account, and it trivially is in a new account |
| Secret `ID_HASH_SALT` | Not set | `backend/wrangler.toml` comment; `backend/cost_guard.js` | Yes. Set once in the new account |
| `[vars]` (budgets and limits) | Not on production yet. chat-v7's built-in defaults equal the committed values | `backend/cost_guard.js` `DEFAULTS` | Yes, from `wrangler.toml` (values for the new account in section 4) |
| KV, R2, D1, Queues, service bindings, Hyperdrive | **None** in any branch's `backend/wrangler.toml`, and the Worker code reads only `AI`, `USAGE_GUARD`, `RATE_LIMITER`, `ID_HASH_SALT` and the vars | MEASURED (code) | No |
| Bindings or vars added by hand in the dashboard | **UNKNOWN.** No read-only listing of the live Worker's settings has succeeded yet. | — | **Owner:** Worker → Settings → Bindings and Variables; note anything not listed above |
| Routes or custom domains | None in `wrangler.toml` (no `routes`, no `account_id`). Live: **UNKNOWN** | MEASURED (config) | **Owner:** Worker → Settings → Domains & Routes |
| Cloudflare Pages `datewiseai.pages.dev` | The Worker's CORS list allows it (`backend/worker.js:28-39`). Whether this project exists, and on which account, is **UNKNOWN**. The App Store build doesn't need it (CORS only affects browsers). | MEASURED (code) | Only if it hosts the website. Moving it is **optional** and not needed for the AI separation |
| App Store Server Notifications | Code exists (`POST /apple/notifications`), off by default (`ASSN_ENABLED = "0"`). The URL in App Store Connect is believed to be empty | MEASURED (code); ASC **UNKNOWN** | If enabled, the URL must name the new host |

## 3. What changes

### 3.1 The v2 app's backend URL
- A new account gets its own workers.dev subdomain, so the URL becomes `https://datewise-photo-coach.<new-subdomain>.workers.dev`.
- The URL is compiled into the app: `AIConfig.productionUrl` in **`lib/services/ai_config.dart:14`** (not `lib/config/`). It can be overridden per build with `--dart-define=COACH_BACKEND_URL=…`, which is useful for TestFlight testing before the code change.
- Files to update together, **before the v2 App Store build**:
  - `lib/services/ai_config.dart:14`;
  - `test/backend_chat_test.dart:97` and `:115` (they assert the URL);
  - `scripts/production-e2e-probe.mjs:9`.
- Once v2 ships, its URL can only change with another app update. This is why the custom-domain question below matters.

### 3.2 Custom domain options (e.g. `api.datewiseai.com`)
A stable hostname means a later move between accounts or vendors doesn't need an app update. The DNS for `datewiseai.com` is believed to be hosted at GoDaddy, with Microsoft 365 mail (a DNS reading from October 2026; **owner to confirm**). The Cloudflare facts in this table come from Cloudflare's documentation and should be re-checked at the time.

| Option | How | Cost | Risk / notes | Verdict |
|---|---|---|---|---|
| **A. New workers.dev URL** | Use `datewise-photo-coach.<new-subdomain>.workers.dev` | $0 | Simple, no DNS work. A later account move needs an app update. | **Default for v2.0** if B isn't done first |
| **B. Move `datewiseai.com` DNS to Cloudflare (free plan) in the new account**, then attach `api.datewiseai.com` as a Worker Custom Domain | Add the zone in the new account, **re-create every GoDaddy record first**, then change the nameservers at the registrar | $0 (Cloudflare free DNS; the registrar stays where it is) | The main risk is **email**: the Microsoft 365 MX, `autodiscover` CNAME, SPF TXT, DMARC TXT and any DKIM `selector1/selector2._domainkey` CNAMEs, plus the website A/CNAME records and any verification TXT records, must all be copied exactly. A Worker Custom Domain needs the zone in the **same account** as the Worker. Nameserver changes take hours to propagate; lower TTLs a day before. | **Best long-term.** Do it before the v2 build only if there is time to verify mail afterwards |
| C. CNAME `api.datewiseai.com` at GoDaddy → the workers.dev host | — | $0 | **Doesn't work.** workers.dev rejects foreign hostnames (Cloudflare errors 1014/1001). | Not viable |
| D. Delegate only `api.datewiseai.com` to Cloudflare (NS records for the subdomain) | Cloudflare subdomain zones | Enterprise plan | Not available on Free or Pro | Not viable |
| E. Cloudflare "partial (CNAME) setup", keeping GoDaddy authoritative | — | Business plan or higher | A paid plan; needs approval | Not recommended |
| F. A new API domain registered at Cloudflare Registrar | e.g. a new dedicated domain | About the registry price a year (**spending: needs approval**) | Keeps `datewiseai.com` mail untouched | Fallback if B is judged too risky |

Recommendation: **A for the first v2 build**, unless the owner moves DNS (B) and verifies mail before the build is cut. If B is done later, a v2.0.x update can switch to `api.datewiseai.com`, and the workers.dev URL stays live for builds that still use it.

### 3.3 v1 builds stay on the old Worker
- App Store 1.0 uses the former developer's Worker (see `V1_TRANSITION_PLAN.md`). 1.0.2, if it shipped, has the **old** URL compiled in. So the old Worker on the shared account must keep serving v1 during the transition.
- **Old Worker (shared account):** deploy **chat-v6** (`f5b0401`) now. It fixes the HTTP 502 for 1.0.2, needs only the existing `AI` binding, and keeps v1's own prompts and photo coach. Later, replace it with a small "please update" responder (section 5, step 11) that uses no AI at all, then delete it.
- **New Worker (new account):** serves only v2, so set `LEGACY_CLIENTS = "0"` and `ANON_NEURON_BUDGET = "0"` there. A token-less request then gets `426 APP_UPDATE_REQUIRED` and costs nothing. The photo coach path is off (v2 has no photos).
- Running both Workers during the transition is the plan; neither replaces the other.

### 3.4 State
- The `UsageGuard` Durable Object in the new account starts **empty**. That is fine: chat-v7 has never been live, so there are no existing counters, revoked-transaction entries or budgets to carry over.
- If `ID_HASH_SALT` is ever rotated later, all counters reset (`backend/wrangler.toml` comment).

### 3.5 App Store Server Notifications
Optional. If enabled (`ASSN_ENABLED = "1"`), set both the Production and Sandbox URLs in App Store Connect → the app → App Information → App Store Server Notifications to `https://<new host>/apple/notifications`, version 2. Never point them at the old Worker.

## 4. Credentials and configuration in the new account

### 4.1 API tokens (Owner creates; My Profile → API Tokens → Create Token → Custom)
| Token | Permissions | Scope | Used by |
|---|---|---|---|
| **Deploy token** | Account · **Workers Scripts · Edit** | **Account Resources: Include → only the new DateWise account.** No zone permissions. | GitHub Actions deploy (`wrangler deploy`, `wrangler secret put`, rollback) |
| (only if wrangler insists on listing accounts) | add Account · Account Settings · Read | same account | — usually not needed when `CLOUDFLARE_ACCOUNT_ID` is set |
| (only if option B is used, and only if CI should manage the domain) | Zone · Workers Routes · Edit on `datewiseai.com` | that zone only | Prefer attaching the custom domain once in the dashboard instead |
| Optional **model-evaluation token** | Account · **Workers AI · Read** and **Edit** | the new account only | the model comparison harness (PR #30), if run |

- The Workers AI **binding** needs no token: the Worker uses its own account's AI.
- Set an expiry date on each token, and keep the Global API Key unused.

### 4.2 GitHub (datewiseaiapp): use an Environment, not repo-wide secrets
- Settings → Environments → **New environment `production-worker`**, with **Required reviewers: the owner** and deployment branches and tags limited to `main`, `claude/datewise-v2-app` and tags `worker-v*` (the workflow deploys from tags too).
- Environment secrets:
  - `CLOUDFLARE_API_TOKEN` (the deploy token);
  - `CLOUDFLARE_ACCOUNT_ID` (the new account's ID; not a secret, but kept out of the repo);
  - `ID_HASH_SALT`: **optional.** Recommended: the owner sets it **once** in the Cloudflare dashboard (Worker → Settings → Variables and Secrets → Add → Secret) and it is never stored in GitHub. If CI is to set it, store it here and use `wrangler secret put ID_HASH_SALT` from a step that reads only this secret.
- The existing `deploy-worker.yml` (on `f5b0401`, not yet on the v2 branch) is the workflow to reuse. Changes it needs for chat-v7:
  - run `node --test backend/worker.test.mjs backend/cost_guard.test.mjs`;
  - pin actions to commit SHAs, as the other workflows already do;
  - set `wranglerVersion` to 4.36 or later (needed for `[[ratelimits]]`);
  - add `environment: production-worker`;
  - check `?version` = `chat-v7-cost-guard` at the new URL.

### 4.3 `wrangler.toml` for the new account (in a reviewed PR)
- Keep: `[ai]`, `[[durable_objects.bindings]]`, `[[migrations]] v1-usage-guard`, `[[ratelimits]]` (740219 is fine in a fresh account).
- Change: `LEGACY_CLIENTS = "0"`, `ANON_NEURON_BUDGET = "0"`, and `DAILY_NEURON_BUDGET` for the plan chosen in section 6.
- Optionally add `account_id`, so a mistaken token can't deploy elsewhere. This is not a secret, but the public repo can leave it to the `CLOUDFLARE_ACCOUNT_ID` secret.

## 5. Migration steps (in order, with rollback)

| # | Step | Who | Rollback |
|---|---|---|---|
| 0 | Decide: Free or Workers Paid (section 6), custom domain A or B (3.2), chat model (Llama 3.3 or Gemma 4 after PR #30), price | **Owner** | — |
| 1 | **Stop-gap on the shared account:** deploy chat-v6 (`f5b0401`) to the old Worker; fixes the 502 for 1.0.2. Reduce other projects' Workers AI use on the shared account while DateWise is still there. | **Owner** approves | Cloudflare → Worker → Deployments → roll back to the previous version |
| 2 | Create the new Cloudflare account (free). Choose its workers.dev subdomain (Workers & Pages → Overview). If Paid is chosen, subscribe ($5/month, **spending approval**). | **Owner** | Nothing deployed yet; the account can be closed |
| 3 | Create the deploy token (4.1). Add the GitHub environment and secrets (4.2). | **Owner** | Revoke the token; delete the environment |
| 4 | PR: wrangler.toml values for the new account (4.3), and the updated `deploy-worker.yml`. Review and merge. | Agent prepares; owner approves | Revert the PR |
| 5 | Run the deploy workflow (`WORKER_DEPLOY_RUNBOOK.md`; dry run first, then the owner approves the `production-worker` gate): `wrangler deploy` creates the Worker, the DO class and migration, the rate-limit binding and the vars. Set `ID_HASH_SALT`. Check `?version` = `chat-v7-cost-guard`. | **Owner** runs it | `wrangler rollback`, or delete the Worker. No app uses it yet |
| 6 | Live tests against the new URL using a TestFlight or debug build with `--dart-define=COACH_BACKEND_URL=<new URL>` (no code change). Include a sandbox purchase, the subscription check, the limits and EN/ES replies. | Owner (device); agent prepares checks | Nothing to roll back |
| 7 | (Option B only) Move DNS to Cloudflare in the new account: copy all records, lower TTLs, switch nameservers at the registrar, verify mail (send and receive at `support@`), then add the `api.datewiseai.com` Custom Domain to the Worker. | **Owner** | Switch the nameservers back at the registrar (GoDaddy keeps the old zone if it isn't deleted) |
| 8 | PR: `productionUrl` → the new URL (`lib/services/ai_config.dart:14`, `test/backend_chat_test.dart:97,115`, `scripts/production-e2e-probe.mjs:9`). CI green. | Agent; owner approves | Revert the PR before the build is submitted |
| 9 | Build and submit v2. Use a **7-day phased release**. | **Owner** | Pause the phased release. Backend problems: roll back the Worker version (step 5) |
| 10 | (Optional) Enable ASSN: `ASSN_ENABLED = "1"` and the URL in App Store Connect (3.5). | **Owner** | Clear the URL; set `ASSN_ENABLED = "0"` |
| 11 | After the adoption window (`V1_TRANSITION_PLAN.md`): replace the old Worker's code with an "update the app" responder (no AI calls), then delete it once v1 traffic is near zero. | **Owner** approves | Redeploy chat-v6 from the version history |
| 12 | Remove the old Worker from any other deploy tooling's allowlist, so no tool keeps a path to it. | Owner / agent | — |

## 6. Costs

The cost guard always enforces the daily neuron budget, on both plans. Workers AI has **no hard spending cap** on Workers Paid; AI Gateway spend limits are soft (MEASURED: `WORKERS_PAID_EVALUATION.md` section 3).

### 6.1 Workers Free vs Workers Paid for the new account
| | Free | Workers Paid |
|---|---|---|
| Subscription | $0 | **$5 a month** (MEASURED) |
| Workers AI | 10,000 neurons a day; above that, calls **fail** | 10,000 neurons a day free, then **$0.011 per 1,000 neurons**, with no cap by default (MEASURED) |
| Requests / CPU | 100,000 requests a day; **10 ms CPU per invocation** | 10 M requests and 30 M CPU-ms a month included (MEASURED) |
| Durable Objects (SQLite) | Available; 100,000 requests a day (MEASURED) | 1 M requests a month included (MEASURED) |
| Capacity of the free AI allowance alone | ≈ 10,000 / 115 ≈ **85–90 typical Llama replies a day**, ≈ **10 typical subscribers**; Gemma 4 (≈ 26 neurons a reply) ≈ **45 typical subscribers** (ASSUMPTION: typical = 250 replies a month, 2,000 in / 300 out) | the same allowance, then billed |
| Fits | Testing and TestFlight only. The 10 ms CPU limit for JWS checks is an untested risk (ASSUMPTION) | **Launch and beyond** |

### 6.2 Monthly Cloudflare cost on Workers Paid (new account, DateWise only)
From `docs/business/WORKERS_PAID_EVALUATION.md` section 4 (`node docs/business/ai_cost_model.mjs --workers-paid`). The cost is $5 + Worker requests + Durable Objects + AI after the free 10,000 neurons a day.
- **MEASURED:** prices and the 4 guard requests per message.
- **ASSUMPTION:** usage profiles (light 60 replies a month at 1,200/250 tokens; typical 250 at 2,000/300; heavy 1,200 at 3,500/400) and even spread over 30 days.

| Subscribers | Llama 3.3 70B: light | typical | heavy | Gemma 4 26B: light | typical | heavy |
|---|---|---|---|---|---|---|
| 100 | $7.19 | **$33.26** | $233.04 | $5.00 | **$8.95** | $58.10 |
| 1,000 | $56.61 | **$317.34** | $2,315.70 | $13.40 | **$74.20** | $566.28 |
| 5,000 | $276.30 | **$1,580.49** | $11,572.31 | $60.23 | **$364.80** | $2,825.18 |

- For comparison, net proceeds at the configured **$9.99** after 15% commission and 3% refunds are about **$824 / $8,237 / $41,184 a month** for 100 / 1,000 / 5,000 subscribers (ASSUMPTION on refunds).
- The per-subscriber cap (1,500 replies a month) bounds one heavy user at about $5.34 a month on Llama, worst case (MEASURED rule; derived in the evaluation).
- `DAILY_NEURON_BUDGET` to set: about 2,000 neurons per subscriber per day on Llama, or 450 on Gemma, with 2x peak headroom. For example, Llama at 1,000 subscribers needs 1,915,000, at most $629 a month (`WORKERS_PAID_EVALUATION.md` section 5, ASSUMPTION).
- The new account's 10,000 free neurons a day (about $3.30 a month of inference) are DateWise's alone.

## 7. Other deploy tooling
- An owner-internal redeploy tool outside this repo can push a pinned single-file `worker.js` to the **shared** account. It can't deploy chat-v7: it has no multi-module upload, no Durable Object migration, no new bindings and no secrets.
- **Recommendation: retire it for DateWise.**
  - Use it at most once more, for the chat-v6 stop-gap on the old Worker (step 1).
  - Deploy the new account only through this repo's reviewed wrangler workflow (section 4.2).
  - Don't give that tool a token for the new account, because that would undo the separation.
  - Remove DateWise from its allowlist at step 12.

## 8. Owner-only steps (short list)
1. Approve and run the chat-v6 stop-gap on the old Worker.
2. Decide Free or Workers Paid; approve $5 a month if Paid.
3. Create the new Cloudflare account and choose its workers.dev subdomain.
4. Create the scoped deploy token (Workers Scripts Edit, new account only).
5. Create the GitHub environment `production-worker` (required reviewer: you) with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
6. Set `ID_HASH_SALT` in the new Worker's dashboard (a long random value; store it in your password manager).
7. Run the deploy workflow; confirm `?version`.
8. Decide on the custom domain. For option B: copy the DNS records, switch nameservers, test `support@` mail.
9. Test on TestFlight; approve the `productionUrl` PR; submit v2 with phased release.
10. (Optional) Set the ASSN URL in App Store Connect.
11. Check Workers & Pages on the shared account for `datewiseai` Pages and for any hand-added bindings, routes or domains on `datewise-photo-coach`, and report them so the inventory can be completed.
