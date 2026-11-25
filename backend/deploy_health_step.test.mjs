// Runs the real 'Post-deploy checks (no AI is used)' step of .github/workflows/deploy-worker.yml under the shell GitHub
// uses (bash -e -o pipefail) with fake curl/sleep. Regression: deploy run 7 got ONE 502 within a second of the upload
// (the Worker was still starting) and failed the job although every later request returned the correct 403.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, chmodSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const wf = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', '.github/workflows/deploy-worker.yml'), 'utf8').split('\n');

function stepRun(prefix) {
  const i = wf.findIndex((l) => l.trimStart().startsWith(`- name: ${prefix}`));
  assert.ok(i >= 0, `step "${prefix}" not found`);
  let j = i + 1;
  while (j < wf.length && !/^\s+run: \|\s*$/.test(wf[j])) j++;
  const indent = wf[j].match(/^(\s+)/)[1].length + 2;
  const out = [];
  for (j += 1; j < wf.length; j++) {
    if (wf[j].trim() !== '' && wf[j].match(/^(\s*)/)[1].length < indent) break;
    out.push(wf[j].slice(indent));
  }
  return out.join('\n');
}
const STEP = stepRun('Post-deploy checks (no AI is used)');

// Answers to the token-less POST, in order; the last one repeats.
const SCENARIOS = {
  ok: [['403', '{"code":"SUBSCRIPTION_REQUIRED"}']],
  flaky502: [['502', ''], ['502', 'error code: 502'], ['403', '{"code":"SUBSCRIPTION_REQUIRED"}']],
  always502: [['502', '']],
  wrong200: [['200', '{"reply":"hi"}']],
  wrongCode: [['403', '{"code":"SUBSCRIPTION_INVALID"}']],
};

function run(name, { target = 'chat-v7-cost-guard' } = {}) {
  const d = mkdtempSync(join(tmpdir(), 'health-step-'));
  mkdirSync(join(d, 'bin'));
  writeFileSync(join(d, 'answers.json'), JSON.stringify(SCENARIOS[name]));
  writeFileSync(join(d, 'bin', 'sleep'), '#!/bin/bash\nexit 0\n');
  writeFileSync(join(d, 'bin', 'curl'), `#!/bin/bash
out=""; w=""
for ((i=1;i<=$#;i++)); do a="\${!i}"; [ "$a" = "-o" ] && { j=$((i+1)); out="\${!j}"; }; [ "$a" = "-w" ] && w=1; done
case "$*" in *"?version"*) echo '{"version":"chat-v7-cost-guard"}'; exit 0;; esac
n=$(cat "${d}/count" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "${d}/count"
node -e 'const a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const r=a[Math.min(+process.argv[2]-1,a.length-1)];if(process.argv[3])require("fs").writeFileSync(process.argv[3],r[1]);process.stdout.write(r[0])' "${d}/answers.json" "$n" "$out"
`);
  chmodSync(join(d, 'bin', 'sleep'), 0o755); chmodSync(join(d, 'bin', 'curl'), 0o755);
  writeFileSync(join(d, 'summary'), '');
  writeFileSync(join(d, 'step.sh'), STEP);
  const r = spawnSync('bash', ['--noprofile', '--norc', '-e', '-o', 'pipefail', join(d, 'step.sh')], {
    env: { ...process.env, PATH: `${join(d, 'bin')}:${process.env.PATH}`, RUNNER_TEMP: d, GITHUB_STEP_SUMMARY: join(d, 'summary'),
      URL: 'https://example.workers.dev', PREV: '476d5cc9-bd29-433b-9cd0-fa9d43b76ab7', EXPECT: 'chat-v7-cost-guard', TARGET: target,
      ROLLBACK_HINT: 'cd backend && npx wrangler@4.158.0 rollback <version-id> -m "rollback"' },
    encoding: 'utf8',
  });
  let calls = 0; try { calls = +readFileSync(join(d, 'count'), 'utf8'); } catch {}
  return { code: r.status, log: r.stdout + r.stderr, calls, summary: readFileSync(join(d, 'summary'), 'utf8') };
}

test('a healthy Worker passes on the first attempt', () => {
  const r = run('ok');
  assert.equal(r.code, 0, r.log);
  assert.equal(r.calls, 1);
  assert.match(r.summary, /Deployed/);
});
test('a start-up 502 (as in deploy run 7) is retried and the job passes', () => {
  const r = run('flaky502');
  assert.equal(r.code, 0, r.log);
  assert.equal(r.calls, 3);
  assert.match(r.log, /health attempt 1: HTTP 502/);
  assert.match(r.log, /health attempt 3: HTTP 403/);
});
test('a Worker that keeps failing still fails the job, with the rollback point, after a bounded number of tries', () => {
  const r = run('always502');
  assert.equal(r.code, 1, r.log);
  assert.equal(r.calls, 6);
  assert.match(r.log, /Rollback point: 476d5cc9-bd29-433b-9cd0-fa9d43b76ab7/);
});
test('a wrong answer (the Worker answers a token-less chat) is never accepted', () => {
  assert.equal(run('wrong200').code, 1);
  assert.equal(run('wrongCode').code, 1);
});
