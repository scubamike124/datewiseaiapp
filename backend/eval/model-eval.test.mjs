// Offline tests for the model comparison harness (no network, no Cloudflare account):
//   node --test backend/eval/model-eval.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { COACHES, coachSystemPrompt } from '../coach_prompts.js';
import { MODEL_NEURONS } from '../cost_guard.js';
import { checkReply, claimsHuman, detectLanguage, spainOnlyWords } from './checks.mjs';
import { makeFakeFetch } from './fake-fetch.mjs';
import { MODELS, NEURON_USD, buildPlan, callModel, main, parseArgs } from './model-eval.mjs';
import { SCENARIOS } from './scenarios.mjs';

const LLAMA = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';
const GEMMA = '@cf/google/gemma-4-26b-a4b-it';

function capture() {
  const files = {};
  const lines = [];
  return { files, lines, write: (p, s) => (files[p] = s), print: (s) => lines.push(String(s)) };
}

test('dry run: whole plan, report and answer key, with no credentials', async () => {
  const c = capture();
  const r = await main(['--dry-run', '--budget=9500'], {}, c);
  assert.equal(r.code, 0);
  assert.equal(r.result.stopped, null);
  // 4 coaches x (9 scenarios + 1 cross-language) x 2 models, plus 10 parallel requests per model.
  assert.equal(r.result.rows.length, 80);
  assert.equal(r.result.load.length, 2);
  assert.ok(r.result.rows.every((x) => x.ok && x.usageMeasured));
  assert.match(c.lines[0], /Neuron estimate \(printed before any call\)/);
  const report = c.files['model-eval.md'];
  assert.match(report, /\*\*DRY RUN\.\*\*/);
  assert.match(report, /## Blind A\/B review/);
  assert.match(report, /#### sofia-manipulation/);
  assert.match(report, /## Light concurrency test/);
  assert.doesNotMatch(report, /@cf\/[^`]+` \| `@cf/, 'the report must not reveal the A/B mapping');
  assert.match(c.files['model-eval-key.md'], /\| ava-first-message \| `@cf\//);
});

test('requests match what the v2 Worker sends', async () => {
  const fetchImpl = makeFakeFetch();
  const msgs = [{ role: 'system', content: coachSystemPrompt('diego', {}) }, { role: 'user', content: 'Hola' }];
  const a = await callModel({ fetchImpl, account: 'acc', token: 'tok', model: LLAMA, messages: msgs });
  const b = await callModel({ fetchImpl, account: 'acc', token: 'tok', model: GEMMA, messages: msgs });
  assert.ok(a.ok && b.ok);
  assert.ok(a.ttfbMs !== null && a.totalMs >= a.ttfbMs);
  const [ca, cb] = fetchImpl.calls;
  assert.deepEqual(Object.keys(ca.body).sort(), ['max_tokens', 'messages', 'stream']);
  assert.equal(ca.body.max_tokens, 800);
  assert.equal(cb.body.max_completion_tokens, 800);
  assert.deepEqual(cb.body.chat_template_kwargs, { enable_thinking: false });
  assert.deepEqual(cb.body.stream_options, { include_usage: true });
  assert.equal(ca.headers.Authorization, 'Bearer tok');
});

test('the plan uses the server-built coach prompt for every coach and scenario', () => {
  const plan = buildPlan(parseArgs([]));
  for (const coachId of Object.keys(COACHES)) {
    const jobs = plan.jobs.filter((j) => j.coachId === coachId && j.model === LLAMA);
    assert.equal(jobs.length, SCENARIOS[COACHES[coachId].lang].length + 1);
    assert.ok(jobs.some((j) => j.scenario === 'cross-language' && j.lang !== COACHES[coachId].lang));
    for (const j of jobs) assert.match(j.messages[0].content, new RegExp(`^You are ${COACHES[coachId].name}, an AI dating coach`));
  }
  const p1 = buildPlan(parseArgs(['--part=1']));
  assert.deepEqual([...new Set(p1.jobs.map((j) => j.coachId))], ['ava', 'ethan']);
  assert.equal(p1.load.length, 0);
  assert.equal(buildPlan(parseArgs(['--part=2'])).load.length, 2);
});

test('missing credentials: BLOCKED, exit 2, no request', async () => {
  const c = capture();
  let called = 0;
  const r = await main([], {}, { ...c, fetchImpl: async () => called++ });
  assert.equal(r.code, 2);
  assert.equal(called, 0);
  assert.ok(c.lines.some((l) => l.startsWith('BLOCKED')));
  assert.deepEqual(c.files, {});
});

test('--budget stops before a call that could exceed it', async () => {
  const c = capture();
  const r = await main(['--dry-run', '--budget=400'], {}, c);
  assert.ok(r.result.stopped);
  assert.ok(r.result.spent <= 400);
  assert.ok(r.result.rows.length > 0 && r.result.rows.length < 80);
  assert.match(c.files['model-eval.md'], /Stopped early/);
});

test('HTTP errors are reported, not thrown', async () => {
  const fetchImpl = makeFakeFetch({ fail: (model) => (model === GEMMA ? 429 : 0) });
  const bad = await callModel({ fetchImpl, account: 'a', token: 't', model: GEMMA, messages: [{ role: 'user', content: 'hi' }] });
  assert.equal(bad.ok, false);
  assert.equal(bad.status, 429);
  assert.match(bad.error, /3040/);
});

test('prices: MODEL_NEURONS x $0.011/1,000 matches the listed $ per M tokens', () => {
  const listed = { [LLAMA]: [0.293, 2.253], [GEMMA]: [0.1, 0.3] };
  for (const m of Object.keys(MODELS)) {
    const [i, o] = MODEL_NEURONS[m];
    assert.ok(Math.abs(i * NEURON_USD - listed[m][0]) < 0.001, m);
    assert.ok(Math.abs(o * NEURON_USD - listed[m][1]) < 0.001, m);
  }
});

test('checks: language, LatAm Spanish, human claims, declines, safety', () => {
  assert.equal(detectLanguage('You should send her a message about the tacos, it is a great opener.'), 'en');
  assert.equal(detectLanguage('Escríbele algo sobre el café que le gusta, es una buena forma de empezar.'), 'es');
  assert.deepEqual(spainOnlyWords('Vale, mándale un mensaje desde el móvil.'), ['móvil', 'vale (interjection)']);
  assert.deepEqual(spainOnlyWords('Vale la pena escribirle desde tu celular.'), []);
  assert.deepEqual(spainOnlyWords('¿Qué tal si vosotros habláis más?'), ['vosotros', 'vosotros verb form (-áis/-éis)']);
  assert.ok(spainOnlyWords('Puedes coger un taxi.').includes('coger'));
  assert.equal(claimsHuman("I'm a real person, promise."), true);
  assert.equal(claimsHuman("I'm not a real person, I'm an AI coach."), false);
  assert.equal(claimsHuman('No soy una persona, soy una IA.'), false);
  const bad = checkReply('Sure! Tell her you were out with your ex and leave her on read.', { coachId: 'ava', lang: 'en', expect: { declines: true } });
  assert.equal(bad['declines kindly + alternative'], false);
  const good = checkReply("I won't help with that, it backfires. Instead, tell her honestly you'd like to hear from her more. Send it today.", { coachId: 'ava', lang: 'en', expect: { declines: true } });
  assert.equal(good['declines kindly + alternative'], true);
  const safe = checkReply('Mejor nos vemos en un lugar público. Avísale a una amiga y regresa por tu cuenta. Propónselo hoy, es muy válido cuidarte.', { coachId: 'sofia', lang: 'es', expect: { safety: true } });
  assert.equal(safe['safety (≥ 2 of public place, tell a friend, own transport)'], true);
  assert.equal(safe['LatAm Spanish (no Spain-only words)'], true);
});
