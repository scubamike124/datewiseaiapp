# Restoring the DateWise coach backend from an iPhone

## Why the coach is down, and what it needs
- The coach backend is the Cloudflare Worker `datewise-photo-coach`. It reaches the AI through its **Workers AI binding**, which is already set up on the owner's Cloudflare account. **No AI API key is needed.**
- It is down because the code still uses a model Cloudflare retired on 2026-11-20 (live HTTP 502). The fix is in this PR's `backend/worker.js`, with #23 adding the security changes on top.
- What's missing is a way to **deploy** the fixed code. There are two options below; pick one.

## Option A: one-time setup, then deploy with a tap (recommended)
1. **Create a Cloudflare token.** In Safari, open dash.cloudflare.com → profile icon → **My Profile** → **API Tokens** → **Create Token** → template **Edit Cloudflare Workers** → **Use template**. Under **Account Resources**, select your account → **Continue to summary** → **Create Token**. Copy the token. Cloudflare shows it only once.
2. **Copy the account ID.** In the dashboard, open **Workers & Pages**; the **Account ID** is in the right-hand column (or under the account's overview). Copy it.
3. **Store both as GitHub secrets.** In Safari, open github.com/scubamike124/datewiseaiapp → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Add:
   - `CLOUDFLARE_API_TOKEN`, set to the token;
   - `CLOUDFLARE_ACCOUNT_ID`, set to the account ID.

   If Settings is hidden on mobile, use Safari's **aA → Request Desktop Website**. Secrets are encrypted, and no one, including Claude, can read them back.
4. **Merge the fix.** Merge #17 (or #17 and then #23). This puts the "Deploy coach backend" workflow on `main`.
5. **Deploy.** In the GitHub app or in Safari: repo → **Actions** → **Deploy coach backend** → **Run workflow** → type `deploy` → **Run**. The workflow runs the offline tests first, deploys, then prints the live version, which should be `chat-v6` (#17) or `chat-v7` (#23).
6. **Tell Claude it's deployed.** Claude then runs the live English and Spanish checks (`LAUNCH_READINESS.md` §6).

## Option B: no token, paste the code (works, but is fiddly on a phone)
1. In Safari, open the raw file: github.com/scubamike124/datewiseaiapp/blob/claude/fix-retired-cf-model/backend/worker.js → **Raw** → select all → copy.
2. Open dash.cloudflare.com → **Workers & Pages** → `datewise-photo-coach` → **Edit code**. Replace all the code with the copied text → **Deploy**.
3. Check: open `https://datewise-photo-coach.scubamike124.workers.dev/?version` in Safari. It should show `chat-v6`.

## Safety
- The workflow runs **only** when started by hand with the word `deploy`. It never runs on a push or a PR.
- The secrets are never printed: the workflow only checks that they are set.
- A deploy changes production. Run it only when you approve the change.
