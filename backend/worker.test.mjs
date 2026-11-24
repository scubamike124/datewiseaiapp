// Offline checks for worker.js against a fake Workers AI binding (no network, no Cloudflare account):
//   node --test backend/worker.test.mjs
// They pin what the 2026-11-20 model retirement broke: every model the Worker calls is still in the catalogue,
// and coach chat and both photo paths still send the same inputs and read the same `response` field.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import worker from './worker.js';
import { _setTrustedRootsForTests } from './cost_guard.js';
import { fakeDoNamespace, makePki, txPayload } from './test/helpers.mjs';

// chat-v7: every AI path goes through the cost guard (an in-memory Durable
// Object here). These requests carry a subscription token signed by a
// throwaway test PKI.
const pki = await makePki();
_setTrustedRootsForTests([pki.rootSha256]);
const JWS = await pki.sign(txPayload());

// Retired on 2026-11-20 (https://developers.cloudflare.com/changelog/post/2026-11-05-planned-model-deprecations/)
// and earlier (llama-3.1-8b-instruct, 2026-05-30). Requests to them now fail with HTTP 410.
const RETIRED = [
  '@cf/meta/llama-3.1-8b-instruct-fp8',
  '@cf/meta/llama-3.1-8b-instruct',
  '@cf/meta/llama-3.2-1b-instruct',
  '@cf/meta/llama-3.2-3b-instruct',
  '@cf/qwen/qwen3-30b-a3b-fp8',
  '@cf/zai-org/glm-5.3-flash',
];
const TEXT_MODEL = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';
const VISION_MODEL = '@cf/meta/llama-3.2-11b-vision-instruct';

// A 1x1 PNG.
const PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

function fakeEnv(reply) {
  const calls = [];
  return {
    calls,
    env: {
      AI: {
        async run(model, input) {
          calls.push({ model, input });
          return reply(model, input);
        },
      },
      USAGE_GUARD: fakeDoNamespace(),
      DAILY_NEURON_BUDGET: '1000000',
    },
  };
}

const post = (body) =>
  new Request('https://example.workers.dev/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://datewiseai.com', 'X-DateWise-Entitlement': JWS },
    body: JSON.stringify(body),
  });

const ANALYSIS = {
  overallScore: 7,
  verdict: 'KEEP',
  headline: 'Warm smile, good light.',
  matchRateDelta: 12,
  dimensions: [],
  tips: ['Try a little more headroom.'],
};

test('no retired model is referenced anywhere in worker.js', () => {
  const src = readFileSync(new URL('./worker.js', import.meta.url), 'utf8');
  for (const id of RETIRED) assert.ok(!src.includes(`'${id}'`), `${id} is retired`);
  assert.ok(src.includes(`'${TEXT_MODEL}'`));
  assert.ok(src.includes(`'${VISION_MODEL}'`));
});

test('GET ?version names the fix', async () => {
  const res = await worker.fetch(new Request('https://example.workers.dev/?version'), fakeEnv(() => ({})).env);
  const body = await res.json();
  assert.equal(body.version, 'chat-v7-cost-guard');
});

test('GET ?agree=1 never runs the model unless ALLOW_AGREE is "1"', async () => {
  for (const extra of [{}, { ALLOW_AGREE: '0' }, { ALLOW_AGREE: 'true' }]) {
    const f = fakeEnv(() => ({ response: 'ok' }));
    const res = await worker.fetch(new Request('https://example.workers.dev/?agree=1'), { ...f.env, ...extra });
    assert.equal(res.status, 405);
    assert.equal(f.calls.length, 0, `model called with ${JSON.stringify(extra)}`);
  }
  // Opt-in for a new account's one-time licence acceptance still works.
  const f = fakeEnv(() => ({ response: 'ok' }));
  const res = await worker.fetch(new Request('https://example.workers.dev/?agree=1'), { ...f.env, ALLOW_AGREE: '1' });
  assert.equal(res.status, 200);
  assert.equal(f.calls.length, 1);
});

test('the committed configs never set ALLOW_AGREE', () => {
  assert.ok(!readFileSync(new URL('./wrangler.toml', import.meta.url), 'utf8').includes('ALLOW_AGREE'));
});

test('coach chat streams from the text model and forwards the SSE body unchanged', async () => {
  const sse = 'data: {"response":"Hola"}\n\ndata: {"response":"!"}\n\ndata: [DONE]\n\n';
  const f = fakeEnv((model, input) => {
    assert.equal(input.stream, true);
    return new Response(sse).body;
  });
  const res = await worker.fetch(post({ tier: 'free', messages: [{ role: 'user', content: 'hi' }] }), f.env);
  assert.equal(res.status, 200);
  assert.match(res.headers.get('Content-Type') || '', /text\/event-stream/);
  assert.equal(await res.text(), sse);
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].model, TEXT_MODEL);
  assert.ok(Array.isArray(f.calls[0].input.messages) && f.calls[0].input.messages.length >= 1);
});

test('single photo: vision model first, then the text model in JSON mode, read from `response`', async () => {
  const f = fakeEnv((model, input) => {
    if (model === VISION_MODEL) return { response: 'A warm, friendly photo with soft light.' }; // not structured: forces pass 2
    assert.equal(model, TEXT_MODEL);
    if (input.response_format) {
      assert.equal(input.response_format.type, 'json_schema');
      return { response: ANALYSIS };
    }
    return { response: JSON.stringify(ANALYSIS) };
  });
  const res = await worker.fetch(post({ tier: 'magnet', mode: 'quick', imageBase64: PNG_BASE64 }), f.env);
  const body = await res.json();
  assert.equal(res.status, 200, JSON.stringify(body));
  assert.equal(body.overallScore, 7);
  assert.equal(body.verdict, 'KEEP');
  assert.deepEqual(f.calls.map((c) => c.model), [VISION_MODEL, TEXT_MODEL]);
});

test('single photo: when JSON mode fails, the plain-text fallback on the same text model still parses', async () => {
  const f = fakeEnv((model, input) => {
    if (model === VISION_MODEL) return { response: 'A warm, friendly photo with soft light.' };
    if (input.response_format) throw new Error("JSON Mode couldn't be met");
    return { response: `Here you go: ${JSON.stringify(ANALYSIS)}` };
  });
  const res = await worker.fetch(post({ tier: 'magnet', mode: 'quick', imageBase64: PNG_BASE64 }), f.env);
  const body = await res.json();
  assert.equal(res.status, 200, JSON.stringify(body));
  assert.equal(body.verdict, 'KEEP');
  assert.deepEqual(f.calls.map((c) => c.model), [VISION_MODEL, TEXT_MODEL, TEXT_MODEL]);
});

test('a retired-model error (HTTP 410) surfaces as a 502 with the detail, not a silent empty reply', async () => {
  const f = fakeEnv(() => {
    throw new Error('AiError: 5028: model has been deprecated (410 Gone)');
  });
  const res = await worker.fetch(post({ tier: 'free', messages: [{ role: 'user', content: 'hi' }] }), f.env);
  assert.equal(res.status, 502);
  assert.match((await res.json()).detail, /5028/);
});

test('an oversized request body is refused with 413 before it is parsed or reaches the model (security review M5)', async () => {
  const f = fakeEnv(() => ({ response: 'never' }));
  f.env.LEGACY_CLIENTS = '0'; // as in production (wrangler.toml)
  const big = 'x'.repeat(300 * 1024);
  const res = await worker.fetch(post({ messages: [{ role: 'user', content: big }] }), f.env);
  assert.equal(res.status, 413);
  assert.equal((await res.json()).code, 'PAYLOAD_TOO_LARGE');
  assert.equal(f.calls.length, 0);
  const declared = new Request('https://example.workers.dev/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': String(10 * 1024 * 1024), 'X-DateWise-Entitlement': JWS },
    body: '{}',
  });
  assert.equal((await worker.fetch(declared, f.env)).status, 413);
});

test('an oversized v1-signature request (no token) gets the 426 update notice, not a bare 413, once v1 is not served (code review M1)', async () => {
  const f = fakeEnv(() => ({ response: 'never' }));
  f.env.LEGACY_CLIENTS = '0'; // as in production (wrangler.toml)
  // A v1 (1.0.2) photo request: base64 image, no X-DateWise-Entitlement header, well over the 256 KB cap.
  const v1Photo = (headers = {}) =>
    new Request('https://example.workers.dev/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: 'https://datewiseai.com', ...headers },
      body: JSON.stringify({ tier: 'magnet', imageBase64: 'A'.repeat(600 * 1024) }),
    });
  for (const headers of [{}, { 'Content-Length': String(10 * 1024 * 1024) }]) {
    const res = await worker.fetch(v1Photo(headers), f.env);
    assert.equal(res.status, 426);
    const out = await res.json();
    assert.equal(out.code, 'APP_UPDATE_REQUIRED');
    assert.match(out.message, /update DateWise from the App Store/);
  }
  // A small v1 photo request already got the same notice.
  const small = new Request('https://example.workers.dev/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tier: 'magnet', imageBase64: 'A'.repeat(1000) }),
  });
  assert.equal((await worker.fetch(small, f.env)).status, 426);
  assert.equal(f.calls.length, 0);
  // While v1 is still served (LEGACY_CLIENTS=1), an over-cap body is a plain 413.
  f.env.LEGACY_CLIENTS = '1';
  const huge = new Request('https://example.workers.dev/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tier: 'magnet', imageBase64: 'A'.repeat(9 * 1024 * 1024) }),
  });
  assert.equal((await worker.fetch(huge, f.env)).status, 413);
});

