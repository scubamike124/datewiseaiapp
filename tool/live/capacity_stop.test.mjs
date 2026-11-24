// Owner rule (2026-11-24): Amber and production take priority on the shared free Workers AI allowance. A LIVE run stops
// at once, cleanly, at the first sign it is used up, marks the rest "not run", never retries, and spends nothing more.
// Offline: a fake Worker answers through fetchImpl.
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { runKit, sharedCapacitySign, STAGING_WORKER } from './live_chat_test.mjs';

const quiet = () => {};
const jws = `eyJhbGciOiJFUzI1NiIsIng1YyI6W119.${Buffer.from(JSON.stringify({ environment: 'Sandbox', expiresDate: Date.now() + 3_600_000 })).toString('base64url')}.c2lnbmF0dXJlLXZhbHVlLWZvci10ZXN0cw`;
const base = `https://${STAGING_WORKER}.acme.workers.dev`;
const sse = (text) => `data: ${JSON.stringify({ response: text })}\n\ndata: {"response":"","usage":{"prompt_tokens":1700,"completion_tokens":60}}\n\ndata: [DONE]\n\n`;
const EN = "Hi, I'm your dating coach. Here is a warm, specific opener you could send her today, plus one easy question to keep the chat going.";
const ES = '¡Hola! Soy tu coach de citas. Aquí tienes un mensaje cálido y específico para empezar la plática con ella, y una pregunta fácil para ahorita.';
const spanish = (init) => /[¿¡áéíóúñ]|\b(hola|oye|quiero|cómo|ustedes|platicar)\b/i.test(JSON.parse(init.body).messages.at(-1).content);

/** A fake Worker: version OK, `okCount` good chats, then `then()` for every later chat. */
function fakeWorker(okCount, then) {
  const chats = [];
  const fetchImpl = async (url, init) => {
    if (init.method === 'GET') return new Response(JSON.stringify({ version: 'chat-v7-cost-guard' }));
    chats.push(url);
    if (chats.length <= okCount) return new Response(sse(spanish(init) ? ES : EN), { headers: { 'Content-Type': 'text/event-stream', 'X-DateWise-Remaining-Today': '5' } });
    return then();
  };
  return { fetchImpl, chats };
}
const go = (fw, extra = {}) => runKit({ mode: 'live', battery: 'all', tier: 2, day: 1, perDay: 16, jws, confirmLive: true, baseUrl: base, fetchImpl: fw.fetchImpl, write: false, log: quiet, ...extra });

const json = (status, body, headers = {}) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...headers } });

test('a Workers AI 4006 (daily free allocation used up) stops the run at once: the rest is "not run: shared capacity", no retry, exit 3', async () => {
  const fw = fakeWorker(2, () => json(502, { error: 'Workers AI error', detail: 'InferenceUpstreamError 4006' }));
  const r = await go(fw);
  assert.equal(fw.chats.length, 3, 'two good requests, the failing one, and nothing after it (no retry, no further scenario)');
  assert.equal(r.haltKind, 'shared-capacity');
  assert.equal(r.exitCode, 3);
  const skipped = r.records.filter((x) => x.skipped);
  assert.ok(skipped.length >= 10);
  for (const x of skipped) assert.match(x.skipped, /^not run: shared capacity/);
  assert.deepEqual(r.failures, [], 'the capacity request itself is not a product failure');
  assert.match(r.report, /not run: shared capacity/);
  assert.match(r.report, /^# DateWise chat-v7 AI test: LIVE\n/);
});

test('an unknown 429 or 503 (not the Worker\'s own guard codes) counts as shared capacity; the Worker\'s own codes do not', async () => {
  for (const [status, body] of [[429, { error: 'Too many requests' }], [503, { error: 'Capacity temporarily exceeded' }], [429, { code: 'SOMETHING_NEW' }]]) {
    const fw = fakeWorker(1, () => json(status, body));
    const r = await go(fw);
    assert.equal(r.haltKind, 'shared-capacity', JSON.stringify([status, body]));
    assert.equal(fw.chats.length, 2);
    assert.equal(r.exitCode, 3);
  }
  // RATE_LIMITED is the Worker's own per-minute limit: not a capacity stop (a plain failing check, as before).
  const fw = fakeWorker(1, () => json(429, { code: 'RATE_LIMITED' }, { 'Retry-After': '1' }));
  const r = await go(fw, { perMinute: 1000 });
  assert.notEqual(r.haltKind, 'shared-capacity');
});

test("the staging Worker's own neuron cap (SERVICE_BUDGET_EXHAUSTED) stops the run with its own label and exit 3", async () => {
  const fw = fakeWorker(3, () => json(503, { code: 'SERVICE_BUDGET_EXHAUSTED', error: 'x' }));
  const r = await go(fw);
  assert.equal(r.haltKind, 'staging-cap');
  assert.equal(r.exitCode, 3);
  assert.equal(fw.chats.length, 4);
  for (const x of r.records.filter((x) => x.skipped)) assert.match(x.skipped, /^not run: staging daily neuron cap/);
});

test('a stream that fails with a capacity error mid-reply stops the run too', async () => {
  const bad = 'data: {"response":"Hi"}\n\ndata: {"error":{"code":4006,"message":"daily free allocation of 10,000 neurons used up"}}\n\n';
  const fw = fakeWorker(1, () => new Response(bad, { headers: { 'Content-Type': 'text/event-stream' } }));
  const r = await go(fw);
  assert.equal(r.haltKind, 'shared-capacity');
  assert.equal(fw.chats.length, 2);
});

test('sharedCapacitySign: pure cases', () => {
  assert.ok(sharedCapacitySign({ status: 502, reply: '{"detail":"InferenceUpstreamError 4006"}' }));
  assert.equal(sharedCapacitySign({ status: 200 }), null);
  assert.equal(sharedCapacitySign({ status: 403, code: 'SUBSCRIPTION_INVALID' }), null);
  assert.equal(sharedCapacitySign({ status: 429, code: 'DAILY_LIMIT' }), null);
  assert.equal(sharedCapacitySign({ status: 503, code: 'GUARD_UNAVAILABLE' }), null);
  assert.ok(sharedCapacitySign({ status: 200, streamError: 'upstream error event: 4006 neurons' }));
  assert.equal(sharedCapacitySign({ status: 200, streamError: 'timeout after 60000 ms' }), null);
});

test('the report and grader packet: LIVE packets are gradable only with real replies, never SIMULATED ones', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'cap-'));
  const fw = fakeWorker(2, () => json(502, { error: 'Workers AI error', detail: 'InferenceUpstreamError 4006' }));
  const r = await go(fw, { write: true, out: dir });
  const packet = JSON.parse(readFileSync(r.reportPath.replace(/\.md$/, '') + '.grader.json', 'utf8'));
  assert.equal(packet.label, 'LIVE');
  assert.equal(packet.gradable, true);
  assert.equal(packet.items.length, 2, 'only the two real replies');
  assert.ok(!readFileSync(r.reportPath, 'utf8').includes(jws));
  assert.equal(readdirSync(dir).length, 2);
  // SIMULATED (local mode) stays SIMULATED and ungradable.
  const sim = await runKit({ mode: 'local', battery: 'all', tier: 1, day: 1, write: true, out: dir, log: quiet });
  assert.match(sim.report, /^# DateWise chat-v7 AI test: SIMULATED\n/);
  const simPacket = JSON.parse(readFileSync(sim.reportPath.replace(/\.md$/, '') + '.grader.json', 'utf8'));
  assert.equal(simPacket.label, 'SIMULATED');
  assert.equal(simPacket.gradable, false);
});
