/**
 * DateWise AI — Photo Coach backend (Cloudflare Worker).
 *
 * FREE: uses Cloudflare Workers AI (built-in, free daily quota, no API key)
 * with Meta's Llama 3.2 11B Vision model. Requires an "AI" binding on the
 * Worker (Settings → Bindings → Workers AI → variable name: AI).
 *
 * Request  (POST, JSON): { imageBase64, tier, mode?, userNote? }
 *   - mode: "quick" (fast, cheap: score + headline + 1 tip, no dimensions)
 *           "deep"  (default: full 5-dimension breakdown + 3 tips)
 * Response (JSON): a PhotoAnalysis object matching the Flutter model.
 *
 * chat-v7 (cost guard): every AI call passes cost_guard.js first (per-subscriber
 * caps, global neuron budget, StoreKit 2 JWS check), the coach system prompt is
 * built on the server (coach_prompts.js) for requests with a coachId, and those
 * (v2) requests are served only with a valid StoreKit token (403
 * SUBSCRIPTION_REQUIRED without one). Requests
 * without a coachId and without a StoreKit token come from the v1 App Store build
 * (1.0.2): its chat and photo coach keep their chat-v6 behaviour, in the
 * anonymous caps and their budget slice, while LEGACY_CLIENTS=1. See docs/business/AI_COST_MODEL.md.
 */
import { admit, estimateTokens, fitToInputBudget, guardConfig, guardError, handleAppleNotification, meterStream, meteredAi, neuronsFor, GUARD_VERSION } from './cost_guard.js';
import { coachMessages, resolveCoachId } from './coach_prompts.js';
export { UsageGuard } from './cost_guard.js';

const MODEL = '@cf/meta/llama-3.2-11b-vision-instruct';
// Allow the production apex and the verified Cloudflare Pages builds.
const ALLOWED_ORIGINS = new Set([
  'https://datewiseai.com',
  'https://www.datewiseai.com',
  'https://datewiseai.pages.dev',
]);

function isAllowedOrigin(origin) {
  if (!origin) return false;
  if (ALLOWED_ORIGINS.has(origin)) return true;
  try {
    const u = new URL(origin);
    return u.protocol === 'https:' && u.hostname.endsWith('.datewiseai.pages.dev');
  } catch {
    return false;
  }
}

// The default allowed origin. fetch() replaces it on each response with the
// request's own allowed origin. (It used to be a module variable set per
// request, which a concurrent request in the same isolate could overwrite
// between two awaits, so a response could carry another request's origin.)
const DEFAULT_ORIGIN = 'https://datewiseai.com';

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': DEFAULT_ORIGIN,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-DateWise-Entitlement',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

// Reject oversized uploads before spending an AI call (the client already
// resizes to ~768px; this guards against a modified/old client). ~1.5 MB of
// base64 ≈ ~1.1 MB image.
const MAX_IMAGE_BASE64_CHARS = 1_500_000;

// Max photos in a single "rank & compare" request.
const MAX_BATCH = 4;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}

// The vision model is great at *seeing* and critiquing but stubbornly replies
// in prose, so we let it write freely here, then convert to JSON in a 2nd pass
// with a text model that supports JSON mode.
const VISION_INTRO =
  'You are DateWise AI, an elite, brutally honest dating-profile photo coach. ' +
  'Critique this dating-profile photo.';

const DEEP_PROMPT = `${VISION_INTRO}
Give all of the following:
- an overall score from 1 to 10
- a verdict: KEEP, RESHOOT, or DELETE
- a one-sentence headline
- the predicted change in match rate as a percentage if the tips are applied
- for each of Lighting, Expression, Outfit, Framing, and Overall vibe: a score from 1 to 10 and a short note
- exactly three short, actionable tips to improve the photo`;

const QUICK_PROMPT = `${VISION_INTRO}
Be brief. Give: an overall score from 1 to 10; a verdict (KEEP, RESHOOT, or DELETE);
a one-sentence headline; the predicted change in match rate as a percentage; and ONE actionable tip.`;

// Second-pass text model (supports JSON mode / structured outputs).
// llama-3.1-8b-instruct was deprecated 2026-05-30, and llama-3.1-8b-instruct-fp8
// on 2026-11-20 (Workers AI now answers it with HTTP 410, error 5028). Llama 3.3
// 70B fp8-fast stays active, is on the JSON Mode list, and returns the same
// `response` shape (and the same SSE stream) the photo coach and the app read.
const TEXT_MODEL = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';

// --- Chat (AI coach replies) ----------------------------------------------
// The same free text model powers the coaching chat. Replies stream back
// token-by-token as Server-Sent Events so the app renders them live. Unlike the
// photo coach, chat is available on every tier.
const CHAT_MODEL = TEXT_MODEL;
const MAX_CHAT_MESSAGES = 24; // cap how many turns we forward to the model
const MAX_CHAT_CHARS = 24_000; // total prompt budget, trimmed from the newest end
const MAX_CHAT_TOKENS = 800;

// JSON schema the text model must fill — mirrors the Flutter PhotoAnalysis model.
const ANALYSIS_SCHEMA = {
  type: 'object',
  properties: {
    overallScore: { type: 'integer', minimum: 1, maximum: 10 },
    verdict: { type: 'string', enum: ['KEEP', 'RESHOOT', 'DELETE'] },
    headline: { type: 'string' },
    matchRateDelta: { type: 'integer' },
    dimensions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          score: { type: 'integer', minimum: 1, maximum: 10 },
          note: { type: 'string' },
        },
        required: ['name', 'score', 'note'],
      },
    },
    tips: { type: 'array', items: { type: 'string' } },
  },
  required: [
    'overallScore',
    'verdict',
    'headline',
    'matchRateDelta',
    'dimensions',
    'tips',
  ],
};

// --- Batch (rank & compare) prompts + schema ------------------------------
const BATCH_VISION_PROMPT = `${VISION_INTRO}
Be brief. Give: an overall score from 1 to 10; a verdict (KEEP, RESHOOT, or DELETE);
a one-sentence headline; and one short reason.`;

const BATCH_CONVERTER_SYSTEM =
  'You merge several dating-photo critiques into strict JSON that ranks them. Each ' +
  'critique is labelled "Photo N". For each photo output imageIndex = N-1, overallScore ' +
  '(integer 1-10), verdict (KEEP/RESHOOT/DELETE), a headline, and a one-line "why". Rank ' +
  'the set best→worst (rank 1 = best). Set bestIndex to the imageIndex of rank 1 and write ' +
  'a one-line recommendation naming which photo to lead with and which to drop.';

const BATCH_SCHEMA = {
  type: 'object',
  properties: {
    photos: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          imageIndex: { type: 'integer' },
          rank: { type: 'integer' },
          overallScore: { type: 'integer', minimum: 1, maximum: 10 },
          verdict: { type: 'string', enum: ['KEEP', 'RESHOOT', 'DELETE'] },
          headline: { type: 'string' },
          why: { type: 'string' },
        },
        required: ['imageIndex', 'overallScore', 'verdict', 'headline', 'why'],
      },
    },
    bestIndex: { type: 'integer' },
    recommendation: { type: 'string' },
  },
  required: ['photos', 'bestIndex', 'recommendation'],
};

// --- Deterministic prose parsing ------------------------------------------
// The vision model reliably writes well-structured prose ("**Overall Score:
// 6/10**", "**Verdict: RESHOOT**", "**Lighting: 5/10** note…", numbered tips).
// Parsing it directly is faster and far more reliable than a second LLM call,
// which only remains as a fallback.

const DIMENSION_NAMES = [
  'Lighting',
  'Expression',
  'Outfit',
  'Framing',
  'Overall vibe',
];

function parseVerdict(text) {
  const m = text.match(/\b(KEEP|RESHOOT|DELETE)\b/i);
  return m ? m[1].toUpperCase() : null;
}

function parseOverallScore(text) {
  // Tolerant of "Overall Score: 6/10", "Score: 6/10", "Overall Score: 4",
  // "Score: 7", etc. — grabs the rating number after a score label.
  let m = text.match(/overall\s*score[:*\s]*([0-9]{1,2})/i);
  if (!m) m = text.match(/\bscore[:*\s]*([0-9]{1,2})/i);
  return m ? clampScore(m[1]) : null;
}

function parseHeadline(text) {
  const m = text.match(/headline[:*\s"']*([^"'\n]+?)["'\n]/i);
  return m ? m[1].trim().replace(/\*+/g, '') : null;
}

function parseDelta(text) {
  const m = text.match(/match[\s-]*rate[^%\d+-]*([+-]?\d+)\s*%/i);
  return m ? parseInt(m[1], 10) : 0;
}

function parseDimension(text, name) {
  // Captures the score then the note, whether the note is on the same line or
  // the following line(s), up to a blank line or the next "**" heading.
  const re = new RegExp(
    name.replace(/\s+/g, '\\s*') +
      '[:*\\s]*([0-9]{1,2})\\s*\\/\\s*10\\**\\s*([\\s\\S]*?)(?=\\n\\s*\\n|\\n\\s*\\*\\*|$)',
    'i',
  );
  const m = text.match(re);
  if (!m) return null;
  return {
    name,
    score: clampScore(m[1]),
    note: (m[2] || '').replace(/\s+/g, ' ').trim().replace(/\*+/g, ''),
  };
}

function parseTips(text) {
  const tips = [];
  const re = /^\s*\d+\.\s*(.+)$/gm;
  let m;
  while ((m = re.exec(text)) !== null && tips.length < 5) {
    tips.push(m[1].trim().replace(/\*+/g, ''));
  }
  return tips;
}

// Returns a normalized single-photo analysis, or null if the prose lacks the
// essentials (score + verdict) and should fall back to the LLM converter.
function parseSingle(text, isQuick) {
  const overallScore = parseOverallScore(text);
  const verdict = parseVerdict(text);
  if (overallScore == null || !verdict) return null;
  const dimensions = isQuick
    ? []
    : DIMENSION_NAMES.map((n) => parseDimension(text, n)).filter(Boolean);
  const tips = parseTips(text);
  return {
    overallScore,
    verdict,
    headline: parseHeadline(text) || 'Here is your read.',
    matchRateDelta: parseDelta(text),
    dimensions,
    tips: isQuick ? tips.slice(0, 1) : tips.slice(0, 3),
  };
}

function firstSentence(text) {
  const t = String(text).trim().replace(/\*+/g, '');
  const m = t.match(/^.*?[.!?](\s|$)/);
  return (m ? m[0] : t).trim().slice(0, 120);
}

// Parse one short batch critique into a ranked-photo entry, or null if the
// essentials (score + verdict) are missing.
function parseBatchPhoto(text, index) {
  const overallScore = parseOverallScore(text);
  const verdict = parseVerdict(text);
  if (overallScore == null || !verdict) return null;
  let why = '';
  const rm = text.match(/reason[:*\s]*([^\n]+)/i);
  if (rm) why = rm[1].trim().replace(/\*+/g, '');
  return {
    imageIndex: index,
    overallScore,
    verdict,
    headline: parseHeadline(text) || firstSentence(text) || 'Analysed.',
    why,
  };
}

// Best-effort JSON extraction from a model's text output.
function extractJson(text) {
  if (!text) return null;
  let t = String(text).trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) t = fence[1].trim();
  const start = t.indexOf('{');
  const end = t.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) return null;
  try {
    return JSON.parse(t.slice(start, end + 1));
  } catch {
    return null;
  }
}

// Decodes a base64 string to a plain array of byte values (what Workers AI wants).
function base64ToBytes(b64) {
  const cleaned = String(b64 || '').replace(/^data:image\/\w+;base64,/, '').trim();
  if (!cleaned || cleaned.length < 32) {
    throw new Error('INVALID_IMAGE: empty or too short');
  }
  let bin;
  try {
    bin = atob(cleaned);
  } catch {
    throw new Error('INVALID_IMAGE: not valid base64');
  }
  if (bin.length < 8) throw new Error('INVALID_IMAGE: decoded payload too small');
  const arr = new Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  // JPEG SOI (FFD8) or PNG signature — reject garbage early with a clear 400.
  const isJpeg = arr[0] === 0xff && arr[1] === 0xd8;
  const isPng =
    arr[0] === 0x89 && arr[1] === 0x50 && arr[2] === 0x4e && arr[3] === 0x47;
  if (!isJpeg && !isPng) {
    throw new Error('INVALID_IMAGE: only JPEG or PNG photos are supported');
  }
  return arr;
}

// Runs a Workers AI model, transparently accepting a one-time Meta Llama
// license (AiError 5016) on first use for that model, then retrying.
async function runModel(env, model, input) {
  try {
    return await env.AI.run(model, input);
  } catch (e) {
    const msg = String(e);
    if (msg.includes('5016') || msg.toLowerCase().includes("prompt 'agree'")) {
      await env.AI.run(model, { prompt: 'agree' });
      return await env.AI.run(model, input);
    }
    throw e;
  }
}

// Coerce the model output into a shape the Flutter PhotoAnalysis model can parse
// (it requires dimensions[], tips[], and a numeric matchRateDelta).
function normalize(a) {
  return {
    overallScore: Number.isFinite(a.overallScore) ? a.overallScore : 5,
    verdict: typeof a.verdict === 'string' ? a.verdict : 'RESHOOT',
    headline: typeof a.headline === 'string' ? a.headline : 'Here is your read.',
    matchRateDelta: Number.isFinite(a.matchRateDelta) ? a.matchRateDelta : 0,
    dimensions: Array.isArray(a.dimensions) ? a.dimensions : [],
    tips: Array.isArray(a.tips) ? a.tips : [],
  };
}

function clampScore(s) {
  const n = Number(s);
  if (!Number.isFinite(n)) return 5;
  return Math.max(1, Math.min(10, Math.round(n)));
}

// Coerce + dedupe the batch result, fill any missing photo, and compute ranks
// from scores in the Worker so the ordering is always consistent.
function normalizeBatch(a, count) {
  const seen = new Set();
  let photos = (Array.isArray(a.photos) ? a.photos : [])
    .map((p) => ({
      imageIndex: Number.isInteger(p.imageIndex) ? p.imageIndex : -1,
      overallScore: clampScore(p.overallScore),
      verdict: typeof p.verdict === 'string' ? p.verdict : 'RESHOOT',
      headline: typeof p.headline === 'string' ? p.headline : 'Analysed.',
      why: typeof p.why === 'string' ? p.why : '',
    }))
    .filter(
      (p) =>
        p.imageIndex >= 0 &&
        p.imageIndex < count &&
        !seen.has(p.imageIndex) &&
        seen.add(p.imageIndex),
    );

  // Fill any photo the model skipped.
  for (let i = 0; i < count; i++) {
    if (!seen.has(i)) {
      photos.push({
        imageIndex: i,
        overallScore: 5,
        verdict: 'RESHOOT',
        headline: 'Analysed.',
        why: '',
      });
    }
  }

  // Rank by score (highest first) and stamp ranks.
  photos.sort((x, y) => y.overallScore - x.overallScore);
  photos.forEach((p, idx) => (p.rank = idx + 1));

  const bestIndex = photos.length ? photos[0].imageIndex : 0;
  let recommendation =
    typeof a.recommendation === 'string' && a.recommendation.trim()
      ? a.recommendation.trim()
      : '';
  if (!recommendation) {
    recommendation = `Lead with photo #${bestIndex + 1}.`;
    const worst = photos[photos.length - 1];
    if (photos.length > 1 && worst && worst.overallScore < 5) {
      recommendation += ` Consider dropping #${worst.imageIndex + 1}.`;
    }
  }
  return { photos, bestIndex, recommendation };
}

// Handles a multi-photo "rank & compare" request: critique each photo in
// parallel (one vision call each, since the model takes one image per call),
// then a single text pass merges + ranks them into strict JSON.
async function handleBatch(env, images, mode, userNote) {
  if (images.length > MAX_BATCH) {
    return json({ error: `Send at most ${MAX_BATCH} photos.` }, 400);
  }
  for (const img of images) {
    if (!img || typeof img !== 'string') {
      return json({ error: 'Each image must be a base64 string.' }, 400);
    }
    if (img.length > MAX_IMAGE_BASE64_CHARS) {
      return json({ error: 'One of the images is too large.' }, 413);
    }
  }

  const noteLine = userNote ? `\nUser note: ${userNote}` : '';

  // Pass 1: critique every photo in parallel (latency ≈ a single call).
  let critiques;
  try {
    critiques = await Promise.all(
      images.map((b64) =>
        runModel(env, MODEL, {
          image: base64ToBytes(b64),
          prompt: BATCH_VISION_PROMPT + noteLine,
          max_tokens: 300,
        }).then((r) => ((r && (r.response ?? r.description)) || '').trim()),
      ),
    );
  } catch (e) {
    return json({ error: 'Workers AI error', detail: String(e) }, 502);
  }

  // Primary: parse each critique directly and rank locally (no converter call).
  // As long as at least one photo parses, normalizeBatch fills any gaps and
  // ranks the set — so a single odd critique format can't break the whole batch.
  const parsedPhotos = critiques
    .map((c, i) => parseBatchPhoto(c, i))
    .filter(Boolean);
  if (parsedPhotos.length > 0) {
    return json(normalizeBatch({ photos: parsedPhotos }, images.length), 200);
  }

  // Fallback (only if nothing parsed): merge + rank via the text model.
  const labelled = critiques
    .map((c, i) => `Photo ${i + 1}:\n${c || '(no critique)'}`)
    .join('\n\n');

  let parsed = null;
  try {
    const conv = await runModel(env, TEXT_MODEL, {
      messages: [
        { role: 'system', content: BATCH_CONVERTER_SYSTEM },
        { role: 'user', content: labelled },
      ],
      response_format: { type: 'json_schema', json_schema: BATCH_SCHEMA },
      max_tokens: 900,
    });
    const r = conv && conv.response;
    parsed = r && typeof r === 'object' ? r : extractJson(r);
  } catch (_) {
    parsed = null;
  }

  if (!parsed) {
    try {
      const conv2 = await runModel(env, TEXT_MODEL, {
        messages: [
          {
            role: 'system',
            content:
              BATCH_CONVERTER_SYSTEM +
              ' Reply with ONLY the JSON object, starting with { and ending with }.',
          },
          { role: 'user', content: labelled },
        ],
        max_tokens: 900,
      });
      parsed = extractJson(conv2 && conv2.response);
    } catch (_) {
      parsed = null;
    }
  }

  if (!parsed) {
    return json({ error: 'Could not format ranking as JSON', raw: labelled }, 502);
  }
  return json(normalizeBatch(parsed, images.length), 200);
}

// Sanitises the client-supplied chat history: drops malformed turns, caps the
// length of each message, always keeps a leading system prompt, and trims the
// oldest turns so the prompt stays within budget (keeping the newest context).
function sanitizeMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) return null;
  const roles = new Set(['system', 'user', 'assistant']);
  const cleaned = [];
  for (const m of messages) {
    if (!m || typeof m.content !== 'string' || !roles.has(m.role)) continue;
    const content = m.content.slice(0, 6000).trim();
    if (content) cleaned.push({ role: m.role, content });
  }
  if (cleaned.length === 0) return null;

  // Always preserve a leading system message (the coach persona).
  const system = cleaned[0].role === 'system' ? cleaned.shift() : null;
  const recent = cleaned.slice(-MAX_CHAT_MESSAGES);

  // Keep the newest turns that fit within the character budget.
  let total = system ? system.content.length : 0;
  const kept = [];
  for (let i = recent.length - 1; i >= 0; i--) {
    total += recent[i].content.length;
    if (total > MAX_CHAT_CHARS && kept.length) break;
    kept.unshift(recent[i]);
  }
  return system ? [system, ...kept] : kept;
}

// Runs the chat model in streaming mode, accepting the one-time Meta Llama
// license (AiError 5016) on first use, then retrying — same as runModel.
async function runChatStream(env, messages, maxTokens = MAX_CHAT_TOKENS) {
  const input = { messages, max_tokens: maxTokens, stream: true };
  try {
    return await env.AI.run(CHAT_MODEL, input);
  } catch (e) {
    const msg = String(e);
    if (msg.includes('5016') || msg.toLowerCase().includes("prompt 'agree'")) {
      await env.AI.run(CHAT_MODEL, { prompt: 'agree' });
      return await env.AI.run(CHAT_MODEL, input);
    }
    throw e;
  }
}

// Handles a coaching chat request (chat-v7). With a coachId or a StoreKit
// token (the v2 app) the server builds the coach's system prompt (the default
// coach when no coachId is given) and drops client system messages, and the
// request needs a valid subscription token (403 SUBSCRIPTION_REQUIRED). Only a
// request with neither (the v1 build, 1.0.2, which never sends the token)
// keeps the chat-v6 behaviour, while LEGACY_CLIENTS=1, in the anonymous caps. Either way the history is trimmed to the input-token cap,
// the request is admitted by the cost guard, and the model's reply streams
// back unchanged as Server-Sent Events while it is metered.
// What the v1 build (1.0.2) shows once LEGACY_CLIENTS=0. v1 has no
// forced-update mechanism and shows only a fixed "unavailable" text for any
// non-200 response, so the notice is sent as a normal one-message reply (SSE,
// HTTP 200) that v1 displays in the chat. No model runs and no budget is used.
export const LEGACY_UPDATE_NOTICE = {
  en: 'DateWise has a new version. Please update the app in the App Store to keep chatting with your coach.',
  es: 'DateWise tiene una nueva versión. Actualiza la app en el App Store para seguir chateando con tu coach.',
};

/**
 * v1 sends no language field, so the hints are, in order: an explicit
 * language/locale in the body or profile (if a build ever sends one), the
 * Accept-Language header, then the user's last message (Spanish marks or
 * common Spanish words). English otherwise.
 */
export function legacyLanguage(request, body) {
  const explicit = [body?.language, body?.locale, body?.profile?.language, body?.profile?.locale].find((v) => typeof v === 'string');
  if (explicit) return /^es\b/i.test(explicit) ? 'es' : 'en';
  const accept = request.headers.get('Accept-Language') || '';
  if (accept) return /^\s*es\b/i.test(accept) ? 'es' : 'en';
  const msgs = Array.isArray(body?.messages) ? body.messages : [];
  const lastUser = [...msgs].reverse().find((m) => m && m.role === 'user' && typeof m.content === 'string');
  const text = (lastUser?.content || '').toLowerCase().slice(0, 2000);
  if (/[ñ¿¡]/.test(text)) return 'es';
  const words = text.match(/[a-záéíóúü]+/g) || [];
  const es = new Set(['hola', 'que', 'qué', 'como', 'cómo', 'para', 'por', 'una', 'con', 'mi', 'quiero', 'cita', 'chica', 'chico', 'gracias', 'pero', 'es', 'el', 'la', 'los', 'las', 'tengo', 'puedo', 'ayuda', 'novia', 'novio', 'mensaje']);
  const hits = words.filter((w) => es.has(w)).length;
  return words.length && hits >= Math.max(1, Math.ceil(words.length * 0.2)) ? 'es' : 'en';
}

function legacyUpdateNotice(request, body) {
  const lang = legacyLanguage(request, body);
  const sse = `data: ${JSON.stringify({ response: LEGACY_UPDATE_NOTICE[lang] })}\n\ndata: [DONE]\n\n`;
  return new Response(sse, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-store',
      'Content-Language': lang,
      'X-DateWise-Code': 'APP_UPDATE_REQUIRED',
      'Access-Control-Expose-Headers': 'X-DateWise-Code',
      ...corsHeaders(),
    },
  });
}

async function handleChat(request, env, ctx, body) {
  const cfg = guardConfig(env);
  const legacy =
    (body.coachId === undefined || body.coachId === null) && !request.headers.get('X-DateWise-Entitlement');
  let safe;
  if (legacy) {
    if (!cfg.LEGACY_CLIENTS) return legacyUpdateNotice(request, body);
    safe = sanitizeMessages(body.messages);
  } else {
    const coachId = resolveCoachId(body.coachId);
    if (!coachId) return json({ error: 'Unknown coachId.', code: 'UNKNOWN_COACH' }, 400);
    const built = coachMessages(coachId, body.profile, body.messages);
    safe = built && sanitizeMessages(built);
  }
  if (!safe) {
    return json({ error: 'Provide at least one user message.' }, 400);
  }
  // The token-less v1 path is anonymous, so it also gets the smaller legacy
  // per-request caps: posing as v1 buys only short prompts and short replies.
  const maxOut =
    Math.min(MAX_CHAT_TOKENS, cfg.MAX_OUTPUT_TOKENS, legacy ? cfg.LEGACY_MAX_OUTPUT_TOKENS : Infinity) || MAX_CHAT_TOKENS;
  const fitted = fitToInputBudget(safe, legacy ? Math.min(cfg.MAX_INPUT_TOKENS, cfg.LEGACY_MAX_INPUT_TOKENS) : cfg.MAX_INPUT_TOKENS);
  const inTokens = estimateTokens(fitted);
  const gate = await admit(request, env, corsHeaders(), {
    kind: legacy ? 'legacy-chat' : 'chat',
    // A v2 request (coachId or token) is served only with a valid StoreKit
    // token: 403 SUBSCRIPTION_REQUIRED otherwise, whatever REQUIRE_SUBSCRIPTION says.
    requireToken: !legacy,
    model: CHAT_MODEL,
    inTokens,
    outTokens: maxOut,
  });
  if (gate.response) return gate.response;
  const { ticket } = gate;
  // Degraded (opt-in fail-open while the counters are down): the smaller
  // legacy per-request caps apply, so the outage allowance stays cheap.
  const modelMessages = ticket.degraded ? fitToInputBudget(fitted, ticket.maxInputTokens) : fitted;
  const modelMaxOut = ticket.degraded ? Math.min(maxOut, ticket.maxOutputTokens) : maxOut;
  let stream;
  try {
    stream = await runChatStream(env, modelMessages, modelMaxOut);
  } catch (e) {
    ctx?.waitUntil?.(ticket.finish(0, { refund: true }));
    return json({ error: 'Workers AI error', detail: String(e) }, 502);
  }
  const metered = meterStream(stream, (m) => {
    const actual = neuronsFor(CHAT_MODEL, m.inTokens || estimateTokens(modelMessages), m.outTokens);
    // A server-side failure (the model stream broke, or ended with no reply)
    // gives the message back; a client that hangs up still uses it.
    const refund = m.outcome === 'error' || (m.outcome === 'done' && !m.produced);
    const done = ticket.finish(actual, { refund });
    if (ctx?.waitUntil) ctx.waitUntil(done);
  });
  // Workers AI returns an SSE ReadableStream ("data: {\"response\":\"…\"}\n\n"
  // … "data: [DONE]"); forward it verbatim with CORS so the app can stream it.
  return new Response(metered, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      ...corsHeaders(),
      ...ticket.headers,
    },
  });
}

// Worst-case neurons for one photo request: one vision call per photo (about
// 1,600 image tokens + the prompt, up to 800 out) plus up to two 70B converter
// passes (JSON mode, then plain JSON) of up to 900 tokens out.
function photoReserve(count) {
  return count * neuronsFor(MODEL, 2000, 800) + 2 * neuronsFor(TEXT_MODEL, 1500, 900);
}

export default {
  async fetch(request, env, ctx) {
    const origin = request.headers.get('Origin') || '';
    const res = await route(request, env, ctx);
    // Per request, after every await: the response carries this request's origin.
    if (isAllowedOrigin(origin) && origin !== DEFAULT_ORIGIN) {
      try {
        res.headers.set('Access-Control-Allow-Origin', origin);
      } catch {
        /* immutable headers: keep the default origin */
      }
    }
    return res;
  },
};

async function route(request, env, ctx) {
  {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    // One-time Llama license acceptance. It runs the model with no subscription
    // check, so it is off unless the Worker has ALLOW_AGREE = "1" (set it only
    // for the first deploy on a new Cloudflare account, open
    // <worker-url>/?agree=1 once, then remove it). Cloudflare registers
    // acceptance for the whole account. We try a few input shapes because some
    // gated models validate inputs differently.
    if (request.method === 'GET') {
      const url = new URL(request.url);
      // Quick deploy check: open <worker-url>/?version to confirm this code is live.
      if (url.searchParams.has('version')) {
        return json({ version: GUARD_VERSION, note: 'chat-v6 + cost guard (fair-use caps, neuron budget, StoreKit 2 JWS), server-side coach prompts; text model llama-3.3-70b-instruct-fp8-fast' });
      }
      if (url.searchParams.get('agree') === '1' && env.ALLOW_AGREE === '1') {
        if (!env.AI) return json({ error: 'AI binding "AI" missing' }, 500);
        const attempts = [
          { prompt: 'agree' },
          { messages: [{ role: 'user', content: 'agree' }] },
        ];
        const errors = [];
        for (const inp of attempts) {
          try {
            const r = await env.AI.run(MODEL, inp);
            return json({ ok: true, message: 'License accepted.', result: r });
          } catch (e) {
            errors.push(String(e));
          }
        }
        return json({ ok: false, errors }, 502);
      }
      return json({ error: 'Method not allowed' }, 405);
    }

    if (request.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405);
    }
    // Optional App Store Server Notifications v2 (refunds/revocations); off by default.
    if (new URL(request.url).pathname === '/apple/notifications') {
      return await handleAppleNotification(request, env);
    }
    if (!env.AI) {
      return json(
        { error: 'Workers AI binding "AI" is not configured on this Worker.' },
        500,
      );
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'Invalid JSON body' }, 400);
    }

    const { imageBase64, images, tier, mode, userNote, messages } = body || {};

    // Coaching chat path — streams a text reply. Checked before the photo
    // coach below.
    if (Array.isArray(messages) && messages.length > 0) {
      return await handleChat(request, env, ctx, body);
    }

    // The photo coach: only the v1 build (1.0.2) uses it (the v2 app sends no
    // photos). Kept while LEGACY_CLIENTS=1, inside the same caps and budget,
    // reserved at its worst case and settled with the measured usage.
    if (!guardConfig(env).LEGACY_CLIENTS) {
      // v1 shows "Photo coach backend error (426): <body>", so the body says what to do.
      return guardError('APP_UPDATE_REQUIRED', corsHeaders(), { message: 'Please update DateWise from the App Store.' });
    }
    if (tier !== 'magnet') {
      return json({ error: 'The AI Photo Coach is a Magnet-tier feature.' }, 403);
    }
    const photoCount = Array.isArray(images) && images.length > 0 ? Math.min(images.length, MAX_BATCH) : 1;
    const photoGate = await admit(request, env, corsHeaders(), { kind: 'photo', neurons: photoReserve(photoCount) });
    if (photoGate.response) return photoGate.response;
    const meter = meteredAi(env.AI);
    let photoResponse;
    try {
      photoResponse = await handlePhoto({ ...env, AI: meter.ai }, { imageBase64, images, tier, mode, userNote });
    } catch (e) {
      photoResponse = json({ error: 'Workers AI error', detail: String(e) }, 502);
    }
    const spent = meter.neurons();
    // Refund the message only when the server failed or no model ran (a bad image).
    ctx?.waitUntil?.(photoGate.ticket.finish(spent, { refund: photoResponse.status >= 500 || spent === 0 }));
    for (const [k, v] of Object.entries(photoGate.ticket.headers)) photoResponse.headers.set(k, v);
    return photoResponse;
  }
}

// The v1 photo coach, unchanged from chat-v6 (only moved into a function).
async function handlePhoto(env, { imageBase64, images, tier, mode, userNote }) {

    // Soft tier gate (client-sent; for real paywalls verify a session/payment).
    if (tier !== 'magnet') {
      return json({ error: 'The AI Photo Coach is a Magnet-tier feature.' }, 403);
    }

    // Multi-photo "rank & compare" path.
    if (Array.isArray(images) && images.length > 0) {
      return await handleBatch(env, images, mode, userNote);
    }

    if (!imageBase64 || typeof imageBase64 !== 'string') {
      return json({ error: 'Missing imageBase64' }, 400);
    }
    // Server-side size guard.
    if (imageBase64.length > MAX_IMAGE_BASE64_CHARS) {
      return json(
        { error: 'Image too large. Please send a smaller photo.' },
        413,
      );
    }

    const isQuick = mode === 'quick';
    const basePrompt = isQuick ? QUICK_PROMPT : DEEP_PROMPT;
    const prompt = userNote ? `${basePrompt}\nUser note: ${userNote}` : basePrompt;

    // --- Pass 1: vision model critiques the photo (prose) -------------------
    let visionResult;
    let visionInputBytes;
    try {
      visionInputBytes = base64ToBytes(imageBase64);
    } catch (e) {
      const msg = String(e.message || e);
      if (msg.startsWith('INVALID_IMAGE:')) {
        return json({ error: msg.replace(/^INVALID_IMAGE:\s*/, '') }, 400);
      }
      return json({ error: 'Could not read that image. Try a JPG or PNG under ~5MB.' }, 400);
    }
    try {
      visionResult = await runModel(env, MODEL, {
        image: visionInputBytes,
        prompt,
        max_tokens: isQuick ? 350 : 800,
      });
    } catch (e) {
      const detail = String(e);
      if (detail.includes('5016') || /terms/i.test(detail)) {
        return json(
          {
            error:
              'Photo coach model license needs a one-time owner acceptance. Open the Worker URL with ?agree=1 once, then retry.',
            detail,
          },
          503,
        );
      }
      return json({ error: 'Workers AI error', detail }, 502);
    }

    const critique = (visionResult && (visionResult.response ?? visionResult.description) || '').trim();
    if (!critique) {
      return json({ error: 'Vision model returned nothing' }, 502);
    }

    // Primary: parse the structured prose directly (deterministic, no 2nd call).
    const parsedDirect = parseSingle(critique, isQuick);
    if (parsedDirect) {
      return json(normalize(parsedDirect), 200);
    }

    // --- Pass 2 (fallback): text model converts the critique to strict JSON -
    const dimensionsRule = isQuick
      ? 'Set "dimensions" to an empty array [].'
      : 'Map Lighting, Expression, Outfit, Framing, and Overall vibe into "dimensions" (5 items).';
    const tipsRule = isQuick
      ? 'Provide exactly one tip in "tips".'
      : 'Provide exactly three tips in "tips".';
    const converterSystem =
      'You convert a dating-photo critique into strict JSON matching the schema. ' +
      'Use only information in the critique; if a value is missing, infer a sensible one. ' +
      'Scores are integers 1-10. "matchRateDelta" is an integer percentage (no % sign). ' +
      `${dimensionsRule} ${tipsRule}`;

    let analysis = null;
    try {
      const conv = await runModel(env, TEXT_MODEL, {
        messages: [
          { role: 'system', content: converterSystem },
          { role: 'user', content: critique },
        ],
        response_format: { type: 'json_schema', json_schema: ANALYSIS_SCHEMA },
        max_tokens: 800,
      });
      // JSON mode may return an already-parsed object or a JSON string.
      const r = conv && conv.response;
      analysis = r && typeof r === 'object' ? r : extractJson(r);
    } catch (_) {
      analysis = null; // fall through to the plain-text fallback below
    }

    // Fallback: ask the text model for raw JSON without structured-output mode.
    if (!analysis) {
      try {
        const conv2 = await runModel(env, TEXT_MODEL, {
          messages: [
            {
              role: 'system',
              content:
                converterSystem +
                ' Reply with ONLY the JSON object, starting with { and ending with }. No prose, no markdown.',
            },
            { role: 'user', content: critique },
          ],
          max_tokens: 800,
        });
        analysis = extractJson(conv2 && conv2.response);
      } catch (_) {
        analysis = null;
      }
    }

    if (!analysis) {
      return json({ error: 'Could not format analysis as JSON', raw: critique }, 502);
    }
    return json(normalize(analysis), 200);
}
