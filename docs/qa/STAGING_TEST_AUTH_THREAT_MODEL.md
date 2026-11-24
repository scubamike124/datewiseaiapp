# Staging test authentication: threat model

Scope: the throwaway authentication that lets the automated live AI test (`.github/workflows/live-ai-test-staging.yml`)
call the staging Worker `datewise-coach-staging` without a person buying a Sandbox subscription. Written 2026-11-24.
Code: `backend/staging_entry.js` (staging only), `tool/live/staging_auth.mjs` (mints the CA and tokens),
`backend/wrangler.toml` `[env.staging]`. Tests: `backend/staging_auth.test.mjs`,
`backend/production_rejects_test_chain.test.mjs`, `backend/live_ai_workflow.test.mjs`.

## 1. Design in one paragraph

Every chat request needs a StoreKit-style JWS that `backend/apple_jws.js` verifies against a **pinned root** (Apple Root
CA - G3). For the live test, each run creates a new CA (root, intermediate, leaf, shaped like Apple's) **on the CI
runner**, signs a test token with it, and **discards the private keys** (they live only in the memory of one Node
process and are never written to disk, a log, a summary or an artifact). Only the **public root certificate** is sent
to the staging Worker as a variable. The staging Worker's own entry file adds that root to the trusted list **next to**
Apple's. The verifier, the bundle id (`com.datewise.datewiseAi`), product id (`datewise_premium_monthly`),
Sandbox/Production environment rule, expiry and revocation checks are the production code, unchanged.

### Why a separate entry file, not a flag in `worker.js`

`[env.staging] main = "staging_entry.js"`; production's `main` is `worker.js`. The test-trust code, the variable name and
the `/?staging-neurons` route exist **only in the staging bundle**. There is no runtime switch in shared code that a
production variable, header or request could turn on. Evidence:

- The production bundle (`wrangler@4.158.0 deploy --dry-run --outdir`, no `--env`) has the same `worker.js` sha256
  before and after this change: `6a933be54cc11a389d12c6bec101b1372ec7c2b8e7ed2265c06462f1e6595043`
  (`worker.js.map` differs only by the checkout folder name it embeds; the README by its timestamp). `[vars]` of
  production did not change (`staging_env.test.mjs` pins the production config hash).
- CI greps the production bundle for the staging markers (workflows Deploy coach Worker, Backend tests, Live AI test)
  and fails if any is present.
- `cost_guard.js` is unchanged. Its existing test hook `_setTrustedRootsForTests` (it was already in the production
  bundle, inert, no Worker variable can reach it) is called by exactly one non-test file, `staging_entry.js`; a test
  asserts that.
- `production_rejects_test_chain.test.mjs`: the production Worker with the real production `[vars]` answers a
  tool-minted, otherwise valid Sandbox token with 403 `SUBSCRIPTION_INVALID` and makes no model call, even when the
  environment names the test root; `/?staging-neurons` does not exist there.

## 2. What the staging Worker trusts, and when

The test root is trusted only while all of this holds, re-checked on every request:

1. `STAGING_TEST_ROOT_CERT_B64` is a well-formed DER certificate of at most 2,000 bytes, a CA, and not Apple's root;
2. its validity window is **at most 2 hours** (a longer-lived root is ignored, so a mistaken or hostile deploy cannot
   make it permanent);
3. now is inside that window.

Past the window the root is dropped and the verified-token cache is emptied: a leaked token or root stops working **by
itself**, without a redeploy. Tokens expire 50 minutes after issue and the Worker's 60-minute leeway ends before the
root does (110 of 120 minutes). The workflow also redeploys staging without the variable at the end (also on failure or
cancel) and proves the token is then refused. Tests: expired token rejected; root expired rejected; over-long,
not-yet-valid, garbage roots ignored.

Genuine Apple Sandbox tokens still verify (Apple's root stays in the list), so the owner's iPhone testing against
staging keeps working. A token from any other chain, including a forged header that names the trusted root but is signed
by another key, is refused (`staging_auth.test.mjs`).

## 3. What an attacker can and cannot do

| Attacker can read | Can do | Cannot do |
|---|---|---|
| The repository (public or private) | Read the code and this document: nothing secret is in them | Mint a token: no CA key exists in the repo, and each run's CA is new |
| The workflow logs and step summaries | See the public root's fingerprint and the neuron counts. Tokens are masked (`::add-mask::`) and the kit prints only `sha256:` prefixes | Obtain a token or a key: tokens are never printed, keys never written |
| The report artifact | Read replies and checks; the report redacts the token | Obtain a token: the redactor strips it and its three parts; a test asserts it |
| The public root certificate (from the Worker variable, the logs or the deploy) | Nothing: a root certificate is public by design; trust needs the matching **private** key | Sign a token (needs the discarded key) |
| A **leaked test token** (for example a compromised runner during the run) | Use staging for at most 110 minutes as one Sandbox subscriber: Sandbox daily limit 20 requests, staging budget 2,000 neurons a day, per-minute and concurrency limits as production | Touch production (different Worker, Durable Object, rate-limit namespace, salt; the token's chain is not trusted there), spend more than the cap, or survive the window |
| A compromised runner during the run (private key in memory for seconds, Cloudflare secrets in the deploy steps) | Same as the Cloudflare token's rights: that is the existing `production-worker` environment risk, unchanged and approval-gated; it could mint tokens only while the process holds the key (seconds) | Read the key afterwards: it is never on disk |
| A pull request or fork | Edit workflow files | Run the workflow: it is `workflow_dispatch` only, requires the commit to be on `main`, and the job waits for the owner's approval in `production-worker` (Cloudflare secrets exist only there) |

Residual points, stated plainly:

- `staging_entry.js` serves `GET /?staging-neurons` to anyone holding a valid entitlement. It returns today's neuron
  total and the cap, and changes nothing (a zero-neuron budget probe).
- The test root can mint a **Production**-environment token as well as Sandbox, because the verifier's environment rule
  is production's. That is acceptable on staging (no real subscribers, same caps) and the tool only mints Sandbox.
- While the root is live, any holder of the matching key could sign tokens; the key exists in memory for seconds.

## 4. Blast radius

What the public root enables on staging: a token holder is one Sandbox subscriber (daily limit 20, own `sbx:` counter).
The staging Worker's total is capped at **2,000 neurons a day** (`DAILY_NEURON_BUDGET` = `SANDBOX_NEURON_BUDGET` =
2000), which is 20% of the account's free 10,000 neurons a day. That allowance is shared with production and Amber, so
the worst case of a leak is: staging burns its 2,000 neurons on a day, which leaves 8,000 for production and Amber. It
cannot exceed 2,000 a day, and each day resets at 00:00 UTC. The per-request caps and the per-minute and concurrency
limits are production's, so staging cannot be used to amplify cost.

## 5. Mitigations (summary)

- No test-trust code or variable in the production bundle; checked by hash, by grep in CI and by tests.
- Private key never leaves memory; only the public root is deployed; tokens masked.
- 2-hour root enforced inside the Worker, 50-minute tokens, cleanup redeploy that removes the root, proof step.
- Staging cap 2,000 neurons a day; pre-flight refuses to start at the cap; the run stops at the first capacity sign
  and never retries (exit 3, "not run: shared capacity"); production and Amber take priority.
- Manual trigger, commit on `main`, one owner approval, secrets only in the `production-worker` environment, its own concurrency
  group (`live-ai-test-staging`) so two test runs cannot overlap and a queued test never replaces a queued production deploy.
- `wrangler deploy` calls name `--env staging`; the production config is only dry-run (a test and the config guard).

## 6. Conditions the owner must keep true

- **The Cloudflare account stays on Workers Free.** With usage-based billing on, calls past the free allowance would
  bill and production and Amber would stop failing closed. The staging cap would still bound staging at about $0.02 a
  day, but nothing here can detect the plan: reading it needs account-level billing permissions that the deploy token
  must not have. Check Billing, Workers plan = Free, before running. There is no paid fallback of any kind in the kit
  (no paid plan, model or provider).
- The `production-worker` environment keeps its required reviewer and branch restriction.
- Do not commit a test root in `[env.staging.vars]` (the workflow's config guard refuses it).

## 7. Assumptions only the owner can verify (the reviewer could not)

1. **`production-worker` environment protection.** The workflow's safety rests on the environment having a **required
   reviewer** and a **deployment-branch rule limited to `main`** (and `worker-v*` tags). Check Settings, Environments,
   production-worker. Without them, anyone with write access could dispatch a run from a branch whose own copy of the
   workflow is modified (a dispatched ref runs ITS version of the workflow file, with the environment's secrets). The
   in-workflow "commit is on main" check cannot protect against a modified workflow on that ref; the environment rule does.
2. **Cloudflare Workers Free plan** (section 6): Billing, Workers plan = Free. Not readable with the deploy token.
3. **Merge order.** This branch contains PR #54's backend changes (it was built on `claude/overnight-2026-11-24`). Merge PR
   #56, then PR #54, then this branch; then re-run `tool/prod_bundle_hash.sh` on the new `main` (before) and on the
   merge result (after) and confirm the production `worker.js` sha256 is identical before merging this branch.

## 8. After the security review (2026-11-24)

The cleanup step fails the job (not a warning) if staging still accepts the token after the root is removed; the
workflow has its own concurrency group; `/?staging-neurons` is rate limited, verifies the token before any work and
returns only generic codes on errors; the pre-flight reserves the worst case of 324 neurons and the daily chunk is 14
requests (docs/qa/LIVE_AI_TEST_PLAN.md section 3a).
