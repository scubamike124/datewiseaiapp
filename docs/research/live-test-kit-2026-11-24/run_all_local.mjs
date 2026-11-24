// Runs every battery day in --mode local with production's SANDBOX_DAILY_LIMIT (20): each day must pass and fit.
import { runKit, selectBattery } from '/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/live-test-prep/work/tool/live/live_chat_test.mjs';
const out = process.argv[2];
const sel = selectBattery({ battery: 'all', tier: 3, day: 'all', perDay: 18 });
let bad = 0;
for (let d = 1; d <= sel.days.length; d++) {
  const r = await runKit({ mode: 'local', battery: 'all', day: String(d), perDay: 18, out, localVars: { SANDBOX_DAILY_LIMIT: '20', SANDBOX_NEURON_BUDGET: '6000' }, log: () => {} });
  const t = r.records.flatMap((x) => x.checks);
  console.log(`day ${d}: ${r.used} requests, fails ${r.failures.length}, warns ${t.filter((c) => c.status === 'WARN').length}, halted ${r.halted}`);
  for (const f of r.failures) console.log('   FAIL', f);
  for (const x of r.records) for (const c of x.checks) if (c.status === 'WARN') console.log('   WARN', x.id, c.name, c.detail);
  bad += r.failures.length;
}
process.exit(bad ? 1 : 0);
