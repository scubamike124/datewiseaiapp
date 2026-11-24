// Owner-only premium access (docs/OWNER_ACCESS.md). The owner redeems a one-time code (the Worker secret
// OWNER_ACCESS_SECRET) and gets a signed, short-lived token bound to a random device id. The cost guard accepts
// the token in `X-DateWise-Owner` as a premium entitlement with the normal Production limits. Customers' Apple
// verification is untouched. Without the secret (or if it is shorter than 16 characters) everything is disabled.
// Rotating the secret revokes the code and every token. Codes and tokens are never logged.
import { sha256Hex } from './apple_jws.js';

const enc = new TextEncoder();
export const OWNER_TOKEN_DAYS = 30;
const RENEW_WINDOW_DAYS = 10; // the app renews when fewer days than this remain
const DEVICE_RE = /^[0-9a-f]{32}$/;
const MAX_FAILS_PER_IP_HOUR = 5;
const MAX_FAILS_ALL_HOUR = 30;

const b64u = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

export const ownerEnabled = (env) => typeof env.OWNER_ACCESS_SECRET === 'string' && env.OWNER_ACCESS_SECRET.length >= 16;

async function hmac(secret, msg) {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return b64u(await crypto.subtle.sign('HMAC', key, enc.encode(msg)));
}

/** Constant-time string compare (equal-length digests). */
function same(a, b) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function sign(env, deviceId, exp) {
  return hmac(env.OWNER_ACCESS_SECRET, `datewise-owner-token-v1|${deviceId}|${exp}`);
}

export async function issueOwnerToken(env, deviceId, now) {
  const exp = Math.floor(now / 1000) + OWNER_TOKEN_DAYS * 86400;
  return { token: `o1.${deviceId}.${exp}.${await sign(env, deviceId, exp)}`, expiresAt: exp * 1000 };
}

/** Returns { deviceId, expiresAt } for a valid, unexpired token, else null. */
export async function verifyOwnerToken(token, env, now) {
  if (!ownerEnabled(env) || typeof token !== 'string' || token.length > 200) return null;
  const [v, deviceId, expS, sig, extra] = token.split('.');
  if (v !== 'o1' || extra !== undefined || !DEVICE_RE.test(deviceId || '') || !/^\d{1,12}$/.test(expS || '') || !sig) return null;
  const exp = Number(expS);
  if (!same(sig, await sign(env, deviceId, exp))) return null;
  if (now >= exp * 1000) return null;
  return { deviceId, expiresAt: exp * 1000 };
}

export async function ownerKey(cfg, deviceId) {
  return 'own:' + (await sha256Hex(enc.encode(`${cfg.ID_HASH_SALT}|owner|${deviceId}`)));
}

const jsonRes = (body, status, cors) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...cors } });

/**
 * POST /owner/redeem {code, deviceId} or /owner/renew {token}. `attempt(name, max)` is the durable counter
 * (UsageGuard 'owner-attempt'); it throws when the guard is down, which fails closed.
 */
export async function handleOwner(request, env, cors, { path, ipHash, now, attempt }) {
  // Disabled: indistinguishable from a route that does not exist.
  if (!ownerEnabled(env)) return jsonRes({ error: 'Not found' }, 404, cors);
  let body;
  try {
    const text = await request.text();
    if (text.length > 2000) return jsonRes({ error: 'Invalid request' }, 400, cors);
    body = JSON.parse(text);
  } catch {
    return jsonRes({ error: 'Invalid request' }, 400, cors);
  }
  let ok;
  try {
    // Every attempt counts before the code is looked at; the global bound stops distributed guessing.
    const ip = await attempt(`ownerauth:${ipHash}`, MAX_FAILS_PER_IP_HOUR, now);
    const all = await attempt('ownerauth:all', MAX_FAILS_ALL_HOUR, now);
    ok = ip && all;
  } catch {
    return jsonRes({ error: 'Unavailable' }, 503, cors);
  }
  if (!ok) return jsonRes({ error: 'Too many attempts', code: 'RATE_LIMITED' }, 429, { ...cors, 'Retry-After': '3600' });

  if (path === '/owner/redeem') {
    const { code, deviceId } = body || {};
    if (typeof code !== 'string' || code.length > 200 || !DEVICE_RE.test(String(deviceId || ''))) {
      return jsonRes({ error: 'Invalid code' }, 403, cors);
    }
    const good = same(await hmac(env.OWNER_ACCESS_SECRET, `datewise-owner-code-v1|${code}`), await hmac(env.OWNER_ACCESS_SECRET, `datewise-owner-code-v1|${env.OWNER_ACCESS_SECRET}`));
    if (!good) return jsonRes({ error: 'Invalid code' }, 403, cors);
    return jsonRes(await issueOwnerToken(env, deviceId, now), 200, cors);
  }
  // Renew: only a still-valid token near its end gets a fresh one for the same device.
  const v = await verifyOwnerToken(body?.token, env, now);
  if (!v) return jsonRes({ error: 'Invalid token' }, 403, cors);
  if (v.expiresAt - now > RENEW_WINDOW_DAYS * 86400_000) return jsonRes({ token: body.token, expiresAt: v.expiresAt }, 200, cors);
  return jsonRes(await issueOwnerToken(env, v.deviceId, now), 200, cors);
}

/** Durable Object side: counts attempts per key per hour. */
export async function ownerAttemptOp(storage, { now, max }) {
  const hour = Math.floor(now / 3_600_000);
  const s = (await storage.get('oa')) || {};
  if (s.hour !== hour) Object.assign(s, { hour, n: 0 });
  s.n += 1;
  await storage.put('oa', s);
  return { ok: s.n <= max };
}
