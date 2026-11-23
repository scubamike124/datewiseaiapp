# Coach Worker deploy runbook

How to deploy the DateWise coach Worker (`datewise-photo-coach`, code in
`backend/`) safely with the **Deploy coach Worker** GitHub Actions workflow
(`.github/workflows/deploy-worker.yml`). No deploy happens without the
owner's approval click.

| Target | What it is | Source | Use it for |
|---|---|---|---|
| `chat-v7-cost-guard` | Multi-module Worker (`worker.js`, `cost_guard.js`, `coach_prompts.js`, `apple_jws.js`), Durable Object `USAGE_GUARD` with migration `v1-usage-guard`, rate-limit binding `RATE_LIMITER`, secret `ID_HASH_SALT` | `backend/` at a commit that is **already on `main`** | The v2 release |
| `chat-v6` | Single file, `AI` binding only | Always commit `f5b0401`, and `worker.js` must hash to `de390ddb…3d23837` | Fixing today's v1 HTTP 502 (production runs chat-v5 on a retired model) |
| `chat-v7-staging` | The chat-v7 code, deployed with `wrangler deploy --env staging` to the **separate** Worker `datewise-coach-staging` (`[env.staging]`: own Durable Object, rate-limit namespace `740221`, random salt, test-sized limits) | `backend/` at a commit **already on `main`**, never `f5b0401` | The live AI test (`docs/qa/LIVE_AI_TEST_PLAN.md`), without touching production (section 9) |

**What the workflow guarantees.** The workflow refuses to run unless **the
commit it runs from** (the dispatched branch head, or the tagged commit, which
supplies this workflow file) is an ancestor of `main`. For chat-v7, the
**deployed code commit** must also be an ancestor of `main`. chat-v6 code
always comes from `f5b0401` with its pinned sha256. "On `main`" means
"reviewed" **only once `main` is protected by the ruleset in 1f** (pull request
with an approving review, no force pushes, restricted pushers). Every deploy
also needs your approval in `production-worker`. The workflow does not review
code itself.

**Consequences:**
- **chat-v7** can be deployed only after the v2 code (and this workflow) is
  merged to `main` through a reviewed PR. When to do that is your decision.
- **chat-v6** also needs this workflow on `main` first, for example through a
  small reviewed PR to `main` that adds only this workflow and the runbook.
  Until then, use the other deploy path in section 7 for the v1 fix.

## 1. Owner setup (once)

### 1a. Choose the Cloudflare account
- **Recommended: a separate Cloudflare account for DateWise**
  (`CLOUDFLARE_ACCOUNT_SEPARATION_PLAN.md`). Today DateWise shares an account,
  and so its free Workers AI allowance of 10,000 neurons a day, with the
  owner's other projects. On a separate account, `DAILY_NEURON_BUDGET = "10000"`
  really is DateWise's own allowance. The owner creates the account (free plan);
  no agent can do it.
  - **Register the account's workers.dev subdomain first** (Workers & Pages,
    Overview). The workflow refuses to deploy when the account has none, because
    Wrangler can't register it non-interactively. A brand-new subdomain can take
    a few minutes to answer; the post-deploy check waits up to about 3 minutes.
  - The Worker URL changes to `https://datewise-photo-coach.<new-subdomain>.workers.dev`,
    and the v2 app's backend URL must point at it before release. v1 builds
    keep calling the old URL, so keep a Worker running on the old account until
    v1 is retired (`V1_TRANSITION_SUMMARY.md`).
  - A v2-only Worker can set `LEGACY_CLIENTS = "0"` and `ANON_NEURON_BUDGET = "0"`
    in a reviewed `wrangler.toml` PR. The workflow's checks accept both, and the
    403 health check doesn't depend on them.
  - Open `https://<worker-url>/?agree=1` once after the first deploy on a new
    account, to accept the Llama licence for that account.
- **Or reuse the current account.** Then lower `DAILY_NEURON_BUDGET` (and
  `ANON_NEURON_BUDGET`) so DateWise plus the other projects stay inside 10,000
  neurons a day, and check that rate-limit namespace `740219` is not used by any
  other Worker on the account.

The workflow deploys to whichever account the `production-worker`
environment's `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` point at.

### 1b. Create an API token (Cloudflare: My Profile, API Tokens, Create Token, Custom token)
- Permission: **Account > Workers Scripts > Edit**. It covers deploy, versions,
  secrets, rollback, the Durable Object and rate-limit bindings, and reading the
  workers.dev subdomain.
- Account resources: **only the DateWise account**. No zone permissions.
- Optional: **Account > Workers AI > Read**, only to read AI usage. Deploying
  doesn't need it, because the Worker reaches Workers AI through its `AI` binding.
- Fallback, only if Wrangler stops with an authentication error while listing
  accounts or the user (`/memberships`, `/user`): add **Account > Account Settings
  > Read** and, if still needed, **User > User Details > Read**. This is not
  usually needed, because `CLOUDFLARE_ACCOUNT_ID` is set.
- Set an expiry date, and renew the token before it expires.
- Copy the Account ID from the account's Workers & Pages overview.

### 1c. Create the `production-worker` environment (GitHub: repo Settings, Environments, New environment). All of the following are required.
1. Name it exactly **`production-worker`**.
2. **Required reviewers: yourself.** Every real deploy then waits for your
   click (on the run, "Review deployments"). Leave "Prevent self-review" off
   while you are the only reviewer.
3. **Deployment branches and tags: "Selected branches and tags".** Add:
   - branch `main`;
   - tag pattern `worker-v*`.

   Nothing else. Without this, a run from any branch could ask for the secrets.

### 1d. Add the secrets to the `production-worker` environment only
| Secret | Value | Needed for |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | the token from 1b | both targets |
| `CLOUDFLARE_ACCOUNT_ID` | the account ID from 1b | both targets |
| `ID_HASH_SALT` | a long random string, e.g. `openssl rand -hex 32`; keep a copy in your password manager | chat-v7, **unless** you set it on the Worker yourself |

- **Use environment secrets only, never repository or organization secrets.**
  Those are given to every job, not only to the approved deploy job. The
  workflow's first step fails if any of these three exists as a repository or
  organization secret.
- `ID_HASH_SALT`, either way works:
  - **(a)** set it once in the Cloudflare dashboard (Worker, Settings,
    Variables and Secrets, Add, Secret). Then the GitHub secret isn't needed.
    This only works once the Worker exists.
  - **(b)** store it as the environment secret. The workflow writes it to the
    Worker **only if the Worker doesn't already have one**, and never prints it.

  If the Worker has no salt and the secret is empty, the run fails before
  uploading anything. If Wrangler can't list the Worker's secrets for any reason
  other than "Worker not found", the run also fails, so an existing salt is never
  overwritten. Rotating the salt resets every usage counter and the revoked list.
- Optional repository **variable** (not a secret) `WORKER_URL`, e.g.
  `https://datewise-photo-coach.<subdomain>.workers.dev`. Without it, the
  workflow reads the account's workers.dev subdomain from the API.

### 1e. Restrict who can create `worker-v*` tags (GitHub: Settings, Rules, Rulesets, New tag ruleset)
- Name: `worker deploy tags`. Enforcement: **Active**.
- Target tags: **include by pattern `worker-v*`**.
- Rules: **Restrict creations**, **Restrict updates**, **Restrict deletions**.
- Bypass list: **Repository admin** (you) only.

A tag push runs the workflow file *at the tagged commit*, so only you should be
able to create these tags. The workflow also refuses tags on commits that are
not on `main`.

### 1f. Protect `main` (GitHub: Settings, Rules, Rulesets, New branch ruleset). Mandatory.
- Name: `protect main`. Enforcement: **Active**. Target branches: **Include
  default branch** (`main`).
- Rules:
  - **Restrict deletions**;
  - **Block force pushes**;
  - **Require a pull request before merging**, with **at least 1 approving
    review** and "Dismiss stale pull request approvals when new commits are
    pushed";
  - optionally "Require status checks to pass" (Backend tests).
- **Restrict who can push:** leave the bypass list empty, or Repository admin
  (you) only. If you are the only maintainer and approve your own PRs, GitHub
  doesn't count self-approval, so either add a second reviewer or let yourself
  bypass as admin. Either way, merging to `main` stays a deliberate step.

Without 1f, anyone with write access could push a modified workflow to `main`,
and the "on main" check would mean nothing.

## 2. Starting a run

`workflow_dispatch` shows in the Actions tab only once this workflow file is on
the default branch (`main`). Until then, use a tag. **Tags are dry runs unless
they end in `-deploy`.**

| Way | chat-v7 | chat-v6 |
|---|---|---|
| Actions, Deploy coach Worker, Run workflow | target `chat-v7-cost-guard`, optional `ref` (must be on `main`), `dry_run` (default on) | target `chat-v6` (ref ignored, always f5b0401) |
| Dry run by tag | `git tag worker-v7-2026-11-24 <commit> && git push origin worker-v7-2026-11-24` | `worker-v6-2026-11-24` |
| Deploy by tag (still waits for your approval) | `worker-v7-2026-11-24-deploy` | `worker-v6-2026-11-24-deploy` |

**Staging** (`chat-v7-staging`) is **dispatch only**: Run workflow, target `chat-v7-staging`, optional `ref` (on `main`),
`dry_run`. There is no staging tag form, and tag names containing `staging` are refused (a `worker-v7-staging-…` tag
would otherwise mean production chat-v7).

- The tagged or dispatched commit must be on `main` and contain this workflow
  file, for both targets. This PR targets `claude/datewise-v2-app`, so
  nothing can run until the workflow reaches `main` (see "Consequences" above).
- `ref` accepts only plain branch, tag or SHA names: one line, no `..`, no leading `-`, no
  `refs/pull/…` or `pull/…`.

## 3. Dry run (job "Check and dry-run bundle": no Cloudflare secrets)
1. Fails if the Cloudflare secrets exist as repository or organization secrets.
2. Validates the target, ref and tag, then checks out the commit with full
   history.
   - **Both targets:** the run's own commit (`GITHUB_SHA`) must be an ancestor of `origin/main`.
   - **chat-v7:** the code commit must be an ancestor of `origin/main` too.
   - **chat-v6:** the code commit must be `f5b0401` with the pinned `worker.js` hash.
3. Refuses a set of files that could change what Wrangler builds, installs or
   connects to (`.env` files can redirect the API base URL):
   - `.npmrc`, `backend/.npmrc`, `backend/package.json`, `backend/node_modules`,
     `backend/wrangler.json(c)`;
   - `.env`, `.env.*`, `backend/.env`, `backend/.env.*`, `backend/.dev.vars(.*)`.

   It also refuses any `build` key at any level of `backend/wrangler.toml`
   (custom build command). The file is parsed with Python `tomllib`, so quoted
   keys are caught too.
4. `node --test backend/*.test.mjs`.
5. Checks `backend/wrangler.toml`:
   - the Worker name, and `main = "worker.js"`;
   - no placeholder `[vars]` values (empty, `REPLACE`, `CHANGEME`, `TODO`, `<…>`, …).

   chat-v7 and chat-v7-staging also need:
   - an integer `[[ratelimits]] namespace_id`;
   - the `USAGE_GUARD` Durable Object binding and the `UsageGuard` migration;
   - every budget and cap a whole number, with `DAILY_NEURON_BUDGET > 0` and
     `ANON_NEURON_BUDGET <= DAILY_NEURON_BUDGET`.

   `[env.staging]`, whenever it exists (on every run, and required for chat-v7-staging), is checked on its own, because
   Wrangler environments inherit no bindings or vars: name `datewise-coach-staging` (never the production name), no
   `main`/`route(s)`/`workers_dev`, its own `AI`, `USAGE_GUARD`, `UsageGuard` migration and `RATE_LIMITER` with a
   namespace_id that is not production's (`740219`, `740220`); every production var declared, no placeholders; the same
   app/product ids, expiry leeway and grace as production; `ALLOW_SANDBOX = "1"`, `LEGACY_CLIENTS = "0"`,
   `REQUIRE_SUBSCRIPTION = "1"`, ASSN and fail-open off; `SANDBOX_DAILY_LIMIT` and `SANDBOX_NEURON_BUDGET` above 0,
   `DAILY_NEURON_BUDGET` from 1 to 4000. Any other `[env.*]` is refused. The `build`-key check (step 3) already walks the
   whole file, `[env.staging]` included.
6. `wrangler@4.158.0 deploy --dry-run --outdir`. For chat-v7, the binding list
   it prints must contain `AI`, `USAGE_GUARD (UsageGuard)`, `RATE_LIMITER` and
   the budget variables. chat-v7-staging runs `deploy --env staging --dry-run`, and its list must also show
   `SANDBOX_DAILY_LIMIT ("40")`, `SANDBOX_NEURON_BUDGET ("3000")`, `DAILY_NEURON_BUDGET` at most 4000,
   `ALLOW_SANDBOX ("1")`, `LEGACY_CLIENTS ("0")`, `REQUIRE_SUBSCRIPTION ("1")`, `ASSN_ENABLED ("0")` and the product id.
   With `[env.staging]` in the file, Wrangler warns that no environment was named on the production runs; that is
   expected (no `--env` = the top-level, production config).
7. Loads the bundle in Node, and `GET /?version` must report the target version (`chat-v7-cost-guard` for chat-v7-staging).
8. Uploads the bundle as a run artifact. The summary shows the **exact commit SHA**
   and a link to it. The deploy job's name also carries the target and SHA.
   **Approve only if that is the commit you mean to deploy.**

Checked locally on 2026-11-23 with wrangler 4.158.0. chat-v7 at `9c0aea1`: 46/46
tests pass, the bundle is 61.21 KiB (18.69 KiB gzip), it reports
`chat-v7-cost-guard`, and all bindings are listed. chat-v6 at `f5b0401`: 6/6
tests pass, and the 20.25 KiB bundle reports `chat-v6`.

## 4. Real deploy (job "Deploy … (owner approval)", environment `production-worker`)
Runs only for `dry_run` = false or a `-deploy` tag, and only after the dry-run
job passes **and** you approve.
1. Re-validates the target and SHA, checks out that exact commit, and re-runs
   the `main`-ancestor checks (workflow commit, plus the chat-v7 code commit) or
   the chat-v6 pin. It also re-runs the refused-file and `build`-key checks.
2. Checks that the Cloudflare secrets are set.
3. **Records the rollback point:** `wrangler deployments status --json`, then
   the version id serving the most traffic, shown in the run summary. It fails
   closed on any error other than "the Worker doesn't exist yet".
4. Works out the Worker URL. It fails if the account has no workers.dev
   subdomain and `WORKER_URL` isn't set. Then it reads the live `?version`.
   **chat-v6:** refuses to deploy if chat-v7 is live. Also refuses if the
   live version can't be read, unless you started the run with
   `force_v6_over_unknown` (check the dashboard first).
5. **chat-v7:** handles `ID_HASH_SALT` as described in 1d. If needed, it is
   uploaded in the same version via `--secrets-file` (additive), and the
   temporary file is deleted afterwards.
6. `cloudflare/wrangler-action` runs `wrangler deploy` from `backend/`. The
   command line contains only constant text and the runner's temp path.
7. Post-deploy checks, which use no AI:
   - `GET /?version` must report the target version. It polls every 10 s for
     up to about 3 minutes.
   - **chat-v7:** `POST /` with `{"coachId":"ava","messages":[…]}` and **no
     StoreKit token** must return **403 `SUBSCRIPTION_REQUIRED`**. That shows
     the server-side subscription check is on and the IP rate limit answered.
     It does **not** prove the `USAGE_GUARD` binding exists, because the token
     check runs before the guard is used. The binding is proven before the
     deploy, by the dry-run binding check (section 3, step 6). The Durable
     Object itself is first exercised by a real v2 chat (section 5).
   - **chat-v6:** `GET /` must return 405.

   On failure, the job fails and the summary prints the rollback command.

## 5. Verify by hand
```
curl -s https://<worker-url>/?version
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://<worker-url>/ \
  -H 'Content-Type: application/json' \
  -d '{"coachId":"ava","messages":[{"role":"user","content":"hi"}]}'   # chat-v7: 403
```
Then send one real chat from a TestFlight build (v2) or the 1.0.2 build (v1),
and check that the usage headers (`x-datewise-*`) come back. That exercises the
Durable Object and uses a little AI.

## 6. Rollback
From a machine with Wrangler, with the same token in the environment, or from the
Cloudflare dashboard (Worker, Deployments, Rollback):
```
cd backend && npx wrangler@4.158.0 rollback <version-id> -m "rollback"
npx wrangler@4.158.0 deployments status
curl -s https://<worker-url>/?version
```
- `<version-id>` is the "Previous version id" in the deploy run's summary.
  `npx wrangler@4.158.0 versions list` lists every version.
- Rolling back from chat-v7 to an older version is allowed. The `UsageGuard`
  class stays migrated, and the older code ignores it. Deploying chat-v6 *source*
  over chat-v7 is different, and the workflow refuses it.
- Secrets survive rollbacks and deploys.

## 7. Other deploy paths
An owner-internal redeploy tool outside this repo can push one pinned
single-file `worker.js` (chat-v6 at `f5b0401`) to the current account, keeping the
existing bindings.

| Need | Use |
|---|---|
| Fix the v1 502 now, on the current account | That tool (chat-v6), **or** this workflow with target `chat-v6` (once the workflow is on `main`) |
| Deploy chat-v7-cost-guard (v2) | **This workflow only.** A single-file upload can't add the extra modules, the DO binding and migration, the rate-limit binding or the secret |
| Deploy to a new DateWise account | **This workflow only.** Don't give other tools a token for the new account |
| Roll back | `wrangler rollback`, the dashboard, or the tool above (current account only) |

One deploy path per Worker version stops the systems from drifting apart.

## 8. Cost
- **GitHub Actions:** free for this public repository. A run takes about 1–5 minutes.
- **Workers (Free plan):** 100,000 requests a day. SQLite-backed Durable Objects
  are included on Free, and the Rate Limiting binding has no listed charge. The
  workflow's own checks make about 3 requests per deploy and use **no neurons**.
- **Workers AI:** 10,000 neurons a day free per account.
  - `DAILY_NEURON_BUDGET = "10000"` (of which `ANON_NEURON_BUDGET = "2000"` for
    v1) stops the Worker at the free allowance, so $0.
  - On a **shared** account, other projects use the same 10,000, and the
    Worker's budget can't see them, so separate the accounts or lower the budget.
  - On the Free plan, going over the allowance makes AI calls fail rather than
    bill. On Workers Paid ($5 a month, owner approval needed), usage over the
    allowance is billed per 1,000 neurons.
  - Raise `DAILY_NEURON_BUDGET` only with the owner's approval.
- A separate Cloudflare account costs nothing on the Free plan.

## 9. Staging Worker for the live AI test

The live AI test (`docs/qa/LIVE_AI_TEST_PLAN.md`, 36 requests) needs more Sandbox room than production allows
(`SANDBOX_DAILY_LIMIT` 20, `SANDBOX_NEURON_BUDGET` 1000). Instead of changing production variables, it runs against a
separate staging Worker, so production is never touched and there is nothing to restore.

| | Production | Staging |
|---|---|---|
| Worker | `datewise-photo-coach` | `datewise-coach-staging` (`[env.staging]`) |
| Deploy | `wrangler deploy` (target `chat-v7-cost-guard`) | `wrangler deploy --env staging` (target `chat-v7-staging`, dispatch only) |
| Durable Object | `USAGE_GUARD` (own namespace) | `USAGE_GUARD` (own namespace: separate counters and budget) |
| Rate limit | `RATE_LIMITER`, namespace `740219` | `RATE_LIMITER`, namespace `740221` |
| `ID_HASH_SALT` | `production-worker` secret or set on the Worker | a random one the workflow sets if the staging Worker has none; never production's |
| Limits | `[vars]` | same caps; `SANDBOX_DAILY_LIMIT` 40, `SANDBOX_NEURON_BUDGET` 3000, `DAILY_NEURON_BUDGET` 4000, no v1 |
| Security | v2 needs a verified StoreKit JWS; Sandbox allowed | the same; also `LEGACY_CLIENTS = "0"`, `REQUIRE_SUBSCRIPTION = "1"`; ASSN and fail-open off |

**What the workflow guarantees for staging.** The same protections as production: the run's commit and the code commit
must be on `main`; the deploy job runs in `production-worker` (your approval; deployment branches `main` and
`worker-v*` tags, unchanged), with the same environment secrets. On top of that, the target fixes the environment
(`--env staging`), the Worker name and the expected version in the workflow itself, never from input; it refuses the
`f5b0401` commit and `force_v6_over_unknown`; the deploy job re-checks that `[env.staging] name` is
`datewise-coach-staging`; the URL is always the staging Worker's own workers.dev host (the `WORKER_URL` variable is
ignored for staging); and the wrangler command differs from production's only by `--env staging`.

**Post-deploy checks (staging, no AI):** `?version` = `chat-v7-cost-guard`; a v2 `POST /` without a token returns
**403 `SUBSCRIPTION_REQUIRED`**; with a malformed token **403 `SUBSCRIPTION_INVALID`**; a v1-shaped request gets the
no-model `APP_UPDATE_REQUIRED` notice (which also shows it is the staging config: production still serves v1).

**Owner steps:**
1. Merge chat-v7 and this staging config to `main` through a reviewed PR (as for any chat-v7 deploy).
2. Confirm rate-limit namespace `740221` is not used by another Worker on the account (each Worker, Settings,
   Bindings). If it is, change it in a reviewed PR first.
3. Actions, Deploy coach Worker, Run workflow from `main`: target `chat-v7-staging`, `dry_run` on. Check the summary
   says **STAGING** and the commit.
4. Run again with `dry_run` off and approve `production-worker`. Note the staging URL in the summary
   (`https://datewise-coach-staging.<subdomain>.workers.dev`).
5. Run the live test against that URL (`docs/qa/LIVE_AI_TEST_PLAN.md`, sections 1 to 3).
6. **Teardown:** `cd backend && npx wrangler@4.158.0 delete --env staging` (Wrangler signed in to the account; check it
   names `datewise-coach-staging`), or the dashboard (Worker, Settings, Delete). This deletes the staging Worker, its
   Durable Object data and its salt only.

Checked locally on 2026-11-23 with wrangler 4.158.0 (`cd backend && npx wrangler@4.158.0 deploy --env staging
--dry-run --outdir /tmp/x`, no credentials): 72.03 KiB (21.74 KiB gzip); bindings `USAGE_GUARD (UsageGuard)` Durable
Object, `AI`, `RATE_LIMITER (60 requests/60s)` and the 31 vars with the staging values; the bundle reports
`chat-v7-cost-guard`. The production dry run's binding list and bundle are byte-identical to before the staging section
was added. CI repeats the staging dry run on every pull request (Backend tests, job `staging-dry-run`).

No new GitHub environment, secret or variable is needed. Rollback of a staging deploy:
`cd backend && npx wrangler@4.158.0 rollback <version-id> --env staging -m "rollback"`.

**Cost:** $0. Workers Free covers the extra Worker, its SQLite Durable Object and the rate-limit binding; the deploy
checks use no neurons. The test uses about 1,839 neurons (stopped at 3,000 by `SANDBOX_NEURON_BUDGET`, and the
staging Worker as a whole at 4,000), inside the account's free 10,000-neuron daily allowance, which staging and
production share on the test day (on Workers Free, use past the allowance fails rather than bills).
