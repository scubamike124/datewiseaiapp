// Hosted avatar pilot endpoints (node --test backend/avatar.test.mjs).
// A fake vendor replaces fetch; nothing touches the network and no real key exists.
import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import worker from './worker.js';
import { _setTrustedRootsForTests } from './cost_guard.js';
import { avatarConfig } from './avatar.js';
import { fakeAi, fakeDoNamespace, makePki, txPayload } from './test/helpers.mjs';

const pki = await makePki();
_setTrustedRootsForTests([pki.rootSha256]);
const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

const KEY = 'sk-test-SECRET-do-not-leak-123';
let ipSeq = 0;
const baseVars = (over = {}) => ({
  AVATAR_PROVIDER: 'simli',
  SIMLI_API_KEY: KEY,
  ANAM_API_KEY: KEY,
  AVATAR_FACE_IDS: JSON.stringify({ ava: 'face-ava', sofia: 'face-sofia' }),
  ID_HASH_SALT: 'test-salt',
  ...over,
});
const makeEnv = (vars = {}, ns = fakeDoNamespace()) => ({ AI: fakeAi(), USAGE_GUARD: ns, DAILY_NEURON_BUDGET: '100000000', ...baseVars(vars) });

function fakeVendor({ status = 200, body } = {}) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (status !== 200) return new Response('{"detail":"vendor says SECRET"}', { status });
    const u = String(url);
    return new Response(JSON.stringify(body ?? (u.includes('simli') ? { session_token: 'tok-simli' } : { sessionToken: 'tok-anam' })), { status: 200 });
  };
  return calls;
}

async function call(env, action, { jws, body = {}, ip = `203.0.113.${++ipSeq}` } = {}) {
  const headers = { 'Content-Type': 'application/json', 'CF-Connecting-IP': ip };
  if (jws) headers['X-DateWise-Entitlement'] = jws;
  const res = await worker.fetch(new Request(`https://x.workers.dev/v1/avatar/${action}`, { method: 'POST', headers, body: JSON.stringify(body) }), env, { waitUntil() {} });
  const text = await res.text();
  return { res, text, json: JSON.parse(text) };
}
const sub = (over) => pki.sign(txPayload({ originalTransactionId: String(4000000000000000 + ++ipSeq), ...over }));

test('provider off (and unset, and junk) => AVATAR_UNAVAILABLE, no vendor call', async () => {
  const calls = fakeVendor();
  const jws = await sub();
  for (const v of ['off', undefined, 'bogus']) {
    const env = makeEnv({ AVATAR_PROVIDER: v });
    const r = await call(env, 'session', { jws, body: { coachId: 'ava' } });
    assert.equal(r.res.status, 503);
    assert.equal(r.json.code, 'AVATAR_UNAVAILABLE');
  }
  assert.equal(calls.length, 0);
});

test('provider on but secret missing => unavailable', async () => {
  const calls = fakeVendor();
  const r = await call(makeEnv({ SIMLI_API_KEY: undefined }), 'session', { jws: await sub(), body: { coachId: 'ava' } });
  assert.equal(r.res.status, 503);
  assert.equal(r.json.reason, 'not_configured');
  assert.equal(calls.length, 0);
});

test('no entitlement, forged entitlement, expired entitlement => 403 and no vendor call', async () => {
  const calls = fakeVendor();
  const env = makeEnv();
  assert.equal((await call(env, 'session', { body: { coachId: 'ava' } })).res.status, 403);
  assert.equal((await call(env, 'session', { jws: 'a.b.c', body: { coachId: 'ava' } })).res.status, 403);
  const expired = await sub({ expiresDate: Date.now() - 10 * 86_400_000 });
  const r = await call(env, 'session', { jws: expired, body: { coachId: 'ava' } });
  assert.equal(r.res.status, 403);
  assert.equal(r.json.code, 'SUBSCRIPTION_EXPIRED');
  assert.equal(calls.length, 0);
});

test('Xcode / unknown environment refused, Sandbox accepted like chat', async () => {
  fakeVendor();
  const env = makeEnv();
  assert.equal((await call(env, 'session', { jws: await sub({ environment: 'Xcode' }), body: { coachId: 'ava' } })).res.status, 403);
  assert.equal((await call(env, 'session', { jws: await sub({ environment: 'Sandbox' }), body: { coachId: 'ava' } })).res.status, 200);
  assert.equal((await call(makeEnv({ ALLOW_SANDBOX: '0' }), 'session', { jws: await sub({ environment: 'Sandbox' }), body: { coachId: 'ava' } })).res.status, 403);
});

test('simli: success returns only the short-lived token and client config; the key is sent to the vendor only', async () => {
  const calls = fakeVendor();
  const r = await call(makeEnv({ AVATAR_SESSION_MAX_SECONDS: '300' }), 'session', { jws: await sub(), body: { coachId: 'ava' } });
  assert.equal(r.res.status, 200);
  assert.equal(r.json.vendor, 'simli');
  assert.equal(r.json.sessionToken, 'tok-simli');
  assert.equal(r.json.maxSeconds, 300);
  assert.deepEqual(r.json.audio, { encoding: 'pcm_s16le', sampleRate: 16000, channels: 1 });
  assert.equal(r.json.allowance.totalSeconds, 3600);
  assert.ok(!r.text.includes(KEY));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://api.simli.ai/compose/token');
  assert.equal(calls[0].init.headers['x-simli-api-key'], KEY);
  const sent = JSON.parse(calls[0].init.body);
  assert.deepEqual(sent, { faceId: 'face-ava', handleSilence: true, maxSessionLength: 300, maxIdleTime: 60 });
});

test('anam: bearer key, audio passthrough, short token', async () => {
  const calls = fakeVendor();
  const r = await call(makeEnv({ AVATAR_PROVIDER: 'anam' }), 'session', { jws: await sub(), body: { coachId: 'sofia' } });
  assert.equal(r.res.status, 200);
  assert.equal(r.json.sessionToken, 'tok-anam');
  assert.equal(r.json.audio.sampleRate, 24000);
  assert.ok(!r.text.includes(KEY));
  assert.equal(calls[0].url, 'https://api.anam.ai/v1/auth/session-token');
  assert.equal(calls[0].init.headers.Authorization, `Bearer ${KEY}`);
  const sent = JSON.parse(calls[0].init.body);
  assert.equal(sent.personaConfig.enableAudioPassthrough, true);
  assert.equal(sent.personaConfig.avatarId, 'face-sofia');
  assert.equal(sent.expiresInSeconds, 120);
});

test('session length is capped at 10 minutes whatever the variable says', () => {
  assert.equal(avatarConfig({ AVATAR_SESSION_MAX_SECONDS: '99999' }).maxSec, 600);
  assert.equal(avatarConfig({}).provider, 'off');
  assert.equal(avatarConfig({ AVATAR_MONTHLY_MINUTES: 'x' }).monthlySec, 3600);
});

test('vendor error or bad body => unavailable, vendor text and key never returned or logged, nothing stays reserved', async () => {
  const logs = [];
  const orig = console.log;
  console.log = (...a) => logs.push(a.join(' '));
  try {
    const env = makeEnv();
    const jws = await sub();
    fakeVendor({ status: 500 });
    let r = await call(env, 'session', { jws, body: { coachId: 'ava' } });
    assert.equal(r.res.status, 503);
    assert.equal(r.json.code, 'AVATAR_UNAVAILABLE');
    assert.ok(!r.text.includes('SECRET') && !r.text.includes(KEY));
    fakeVendor({ body: { nothing: true } });
    r = await call(env, 'session', { jws, body: { coachId: 'ava' } });
    assert.equal(r.res.status, 503);
    // The failed opens were refunded: the full allowance is still there.
    fakeVendor();
    r = await call(env, 'session', { jws, body: { coachId: 'ava' } });
    assert.equal(r.res.status, 200);
    assert.ok(r.json.allowance.usedSeconds <= 600 + 5, 'only the live grant is reserved');
  } finally {
    console.log = orig;
  }
  const all = logs.join('\n');
  assert.ok(!all.includes(KEY) && !all.includes('SECRET'));
  assert.ok(!all.includes('203.0.113'), 'no IP in logs');
});

test('vendor network failure (fetch throws) => unavailable', async () => {
  globalThis.fetch = async () => {
    throw new Error('network down');
  };
  const r = await call(makeEnv(), 'session', { jws: await sub(), body: { coachId: 'ava' } });
  assert.equal(r.res.status, 503);
  assert.equal(r.json.code, 'AVATAR_UNAVAILABLE');
});

test('unknown coach or no face mapped => unavailable (app falls back)', async () => {
  const calls = fakeVendor();
  const env = makeEnv();
  assert.equal((await call(env, 'session', { jws: await sub(), body: { coachId: 'diego' } })).json.reason, 'no_face');
  assert.equal((await call(env, 'session', { jws: await sub(), body: { coachId: 'nobody' } })).json.reason, 'no_face');
  assert.equal(calls.length, 0);
});

test('monthly allowance: over allowance => 429 AVATAR_ALLOWANCE, end refunds unused time', async () => {
  fakeVendor();
  const env = makeEnv({ AVATAR_MONTHLY_MINUTES: '12', AVATAR_SESSION_MAX_SECONDS: '600' });
  const jws = await sub();
  // First session reserves 600 s of 720 s.
  const a = await call(env, 'session', { jws, body: { coachId: 'ava' } });
  assert.equal(a.res.status, 200);
  assert.equal(a.json.maxSeconds, 600);
  // Second while the first is live: busy.
  assert.equal((await call(env, 'session', { jws, body: { coachId: 'ava' } })).json.code, 'AVATAR_BUSY');
  // End right away: charged ~0-2 s, 598+ refunded.
  const e = await call(env, 'end', { jws, body: { sessionId: a.json.sessionId } });
  assert.equal(e.res.status, 200);
  assert.ok(e.json.usedSeconds <= 3);
  // Burn the allowance: never-ended sessions are charged in full.
  const ns = env.USAGE_GUARD;
  const b = await call(env, 'session', { jws, body: { coachId: 'ava' } });
  assert.equal(b.json.maxSeconds, 600);
  // Pretend the app crashed 25 s later (no heartbeat): next open settles it in full (600 s) and has 120 s left.
  const realNow = Date.now;
  Date.now = () => realNow() + 25_000;
  try {
    const c = await call(env, 'session', { jws, body: { coachId: 'ava' } });
    assert.equal(c.res.status, 200);
    assert.ok(c.json.maxSeconds <= 120 && c.json.maxSeconds >= 118, `remaining grant ${c.json.maxSeconds}`);
    await call(env, 'end', { jws, body: { sessionId: c.json.sessionId } });
    Date.now = () => realNow() + 60 * 60_000;
    // 600+ s used of 720: only ~118 s remain, a fresh session is granted that much; after it runs out: 429.
    const d = await call(env, 'session', { jws, body: { coachId: 'ava' } });
    assert.equal(d.res.status, 200);
    Date.now = () => realNow() + 60 * 60_000 + 200_000;
    // d never ended: charged in full.
    const f = await call(env, 'session', { jws, body: { coachId: 'ava' } });
    assert.equal(f.res.status, 429);
    assert.equal(f.json.code, 'AVATAR_ALLOWANCE');
    assert.equal(f.json.allowanceSeconds, 720);
    assert.ok(f.json.resetAt > Date.now());
  } finally {
    Date.now = realNow;
  }
  assert.ok(ns.requests > 0);
});

test('allowance is per subscriber: another subscriber is unaffected', async () => {
  fakeVendor();
  const env = makeEnv({ AVATAR_MONTHLY_MINUTES: '1' });
  const a = await sub();
  const b = await sub();
  assert.equal((await call(env, 'session', { jws: a, body: { coachId: 'ava' } })).json.maxSeconds, 60);
  assert.equal((await call(env, 'session', { jws: b, body: { coachId: 'ava' } })).res.status, 200);
});

test('global daily cap => 429 AVATAR_DAILY_CAP and the subscriber reservation is released', async () => {
  fakeVendor();
  const env = makeEnv({ AVATAR_DAILY_MINUTES: '10', AVATAR_SESSION_MAX_SECONDS: '600' });
  const s1 = await sub();
  const s2 = await sub();
  assert.equal((await call(env, 'session', { jws: s1, body: { coachId: 'ava' } })).res.status, 200);
  const r = await call(env, 'session', { jws: s2, body: { coachId: 'ava' } });
  assert.equal(r.res.status, 429);
  assert.equal(r.json.code, 'AVATAR_DAILY_CAP');
  // s2 holds no reservation: raising the cap lets it in with the full month.
  env.AVATAR_DAILY_MINUTES = '100';
  const again = await call(env, 'session', { jws: s2, body: { coachId: 'ava' } });
  assert.equal(again.res.status, 200);
  assert.ok(again.json.allowance.usedSeconds <= 605);
});

test('heartbeat and end need the same entitlement; unknown or malformed ids are refused', async () => {
  fakeVendor();
  const env = makeEnv();
  const jws = await sub();
  const a = await call(env, 'session', { jws, body: { coachId: 'ava' } });
  assert.equal((await call(env, 'heartbeat', { body: { sessionId: a.json.sessionId } })).res.status, 403);
  assert.equal((await call(env, 'end', { body: { sessionId: a.json.sessionId } })).res.status, 403);
  assert.equal((await call(env, 'heartbeat', { jws, body: { sessionId: 'nope' } })).res.status, 404);
  const hb = await call(env, 'heartbeat', { jws, body: { sessionId: a.json.sessionId } });
  assert.equal(hb.res.status, 200);
  assert.ok(hb.json.remainingSessionSeconds <= 600);
  // Another subscriber cannot touch this session id.
  const other = await sub();
  assert.equal((await call(env, 'heartbeat', { jws: other, body: { sessionId: a.json.sessionId } })).res.status, 404);
});

test('guard unavailable (no Durable Object) fails closed', async () => {
  const calls = fakeVendor();
  const env = makeEnv();
  delete env.USAGE_GUARD;
  const r = await call(env, 'session', { jws: await sub(), body: { coachId: 'ava' } });
  assert.equal(r.res.status, 503);
  assert.equal(calls.length, 0);
  const down = makeEnv({}, fakeDoNamespace({ fail: true }));
  const r2 = await call(down, 'session', { jws: await sub(), body: { coachId: 'ava' } });
  assert.equal(r2.res.status, 503);
  assert.equal(calls.length, 0);
});

test('per-subscriber open rate limit', async () => {
  fakeVendor();
  const env = makeEnv();
  const jws = await sub();
  let limited = 0;
  for (let i = 0; i < 14; i++) {
    const r = await call(env, 'session', { jws, body: { coachId: 'ava' } });
    if (r.res.status === 200) await call(env, 'end', { jws, body: { sessionId: r.json.sessionId } });
    else if (r.json.code === 'RATE_LIMITED') limited++;
  }
  assert.ok(limited >= 1);
});

test('GET and bad JSON are refused', async () => {
  const env = makeEnv();
  const g = await worker.fetch(new Request('https://x.workers.dev/v1/avatar/session'), env, {});
  assert.equal(g.status, 405);
  const bad = await worker.fetch(new Request('https://x.workers.dev/v1/avatar/session', { method: 'POST', body: '{nope' }), env, {});
  assert.equal(bad.status, 400);
});
