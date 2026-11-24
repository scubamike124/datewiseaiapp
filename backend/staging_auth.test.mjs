// The STAGING Worker's throwaway test authentication (backend/staging_entry.js, tool/live/staging_auth.mjs,
// docs/qa/STAGING_TEST_AUTH_THREAT_MODEL.md). Everything except the trust anchor is the production verification.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import staging, { activeTestRoot, MAX_TEST_ROOT_LIFETIME_MS, rootsFor, TEST_ROOT_VAR } from './staging_entry.js';
import { APPLE_ROOT_CA_G3_SHA256 } from './apple_jws.js';
import { makePki, txPayload } from './test/helpers.mjs';
import { chatRequest, makeEnv, tomlSkip } from './test/staging_env_helpers.mjs';
import { makeStagingAuth, ROOT_LIFETIME_MS, TOKEN_LIFETIME_MS } from '../tool/live/staging_auth.mjs';

const skip = tomlSkip;
const send = async (env, jws) => {
  const res = await staging.fetch(chatRequest(jws), env, {});
  const text = await res.text();
  let code = null;
  if (res.status !== 200) try { code = JSON.parse(text).code; } catch { /* not JSON */ }
  return { status: res.status, code };
};
const withNow = async (ms, fn) => {
  const real = Date.now;
  Date.now = () => real() + ms;
  try { return await fn(); } finally { Date.now = real; }
};

test('staging with the test root configured accepts a tool-minted token (same checks, test trust anchor)', { skip }, async () => {
  const a = await makeStagingAuth();
  const env = makeEnv('staging', { [TEST_ROOT_VAR]: a.rootB64 });
  const r = await send(env, a.tokens[0]);
  assert.equal(r.status, 200);
  assert.equal(env.AI.calls.length, 1);
  // The subscriber is a Sandbox one (own counter, Sandbox daily limit and neuron slice).
  assert.ok([...env.USAGE_GUARD.objects.keys()].some((k) => k.startsWith('sbx:')));
});

test('staging without the root var rejects the same token (the trust is opt-in per deploy)', { skip }, async () => {
  const a = await makeStagingAuth();
  const env = makeEnv('staging');
  const r = await send(env, a.tokens[0]);
  assert.deepEqual([r.status, r.code], [403, 'SUBSCRIPTION_INVALID']);
  assert.equal(env.AI.calls.length, 0);
});

test('staging rejects a token from any other chain, even with the test root configured', { skip }, async () => {
  const a = await makeStagingAuth();
  const other = await makePki({ validFrom: Date.now() - 60_000, validTo: Date.now() + 3_600_000 });
  const env = makeEnv('staging', { [TEST_ROOT_VAR]: a.rootB64 });
  const r = await send(env, await other.sign(txPayload({ environment: 'Sandbox' })));
  assert.deepEqual([r.status, r.code], [403, 'SUBSCRIPTION_INVALID']);
  // A token whose header names the trusted root but is signed by another key fails the chain/signature checks.
  const forged = await other.sign(txPayload({ environment: 'Sandbox' }));
  const [h, p, s] = forged.split('.');
  const hdr = JSON.parse(Buffer.from(h, 'base64url'));
  const real = JSON.parse(Buffer.from(a.tokens[0].split('.')[0], 'base64url'));
  hdr.x5c[2] = real.x5c[2]; // claim the trusted root
  const r2 = await send(env, `${Buffer.from(JSON.stringify(hdr)).toString('base64url')}.${p}.${s}`);
  assert.deepEqual([r2.status, r2.code], [403, 'SUBSCRIPTION_INVALID']);
  assert.equal(env.AI.calls.length, 0);
});

test('Apple Root CA - G3 stays trusted next to the test root (genuine Sandbox tokens keep working)', async () => {
  assert.deepEqual(rootsFor('ab'.repeat(32)), [APPLE_ROOT_CA_G3_SHA256, 'ab'.repeat(32)]);
  assert.equal(rootsFor(null), null, 'no test root: the verifier default (Apple Root CA - G3 only)');
});

test('the same checks apply: wrong bundle id, wrong product, Production-less environments, revoked and expired tokens are refused', { skip }, async () => {
  const now = Date.now();
  const pki = await makePki({ validFrom: now - 60_000, validTo: now - 60_000 + ROOT_LIFETIME_MS });
  const rootB64 = Buffer.from(pki.certs.root).toString('base64');
  const env = makeEnv('staging', { [TEST_ROOT_VAR]: rootB64 });
  const base = { environment: 'Sandbox', signedDate: now - 30_000, expiresDate: now + TOKEN_LIFETIME_MS };
  const cases = [
    [{ ...base, originalTransactionId: 'a1', bundleId: 'com.other.app' }, 'SUBSCRIPTION_INVALID'],
    [{ ...base, originalTransactionId: 'a2', productId: 'other_product' }, 'SUBSCRIPTION_INVALID'],
    [{ ...base, originalTransactionId: 'a3', environment: 'Xcode' }, 'SUBSCRIPTION_INVALID'],
    [{ ...base, originalTransactionId: 'a4', environment: undefined }, 'SUBSCRIPTION_INVALID'],
    [{ ...base, originalTransactionId: 'a5', revocationDate: now - 1000 }, 'SUBSCRIPTION_REVOKED'],
    [{ ...base, originalTransactionId: 'a6', expiresDate: now - 3 * 3_600_000 }, 'SUBSCRIPTION_EXPIRED'],
    [{ ...base, originalTransactionId: 'a7', signedDate: now + 3_600_000 }, 'SUBSCRIPTION_INVALID'],
    [{ ...base, originalTransactionId: 'a8', signedDate: now - 2 * ROOT_LIFETIME_MS }, 'SUBSCRIPTION_INVALID'], // before the certificates existed
  ];
  for (const [over, code] of cases) {
    const r = await send(env, await pki.sign(txPayload(over)));
    assert.deepEqual([r.status, r.code], [403, code], JSON.stringify(over));
  }
  assert.equal(env.AI.calls.length, 0);
  // Control: the same chain with correct fields works.
  assert.equal((await send(env, await pki.sign(txPayload({ ...base, originalTransactionId: 'ok1' })))).status, 200);
});

test('an expired test token is rejected by staging (token expiry plus the 60-minute leeway)', { skip }, async () => {
  const a = await makeStagingAuth();
  const env = makeEnv('staging', { [TEST_ROOT_VAR]: a.rootB64 });
  assert.equal((await send(env, a.tokens[0])).status, 200);
  // Token expires at +50 min, accepted until +110 min; the root is still valid until +119 min.
  const r = await withNow(TOKEN_LIFETIME_MS + 61 * 60_000, () => send(env, a.tokens[0]));
  assert.deepEqual([r.status, r.code], [403, 'SUBSCRIPTION_EXPIRED']);
});

test('after the root expires (2 hours) staging stops trusting it by itself, with no redeploy', { skip }, async () => {
  const a = await makeStagingAuth();
  const env = makeEnv('staging', { [TEST_ROOT_VAR]: a.rootB64 });
  assert.equal((await send(env, a.tokens[0])).status, 200);
  const r = await withNow(ROOT_LIFETIME_MS + 5 * 60_000, () => send(env, a.tokens[0]));
  assert.deepEqual([r.status, r.code], [403, 'SUBSCRIPTION_INVALID']);
  // ...and a fresh token signed by a leaked-but-expired root is refused too (the cached verification is dropped).
  const env2 = makeEnv('staging', { [TEST_ROOT_VAR]: a.rootB64 });
  const r2 = await withNow(ROOT_LIFETIME_MS + 5 * 60_000, () => send(env2, a.tokens[0]));
  assert.equal(r2.status, 403);
});

test('a root valid longer than 2 hours, not yet valid, a non-CA or garbage is never trusted', { skip }, async () => {
  const now = Date.now();
  const rootOf = async (opts) => Buffer.from((await makePki(opts)).certs.root).toString('base64');
  assert.ok(await activeTestRoot({ [TEST_ROOT_VAR]: await rootOf({ validFrom: now - 60_000, validTo: now - 60_000 + ROOT_LIFETIME_MS }) }, now));
  assert.equal(await activeTestRoot({ [TEST_ROOT_VAR]: await rootOf({ validFrom: now - 60_000, validTo: now - 60_000 + MAX_TEST_ROOT_LIFETIME_MS + 1000 }) }, now), null, 'too long-lived');
  assert.equal(await activeTestRoot({ [TEST_ROOT_VAR]: await rootOf() }, now), null, 'one year');
  assert.equal(await activeTestRoot({ [TEST_ROOT_VAR]: await rootOf({ validFrom: now + 600_000, validTo: now + 3_000_000 }) }, now), null, 'not yet valid');
  for (const bad of ['', 'AAAA', '!!!', 'A'.repeat(20_000), 123, null, undefined]) assert.equal(await activeTestRoot({ [TEST_ROOT_VAR]: bad }, now), null);
  assert.equal(await activeTestRoot({}, now), null);
});

test('the 2,000-neuron cap holds: with ~107-neuron replies the staging budget admits 17 requests, then SERVICE_BUDGET_EXHAUSTED and no model call', { skip }, async () => {
  const a = await makeStagingAuth();
  const sse = 'data: {"response":"Hola"}\n\ndata: {"response":"","usage":{"prompt_tokens":1700,"completion_tokens":300}}\n\ndata: [DONE]\n\n';
  const ai = { calls: [], async run(m, i) { this.calls.push(m); return new Response(sse).body; } };
  // Only the per-minute limits are lifted so that the budget is what stops the run; budgets and caps are the real staging ones.
  const env = makeEnv('staging', { [TEST_ROOT_VAR]: a.rootB64, AI: ai, PER_MINUTE_LIMIT: '1000', IP_PER_MINUTE_LIMIT: '1000' });
  assert.equal(env.DAILY_NEURON_BUDGET, '2000');
  assert.equal(env.SANDBOX_NEURON_BUDGET, '2000');
  assert.equal(env.SANDBOX_DAILY_LIMIT, '20');
  let ok = 0;
  let last;
  for (let i = 0; i < 20; i++) {
    last = await send(env, a.tokens[0]);
    await new Promise((r) => setTimeout(r, 10)); // the settle runs after the stream ends
    if (last.status !== 200) break;
    ok++;
  }
  assert.equal(ok, 17); // 16 x 107 = 1712 spent, +209 reserve fits; 17 x 107 = 1819, +209 does not
  assert.deepEqual([last.status, last.code], [503, 'SERVICE_BUDGET_EXHAUSTED']);
  assert.equal(ai.calls.length, 17);
});

test('GET /?staging-neurons needs a valid token and reads the staging counter without changing it', { skip }, async () => {
  const a = await makeStagingAuth();
  const env = makeEnv('staging', { [TEST_ROOT_VAR]: a.rootB64 });
  const get = (jws) => staging.fetch(new Request('https://worker.invalid/?staging-neurons', { headers: jws ? { 'X-DateWise-Entitlement': jws } : {} }), env, {});
  assert.equal((await get(null)).status, 403);
  const other = await makePki();
  assert.equal((await get(await other.sign(txPayload({ environment: 'Sandbox' })))).status, 403);
  const before = await (await get(a.tokens[0])).json();
  assert.equal(before.cap, 2000);
  assert.equal(before.spent, 0);
  await send(env, a.tokens[0]);
  await new Promise((r) => setTimeout(r, 20)); // settle runs after the stream ends
  const after = await (await get(a.tokens[0])).json();
  const again = await (await get(a.tokens[0])).json();
  assert.ok(after.spent > 0 && after.spent <= 2000);
  assert.equal(again.spent, after.spent, 'reading does not change the counter');
});

test('the minting tool: 2-hour root, 50-minute tokens, real ids, Sandbox, public root only on disk, tokens 0600', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'sa-'));
  try {
    const r = spawnSync('node', [fileURLToPath(new URL('../tool/live/staging_auth.mjs', import.meta.url)), '--out-dir', dir, '--count', '2'], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(readdirSync(dir).sort(), ['root.b64', 'tokens']);
    assert.equal(statSync(join(dir, 'tokens')).mode & 0o777, 0o600);
    const tokens = readFileSync(join(dir, 'tokens'), 'utf8').trim().split('\n');
    assert.equal(tokens.length, 2);
    const all = r.stdout + r.stderr + readFileSync(join(dir, 'root.b64'), 'utf8');
    for (const t of tokens) {
      assert.ok(!all.includes(t.split('.')[2]), 'tokens are never printed');
      const p = JSON.parse(Buffer.from(t.split('.')[1], 'base64url'));
      assert.equal(p.bundleId, 'com.datewise.datewiseAi');
      assert.equal(p.productId, 'datewise_premium_monthly');
      assert.equal(p.environment, 'Sandbox');
      assert.ok(p.expiresDate - p.signedDate <= TOKEN_LIFETIME_MS + 60_000);
    }
    assert.notEqual(JSON.parse(Buffer.from(tokens[0].split('.')[1], 'base64url')).originalTransactionId, JSON.parse(Buffer.from(tokens[1].split('.')[1], 'base64url')).originalTransactionId);
    assert.ok(!/PRIVATE|BEGIN/.test(all));
    // The root file is a DER certificate only.
    const der = Buffer.from(readFileSync(join(dir, 'root.b64'), 'utf8').trim(), 'base64');
    assert.equal(der[0], 0x30);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  assert.ok(!existsSync(dir));
  assert.equal(ROOT_LIFETIME_MS, 2 * 3_600_000);
  assert.ok(TOKEN_LIFETIME_MS + 60 * 60_000 < ROOT_LIFETIME_MS, 'token expiry plus the Worker leeway ends before the root does');
});

// --- review hardening of GET /?staging-neurons --------------------------------------------------------
test('/?staging-neurons fails safe: generic bodies, no cost before a verified token, rate limited, DO errors are 503 without detail', { skip }, async () => {
  const a = await makeStagingAuth();
  const mk = (extra = {}) => makeEnv('staging', { [TEST_ROOT_VAR]: a.rootB64, ...extra });
  const get = (env, jws) => staging.fetch(new Request('https://worker.invalid/?staging-neurons', { headers: jws ? { 'X-DateWise-Entitlement': jws } : {} }), env, {});
  // No token, or an absurdly long one: 403 before any verification, limiter or Durable Object call.
  let calls = 0;
  const counting = mk({ RATE_LIMITER: { limit: async () => { calls++; return { success: true }; } } });
  assert.equal((await get(counting, null)).status, 403);
  assert.equal((await get(counting, 'x'.repeat(9_000))).status, 403);
  assert.equal(calls, 0, 'no limiter or other work without a plausible token');
  // Rate limited: 429 with a generic body.
  const limited = await get(mk({ RATE_LIMITER: { limit: async () => ({ success: false }) } }), a.tokens[0]);
  assert.equal(limited.status, 429);
  assert.deepEqual(await limited.json(), { code: 'RATE_LIMITED' });
  // A failing limiter and a failing Durable Object: 503, nothing but the code (no message, no stack).
  for (const env of [mk({ RATE_LIMITER: { limit: async () => { throw new Error('secret internal detail at /src/x.js:1'); } } }), (() => {
    const e = mk();
    e.USAGE_GUARD = { idFromName: () => 'id', get: () => ({ fetch: async () => { throw new Error('secret internal detail at /src/x.js:1'); } }) };
    return e;
  })()]) {
    const res = await get(env, a.tokens[0]);
    assert.equal(res.status, 503);
    const text = await res.text();
    assert.deepEqual(JSON.parse(text), { code: 'UNAVAILABLE' });
    assert.ok(!/secret|stack|\.js/.test(text));
  }
  // Still works normally.
  assert.equal((await (await get(mk(), a.tokens[0])).json()).cap, 2000);
});

test('worst case: one request can reserve 324 neurons (6,000 input + 800 output); the workflow pre-flight uses 324, not 209', async () => {
  const { neuronsFor } = await import('./cost_guard.js');
  assert.equal(neuronsFor('@cf/meta/llama-3.3-70b-instruct-fp8-fast', 6000, 800), 324);
  const wf = readFileSync(new URL('../.github/workflows/live-ai-test-staging.yml', import.meta.url), 'utf8');
  assert.match(wf, /RESERVE_NEURONS: '324'/);
  assert.match(wf, /PER_DAY: '14'/);
});
