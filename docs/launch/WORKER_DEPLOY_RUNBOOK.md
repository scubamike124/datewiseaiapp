# Coach Worker deploy runbook

How to deploy the DateWise coach Worker (`datewise-photo-coach`, code in
`backend/`) safely with the **Deploy coach Worker** GitHub Actions workflow
(`.github/workflows/deploy-worker.yml`). No deploy happens without the
owner's approval click.

| Target | What it is | Source | Use it for |
|---|---|---|---|
| `chat-v7-cost-guard` | Multi-module Worker (`worker.js`, `cost_guard.js`, `coach_prompts.js`, `apple_jws.js`), Durable Object `USAGE_GUARD` with migration `v1-usage-guard`, rate-limit binding `RATE_LIMITER`, secret `ID_HASH_SALT` | `backend/` at the ref you choose (default: the commit the run uses) | The v2 release |
| `chat-v6` | Single file, `AI` binding only | Always commit `f5b0401`, and `worker.js` must hash to `de390ddb…3d23837` (the same pin as Amber's allowlist) | Fixing today's v1 HTTP 502 (production runs chat-v5 on a retired model) |

## 1. Owner setup (once)

### 1a. Choose the Cloudflare account
- **Recommended: a separate Cloudflare account for DateWise.** Today DateWise
  and Amber's coding worker share one account, and so share its free Workers AI
  allowance of 10,000 neurons a day. On a separate account, DateWise's
  `DAILY_NEURON_BUDGET = "10000"` really is DateWise's own allowance. The owner
  creates the account (free plan), with the owner's own email; no agent can do it.
  - A new account gets a new `workers.dev` subdomain, so the Worker URL
    changes (`https://datewise-photo-coach.<new-subdomain>.workers.dev`). The
    v2 app's backend URL must point at the new URL before release. The v1 builds
    keep calling the old URL, so keep chat-v6 (or v7) running on the old account
    until v1 is retired.
  - A v2-only Worker on the new account can set `LEGACY_CLIENTS = "0"` and
    `ANON_NEURON_BUDGET = "0"` in a reviewed `wrangler.toml` PR
    (`CLOUDFLARE_ACCOUNT_SEPARATION_PLAN.md`, 4.3). The workflow's checks accept
    both settings, and the 403 health check doesn't depend on them.
  - Open `https://<worker-url>/?agree=1` once after the first deploy on a new
    account, to accept the Llama licence for that account.
- **Or reuse the current account.** It works, but then lower
  `DAILY_NEURON_BUDGET` (and `ANON_NEURON_BUDGET`) in `backend/wrangler.toml`
  so DateWise plus Amber stay inside 10,000 neurons a day, and check that
  rate-limit namespace `740219` is not used by any other Worker on the account.

The workflow deploys to whichever account `CLOUDFLARE_ACCOUNT_ID` and
`CLOUDFLARE_API_TOKEN` point at. Nothing in the workflow names an account.

### 1b. Create an API token (Cloudflare dashboard, My Profile, API Tokens, Create Token, Custom token)
- Permissions: **Account > Workers Scripts > Edit**. This covers deploy,
  versions, secrets, rollback, Durable Object and rate-limit bindings and reading
  the `workers.dev` subdomain.
- Add **Account > Workers AI > Read** only if you also want the token to read
  AI usage. It is not needed to deploy: the Worker reaches Workers AI through its
  `AI` binding, not through the token.
- If Wrangler stops with an authentication error on `/memberships` or `/user`,
  add **User > User Details > Read**.
- Account resources: **only the DateWise account**. Set a TTL if you like;
  renew it before it expires.
- Copy the Account ID from the account's Workers & Pages overview.

### 1c. Create the `production-worker` environment (GitHub, repo Settings, Environments, New environment)
- Name it exactly **`production-worker`**.
- Tick **Required reviewers** and add **yourself**. Every real deploy then waits
  for your click under Actions, on that run, "Review deployments".
- Optional: tick "Prevent self-review" only if someone else should approve.
  With you as the only reviewer, leave it off.
- Optional: under "Deployment branches and tags", allow only selected
  branches/tags (`claude/datewise-v2-app`, `main`, tags `worker-v*`).

### 1d. Add the secrets (in the `production-worker` environment, preferred, or as repository secrets)
| Secret | Value | Needed for |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | the token from 1b | both targets |
| `CLOUDFLARE_ACCOUNT_ID` | the account ID from 1b | both targets |
| `ID_HASH_SALT` | a long random string, e.g. the output of `openssl rand -hex 32` | chat-v7. Optional **only if** you set it once on the Worker yourself (dashboard, Worker, Settings, Variables and Secrets, Secret). The deploy fails before uploading if the Worker has no salt and this secret is empty |

Environment secrets are only given to jobs that passed the approval gate. The
workflow passes them only to the steps that call Cloudflare, never prints them,
and writes `ID_HASH_SALT` to the Worker **only if the Worker does not already
have one**. Rotating the salt resets every usage counter and the revoked list,
so don't change it casually.

Optional repository variable `WORKER_URL` (Settings, Variables): the Worker's
public URL. Without it, the workflow works out
`https://datewise-photo-coach.<account subdomain>.workers.dev` from the API.

## 2. Starting a run

`workflow_dispatch` shows in the Actions tab only once this workflow file is on
the default branch (`main`). Until then, use a tag push. A tag push runs the
workflow file **at the tagged commit**, so tag a commit that has this file.

| Way | chat-v7 | chat-v6 |
|---|---|---|
| Actions, Deploy coach Worker, Run workflow | target `chat-v7-cost-guard`, optional `ref`, `dry_run` | target `chat-v6` (ref is ignored, always f5b0401) |
| Dry run by tag | `git tag worker-v7-<date>-dry <commit> && git push origin worker-v7-<date>-dry` | `worker-v6-<date>-dry` |
| Deploy by tag (still waits for approval) | `worker-v7-<date>` | `worker-v6-<date>` |

`dry_run` defaults to **true**, so a dispatch run without changes never uploads.

## 3. Dry run (job "Check and dry-run bundle": no secrets, no Cloudflare access)
1. Checks out the target commit (for chat-v6, checks the commit and the
   `worker.js` sha256 against the pin).
2. `node --test backend/*.test.mjs`.
3. Checks `backend/wrangler.toml`: Worker name; no placeholder `[vars]` values
   (empty, `REPLACE`, `CHANGEME`, `TODO`, `<…>`, …). For chat-v7 it also checks
   that `[[ratelimits]]` has an integer `namespace_id`, that the `USAGE_GUARD`
   Durable Object binding and the `UsageGuard` migration exist, and that every
   budget and cap is a whole number, with `DAILY_NEURON_BUDGET > 0` and
   `ANON_NEURON_BUDGET <= DAILY_NEURON_BUDGET`.
4. `wrangler@4.158.0 deploy --dry-run --outdir`. For chat-v7, the binding list
   it prints must contain `AI`, `USAGE_GUARD (UsageGuard)`, `RATE_LIMITER` and
   the budget variables.
5. Loads the bundle in Node and calls `GET /?version`. It must report the
   target's version.
6. Uploads the bundle as a run artifact (`worker-bundle-<target>`).

Checked locally on 2026-11-23 with wrangler 4.158.0. chat-v7 at `9c0aea1`: 46/46
tests pass, the bundle is 61.21 KiB (18.69 KiB gzip) and reports
`chat-v7-cost-guard`, and every binding is listed. chat-v6 at `f5b0401`: 6/6
tests pass, the bundle is 20.25 KiB and reports `chat-v6`.

## 4. Real deploy (job "Deploy", environment `production-worker`)
Runs only when `dry_run` is false (or on a non-`-dry` tag), after the dry-run
job passes **and** you approve.
1. Checks that the Cloudflare secrets are set.
2. **Records the rollback point:** `wrangler deployments status --json`, then
   the version id that currently serves the most traffic. Shown in the run
   summary as "Previous version id".
3. Reads the live `?version` and the Worker URL. It refuses to deploy chat-v6
   over a live chat-v7 (that would drop the migrated Durable Object class; use
   a rollback instead).
4. chat-v7: `wrangler secret list` tells whether `ID_HASH_SALT` exists. If it is
   missing, the deploy uploads it from the `ID_HASH_SALT` secret in the same
   version (`--secrets-file`, which is additive), and the temporary file is
   deleted afterwards. If it is missing on the Worker and the secret is empty,
   **the run fails here, before anything is uploaded.**
5. `cloudflare/wrangler-action` runs `wrangler deploy` from `backend/`, with a
   message naming the target, commit and run.
6. Post-deploy checks (no AI is used):
   - `GET /?version` must report the target version (polled up to 6 times, 10 s apart);
   - chat-v7: `POST /` with `{"coachId":"ava","messages":[…]}` and **no StoreKit
     token** must return **403 `SUBSCRIPTION_REQUIRED`**. This proves that server-side
     subscription checks are on and that the `USAGE_GUARD` binding works (a
     missing binding gives 503 `GUARD_UNAVAILABLE`). It is refused before any model call;
   - chat-v6: `GET /` must return 405.

   If a check fails, the job fails and the summary prints the rollback command.

## 5. Verify by hand (optional)
```
curl -s https://<worker-url>/?version
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://<worker-url>/ \
  -H 'Content-Type: application/json' \
  -d '{"coachId":"ava","messages":[{"role":"user","content":"hi"}]}'   # chat-v7: 403
```
Then send one real chat from a TestFlight build (v2) or the 1.0.2 build (v1).
That does use a little AI.

## 6. Rollback
From a machine with Wrangler and the same token (or the Cloudflare dashboard,
Worker, Deployments, "Rollback"):
```
cd backend
CLOUDFLARE_API_TOKEN=… CLOUDFLARE_ACCOUNT_ID=… \
  npx wrangler@4.158.0 rollback <previous-version-id> -m "rollback after <run>"
npx wrangler@4.158.0 deployments status     # confirm
curl -s https://<worker-url>/?version
```
- The previous version id is in the deploy run's summary. `wrangler versions list`
  also lists every version.
- Rolling back from chat-v7 to an older version is allowed. The `UsageGuard`
  class stays migrated on the account, and the older code just ignores it.
  Deploying chat-v6 *source* over chat-v7 is not the same thing, and the workflow
  refuses it.
- Secrets survive rollbacks and deploys.

## 7. How this relates to Amber's HQ Verify/Deploy page
Amber's HQ page (Deployments, Worker; `src/lib/cloudflare/redeploy-worker.ts`
in the amberai repo) uploads **one pinned file** and keeps the existing bindings.
It is allowlisted for exactly **chat-v6 at f5b0401**.

| Need | Use |
|---|---|
| Fix the v1 502 now, on the current account | Amber HQ Verify/Deploy (chat-v6), **or** this workflow with target `chat-v6` if Amber's Verify stays blocked |
| Deploy chat-v7-cost-guard (v2) | **This workflow only.** Amber's path can't upload extra modules, add the DO binding and migration or the rate-limit binding, or set secrets, and its source check doesn't match v7 |
| Deploy to the new DateWise account | This workflow (set the secrets to the new account). Amber's allowlist points at the current account's URL |
| Roll back | Either: Amber HQ rollback, `wrangler rollback`, or the dashboard |

Using one path per Worker version avoids two systems drifting apart (AGENTS.md
reuse rule). Amber is not extended for v7.

## 8. Cost
- **GitHub Actions:** free for this public repository. A run takes about 1–2 minutes.
- **Workers (Free plan):** 100,000 requests a day. SQLite-backed Durable Objects
  are included on Free. The Rate Limiting binding has no listed charge. The
  workflow's own checks make about 3 requests a deploy and use **no neurons**.
- **Workers AI:** 10,000 neurons a day free per account. `DAILY_NEURON_BUDGET =
  "10000"` (of which `ANON_NEURON_BUDGET = "2000"` for v1) stops the Worker at
  the free allowance, so it costs $0. On a **shared** account, Amber's usage comes
  out of the same 10,000, and the Worker's budget can't see it, so either
  separate the accounts or lower the budget. On the Free plan, going over the
  allowance makes AI calls fail rather than bill. On Workers Paid ($5 a month,
  owner approval needed) usage over the allowance is billed per 1,000 neurons. Raise
  `DAILY_NEURON_BUDGET` only with the owner's approval.
- A separate Cloudflare account costs nothing on the Free plan.
