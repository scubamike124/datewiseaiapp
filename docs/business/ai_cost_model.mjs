// Cost model calculator for docs/business/AI_COST_MODEL.md (prints markdown tables).
const NEURON_USD = 0.011 / 1000; // MEASURED
const FREE_NEURONS_DAY = 10000; // MEASURED
const M = {
  llama: { name: 'Llama 3.3 70B fp8-fast', inN: 26668, outN: 204805, inUsd: 0.293, outUsd: 2.253 },
  gemma: { name: 'Gemma 4 26B', inN: 9091, outN: 27273, inUsd: 0.1, outUsd: 0.3 },
};
const U = {
  light: { msgsMonth: 60, inTok: 1200, outTok: 250, desc: '3 msgs/day x 20 days' },
  typical: { msgsMonth: 250, inTok: 2000, outTok: 300, desc: '10 msgs/day x 25 days' },
  heavy: { msgsMonth: 1200, inTok: 3500, outTok: 400, desc: '40 msgs/day x 30 days' },
};
const SUBS = [100, 500, 1000, 5000];
const PRICES = [9.99, 14.99, 19.99, 24.99];
const CONFIGURED_PRICE = 19.99; // owner decision 2026-11-23: the only plan, datewise_premium_monthly
const COMMS = [0.15, 0.3];
const REFUND = 0.03; // ASSUMPTION
const APPLE_FEE_MONTH = 99 / 12; // MEASURED
const WORKERS_PAID = 5; // MEASURED
const DO_REQ_PER_MSG = 4; // MEASURED (code design)
const CPU_MS_PER_MSG = 5; // ASSUMPTION

const usdPerMsg = (m, u) => (u.inTok * m.inUsd + u.outTok * m.outUsd) / 1e6;
const neuronsPerMsg = (m, u) => (u.inTok * m.inN + u.outTok * m.outN) / 1e6;

function monthCosts(model, usage, subs) {
  const msgs = usage.msgsMonth * subs;
  const neurons = msgs * neuronsPerMsg(model, usage);
  const freeN = FREE_NEURONS_DAY * 30;
  const paidNeeded = neurons / 30 > FREE_NEURONS_DAY;
  const ai = Math.max(0, neurons - freeN) * NEURON_USD;
  const workerReq = msgs * 1.05; // +5% preflight/retries ASSUMPTION
  const doReq = msgs * DO_REQ_PER_MSG;
  const infraOver =
    Math.max(0, workerReq - 10e6) / 1e6 * 0.3 +
    Math.max(0, doReq - 1e6) / 1e6 * 0.15 +
    Math.max(0, msgs * CPU_MS_PER_MSG - 30e6) / 1e6 * 0.02;
  return { msgs, neurons, ai, paidNeeded, infra: (paidNeeded ? WORKERS_PAID : 0) + infraOver };
}

const f = (x) => (x < 0 ? '-$' + Math.abs(x).toFixed(2) : '$' + x.toFixed(2));
const out = [];
const p = (s = '') => out.push(s);

p('### Per-message and per-subscriber AI cost');
p('| Model | Usage | Tokens in/out per msg (ASSUMPTION) | Msgs/month (ASSUMPTION) | $/msg | Neurons/msg | AI $/subscriber/month (list price, before free allowance) |');
p('|---|---|---|---|---|---|---|');
for (const [mk, m] of Object.entries(M)) for (const [uk, u] of Object.entries(U)) {
  p(`| ${m.name} | ${uk} (${u.desc}) | ${u.inTok} / ${u.outTok} | ${u.msgsMonth} | $${usdPerMsg(m, u).toFixed(5)} | ${neuronsPerMsg(m, u).toFixed(1)} | ${f(usdPerMsg(m, u) * u.msgsMonth)} |`);
}
p();
for (const price of PRICES) {
  p(`#### $${price.toFixed(2)} / month${price === CONFIGURED_PRICE ? ' (configured price)' : ''}`);
  p('Monthly net profit = subscribers x price x (1 - commission) x (1 - 3% refunds) - AI (Llama 3.3, after the 10k neurons/day free allowance) - infrastructure (Workers Paid $5 when needed + overage) - Apple Developer Program $8.25. All results are derived from MEASURED prices and the ASSUMPTION usage profiles above.');
  p();
  p('| Subscribers | Usage | Net proceeds @15% | Net proceeds @30% | AI cost | Infra | Cost/customer | Profit @15% | Profit @30% | Margin @30% |');
  p('|---|---|---|---|---|---|---|---|---|---|');
  for (const s of SUBS) for (const [uk, u] of Object.entries(U)) {
    const c = monthCosts(M.llama, u, s);
    const n15 = s * price * 0.85 * (1 - REFUND);
    const n30 = s * price * 0.7 * (1 - REFUND);
    const cost = c.ai + c.infra + APPLE_FEE_MONTH;
    p(`| ${s} | ${uk} | ${f(n15)} | ${f(n30)} | ${f(c.ai)} | ${f(c.infra)} | $${(cost / s).toFixed(3)} | ${f(n15 - cost)} | ${f(n30 - cost)} | ${(((n30 - cost) / n30) * 100).toFixed(1)}% |`);
  }
  p();
}

p('### Break-even, affordable AI cost and allowances per price point');
p('| Price | Commission | Net per subscriber after refunds | Break-even subscribers (heavy usage, Workers Paid + Apple fee) | Max AI+infra per subscriber at 70% gross margin | Sustainable msgs/month at worst-case $0.00356/msg | Sustainable msgs/month at heavy $0.00193/msg with 1.5x safety | Voice-only equivalent, minutes/month (2 turns/min, ASSUMPTION) |');
p('|---|---|---|---|---|---|---|---|');
const WORST = (6000 * 0.293 + 800 * 2.253) / 1e6; // capped request
const HEAVY = usdPerMsg(M.llama, U.heavy);
for (const price of PRICES) for (const c of COMMS) {
  const net = price * (1 - c) * (1 - REFUND);
  const heavyCost = HEAVY * U.heavy.msgsMonth;
  const be = Math.ceil((WORKERS_PAID + APPLE_FEE_MONTH) / (net - heavyCost));
  const maxAi = net * 0.3;
  p(`| $${price.toFixed(2)} | ${c * 100}% | ${f(net)} | ${be} | ${f(maxAi)} | ${Math.floor(maxAi / WORST)} | ${Math.floor(maxAi / (HEAVY * 1.5))} | ${Math.floor(maxAi / WORST / 2)} to ${Math.floor(maxAi / (HEAVY * 1.5) / 2)} |`);
}
p();
p(`Worst-case capped message: $${WORST.toFixed(5)} (6,000 input + 800 output tokens). Heavy message: $${HEAVY.toFixed(5)}.`);
p();
p('### Capacity on the free allowance only (no Workers Paid)');
for (const m of Object.values(M)) for (const [uk, u] of Object.entries(U)) {
  p(`- ${m.name}, ${uk}: ${Math.floor(FREE_NEURONS_DAY / neuronsPerMsg(m, u))} msgs/day for the whole service, about ${Math.floor((FREE_NEURONS_DAY * 30) / neuronsPerMsg(m, u) / u.msgsMonth)} subscribers.`);
}
p();
p('### Worst-case exposure');
for (const [label, perMsg] of [['uncapped request (24k tokens in, 800 out)', (24000 * 0.293 + 800 * 2.253) / 1e6], ['capped request (6k in, 800 out)', WORST]]) {
  p(`- ${label}: $${perMsg.toFixed(5)}/msg; 1 req/5 s for 30 days = ${f(perMsg * 17280 * 30)}; at the account's Workers AI rate limit (300 req/min) = ${f(perMsg * 300 * 60 * 24 * 30)}/month.`);
}
p(`- With guard defaults (150/day, 1,500/month): one subscriber at worst-case capped size = ${f(1500 * WORST)}/month.`);
console.log(out.join('\n'));
