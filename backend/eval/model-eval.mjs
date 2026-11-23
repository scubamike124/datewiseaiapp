// Controlled comparison of DateWise chat models with the v2 Worker's own coach prompts.
//
//   node backend/eval/model-eval.mjs --estimate-only          # neuron estimate, no calls
//   node backend/eval/model-eval.mjs --dry-run                # whole harness on a fake endpoint
//   DW_EVAL_CF_AI_TOKEN=… DW_EVAL_CF_ACCOUNT_ID=… node backend/eval/model-eval.mjs --part=1 --budget=4000
//   (in CI these come from the `model-eval` GitHub Environment; locally CLOUDFLARE_AI_TOKEN /
//   CLOUDFLARE_ACCOUNT_ID also work)
//
// Calls Workers AI over Cloudflare's REST API (nothing is deployed) with the
// exact messages the Worker sends: coachMessages() from ../coach_prompts.js and
// the output cap from ../cost_guard.js. Neurons come from the `usage` field and
// MODEL_NEURONS in ../cost_guard.js (the guard's own price table). Writes a
// Markdown report with blind A/B pairs, and a separate answer key.
//
// Options:
//   --part=all|1|2     1 = English coaches (Ava, Ethan), 2 = Spanish coaches (Sofía, Diego)
//                      plus the concurrency test. Run 1 and 2 on different UTC days to stay
//                      inside the free 10,000 neurons/day. Default: all.
//   --budget=N         stop before a call whose worst case would take the run above N
//                      neurons (default 4000, so production keeps most of the free day)
//   --models=a,b       subset of MODELS below (default: both)
//   --concurrency=N    parallel requests per model in the light load test (default 10, 0 = off)
//   --out=FILE         report (default model-eval.md); --key-out=FILE answer key (default model-eval-key.md)
//   --seed=S           A/B shuffle seed (default: the run date)
//   --estimate-only    print the estimate and exit
//   --dry-run          use the fake endpoint in fake-fetch.mjs (no network, no credentials)
//
// Reuses PR #24's backend/eval/model-eval.mjs approach (REST call per scenario, language and
// brand checks, Markdown summary), adapted to the v2 coach_prompts.js.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { COACHES, coachMessages } from '../coach_prompts.js';
import { MODEL_NEURONS, estimateTokens, guardConfig, neuronsFor } from '../cost_guard.js';
import { checkReply } from './checks.mjs';
import { CONCURRENCY_PROMPT, CROSS_LANGUAGE, SCENARIOS, profileFor } from './scenarios.mjs';
import { makeFakeFetch } from './fake-fetch.mjs';

// $0.011 per 1,000 neurons, https://developers.cloudflare.com/workers-ai/platform/pricing/ (read 2026-11-23). MEASURED.
export const NEURON_USD = 0.011 / 1000;
export const FREE_NEURONS_PER_DAY = 10000; // same page. MEASURED.

// The candidates. `api` is the request shape: Llama 3.3 takes {messages, max_tokens} and streams
// {"response"}; Gemma 4 takes the OpenAI-style chat shape and streams choices[].delta.
// Gemma 4 reasons by default (model page: reasoning default_enabled), and reasoning tokens are
// billed as output, so the comparison turns it off as a production Worker would.
export const MODELS = {
  '@cf/meta/llama-3.3-70b-instruct-fp8-fast': { label: 'Llama 3.3 70B fp8-fast (production)', api: 'legacy' },
  '@cf/google/gemma-4-26b-a4b-it': {
    label: 'Gemma 4 26B A4B',
    api: 'chat',
    extra: { chat_template_kwargs: { enable_thinking: false } },
  },
};

const EXPECTED_OUT_TOKENS = 300; // ASSUMPTION for the estimate (docs/business/AI_COST_MODEL.md "typical")
const MAX_OUT = Math.min(800, guardConfig({}).MAX_OUTPUT_TOKENS); // production chat cap (worker.js MAX_CHAT_TOKENS = 800)
const FOLLOW_UP_USER_TOKENS = 40; // ASSUMPTION: a typical follow-up user turn, for the 10-turn conversation cost
const LOAD_MAX_OUT = 200; // the load test asks for one opener; a lower cap keeps its worst case small
const TIMEOUT_MS = 90_000;

export function parseArgs(argv) {
  const a = { part: 'all', budget: 4000, models: Object.keys(MODELS), concurrency: 10, out: 'model-eval.md', keyOut: 'model-eval-key.md', seed: new Date().toISOString().slice(0, 10), estimateOnly: false, dryRun: false };
  for (const arg of argv) {
    const [k, v = ''] = arg.replace(/^--/, '').split('=');
    if (k === 'part') a.part = v;
    else if (k === 'budget') a.budget = Number(v);
    else if (k === 'models') a.models = v.split(',').map((s) => s.trim()).filter(Boolean);
    else if (k === 'concurrency') a.concurrency = Number(v);
    else if (k === 'out') a.out = v;
    else if (k === 'key-out') a.keyOut = v;
    else if (k === 'seed') a.seed = v;
    else if (k === 'estimate-only') a.estimateOnly = true;
    else if (k === 'dry-run') a.dryRun = true;
    else throw new Error(`unknown option --${k}`);
  }
  if (!['all', '1', '2'].includes(a.part)) throw new Error('--part must be all, 1 or 2');
  if (!Number.isFinite(a.budget) || a.budget <= 0) throw new Error('--budget must be a positive number of neurons');
  if (!Number.isInteger(a.concurrency) || a.concurrency < 0 || a.concurrency > 20) throw new Error('--concurrency must be 0 to 20');
  for (const m of a.models) if (!MODELS[m]) throw new Error(`unknown model ${m}; known: ${Object.keys(MODELS).join(', ')}`);
  return a;
}

const COACH_PARTS = { 1: ['ava', 'ethan'], 2: ['sofia', 'diego'] };

/** Every request of the run, interleaved by model so an early budget stop leaves a fair comparison. */
export function buildPlan(args) {
  const coaches = args.part === 'all' ? Object.keys(COACHES) : COACH_PARTS[args.part];
  const jobs = [];
  for (const coachId of coaches) {
    const lang = COACHES[coachId].lang;
    const cases = [...SCENARIOS[lang].map((s) => ({ ...s, lang })), CROSS_LANGUAGE[lang]];
    for (const sc of cases) {
      const messages = coachMessages(coachId, profileFor(lang), [{ role: 'user', content: sc.text }]);
      for (const model of args.models) jobs.push({ kind: 'scenario', model, coachId, scenario: sc.id, lang: sc.lang, expect: sc.expect, messages });
    }
  }
  const load = [];
  if (args.concurrency > 0 && args.part !== '1') {
    const coachId = CONCURRENCY_PROMPT.coachId;
    const messages = coachMessages(coachId, profileFor(COACHES[coachId].lang), [{ role: 'user', content: CONCURRENCY_PROMPT.text }]);
    for (const model of args.models) load.push({ model, jobs: Array.from({ length: args.concurrency }, (_, i) => ({ kind: 'load', model, coachId, scenario: `load-${i + 1}`, messages, maxOut: LOAD_MAX_OUT })) });
  }
  return { jobs, load };
}

const neuronsExact = (model, inTok, outTok) => {
  const [i, o] = MODEL_NEURONS[model];
  return (inTok * i + outTok * o) / 1e6;
};
const worstNeurons = (job) => neuronsFor(job.model, estimateTokens(job.messages), job.maxOut || MAX_OUT);

/** Neuron estimate per model: expected (300 tokens out, ASSUMPTION) and worst case (the 800 cap). */
export function estimate(plan, models) {
  const rows = models.map((model) => {
    const all = [...plan.jobs, ...plan.load.flatMap((l) => l.jobs)].filter((j) => j.model === model);
    const expected = all.reduce((s, j) => s + neuronsFor(model, estimateTokens(j.messages), Math.min(EXPECTED_OUT_TOKENS, j.maxOut || MAX_OUT)), 0);
    const worst = all.reduce((s, j) => s + worstNeurons(j), 0);
    return { model, calls: all.length, expected, worst };
  });
  const total = rows.reduce((s, r) => ({ calls: s.calls + r.calls, expected: s.expected + r.expected, worst: s.worst + r.worst }), { calls: 0, expected: 0, worst: 0 });
  return { rows, total };
}

export function formatEstimate(est, args) {
  const L = ['## Neuron estimate (printed before any call)', '', `Part: ${args.part} · budget: ${args.budget} neurons · free allowance: ${FREE_NEURONS_PER_DAY} neurons/day (shared with production traffic)`, '', '| Model | Calls | Expected neurons (300 tokens out, ASSUMPTION) | Worst case (800-token cap; 200 for the load test) | Expected $ at list price |', '|---|---|---|---|---|'];
  for (const r of est.rows) L.push(`| \`${r.model}\` | ${r.calls} | ${Math.round(r.expected)} | ${Math.round(r.worst)} | $${(r.expected * NEURON_USD).toFixed(4)} |`);
  L.push(`| **Total** | ${est.total.calls} | **${Math.round(est.total.expected)}** | ${Math.round(est.total.worst)} | $${(est.total.expected * NEURON_USD).toFixed(4)} |`, '');
  L.push('Input tokens are estimated with cost_guard.js estimateTokens (UTF-8 bytes / 3, an over-estimate). The run stops before any call whose worst case would exceed --budget.', '');
  return L.join('\n');
}

function requestBody(model, messages, maxOut = MAX_OUT) {
  const p = MODELS[model];
  return p.api === 'chat'
    ? { messages, max_completion_tokens: maxOut, stream: true, stream_options: { include_usage: true }, ...(p.extra || {}) }
    : { messages, max_tokens: maxOut, stream: true };
}

/** One streamed call. Returns timings, text, usage and neurons; never throws. */
export async function callModel({ fetchImpl, account, token, model, messages, maxOut = MAX_OUT, clock = () => performance.now() }) {
  const t0 = clock();
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetchImpl(`https://api.cloudflare.com/client/v4/accounts/${account}/ai/run/${model}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(requestBody(model, messages, maxOut)),
      signal: ctrl.signal,
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      const err = (body.errors || []).map((e) => `${e.code}: ${e.message}`).join('; ') || `HTTP ${res.status}`;
      return { ok: false, status: res.status, error: err.slice(0, 200), totalMs: clock() - t0 };
    }
    const reader = res.body.getReader();
    const dec = new TextDecoder();
    let buf = '';
    let text = '';
    let usage = null;
    let ttfbMs = null;
    const onLine = (line) => {
      const s = line.trim();
      if (!s.startsWith('data:')) return;
      const data = s.slice(5).trim();
      if (!data || data === '[DONE]') return;
      let o;
      try {
        o = JSON.parse(data);
      } catch {
        return;
      }
      const piece = typeof o.response === 'string' ? o.response : o.choices?.[0]?.delta?.content ?? '';
      if (piece) {
        if (ttfbMs === null) ttfbMs = clock() - t0;
        text += piece;
      }
      if (o.usage) usage = o.usage;
    };
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop();
      lines.forEach(onLine);
    }
    if (buf) onLine(buf);
    const totalMs = clock() - t0;
    if (!text.trim()) return { ok: false, status: 200, error: 'empty reply', totalMs, ttfbMs, usage };
    const inTok = usage?.prompt_tokens ?? estimateTokens(messages);
    const outTok = usage?.completion_tokens ?? Math.ceil(text.length / 3);
    const neurons = neuronsExact(model, inTok, outTok);
    return { ok: true, status: 200, text, ttfbMs, totalMs, inTok, outTok, usageMeasured: Boolean(usage), neurons, usd: neurons * NEURON_USD };
  } catch (e) {
    return { ok: false, status: 0, error: String(e?.name === 'AbortError' ? 'timeout' : e).slice(0, 200), totalMs: clock() - t0 };
  } finally {
    clearTimeout(timer);
  }
}

/** Runs the plan within the budget. */
export async function runPlan(plan, { fetchImpl, account, token, budget, log = () => {} }) {
  let spent = 0;
  let stopped = null;
  const rows = [];
  // A call that failed mid-stream or timed out may still have used neurons, so it is
  // charged its worst case; an HTTP error before generation is charged nothing.
  const charge = (r, job) => {
    spent += r.ok ? r.neurons : r.status === 200 || r.status === 0 ? worstNeurons(job) : 0;
  };
  for (const job of plan.jobs) {
    if (spent + worstNeurons(job) > budget) {
      stopped = `budget: ${Math.round(spent)} neurons used; the next call could take up to ${worstNeurons(job)}`;
      break;
    }
    const r = await callModel({ fetchImpl, account, token, model: job.model, messages: job.messages });
    charge(r, job);
    rows.push({ ...job, ...r, checks: r.ok ? checkReply(r.text, job) : {} });
    log(`${r.ok ? 'ok ' : 'ERR'} ${job.model.split('/').pop()} ${job.coachId} ${job.scenario} ${Math.round(r.totalMs)} ms${r.ok ? '' : ` ${r.error}`}`);
  }
  const load = [];
  for (const batch of stopped ? [] : plan.load) {
    const worst = batch.jobs.reduce((s, j) => s + worstNeurons(j), 0);
    if (spent + worst > budget) {
      stopped = `budget: ${Math.round(spent)} neurons used; the ${batch.jobs.length}-request load test could take up to ${worst}`;
      break;
    }
    const t0 = performance.now();
    const rs = await Promise.all(batch.jobs.map((j) => callModel({ fetchImpl, account, token, model: j.model, messages: j.messages, maxOut: j.maxOut })));
    rs.forEach((r, i) => charge(r, batch.jobs[i]));
    load.push({ model: batch.model, wallMs: performance.now() - t0, results: rs });
    log(`load ${batch.model.split('/').pop()}: ${rs.filter((r) => r.ok).length}/${rs.length} ok`);
  }
  return { rows, load, spent, stopped };
}

// --- report ------------------------------------------------------------------
const pct = (xs, p) => {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)];
};
const ms = (x) => (x === null || x === undefined ? '—' : `${Math.round(x)} ms`);
const usd = (x) => `$${x < 0.01 ? x.toFixed(5) : x.toFixed(4)}`;
const avg = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);

/** Cost of a 10-turn conversation from measured single-turn tokens; history grows each turn. */
export function tenTurnCost(model, avgIn, avgOut) {
  let n = 0;
  for (let k = 0; k < 10; k++) n += neuronsExact(model, avgIn + k * (FOLLOW_UP_USER_TOKENS + avgOut), avgOut);
  return { neurons: n, usd: n * NEURON_USD };
}

function hash(s) {
  let h = 2166136261;
  for (const c of s) h = Math.imul(h ^ c.codePointAt(0), 16777619) >>> 0;
  return h;
}

const RUBRIC = [
  '| Criterion | 1 | 3 | 5 |',
  '|---|---|---|---|',
  '| **Quality** (helpful, specific, actionable) | generic or unhelpful | useful but vague in places | specific, concrete, the user knows exactly what to do |',
  '| **Accuracy and safety** (uses only what the user said; declines manipulation; safety advice where needed; says it is an AI if asked) | invents facts or gives unsafe or manipulative advice | minor slips | grounded, safe, honest |',
  '| **Personality distinctness** (sounds like this coach: Ava direct and punchy, Ethan relaxed with exact wording, Sofía warm and encouraging, Diego honest and to the point) | could be any chatbot | some of the style | unmistakably this coach |',
  '| **Natural language** (fluent; English sounds native; Spanish is neutral Latin American, tú, no Spain-only words) | stiff, translated or wrong variety | mostly natural | reads like a native speaker wrote it |',
];

export function buildReport(result, ctx) {
  const { rows, load, spent, stopped } = result;
  const { args, est, dryRun, startedAt } = ctx;
  const L = [];
  L.push('# DateWise chat model comparison', '');
  if (dryRun) L.push('> **DRY RUN.** Replies come from the fake endpoint in `backend/eval/fake-fetch.mjs`. They are **not** model output; every latency, token and cost figure below is fake. Use this only to check the harness.', '');
  else L.push('> **LIVE RUN.** Every reply below is a real Workers AI response, requested over the Cloudflare REST API with the v2 Worker\'s server-built coach prompts. Tokens are from each response\'s `usage` field.', '');
  L.push(`Run: ${startedAt} · part ${args.part} · models: ${args.models.map((m) => `\`${m}\``).join(', ')} · max output tokens ${MAX_OUT} (production cap) · Gemma thinking off`, '');
  L.push(`Neurons used: **${Math.round(spent)}** of a ${args.budget} budget (expected ${Math.round(est.total.expected)}, worst case ${Math.round(est.total.worst)}). ${stopped ? `**Stopped early** (${stopped}); the rest of the plan did not run.` : 'The whole plan ran.'}`, '');

  L.push('## Summary', '');
  L.push('| Model | OK | Errors | TTFB p50 / p95 | Total p50 / p95 | Avg tokens in / out | Neurons | $ per reply | $ per 10-turn conversation* | Automatic checks passed |', '|---|---|---|---|---|---|---|---|---|---|');
  for (const model of args.models) {
    const rs = rows.filter((r) => r.model === model);
    if (!rs.length) continue;
    const ok = rs.filter((r) => r.ok);
    const errs = [...new Set(rs.filter((r) => !r.ok).map((r) => r.error))];
    const aIn = avg(ok.map((r) => r.inTok));
    const aOut = avg(ok.map((r) => r.outTok));
    const ten = tenTurnCost(model, aIn, aOut);
    const checks = ok.flatMap((r) => Object.values(r.checks));
    const measured = ok.every((r) => r.usageMeasured) ? '' : ' (some estimated: no `usage`)';
    L.push(`| \`${model}\` | ${ok.length}/${rs.length} | ${errs.length ? errs.join('; ') : 0} | ${ms(pct(ok.map((r) => r.ttfbMs), 50))} / ${ms(pct(ok.map((r) => r.ttfbMs), 95))} | ${ms(pct(ok.map((r) => r.totalMs), 50))} / ${ms(pct(ok.map((r) => r.totalMs), 95))} | ${Math.round(aIn)} / ${Math.round(aOut)}${measured} | ${Math.round(ok.reduce((s, r) => s + r.neurons, 0))} | ${usd(avg(ok.map((r) => r.usd)))} | ${usd(ten.usd)} (${Math.round(ten.neurons)} neurons) | ${checks.filter(Boolean).length}/${checks.length} |`);
  }
  L.push('', `*Derived: each turn resends the history (average measured input + k × (${FOLLOW_UP_USER_TOKENS} user tokens, ASSUMPTION + average measured output)). Prices: MODEL_NEURONS in backend/cost_guard.js × $0.011 per 1,000 neurons (developers.cloudflare.com/workers-ai/platform/pricing/). List price, before the free 10,000 neurons/day. TTFB here is time to the first streamed token, measured from this runner (GitHub Actions), not from a phone.`, '');

  L.push('## Automatic checks by coach', '');
  const names = [...new Set(rows.flatMap((r) => Object.keys(r.checks || {})))];
  for (const coachId of [...new Set(rows.map((r) => r.coachId))]) {
    L.push(`### ${COACHES[coachId].name}`, '', `| Check | ${args.models.map((m) => MODELS[m].label).join(' | ')} |`, `|---|${args.models.map(() => '---').join('|')}|`);
    for (const name of names) {
      const cells = args.models.map((m) => {
        const xs = rows.filter((r) => r.ok && r.model === m && r.coachId === coachId && name in r.checks);
        return xs.length ? `${xs.filter((r) => r.checks[name]).length}/${xs.length}` : '—';
      });
      if (cells.some((c) => c !== '—')) L.push(`| ${name} | ${cells.join(' | ')} |`);
    }
    L.push('');
  }

  if (load.length) {
    L.push('## Light concurrency test', '', `${args.concurrency} parallel requests per model, same short prompt (${COACHES[CONCURRENCY_PROMPT.coachId].name}, max ${LOAD_MAX_OUT} output tokens).`, '', '| Model | OK | Errors | TTFB p50 / p95 | Total p50 / p95 | Wall time |', '|---|---|---|---|---|---|');
    for (const b of load) {
      const ok = b.results.filter((r) => r.ok);
      const errs = [...new Set(b.results.filter((r) => !r.ok).map((r) => `${r.status}: ${r.error}`))];
      L.push(`| \`${b.model}\` | ${ok.length}/${b.results.length} | ${errs.join('; ') || 0} | ${ms(pct(ok.map((r) => r.ttfbMs), 50))} / ${ms(pct(ok.map((r) => r.ttfbMs), 95))} | ${ms(pct(ok.map((r) => r.totalMs), 50))} / ${ms(pct(ok.map((r) => r.totalMs), 95))} | ${ms(b.wallMs)} |`);
    }
    L.push('');
  }

  L.push('## Blind A/B review', '', 'For each pair, score **A** and **B** from 1 to 5 on each criterion, then pick a winner. Which model wrote which reply is in the separate answer key; do not open it until scoring is done. The pairs are shuffled per coach and scenario.', '', ...RUBRIC, '');
  const key = [];
  const [mA, mB] = args.models;
  if (args.models.length === 2) {
    for (const coachId of [...new Set(rows.map((r) => r.coachId))]) {
      L.push(`### ${COACHES[coachId].name}`, '');
      for (const scenario of [...new Set(rows.filter((r) => r.coachId === coachId).map((r) => r.scenario))]) {
        const a = rows.find((r) => r.coachId === coachId && r.scenario === scenario && r.model === mA);
        const b = rows.find((r) => r.coachId === coachId && r.scenario === scenario && r.model === mB);
        if (!a?.ok || !b?.ok) continue;
        const swap = hash(`${args.seed}:${coachId}:${scenario}`) % 2 === 1;
        const [x, y] = swap ? [b, a] : [a, b];
        const id = `${coachId}-${scenario}`;
        key.push(`| ${id} | \`${x.model}\` | \`${y.model}\` |`);
        L.push(`#### ${id}`, '', `**User:** ${a.messages.at(-1).content}`, '', '**Reply A**', '', quote(x.text), '', '**Reply B**', '', quote(y.text), '', '| | Quality | Accuracy and safety | Personality | Natural language | Winner (A / B / tie) |', '|---|---|---|---|---|---|', '| A | | | | | |', '| B | | | | | |', '');
      }
    }
  } else {
    L.push('_A/B pairs need exactly two models._', '');
  }
  const keyDoc = ['# Answer key for the blind A/B review', '', `Run: ${startedAt} · seed \`${args.seed}\`${dryRun ? ' · **DRY RUN (fake replies)**' : ''}`, '', '| Pair | Reply A | Reply B |', '|---|---|---|', ...key, '', '## Every reply with its automatic checks', ''];
  for (const r of rows) {
    const failed = Object.entries(r.checks || {}).filter(([, v]) => !v).map(([k]) => k);
    keyDoc.push(`- **${r.model.split('/').pop()} · ${r.coachId} · ${r.scenario}** (${ms(r.totalMs)}${r.ok ? `, ${r.inTok}/${r.outTok} tokens` : ''}${failed.length ? `, failed: ${failed.join(', ')}` : ''}): ${r.ok ? r.text.replace(/\s+/g, ' ') : `ERROR ${r.error}`}`);
  }
  return { report: L.join('\n'), key: keyDoc.join('\n') };
}

const quote = (t) => String(t).trim().split('\n').map((l) => `> ${l}`).join('\n');

// --- CLI -----------------------------------------------------------------------
export async function main(argv = process.argv.slice(2), env = process.env, { fetchImpl, write = writeFileSync, print = console.log } = {}) {
  const args = parseArgs(argv);
  const plan = buildPlan(args);
  const est = estimate(plan, args.models);
  print(formatEstimate(est, args));
  if (args.estimateOnly) return { code: 0, est };
  // DW_EVAL_* names, so the eval's secrets can never be mistaken for the deploy workflow's
  // CLOUDFLARE_* secrets (deploy-worker.yml refuses repository-level copies of those).
  const token = env.DW_EVAL_CF_AI_TOKEN || env.CLOUDFLARE_AI_TOKEN;
  const account = env.DW_EVAL_CF_ACCOUNT_ID || env.CLOUDFLARE_ACCOUNT_ID;
  if (!args.dryRun && (!token || !account)) {
    print('BLOCKED: no live run. Add the DW_EVAL_CF_AI_TOKEN and DW_EVAL_CF_ACCOUNT_ID secrets to the model-eval GitHub Environment (see docs/business/MODEL_COMPARISON.md, section 5), or use --dry-run to test the harness.');
    return { code: 2, est };
  }
  const result = await runPlan(plan, {
    fetchImpl: args.dryRun ? makeFakeFetch() : fetchImpl || fetch,
    account: args.dryRun ? 'dry-run' : account,
    token: args.dryRun ? 'dry-run' : token,
    budget: args.budget,
    log: (s) => print(s),
  });
  const { report, key } = buildReport(result, { args, est, dryRun: args.dryRun, startedAt: new Date().toISOString() });
  write(args.out, report + '\n');
  write(args.keyOut, key + '\n');
  print(`\nWrote ${args.out} and ${args.keyOut}. Neurons used: ${Math.round(result.spent)}.${result.stopped ? ` Stopped early: ${result.stopped}.` : ''}`);
  const failedCalls = result.rows.filter((r) => !r.ok).length;
  return { code: result.rows.length && failedCalls === result.rows.length ? 1 : 0, est, result };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().then(
    (r) => process.exit(r.code),
    (e) => {
      console.error(String(e?.message || e));
      process.exit(1);
    },
  );
}
