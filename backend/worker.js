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
 */

const MODEL = '@cf/meta/llama-3.2-11b-vision-instruct';
const ALLOWED_ORIGIN = '*'; // lock to 'https://kaowserf.github.io' in production

// Reject oversized uploads before spending an AI call (the client already
// resizes to ~768px; this guards against a modified/old client). ~1.5 MB of
// base64 ≈ ~1.1 MB image.
const MAX_IMAGE_BASE64_CHARS = 1_500_000;

// Max photos in a single "rank & compare" request.
const MAX_BATCH = 4;

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

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
const TEXT_MODEL = '@cf/meta/llama-3.1-8b-instruct';

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
  const bin = atob(b64);
  const arr = new Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
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
async function runChatStream(env, messages) {
  const input = { messages, max_tokens: MAX_CHAT_TOKENS, stream: true };
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

// Handles a coaching chat request: streams the model's reply straight back to
// the client as Server-Sent Events. The client builds the system prompt (the
// DateWise persona + the user's dating profile), so this stays generic.
async function handleChat(env, messages) {
  const safe = sanitizeMessages(messages);
  if (!safe) {
    return json({ error: 'Provide a non-empty "messages" array.' }, 400);
  }
  let stream;
  try {
    stream = await runChatStream(env, safe);
  } catch (e) {
    return json({ error: 'Workers AI error', detail: String(e) }, 502);
  }
  // Workers AI returns an SSE ReadableStream ("data: {\"response\":\"…\"}\n\n"
  // … "data: [DONE]"); forward it verbatim with CORS so the app can stream it.
  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      ...corsHeaders(),
    },
  });
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    // One-time Llama license acceptance. Open <worker-url>/?agree=1 once in a
    // browser; Cloudflare registers acceptance for the whole account. We try a
    // few input shapes because some gated models validate inputs differently.
    if (request.method === 'GET') {
      const url = new URL(request.url);
      // Quick deploy check: open <worker-url>/?version to confirm this code is live.
      if (url.searchParams.has('version')) {
        return json({ version: 'chat-v5', note: 'streaming coach chat + single + batch parsing' });
      }
      if (url.searchParams.get('agree') === '1') {
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

    // Coaching chat path (all tiers) — streams a text reply. Checked before the
    // Magnet gate below, which only guards the photo coach.
    if (Array.isArray(messages) && messages.length > 0) {
      return await handleChat(env, messages);
    }

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
    const visionInput = {
      image: base64ToBytes(imageBase64),
      prompt,
      max_tokens: isQuick ? 350 : 800,
    };

    let visionResult;
    try {
      visionResult = await runModel(env, MODEL, visionInput);
    } catch (e) {
      return json({ error: 'Workers AI error', detail: String(e) }, 502);
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
  },
};
