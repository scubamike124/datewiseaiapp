/**
 * DateWise cost guard (chat-v7): server-side fair-use limits, a global spending
 * circuit breaker and privacy-preserving subscription checks.
 *
 * - Identity: SHA-256(salt | originalTransactionId) from an App Store-signed
 *   StoreKit 2 transaction (verified offline, see apple_jws.js). No accounts, and
 *   nothing stored on the device is trusted, so reinstalling or clearing app data
 *   does not reset a counter. Rotating ID_HASH_SALT resets every counter.
 * - Requests without a token (the v1 App Store build, and v2 before its
 *   entitlement loads) share per-network buckets: the IPv4 address or the IPv6
 *   /64. They also share their own slice of the budget (ANON_NEURON_BUDGET).
 * - Counters: one SQLite-backed Durable Object per subscriber and per anonymous
 *   bucket, plus one global object (free on Workers Free). A Durable Object
 *   handles one request at a time, so check-and-increment is atomic.
 * - Budget: every AI call first reserves its worst-case neurons in the global
 *   object; when the daily budget would be exceeded, the call is refused before
 *   the model runs, then settled with the measured usage. Fails closed: no
 *   guard, no AI call, and no paid fallback.
 * - Logs: counts only (hashed id prefix, counters, estimated neurons, outcome).
 *   No message text, no profile, no IP address, no transaction id.
 *
 * Every limit is a Worker variable (wrangler.toml [vars]). The defaults are
 * provisional; see docs/business/AI_COST_MODEL.md.
 */
import { JwsError, sha256Hex, verifyAppleJws } from './apple_jws.js';

export const GUARD_VERSION = 'chat-v7-cost-guard';

// Neurons per million tokens, from developers.cloudflare.com/workers-ai/platform/pricing (2026-11-22).
export const MODEL_NEURONS = {
  '@cf/meta/llama-3.3-70b-instruct-fp8-fast': [26668, 204805],
  '@cf/meta/llama-3.2-11b-vision-instruct': [4410, 61493],
  '@cf/google/gemma-4-26b-a4b-it': [9091, 27273],
  '@cf/qwen/qwen3.8-27b': [40909, 290909],
  '@cf/deepseek-ai/deepseek-v4.1-flash-1017': [27273, 109091],
};
const UNKNOWN_MODEL_NEURONS = [40909, 290909]; // priced like the most expensive known model

const DEFAULTS = {
  DAILY_MESSAGE_LIMIT: 150,
  MONTHLY_MESSAGE_LIMIT: 1500,
  SOFT_NOTICE_PERCENT: 80,
  PER_MINUTE_LIMIT: 12,
  MAX_CONCURRENT: 2,
  MAX_INPUT_TOKENS: 6000,
  MAX_OUTPUT_TOKENS: 800,
  IP_PER_MINUTE_LIMIT: 60,
  ANON_DAILY_LIMIT: 60,
  ANON_MONTHLY_LIMIT: 600,
  SANDBOX_DAILY_LIMIT: 20,
  DAILY_NEURON_BUDGET: 10000,
  ANON_NEURON_BUDGET: -1, // -1 = 20% of DAILY_NEURON_BUDGET
  MONTHLY_NEURON_BUDGET: 0, // 0 = off
  LEASE_SECONDS: 120,
  EXPIRY_LEEWAY_MINUTES: 60,
  BILLING_GRACE_DAYS: 0,
};

export function guardConfig(env = {}) {
  const cfg = {};
  for (const [k, def] of Object.entries(DEFAULTS)) {
    const raw = env[k];
    const n = raw === undefined || raw === '' ? def : Number(raw);
    cfg[k] = Number.isFinite(n) && n >= 0 ? n : def;
  }
  if (cfg.ANON_NEURON_BUDGET < 0) cfg.ANON_NEURON_BUDGET = Math.floor(cfg.DAILY_NEURON_BUDGET * 0.2);
  cfg.REQUIRE_SUBSCRIPTION = String(env.REQUIRE_SUBSCRIPTION ?? '0') === '1';
  cfg.LEGACY_CLIENTS = String(env.LEGACY_CLIENTS ?? '1') === '1';
  cfg.ALLOW_SANDBOX = String(env.ALLOW_SANDBOX ?? '1') === '1';
  cfg.APPLE_BUNDLE_ID = env.APPLE_BUNDLE_ID || 'com.datewise.datewiseAi';
  cfg.APPLE_PRODUCT_ID = env.APPLE_PRODUCT_ID || 'datewise_premium_monthly';
  // Without the secret, hashes use a public default salt; `who` is then left out of logs.
  cfg.SALT_SET = Boolean(env.ID_HASH_SALT);
  cfg.ID_HASH_SALT = env.ID_HASH_SALT || 'datewise-cost-guard-v1';
  cfg.ASSN_ENABLED = String(env.ASSN_ENABLED ?? '0') === '1';
  return cfg;
}

// --- error codes (stable; the app maps them to localized text) -------------
export const CODES = {
  DAILY_LIMIT: 429,
  MONTHLY_LIMIT: 429,
  RATE_LIMITED: 429,
  CONCURRENCY_LIMIT: 429,
  SERVICE_BUDGET_EXHAUSTED: 503,
  GUARD_UNAVAILABLE: 503,
  SUBSCRIPTION_REQUIRED: 403,
  SUBSCRIPTION_INVALID: 403,
  SUBSCRIPTION_EXPIRED: 403,
  SUBSCRIPTION_REVOKED: 403,
  APP_UPDATE_REQUIRED: 426,
};

export function guardError(code, cors, extra = {}) {
  const status = CODES[code] || 503;
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...cors };
  if (extra.retryAfter) headers['Retry-After'] = String(Math.max(1, Math.ceil(extra.retryAfter)));
  return new Response(JSON.stringify({ error: code, code, ...extra }), { status, headers });
}

// --- time windows (UTC) ------------------------------------------------------
const dayKey = (t) => new Date(t).toISOString().slice(0, 10);
const monthKey = (t) => new Date(t).toISOString().slice(0, 7);
const nextDay = (t) => {
  const d = new Date(t);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
};
const nextMonth = (t) => {
  const d = new Date(t);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
};

// --- token estimates ---------------------------------------------------------
const enc = new TextEncoder();
const bytes = (s) => enc.encode(String(s ?? '')).length;
/** Over-estimates tokens (UTF-8 bytes / 3, plus 4 per message) so budgets err on the safe side. */
export function estimateTokens(messages) {
  let t = 0;
  for (const m of messages) t += Math.ceil(bytes(m.content) / 3) + 4;
  return t;
}

/** Drops the oldest non-system turns (then trims the last one) until the estimate fits. */
export function fitToInputBudget(messages, maxTokens) {
  const out = messages.map((m) => ({ ...m }));
  const sysCount = out[0]?.role === 'system' ? 1 : 0;
  while (estimateTokens(out) > maxTokens && out.length > sysCount + 1) out.splice(sysCount, 1);
  if (estimateTokens(out) > maxTokens) {
    // One huge message left: keep its newest part within the budget.
    const other = estimateTokens(out.slice(0, -1));
    const keepBytes = Math.max(0, (maxTokens - other - 4) * 3);
    const last = out[out.length - 1];
    let s = last.content;
    while (bytes(s) > keepBytes && s.length) s = s.slice(Math.ceil(s.length * 0.1 || 1));
    last.content = s;
  }
  return out.filter((m) => m.content);
}

export function neuronsFor(model, inTokens, outTokens) {
  const [i, o] = MODEL_NEURONS[model] || UNKNOWN_MODEL_NEURONS;
  return Math.ceil((inTokens * i + outTokens * o) / 1e6);
}

// --- network buckets ----------------------------------------------------------
/** IPv4: the address. IPv6: the /64 (a home or phone network usually gets a whole /64). */
export function ipBucket(ip) {
  const s = String(ip || 'unknown').trim().toLowerCase();
  if (!s.includes(':')) return s;
  const v4 = s.match(/::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (v4) return v4[1];
  const [head, tail = ''] = s.split('::');
  const h = head ? head.split(':') : [];
  const t = tail ? tail.split(':') : [];
  const full = [...h, ...Array(Math.max(0, 8 - h.length - t.length)).fill('0'), ...t];
  return full.slice(0, 4).map((x) => (x || '0').replace(/^0+(?=.)/, '')).join(':') + '::/64';
}

// --- subscription check -----------------------------------------------------
const jwsCache = new Map(); // sha256(jws) -> payload (per isolate, bounded)

// Tests only: trust a test root instead of Apple Root CA - G3. Production code
// never calls this, and no Worker variable can change the trusted root.
let testRoots = null;
export function _setTrustedRootsForTests(roots) {
  testRoots = roots;
  jwsCache.clear();
}
const verifyOpts = (now, extra = {}) => ({ ...(testRoots ? { trustedRootSha256: testRoots } : {}), now, ...extra });

/** Production, or Sandbox when allowed (TestFlight and App Review). Missing, Xcode or anything else: invalid. */
function environmentAllowed(cfg, envName) {
  return envName === 'Production' || (cfg.ALLOW_SANDBOX && envName === 'Sandbox');
}

/** Returns { code } on failure or { tx } with the verified transaction payload. */
export async function checkEntitlement(jws, cfg, now) {
  let payload;
  const cacheKey = await sha256Hex(enc.encode(jws));
  if (jwsCache.has(cacheKey)) {
    payload = jwsCache.get(cacheKey);
  } else {
    try {
      payload = await verifyAppleJws(jws, verifyOpts(now));
    } catch (e) {
      return { code: 'SUBSCRIPTION_INVALID', reason: e instanceof JwsError ? e.reason : 'verify_error' };
    }
    if (jwsCache.size > 500) jwsCache.delete(jwsCache.keys().next().value);
    jwsCache.set(cacheKey, payload);
  }
  if (payload.bundleId !== cfg.APPLE_BUNDLE_ID || payload.productId !== cfg.APPLE_PRODUCT_ID) {
    return { code: 'SUBSCRIPTION_INVALID', reason: 'wrong_app_or_product' };
  }
  if (!environmentAllowed(cfg, payload.environment)) return { code: 'SUBSCRIPTION_INVALID', reason: 'environment' };
  if (!payload.originalTransactionId) return { code: 'SUBSCRIPTION_INVALID', reason: 'no_original_id' };
  if (payload.revocationDate) return { code: 'SUBSCRIPTION_REVOKED', tx: payload };
  const expires = Number(payload.expiresDate);
  const allowance = cfg.EXPIRY_LEEWAY_MINUTES * 60_000 + cfg.BILLING_GRACE_DAYS * 86_400_000;
  if (!Number.isFinite(expires) || now > expires + allowance) return { code: 'SUBSCRIPTION_EXPIRED', tx: payload };
  return { tx: payload };
}

const hashed = async (cfg, kind, value) => sha256Hex(enc.encode(`${cfg.ID_HASH_SALT}|${kind}|${value}`));
export async function subscriberKey(cfg, tx) {
  const prefix = tx.environment === 'Sandbox' ? 'sbx:' : 'sub:';
  return prefix + (await hashed(cfg, 'otid', tx.originalTransactionId));
}
/** Revoked transactions are stored only as salted hashes. */
export async function txHash(cfg, transactionId) {
  return (await hashed(cfg, 'txid', transactionId)).slice(0, 32);
}
async function anonKey(cfg, ip) {
  return 'anon:' + (await hashed(cfg, 'net', ipBucket(ip)));
}

// --- per-IP limiter (Rate Limiting binding when present + in-isolate window) --
const ipWindows = new Map();
async function ipAllowed(env, cfg, netHash, now) {
  if (env.RATE_LIMITER && typeof env.RATE_LIMITER.limit === 'function') {
    try {
      const { success } = await env.RATE_LIMITER.limit({ key: netHash });
      if (!success) return false;
    } catch {
      /* the binding is optional; fall through to the local window */
    }
  }
  const minute = Math.floor(now / 60_000);
  const w = ipWindows.get(netHash);
  if (!w || w.minute !== minute) {
    if (ipWindows.size > 5000) ipWindows.clear();
    ipWindows.set(netHash, { minute, count: 1 });
    return true;
  }
  w.count += 1;
  return w.count <= cfg.IP_PER_MINUTE_LIMIT;
}

// --- Durable Object ----------------------------------------------------------
/**
 * One instance per subscriber ("sub:<hash>", "sbx:<hash>" for Sandbox), per
 * anonymous network bucket ("anon:<hash>") and one "global" instance for the
 * budget. State is a few counters and hashed revoked transaction ids; no
 * content is ever stored.
 */
export class UsageGuard {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    const op = new URL(request.url).pathname.slice(1);
    const body = await request.json();
    const ops = {
      reserve: () => this.reserve(body),
      settle: () => this.settle(body),
      budget: () => this.budget(body),
      'budget-settle': () => this.budgetSettle(body),
      revoke: () => this.revoke(body),
      unrevoke: () => this.unrevoke(body),
    };
    if (!Object.hasOwn(ops, op)) return new Response('not found', { status: 404 });
    return new Response(JSON.stringify(await ops[op]()), { headers: { 'Content-Type': 'application/json' } });
  }

  async load(now) {
    const s = (await this.storage.get('u')) || {};
    const day = dayKey(now);
    const month = monthKey(now);
    if (s.day !== day) Object.assign(s, { day, dayCount: 0 });
    if (s.month !== month) Object.assign(s, { month, monthCount: 0 });
    s.inflight = Object.fromEntries(Object.entries(s.inflight || {}).filter(([, exp]) => exp > now));
    s.revoked = s.revoked || [];
    return s;
  }

  async reserve({ now, txHash: tx, limits }) {
    const s = await this.load(now);
    if (tx && s.revoked.includes(tx)) return { ok: false, code: 'SUBSCRIPTION_REVOKED' };
    if (s.dayCount >= limits.daily) {
      return { ok: false, code: 'DAILY_LIMIT', resetAt: nextDay(now), retryAfter: (nextDay(now) - now) / 1000 };
    }
    if (s.monthCount >= limits.monthly) {
      return { ok: false, code: 'MONTHLY_LIMIT', resetAt: nextMonth(now), retryAfter: (nextMonth(now) - now) / 1000 };
    }
    const minute = Math.floor(now / 60_000);
    if (s.minute !== minute) Object.assign(s, { minute, minuteCount: 0 });
    if (s.minuteCount >= limits.perMinute) {
      return { ok: false, code: 'RATE_LIMITED', retryAfter: 60 - (now % 60_000) / 1000 };
    }
    if (Object.keys(s.inflight).length >= limits.maxConcurrent) {
      return { ok: false, code: 'CONCURRENCY_LIMIT', retryAfter: 5 };
    }
    s.dayCount += 1;
    s.monthCount += 1;
    s.minuteCount += 1;
    const leaseId = `${now}-${Math.random().toString(36).slice(2, 10)}`;
    s.inflight[leaseId] = now + limits.leaseMs;
    await this.storage.put('u', s);
    const soft = limits.softPercent / 100;
    let notice = null;
    if (s.monthCount >= Math.ceil(limits.monthly * soft)) notice = 'approaching_monthly_limit';
    if (s.dayCount >= Math.ceil(limits.daily * soft)) notice = 'approaching_daily_limit';
    return {
      ok: true,
      leaseId,
      dayCount: s.dayCount,
      monthCount: s.monthCount,
      remainingToday: Math.max(0, limits.daily - s.dayCount),
      remainingMonth: Math.max(0, limits.monthly - s.monthCount),
      notice,
    };
  }

  /** Ends a lease; `refund` gives the message back after a server-side failure. */
  async settle({ now, leaseId, refund, day, month }) {
    const s = await this.load(now);
    delete s.inflight[leaseId];
    if (refund) {
      if (s.day === day && s.dayCount > 0) s.dayCount -= 1;
      if (s.month === month && s.monthCount > 0) s.monthCount -= 1;
    }
    await this.storage.put('u', s);
    return { ok: true };
  }

  async revoke({ txHash: tx }) {
    const s = (await this.storage.get('u')) || {};
    s.revoked = [...new Set([...(s.revoked || []), String(tx)])].slice(-50);
    await this.storage.put('u', s);
    return { ok: true };
  }

  /** REFUND_REVERSED: Apple reinstated the transaction. */
  async unrevoke({ txHash: tx }) {
    const s = (await this.storage.get('u')) || {};
    s.revoked = (s.revoked || []).filter((x) => x !== String(tx));
    await this.storage.put('u', s);
    return { ok: true };
  }

  async budget({ now, neurons, daily, monthly, anon, anonDaily }) {
    const s = (await this.storage.get('g')) || {};
    const day = dayKey(now);
    const month = monthKey(now);
    if (s.day !== day) Object.assign(s, { day, spent: 0, anonSpent: 0 });
    if (s.month !== month) Object.assign(s, { month, monthSpent: 0 });
    s.anonSpent = s.anonSpent || 0;
    const refuse = (retryAt) => ({ ok: false, code: 'SERVICE_BUDGET_EXHAUSTED', retryAfter: (retryAt - now) / 1000 });
    if (s.spent + neurons > daily) return refuse(nextDay(now));
    if (anon && s.anonSpent + neurons > anonDaily) return refuse(nextDay(now));
    if (monthly > 0 && s.monthSpent + neurons > monthly) return refuse(nextMonth(now));
    s.spent += neurons;
    s.monthSpent += neurons;
    if (anon) s.anonSpent += neurons;
    await this.storage.put('g', s);
    return { ok: true, day, spent: s.spent };
  }

  /** Replaces a worst-case reservation with the measured amount (only ever gives back). */
  async budgetSettle({ day, reserved, actual, anon }) {
    const s = (await this.storage.get('g')) || {};
    const delta = Math.min(0, actual - reserved);
    if (s.day === day) {
      s.spent = Math.max(0, s.spent + delta);
      if (anon) s.anonSpent = Math.max(0, (s.anonSpent || 0) + delta);
    }
    if (s.month === day.slice(0, 7)) s.monthSpent = Math.max(0, s.monthSpent + delta);
    await this.storage.put('g', s);
    return { ok: true };
  }
}

async function callDo(env, name, op, body) {
  const ns = env.USAGE_GUARD;
  const stub = ns.get(ns.idFromName(name));
  const res = await stub.fetch(`https://usage-guard/${op}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`guard ${op} ${res.status}`);
  return res.json();
}

function logUsage(fields) {
  // Counts only. `who` is a 12-hex prefix of the salted hash (left out without
  // the ID_HASH_SALT secret); no text, no IP, no transaction id.
  try {
    console.log(JSON.stringify({ event: 'usage', v: GUARD_VERSION, ...fields }));
  } catch {
    /* logging never breaks a request */
  }
}

/**
 * Admits (or refuses) one AI request before any model call.
 * kind: 'chat' | 'legacy-chat' | 'photo'; model + estimated input/output
 * tokens (or `neurons`) give the worst-case reservation.
 * Returns { response } to send as-is, or { ticket } with headers to add and
 * finish(actualNeurons, { refund }) to call once when the work is done.
 */
export async function admit(request, env, cors, { kind, model, inTokens, outTokens, neurons }) {
  const cfg = guardConfig(env);
  const now = Date.now();
  if (!env.USAGE_GUARD || typeof env.USAGE_GUARD.idFromName !== 'function') {
    logUsage({ kind, outcome: 'GUARD_UNAVAILABLE' });
    return { response: guardError('GUARD_UNAVAILABLE', cors) };
  }
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const netKey = await anonKey(cfg, ip);
  if (!(await ipAllowed(env, cfg, netKey.slice(5, 37), now))) {
    logUsage({ kind, outcome: 'RATE_LIMITED', scope: 'ip' });
    return { response: guardError('RATE_LIMITED', cors, { retryAfter: 60 }) };
  }

  // Who is asking: a verified subscriber, or (while allowed) an anonymous network bucket.
  const jws = request.headers.get('X-DateWise-Entitlement');
  let key;
  let tx = null;
  let limits;
  const base = {
    perMinute: cfg.PER_MINUTE_LIMIT,
    maxConcurrent: cfg.MAX_CONCURRENT,
    softPercent: cfg.SOFT_NOTICE_PERCENT,
    leaseMs: cfg.LEASE_SECONDS * 1000,
  };
  if (jws) {
    const r = await checkEntitlement(jws, cfg, now);
    if (r.code) {
      if (r.code === 'SUBSCRIPTION_REVOKED' && r.tx) {
        // Remember the refund so an older saved copy of this transaction is refused too.
        try {
          await callDo(env, await subscriberKey(cfg, r.tx), 'revoke', { txHash: await txHash(cfg, r.tx.transactionId) });
        } catch {
          /* best effort */
        }
      }
      logUsage({ kind, outcome: r.code, reason: r.reason });
      return { response: guardError(r.code, cors) };
    }
    key = await subscriberKey(cfg, r.tx);
    tx = await txHash(cfg, r.tx.transactionId);
    const sandbox = r.tx.environment === 'Sandbox';
    limits = { ...base, daily: sandbox ? cfg.SANDBOX_DAILY_LIMIT : cfg.DAILY_MESSAGE_LIMIT, monthly: cfg.MONTHLY_MESSAGE_LIMIT };
  } else if (cfg.REQUIRE_SUBSCRIPTION) {
    logUsage({ kind, outcome: 'SUBSCRIPTION_REQUIRED' });
    return { response: guardError('SUBSCRIPTION_REQUIRED', cors) };
  } else {
    key = netKey;
    limits = { ...base, daily: cfg.ANON_DAILY_LIMIT, monthly: cfg.ANON_MONTHLY_LIMIT };
  }
  const anon = !jws;
  const who = cfg.SALT_SET ? key.slice(0, key.indexOf(':') + 13) : undefined;

  const reserveNeurons = neurons ?? neuronsFor(model, inTokens, outTokens);
  let sub;
  try {
    sub = await callDo(env, key, 'reserve', { now, txHash: tx, limits });
  } catch {
    logUsage({ kind, who, outcome: 'GUARD_UNAVAILABLE' });
    return { response: guardError('GUARD_UNAVAILABLE', cors) };
  }
  if (!sub.ok) {
    logUsage({ kind, who, outcome: sub.code });
    return { response: guardError(sub.code, cors, { resetAt: sub.resetAt, retryAfter: sub.retryAfter }) };
  }
  const releaseSub = (refund) =>
    callDo(env, key, 'settle', { now: Date.now(), leaseId: sub.leaseId, refund, day: dayKey(now), month: monthKey(now) }).catch(() => {});

  let budget;
  try {
    budget = await callDo(env, 'global', 'budget', {
      now,
      neurons: reserveNeurons,
      daily: cfg.DAILY_NEURON_BUDGET,
      monthly: cfg.MONTHLY_NEURON_BUDGET,
      anon,
      anonDaily: cfg.ANON_NEURON_BUDGET,
    });
  } catch {
    await releaseSub(true);
    logUsage({ kind, who, outcome: 'GUARD_UNAVAILABLE' });
    return { response: guardError('GUARD_UNAVAILABLE', cors) };
  }
  if (!budget.ok) {
    await releaseSub(true);
    logUsage({ kind, who, outcome: 'SERVICE_BUDGET_EXHAUSTED', reserve: reserveNeurons, anon });
    return { response: guardError('SERVICE_BUDGET_EXHAUSTED', cors, { retryAfter: budget.retryAfter }) };
  }

  const headers = {
    'X-DateWise-Remaining-Today': String(sub.remainingToday),
    'X-DateWise-Remaining-Month': String(sub.remainingMonth),
    'Access-Control-Expose-Headers': 'X-DateWise-Usage-Notice, X-DateWise-Remaining-Today, X-DateWise-Remaining-Month',
  };
  if (sub.notice) headers['X-DateWise-Usage-Notice'] = sub.notice;

  let finished = false;
  const finish = async (actualNeurons, { refund = false } = {}) => {
    if (finished) return;
    finished = true;
    const actual = Math.min(reserveNeurons, Math.max(0, Math.ceil(actualNeurons)));
    await Promise.all([
      releaseSub(refund),
      callDo(env, 'global', 'budget-settle', { day: budget.day, reserved: reserveNeurons, actual, anon }).catch(() => {}),
    ]);
    logUsage({
      kind,
      who,
      outcome: refund ? 'failed' : 'ok',
      day: sub.dayCount - (refund ? 1 : 0),
      month: sub.monthCount - (refund ? 1 : 0),
      reserve: reserveNeurons,
      neurons: actual,
      anon,
    });
  };
  return { ticket: { headers, finish, cfg, reserveNeurons } };
}

/**
 * Passes an SSE stream through unchanged while measuring it: the reply's UTF-8
 * size (for an output-token estimate) and any `usage` object the model sends.
 * onEnd runs once with { outTokens, inTokens, produced, outcome } where
 * outcome is 'done', 'error' (the upstream stream failed: a server-side
 * error) or 'canceled' (the client went away: what was produced still counts).
 */
export function meterStream(stream, onEnd) {
  const decoder = new TextDecoder();
  const reader = stream.getReader();
  let tail = '';
  let outBytes = 0;
  let usage = null;
  let ended = false;
  const scanLine = (line) => {
    const t = line.trim();
    if (!t.startsWith('data:')) return;
    const data = t.slice(5).trim();
    if (!data || data === '[DONE]') return;
    try {
      const obj = JSON.parse(data);
      const tok = typeof obj.response === 'string' ? obj.response : obj?.choices?.[0]?.delta?.content;
      if (typeof tok === 'string') outBytes += bytes(tok);
      if (obj.usage && typeof obj.usage === 'object') usage = obj.usage;
    } catch {
      /* not JSON: ignored for metering, still forwarded */
    }
  };
  const scan = (text) => {
    const lines = (tail + text).split('\n');
    tail = lines.pop();
    lines.forEach(scanLine);
  };
  const end = (outcome) => {
    if (ended) return;
    ended = true;
    if (tail) scanLine(tail);
    onEnd({
      outTokens: Number(usage?.completion_tokens) || Math.ceil(outBytes / 3),
      inTokens: Number(usage?.prompt_tokens) || null,
      produced: outBytes > 0,
      outcome,
    });
  };
  return new ReadableStream({
    async pull(controller) {
      let r;
      try {
        r = await reader.read();
      } catch (e) {
        end('error');
        controller.error(e);
        return;
      }
      if (r.done) {
        end('done');
        controller.close();
        return;
      }
      scan(decoder.decode(r.value, { stream: true }));
      controller.enqueue(r.value);
    },
    cancel(reason) {
      end('canceled');
      return reader.cancel(reason);
    },
  });
}

/** Wraps env.AI so every non-streaming call's usage is measured (photo coach). */
export function meteredAi(ai) {
  let neurons = 0;
  return {
    ai: {
      async run(model, input) {
        const result = await ai.run(model, input);
        const u = result && result.usage;
        const promptTok = Number(u?.prompt_tokens);
        const outTok = Number(u?.completion_tokens);
        if (Number.isFinite(promptTok) && Number.isFinite(outTok)) {
          neurons += neuronsFor(model, promptTok, outTok);
        } else {
          // No usage reported: estimate. An image counts as 1,600 input tokens (ASSUMPTION).
          const text = input.messages ? estimateTokens(input.messages) : Math.ceil(bytes(input.prompt) / 3);
          const reply = result && (result.response ?? result.description);
          const out = Math.ceil(bytes(typeof reply === 'string' ? reply : JSON.stringify(reply ?? '')) / 3);
          neurons += neuronsFor(model, text + (input.image ? 1600 : 0), out);
        }
        return result;
      },
    },
    neurons: () => neurons,
  };
}

/**
 * Optional App Store Server Notifications v2 endpoint (POST /apple/notifications),
 * off unless ASSN_ENABLED=1 and the URL is set in App Store Connect. REFUND and
 * REVOKE mark the transaction as revoked so a saved copy of it stops working;
 * REFUND_REVERSED lifts that again.
 */
export async function handleAppleNotification(request, env) {
  const cfg = guardConfig(env);
  if (!cfg.ASSN_ENABLED || !env.USAGE_GUARD) return new Response('not found', { status: 404 });
  let body;
  try {
    body = await request.json();
  } catch {
    return new Response('bad request', { status: 400 });
  }
  const now = Date.now();
  try {
    // A notification nests the signed transaction and renewal info: allow 64k.
    const n = await verifyAppleJws(body?.signedPayload, verifyOpts(now, { maxLength: 64_000 }));
    const data = n.data || {};
    if (data.bundleId !== cfg.APPLE_BUNDLE_ID) throw new JwsError('notification_bundle');
    if (!environmentAllowed(cfg, data.environment)) throw new JwsError('notification_environment');
    const type = n.notificationType;
    if ((type === 'REFUND' || type === 'REVOKE' || type === 'REFUND_REVERSED') && data.signedTransactionInfo) {
      const tx = await verifyAppleJws(data.signedTransactionInfo, verifyOpts(now));
      if (tx.bundleId !== cfg.APPLE_BUNDLE_ID || tx.environment !== data.environment) throw new JwsError('transaction_mismatch');
      const op = type === 'REFUND_REVERSED' ? 'unrevoke' : 'revoke';
      await callDo(env, await subscriberKey(cfg, tx), op, { txHash: await txHash(cfg, tx.transactionId) });
      logUsage({ kind: 'assn', outcome: type });
    }
    return new Response('ok', { status: 200 });
  } catch (e) {
    logUsage({ kind: 'assn', outcome: 'invalid', reason: e instanceof JwsError ? e.reason : 'error' });
    return new Response('invalid', { status: 400 });
  }
}
