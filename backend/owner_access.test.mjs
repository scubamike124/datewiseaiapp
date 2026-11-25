// Owner-only premium access: node --test backend/owner_access.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import worker from './worker.js';
import { _setTrustedRootsForTests } from './cost_guard.js';
import { issueOwnerToken } from './owner_access.js';
import { fakeDoNamespace, makePki, txPayload } from './test/helpers.mjs';

const pki = await makePki();
_setTrustedRootsForTests([pki.rootSha256]);
const SECRET = 'owner-secret-0123456789abcdef';
const DEV = 'a'.repeat(32);
const chat = { tier: 'magnet', coachId: 'ava', messages: [{ role: 'user', content: 'hi' }] };
const sse = () => new Response('data: {"response":"Hi"}\n\ndata: [DONE]\n\n').body;
const mkEnv = (extra = {}) => ({
  AI: { run: async () => sse() },
  USAGE_GUARD: fakeDoNamespace(),
  DAILY_NEURON_BUDGET: '1000000',
  OWNER_ACCESS_SECRET: SECRET,
  ...extra,
});
let ip = 0;
const req = (path, body, headers = {}, addr = `10.0.0.${++ip}`) =>
  new Request(`https://w.example.workers.dev${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': addr, ...headers },
    body: JSON.stringify(body),
  });
const redeem = (env, code, addr) => worker.fetch(req('/owner/redeem', { code, deviceId: DEV }, {}, addr), env);
const askChat = (env, headers) => worker.fetch(req('/', chat, headers), env);

test('right code issues a token that unlocks chat with normal limits', async () => {
  const env = mkEnv();
  const r = await redeem(env, SECRET);
  assert.equal(r.status, 200);
  const { token, expiresAt } = await r.json();
  assert.ok(expiresAt > Date.now() + 29 * 86400_000);
  const res = await askChat(env, { 'X-DateWise-Owner': token });
  assert.equal(res.status, 200);
  assert.ok(res.headers.get('X-DateWise-Remaining-Today'), 'normal usage counters apply');
  assert.equal((await redeem(env, SECRET)).status, 200);
});

test('wrong code is refused and issues nothing', async () => {
  const r = await redeem(mkEnv(), 'nope');
  assert.equal(r.status, 403);
  assert.ok(!JSON.stringify(await r.json()).includes('o1.'));
});

test('disabled without the secret (or a short one): 404, tokens never accepted', async () => {
  for (const extra of [{ OWNER_ACCESS_SECRET: undefined }, { OWNER_ACCESS_SECRET: '' }, { OWNER_ACCESS_SECRET: 'short' }]) {
    const env = mkEnv(extra);
    assert.equal((await redeem(env, extra.OWNER_ACCESS_SECRET ?? '')).status, 404);
    const { token } = await issueOwnerToken({ OWNER_ACCESS_SECRET: SECRET }, DEV, Date.now());
    const res = await askChat(env, { 'X-DateWise-Owner': token });
    assert.equal((await res.json()).code, 'SUBSCRIPTION_REQUIRED');
  }
});

test('attempts are rate limited per network, even for the right code afterwards', async () => {
  const env = mkEnv();
  const codes = [];
  for (let i = 0; i < 7; i++) codes.push((await redeem(env, i < 6 ? 'bad' + i : SECRET, '9.9.9.9')).status);
  assert.deepEqual(codes.slice(0, 5), [403, 403, 403, 403, 403]);
  assert.equal(codes[5], 429);
  assert.equal(codes[6], 429);
});

test('rate limit fails closed when the guard is down', async () => {
  const r = await redeem(mkEnv({ USAGE_GUARD: fakeDoNamespace({ fail: true }) }), SECRET);
  assert.equal(r.status, 503);
});

test('expired token is refused', async () => {
  const env = mkEnv();
  const { token } = await issueOwnerToken(env, DEV, Date.now() - 31 * 86400_000);
  assert.equal((await (await askChat(env, { 'X-DateWise-Owner': token })).json()).code, 'SUBSCRIPTION_REQUIRED');
});

test('tampered tokens are refused (device, expiry, signature, junk)', async () => {
  const env = mkEnv();
  const { token } = await issueOwnerToken(env, DEV, Date.now());
  const [v, d, e, s] = token.split('.');
  const bad = [`${v}.${'b'.repeat(32)}.${e}.${s}`, `${v}.${d}.${Number(e) + 999999}.${s}`, `${v}.${d}.${e}.${s.slice(0, -2)}xx`, `${v}.${d}.${e}`, 'o1', `${token}.x`];
  for (const t of bad) assert.equal((await (await askChat(env, { 'X-DateWise-Owner': t })).json()).code, 'SUBSCRIPTION_REQUIRED', t);
});

test('rotating the secret revokes the code and all tokens', async () => {
  const env = mkEnv();
  const { token } = await (await redeem(env, SECRET)).json();
  const rotated = { ...env, OWNER_ACCESS_SECRET: 'rotated-secret-fedcba9876543210' };
  assert.equal((await (await askChat(rotated, { 'X-DateWise-Owner': token })).json()).code, 'SUBSCRIPTION_REQUIRED');
  assert.equal((await redeem(rotated, SECRET)).status, 403);
});

test('renew: valid token returns a token for the same device; invalid is refused', async () => {
  const env = mkEnv();
  const old = await issueOwnerToken(env, DEV, Date.now() - 25 * 86400_000);
  const r = await worker.fetch(req('/owner/renew', { token: old.token }), env);
  const { token, expiresAt } = await r.json();
  assert.ok(expiresAt > Date.now() + 29 * 86400_000);
  assert.ok(token.split('.')[1] === DEV);
  assert.equal((await worker.fetch(req('/owner/renew', { token: 'o1.x.1.y' }), env)).status, 403);
});

test('customer path unchanged: a real-shaped JWS works, synthetic receipts are still rejected', async () => {
  const env = mkEnv();
  const jws = await pki.sign(txPayload());
  assert.equal((await askChat(env, { 'X-DateWise-Entitlement': jws })).status, 200);
  const forged = await (await makePki()).sign(txPayload());
  const res = await askChat(env, { 'X-DateWise-Entitlement': forged });
  assert.equal((await res.json()).code, 'SUBSCRIPTION_INVALID');
  // An owner token never rescues a bad receipt's refusal when the token itself is invalid.
  const res2 = await askChat(env, { 'X-DateWise-Entitlement': forged, 'X-DateWise-Owner': 'o1.bad' });
  assert.equal((await res2.json()).code, 'SUBSCRIPTION_INVALID');
});

test('no subscription and no owner token: still SUBSCRIPTION_REQUIRED', async () => {
  assert.equal((await (await askChat(mkEnv(), {})).json()).code, 'SUBSCRIPTION_REQUIRED');
});
