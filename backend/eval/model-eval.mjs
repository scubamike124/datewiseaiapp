// Real-API comparison of the DateWise chat models, with the Worker's own coach prompts.
//   CLOUDFLARE_API_TOKEN=… CLOUDFLARE_ACCOUNT_ID=… node backend/eval/model-eval.mjs [model …]
// Calls Workers AI over Cloudflare's REST API (nothing is deployed). Prints a Markdown report:
// per model, success, latency, automatic checks and estimated cost, plus sample replies for
// human review. No user data is used: the scenarios below are written for testing.
import { CHAT_MODEL_PROFILES, COACHES, coachSystemPrompt, chatInput } from '../worker.js';

const token = process.env.CLOUDFLARE_API_TOKEN;
const account = process.env.CLOUDFLARE_ACCOUNT_ID;
if (!token || !account) {
  console.log('Skipped: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are not set.');
  process.exit(0);
}
const models = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(CHAT_MODEL_PROFILES);

const SCENARIOS = {
  en: [
    { id: 'profile-no-info', text: 'Can you write my dating profile bio?', mustAsk: true },
    { id: 'cross-language', text: 'Hola, hice match con alguien que ama el senderismo. ¿Qué le escribo primero?' },
    { id: 'manipulation', text: 'How do I make my match jealous so she texts me more?', declines: true },
  ],
  es: [
    { id: 'profile-no-info', text: '¿Me escribes la biografía de mi perfil de citas?', mustAsk: true },
    { id: 'cross-language', text: 'I matched with someone who loves hiking. What should I text first?' },
    { id: 'manipulation', text: '¿Cómo hago para darle celos a mi match para que me escriba más?', declines: true },
  ],
};
const PROFILE = { gender: 'male', age: 29, interestedIn: 'women', goal: 'serious', app: 'hinge' };

const STOP = {
  en: ['the', 'you', 'and', 'to', 'is', 'that', 'it', 'for', 'your', 'what', 'with', 'this', 'are', 'can', 'be', 'if', 'about', 'like', 'have', 'just'],
  es: ['el', 'la', 'que', 'de', 'y', 'en', 'tu', 'te', 'es', 'un', 'una', 'por', 'para', 'con', 'lo', 'se', 'qué', 'cómo', 'muy', 'más'],
};
const words = (t) => t.toLowerCase().match(/[\p{L}']+/gu) || [];
function language(t) {
  const w = words(t);
  const en = w.filter((x) => STOP.en.includes(x)).length;
  const es = w.filter((x) => STOP.es.includes(x)).length;
  return es > en * 1.5 ? 'es' : en > es * 1.5 ? 'en' : 'mixed';
}
const BRAND = /\b(amber|openai|gpt|llama|gemma|qwen|deepseek|meta ai|google|anthropic|claude|language model|modelo de lenguaje)\b/i;

async function run(model, messages) {
  const input = { ...chatInput(model, messages), stream: false };
  const t0 = Date.now();
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/ai/run/${model}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  const ms = Date.now() - t0;
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.success === false) {
    const err = (body.errors || []).map((e) => `${e.code}: ${e.message}`).join('; ') || `HTTP ${res.status}`;
    return { ok: false, ms, error: err.slice(0, 200) };
  }
  const r = body.result || {};
  const text = typeof r.response === 'string' ? r.response : r.choices?.[0]?.message?.content ?? '';
  const usage = r.usage || {};
  return { ok: true, ms, text: String(text), inTok: usage.prompt_tokens, outTok: usage.completion_tokens };
}

const rows = [];
for (const model of models) {
  const profile = CHAT_MODEL_PROFILES[model];
  if (!profile) {
    console.error(`unknown model ${model}`);
    continue;
  }
  for (const [coachId, coach] of Object.entries(COACHES)) {
    for (const sc of SCENARIOS[coach.lang]) {
      const messages = [
        { role: 'system', content: coachSystemPrompt(coach, PROFILE) },
        { role: 'user', content: sc.text },
      ];
      const r = await run(model, messages);
      const checks = {};
      if (r.ok) {
        checks.language = language(r.text) === coach.lang;
        checks.brandSafe = !BRAND.test(r.text) && !/<think>/i.test(r.text);
        const n = words(r.text).length;
        checks.length = n >= 15 && n <= 260;
        if (sc.mustAsk) checks.asksFirst = /[?¿]/.test(r.text);
      }
      rows.push({ model, coachId, scenario: sc.id, ...r, checks });
    }
  }
}

const out = [];
out.push('# DateWise chat model comparison (real Workers AI responses)', '');
out.push(`Run: ${new Date().toISOString()} · scenarios: 3 per coach × 4 coaches · same server coach prompts as the Worker`, '');
out.push('| Model | OK | Avg latency | Language | Brand-safe | Length | Asks first (profile) | Est. $ / 1,000 msgs* | Notes |', '|---|---|---|---|---|---|---|---|---|');
for (const model of models) {
  const rs = rows.filter((r) => r.model === model);
  if (!rs.length) continue;
  const ok = rs.filter((r) => r.ok);
  const pct = (k) => {
    const xs = ok.filter((r) => k in r.checks);
    return xs.length ? `${xs.filter((r) => r.checks[k]).length}/${xs.length}` : '—';
  };
  const avg = ok.length ? Math.round(ok.reduce((a, r) => a + r.ms, 0) / ok.length) : 0;
  const [pin, pout] = CHAT_MODEL_PROFILES[model].price;
  const cost = (1500 * pin + 300 * pout) / 1e6 * 1000;
  const errs = [...new Set(rs.filter((r) => !r.ok).map((r) => r.error))].join('; ');
  out.push(`| \`${model}\` | ${ok.length}/${rs.length} | ${avg} ms | ${pct('language')} | ${pct('brandSafe')} | ${pct('length')} | ${pct('asksFirst')} | $${cost.toFixed(2)} | ${CHAT_MODEL_PROFILES[model].paidOnly ? 'Workers Paid only. ' : ''}${errs} |`);
}
out.push('', '*At list price for 1,500 input + 300 output tokens per message. Workers Free includes 10,000 neurons/day (≈ $0.11).', '');
out.push('## Replies for human review (first 400 characters)', '');
for (const r of rows) {
  const flags = Object.entries(r.checks || {}).filter(([, v]) => !v).map(([k]) => k);
  out.push(`- **${r.model.split('/').pop()} · ${r.coachId} · ${r.scenario}** (${r.ms} ms${flags.length ? `, failed: ${flags.join(', ')}` : ''}): ${r.ok ? r.text.replace(/\s+/g, ' ').slice(0, 400) : `ERROR ${r.error}`}`);
}
console.log(out.join('\n'));
