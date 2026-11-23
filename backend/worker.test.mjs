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
// Object here) and the photo coach needs PHOTO_COACH_ENABLED=1 plus a verified
// subscription (a JWS from a throwaway test PKI).
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
      PHOTO_COACH_ENABLED: '1',
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
