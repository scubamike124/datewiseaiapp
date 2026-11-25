// Kokoro speech service: request validation and the POST /v1/speech contract (docs/avatar/KOKORO_SPEECH_CONTRACT.md).
//
// This is a stub. It validates requests exactly as the contract says and hands valid ones to a renderer. No renderer
// is wired in yet, so the default answer is 503 "not_configured" and nothing is synthesized, stored or billed. The
// renderer (Kokoro-82M ONNX, Apache-2.0) is added later behind the same `render` function.

export const KOKORO_VOICES = Object.freeze({
  af_bella: 'en-us',
  am_michael: 'en-us',
  ef_dora: 'es',
  em_alex: 'es',
});

export const MAX_TEXT_CHARS = 1000;
export const SPEED_MIN = 0.6;
export const SPEED_MAX = 1.3;

/** Validates a parsed request body. Returns { ok: true, value } or { ok: false, error }. */
export function validateSpeechRequest(body) {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return { ok: false, error: 'body must be a JSON object' };
  }
  const { text, voice, lang, speed } = body;
  if (typeof text !== 'string' || text.trim().length === 0) {
    return { ok: false, error: 'text must be a non-empty string' };
  }
  if (text.length > MAX_TEXT_CHARS) {
    return { ok: false, error: `text must be at most ${MAX_TEXT_CHARS} characters` };
  }
  if (typeof voice !== 'string' || !Object.hasOwn(KOKORO_VOICES, voice)) {
    return { ok: false, error: 'voice must be one of the listed Kokoro voices' };
  }
  if (lang !== KOKORO_VOICES[voice]) {
    return { ok: false, error: `lang must be "${KOKORO_VOICES[voice]}" for voice ${voice}` };
  }
  if (typeof speed !== 'number' || !Number.isFinite(speed) || speed < SPEED_MIN || speed > SPEED_MAX) {
    return { ok: false, error: `speed must be a number from ${SPEED_MIN} to ${SPEED_MAX}` };
  }
  return { ok: true, value: { text, voice, lang, speed } };
}

/**
 * Handles one POST /v1/speech. Returns { status, json }.
 * `render(value)` must resolve to { timeline, audio_url } (see the contract). Without it the service answers 503.
 */
export async function handleSpeech({ method, contentType, rawBody }, { render } = {}) {
  if (method !== 'POST') return { status: 405, json: { error: 'method_not_allowed' } };
  if (!String(contentType ?? '').toLowerCase().startsWith('application/json')) {
    return { status: 415, json: { error: 'content_type_must_be_application_json' } };
  }
  let body;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return { status: 400, json: { error: 'invalid_json' } };
  }
  const checked = validateSpeechRequest(body);
  if (!checked.ok) return { status: 400, json: { error: 'invalid_request', detail: checked.error } };
  if (typeof render !== 'function') return { status: 503, json: { error: 'not_configured' } };
  try {
    const out = await render(checked.value);
    if (!out || typeof out.audio_url !== 'string' || !out.timeline || typeof out.timeline !== 'object') {
      return { status: 500, json: { error: 'renderer_returned_invalid_reply' } };
    }
    return { status: 200, json: { timeline: out.timeline, audio_url: out.audio_url } };
  } catch {
    return { status: 502, json: { error: 'render_failed' } };
  }
}
