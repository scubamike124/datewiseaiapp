/**
 * Entry point of the STAGING Worker only (wrangler.toml [env.staging] main).
 * The production Worker's `main` is worker.js, so nothing in this file is in
 * the production bundle (CI compares the production bundle byte for byte, and
 * a test checks that none of this file's strings are in it).
 *
 * What it adds on top of worker.js, and nothing else:
 *
 * 1. A throwaway test root for the automated live AI test
 *    (docs/qa/STAGING_TEST_AUTH_THREAT_MODEL.md). The workflow generates a CA
 *    on its runner, deploys only the PUBLIC root certificate here as the var
 *    STAGING_TEST_ROOT_CERT_B64 (DER, base64), signs test StoreKit tokens with
 *    the CA and then throws the private key away. This file makes the verifier
 *    trust that root IN ADDITION to Apple Root CA - G3 (so genuine Apple
 *    Sandbox tokens still work). Every other check is unchanged: the same
 *    verifyAppleJws / checkEntitlement code runs (chain, signature, marker
 *    OIDs, bundle id, product id, Sandbox, expiry, revocation).
 *    The root is trusted only while all of this holds, re-checked per request:
 *      - it parses as a CA certificate and is not Apple's root;
 *      - its validity window is at most MAX_TEST_ROOT_LIFETIME_MS (2 hours), so
 *        even a deployment that is never cleaned up stops trusting it by itself;
 *      - the current time is inside that window.
 *    Anything else (missing, malformed, too long-lived, expired) leaves the
 *    default: Apple Root CA - G3 only.
 *
 * 2. GET /?staging-neurons (needs a valid entitlement header): today's neuron
 *    spend of this staging Worker's own budget counter, read with a zero-neuron
 *    budget probe (it changes nothing). The workflow uses it to refuse to start
 *    at the cap and to print the usage after the run.
 */
import worker from './worker.js';
import { _setTrustedRootsForTests, checkEntitlement, guardConfig } from './cost_guard.js';
import { APPLE_ROOT_CA_G3_SHA256, parseCertificate, sha256Hex } from './apple_jws.js';

export { UsageGuard } from './worker.js';

export const TEST_ROOT_VAR = 'STAGING_TEST_ROOT_CERT_B64';
export const MAX_TEST_ROOT_LIFETIME_MS = 2 * 60 * 60_000;
const MAX_ROOT_DER_BYTES = 2_000;

let applied; // the root fingerprint currently trusted in addition to Apple's (null: none)

/** SHA-256 (hex) of the test root to trust now, or null. Never throws. */
export async function activeTestRoot(env, now) {
  const raw = env?.[TEST_ROOT_VAR];
  if (typeof raw !== 'string' || !raw || raw.length > 4 * MAX_ROOT_DER_BYTES || !/^[A-Za-z0-9+/]+={0,2}$/.test(raw)) return null;
  try {
    const bin = atob(raw);
    if (bin.length > MAX_ROOT_DER_BYTES) return null;
    const der = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    const cert = parseCertificate(der);
    if (cert.isCa !== true) return null;
    if (cert.notAfter - cert.notBefore > MAX_TEST_ROOT_LIFETIME_MS) return null;
    if (now < cert.notBefore || now > cert.notAfter) return null;
    const fp = await sha256Hex(der);
    return fp === APPLE_ROOT_CA_G3_SHA256 ? null : fp;
  } catch {
    return null;
  }
}

/** The roots to trust: Apple Root CA - G3 always, plus the active test root. null = the verifier's default (Apple only). */
export const rootsFor = (fp) => (fp ? [APPLE_ROOT_CA_G3_SHA256, fp] : null);

async function applyRoots(env, now) {
  const fp = await activeTestRoot(env, now);
  if (fp === applied) return;
  applied = fp;
  // The call also empties the verified-JWS cache.
  _setTrustedRootsForTests(rootsFor(fp));
}

async function stagingNeurons(request, env, now) {
  const jws = request.headers.get('X-DateWise-Entitlement') || '';
  const cfg = guardConfig(env);
  const r = jws ? await checkEntitlement(jws, cfg, now) : { code: 'SUBSCRIPTION_REQUIRED' };
  if (!r.tx) return Response.json({ code: r.code }, { status: 403 });
  const stub = env.USAGE_GUARD.get(env.USAGE_GUARD.idFromName('global'));
  const res = await stub.fetch('https://usage-guard/budget', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ now, neurons: 0, daily: cfg.DAILY_NEURON_BUDGET, monthly: 0, anon: false, anonDaily: 0, sandbox: false, sandboxDaily: 0 }),
  });
  const b = await res.json();
  // ok:false only when the day's spend is already above the cap.
  return Response.json({ day: new Date(now).toISOString().slice(0, 10), spent: b.ok ? b.spent : null, cap: cfg.DAILY_NEURON_BUDGET, overCap: !b.ok });
}

export default {
  async fetch(request, env, ctx) {
    const now = Date.now();
    await applyRoots(env, now);
    const url = new URL(request.url);
    if (request.method === 'GET' && url.searchParams.has('staging-neurons')) return stagingNeurons(request, env, now);
    return worker.fetch(request, env, ctx);
  },
};
