/**
 * Hosted live avatar pilot: session endpoints (avatar-pilot harness).
 *
 *   POST /v1/avatar/session    mint a short-lived vendor session token
 *   POST /v1/avatar/heartbeat  { sessionId }  (every ~30 s while the face is live)
 *   POST /v1/avatar/end        { sessionId }  (settles minutes, refunds unused time)
 *
 * Rules (docs/avatar/PILOT_RUNBOOK.md):
 *  - OFF by default. AVATAR_PROVIDER = 'off' | 'simli' | 'anam'. Anything else is off.
 *  - Same StoreKit entitlement gate as chat: identify() from cost_guard.js
 *    (JWS verified offline against Apple Root CA - G3, Sandbox handling, revocations,
 *    ASSN renewals, per-network limit). No second auth path.
 *  - Per-subscriber monthly allowance (AVATAR_MONTHLY_MINUTES, default 60) and a
 *    global daily cap (AVATAR_DAILY_MINUTES) in the existing UsageGuard Durable
 *    Object. Minutes are counted by session time: sessions are at most 10 minutes
 *    and close when idle; the grant is reserved up front and the unused part is
 *    refunded on /end.
 *  - The vendor key exists only as a Worker secret (SIMLI_API_KEY / ANAM_API_KEY).
 *    It is never returned and never logged. Without it the endpoint answers
 *    AVATAR_UNAVAILABLE and the app shows the on-device avatar.
 *  - Fail closed on every error; no vendor error text is passed on; logs hold
 *    counts only (no text, no audio, no IP, no transaction id).
 *
 * Vendor APIs (documented, checked 2026-11-24):
 *  Simli  POST https://api.simli.ai/compose/token, header x-simli-api-key, body
 *         { faceId, handleSilence, maxSessionLength (s), maxIdleTime (s) } ->
 *         { session_token }; the token is valid 5 minutes.
 *         https://docs.simli.com/api-reference/simli-webrtc
 *         https://docs.simli.com/api-reference/javascript
 *  Anam   POST https://api.anam.ai/v1/auth/session-token, Authorization: Bearer,
 *         body { personaConfig: { avatarId, enableAudioPassthrough: true,
 *         maxSessionLengthSeconds }, expiresInSeconds, maxSessions } ->
 *         { sessionToken }.
 *         https://anam.ai/docs/api-reference/sessions/create-session-token
 *         https://anam.ai/docs/javascript-sdk/examples/custom-tts
 */
import { callDo, dayKey, guardError, identify, logUsage, readBodyCapped } from './cost_guard.js';
import { resolveCoachId } from './coach_prompts.js';

export const AVATAR_PROVIDERS = ['simli', 'anam'];
const MAX_BODY = 4 * 1024;
const VENDOR_TIMEOUT_MS = 8000;

const num = (v, def, min, max) => {
  const n = v === undefined || v === '' ? def : Number(v);
  return Number.isFinite(n) && n >= min ? Math.min(n, max) : def;
};

export function avatarConfig(env = {}) {
  const raw = String(env.AVATAR_PROVIDER ?? 'off').trim().toLowerCase();
  const provider = AVATAR_PROVIDERS.includes(raw) ? raw : 'off';
  let faces = {};
  try {
    const f = JSON.parse(env.AVATAR_FACE_IDS || '{}');
    if (f && typeof f === 'object' && !Array.isArray(f)) faces = f;
  } catch {
    /* no mapping: every coach falls back */
  }
  return {
    provider,
    monthlySec: Math.floor(num(env.AVATAR_MONTHLY_MINUTES, 60, 0, 100000) * 60),
    dailySec: Math.floor(num(env.AVATAR_DAILY_MINUTES, 120, 0, 1000000) * 60),
    // 10 minutes is the ceiling whatever the variable says.
    maxSec: Math.floor(num(env.AVATAR_SESSION_MAX_SECONDS, 600, 30, 600)),
    idleSec: Math.floor(num(env.AVATAR_IDLE_SECONDS, 60, 15, 300)),
    minSec: 30,
    heartbeatSec: 30,
    opensPerHour: 12,
    faces,
    model: typeof env.ANAM_AVATAR_MODEL === 'string' ? env.ANAM_AVATAR_MODEL : '',
  };
}

const secretFor = (provider, env) => (provider === 'simli' ? env.SIMLI_API_KEY : provider === 'anam' ? env.ANAM_API_KEY : '');

const unavailable = (cors, reason) => guardError('AVATAR_UNAVAILABLE', cors, { reason });

async function vendorFetch(url, init) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), VENDOR_TIMEOUT_MS);
  try {
    return await fetch(url, { ...init, signal: ctl.signal });
  } finally {
    clearTimeout(timer);
  }
}

/** Vendor adapters: return the short-lived token and the client config, or throw (fail closed). */
const ADAPTERS = {
  async simli({ env, faceId, maxSec, idleSec }) {
    const res = await vendorFetch('https://api.simli.ai/compose/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-simli-api-key': env.SIMLI_API_KEY },
      body: JSON.stringify({ faceId, handleSilence: true, maxSessionLength: maxSec, maxIdleTime: idleSec }),
    });
    if (!res.ok) throw new Error(`simli ${res.status}`);
    const data = await res.json();
    if (typeof data?.session_token !== 'string' || !data.session_token) throw new Error('simli no token');
    // PCM16 little-endian, 16 kHz, mono (docs.simli.com/api-reference/javascript, sendAudioData).
    return { token: data.session_token, audio: { encoding: 'pcm_s16le', sampleRate: 16000, channels: 1 }, tokenTtlSec: 300 };
  },
  async anam({ env, faceId, maxSec, cfg }) {
    const personaConfig = { avatarId: faceId, enableAudioPassthrough: true, maxSessionLengthSeconds: maxSec };
    if (cfg.model) personaConfig.avatarModel = cfg.model;
    const res = await vendorFetch('https://api.anam.ai/v1/auth/session-token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${env.ANAM_API_KEY}` },
      // The SDK retries a failed start up to 3 times and each attempt counts, hence maxSessions 3.
      body: JSON.stringify({ personaConfig, expiresInSeconds: 120, maxSessions: 3, clientLabel: 'datewise-pilot' }),
    });
    if (!res.ok) throw new Error(`anam ${res.status}`);
    const data = await res.json();
    if (typeof data?.sessionToken !== 'string' || !data.sessionToken) throw new Error('anam no token');
    // pcm_s16le mono; 24 kHz is Anam's native rate (anam.ai/docs/javascript-sdk/examples/custom-tts).
    return { token: data.sessionToken, audio: { encoding: 'pcm_s16le', sampleRate: 24000, channels: 1 }, tokenTtlSec: 120 };
  },
};

function jsonOk(body, cors) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...cors },
  });
}

async function readJson(request) {
  try {
    const text = await readBodyCapped(request, MAX_BODY);
    if (text === null) return null;
    const v = text ? JSON.parse(text) : {};
    return v && typeof v === 'object' && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

const SESSION_ID = /^av_[0-9a-f]{24}$/;
const newSessionId = () => {
  const b = new Uint8Array(12);
  crypto.getRandomValues(b);
  return 'av_' + [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
};

/** Entry point from worker.js for POST /v1/avatar/{session,heartbeat,end}. */
export async function handleAvatar(request, env, cors, action) {
  const cfg = avatarConfig(env);
  if (action === 'session') {
    if (cfg.provider === 'off') return unavailable(cors, 'off');
    if (!secretFor(cfg.provider, env)) return unavailable(cors, 'not_configured');
  }
  const body = await readJson(request);
  if (!body) return new Response(JSON.stringify({ error: 'Invalid JSON body', code: 'BAD_REQUEST' }), { status: 400, headers: { 'Content-Type': 'application/json', ...cors } });

  const id = await identify(request, env, cors, { kind: 'avatar', requireToken: true });
  if (id.response) return id.response;
  if (!id.hasGuard) {
    logUsage({ kind: 'avatar', outcome: 'GUARD_UNAVAILABLE' });
    return unavailable(cors, 'guard');
  }
  if (action === 'session') return await openSession(env, cors, cfg, id, body);

  const sessionId = String(body.sessionId || '');
  if (!SESSION_ID.test(sessionId)) return guardError('AVATAR_SESSION_UNKNOWN', cors);
  try {
    if (action === 'heartbeat') {
      const r = await callDo(env, id.key, 'avatar-beat', { now: Date.now(), sessionId });
      if (!r.ok) return guardError(r.code, cors);
      return jsonOk({ ok: true, usedSeconds: r.usedSec, remainingSessionSeconds: r.remainingGrantSec }, cors);
    }
    // end
    const r = await callDo(env, id.key, 'avatar-end', { now: Date.now(), sessionId });
    if (r.known && r.gday) {
      await callDo(env, 'global', 'avatar-global-settle', { day: r.gday, refund: r.grant - r.charge }).catch(() => {});
    }
    logUsage({ kind: 'avatar', who: id.who, outcome: 'end', seconds: r.charge });
    return jsonOk({ ok: true, usedSeconds: r.usedSec, allowanceSeconds: cfg.monthlySec }, cors);
  } catch {
    logUsage({ kind: 'avatar', who: id.who, outcome: 'GUARD_UNAVAILABLE' });
    return guardError('GUARD_UNAVAILABLE', cors, { retryAfter: 30 });
  }
}

async function openSession(env, cors, cfg, id, body) {
  const coachId = resolveCoachId(body.coachId);
  const faceId = coachId && typeof cfg.faces[coachId] === 'string' ? cfg.faces[coachId] : '';
  if (!faceId) return unavailable(cors, 'no_face');
  const now = Date.now();
  const sessionId = newSessionId();
  const gday = dayKey(now);
  let open;
  try {
    open = await callDo(env, id.key, 'avatar-open', {
      now,
      sessionId,
      gday,
      allowanceSec: cfg.monthlySec,
      maxSec: cfg.maxSec,
      minSec: cfg.minSec,
      opensPerHour: cfg.opensPerHour,
      graceS: 90,
    });
  } catch {
    logUsage({ kind: 'avatar', who: id.who, outcome: 'GUARD_UNAVAILABLE' });
    return guardError('GUARD_UNAVAILABLE', cors, { retryAfter: 30 });
  }
  if (!open.ok) {
    logUsage({ kind: 'avatar', who: id.who, outcome: open.code });
    const extra = { retryAfter: open.retryAfter };
    if (open.code === 'AVATAR_ALLOWANCE') Object.assign(extra, { usedSeconds: open.usedSec, allowanceSeconds: open.allowanceSec, resetAt: open.resetAt });
    return guardError(open.code, cors, extra);
  }
  const refundAll = async (globalReserved) => {
    // The session never started: avatar-end charges only the seconds that really
    // passed (about 0-2) and gives the rest of the grant back.
    const r = await callDo(env, id.key, 'avatar-end', { now: Date.now(), sessionId }).catch(() => null);
    if (globalReserved && r?.gday) {
      await callDo(env, 'global', 'avatar-global-settle', { day: r.gday, refund: r.grant - r.charge }).catch(() => {});
    }
  };

  let g;
  try {
    g = await callDo(env, 'global', 'avatar-global', { now, sec: open.grant, daily: cfg.dailySec });
  } catch {
    await refundAll(false);
    logUsage({ kind: 'avatar', who: id.who, outcome: 'GUARD_UNAVAILABLE' });
    return guardError('GUARD_UNAVAILABLE', cors, { retryAfter: 30 });
  }
  if (!g.ok) {
    await refundAll(false);
    logUsage({ kind: 'avatar', who: id.who, outcome: g.code });
    return guardError(g.code, cors, { retryAfter: g.retryAfter });
  }

  let vendor;
  try {
    vendor = await ADAPTERS[cfg.provider]({ env, faceId, maxSec: open.grant, idleSec: cfg.idleSec, cfg });
  } catch {
    await refundAll(true);
    logUsage({ kind: 'avatar', who: id.who, provider: cfg.provider, outcome: 'vendor_error' });
    return unavailable(cors, 'vendor');
  }
  logUsage({ kind: 'avatar', who: id.who, provider: cfg.provider, outcome: 'open', grant: open.grant, used: open.usedSec });
  // Only the short-lived token and what the client needs. Never the key.
  return jsonOk(
    {
      sessionId,
      vendor: cfg.provider,
      sessionToken: vendor.token,
      tokenTtlSeconds: vendor.tokenTtlSec,
      maxSeconds: open.grant,
      idleSeconds: cfg.idleSec,
      heartbeatSeconds: cfg.heartbeatSec,
      audio: vendor.audio,
      allowance: { usedSeconds: open.usedSec, totalSeconds: open.allowanceSec },
    },
    cors,
  );
}
