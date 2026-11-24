// Runs the real steps of .github/workflows/live-ai-test-staging.yml under the shell GitHub uses
// (bash --noprofile --norc -e -o pipefail) with fake `npx` (Wrangler), `curl`, `node` (battery only), `sleep`.
// Pattern of backend/deploy_salt_step.test.mjs. Also pins the workflow's shape: manual only, one gated job, secrets only
// where the Cloudflare calls are, no ${{ }} inside any script.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const WF_TEXT = readFileSync(join(ROOT, '.github/workflows/live-ai-test-staging.yml'), 'utf8');
const wf = WF_TEXT.split('\n');

function stepBlock(namePrefix) {
  const i = wf.findIndex((l) => l.trimStart().startsWith(`- name: ${namePrefix}`));
  assert.ok(i >= 0, `step "${namePrefix}" not found`);
  let j = i + 1;
  while (j < wf.length && !/^\s+run: [|>]?\s*$/.test(wf[j]) && !/^\s+run: \|\s*$/.test(wf[j])) {
    assert.ok(!/^\s+- (name|uses):/.test(wf[j]), `step "${namePrefix}" has no run block`);
    j++;
  }
  const indent = wf[j].match(/^(\s+)/)[1].length + 2;
  const out = [];
  for (j += 1; j < wf.length; j++) {
    if (wf[j].trim() !== '' && wf[j].match(/^(\s*)/)[1].length < indent) break;
    out.push(wf[j].slice(indent));
  }
  return out.join('\n');
}
const STEP = {
  guard: stepBlock('Repository-level Cloudflare secrets'),
  plan: stepBlock('Validate the inputs'),
  main: stepBlock("This run's commit must be on main"),
  config: stepBlock('Refuse files that change what Wrangler builds'),
  prod: stepBlock('Production bundle must contain no staging test-trust code'),
  day: stepBlock('Check that the chosen day exists'),
  mint: stepBlock('Generate the throwaway CA'),
  deploy: stepBlock('Deploy the staging Worker with the PUBLIC test root only'),
  url: stepBlock('Find the staging URL'),
  pre: stepBlock('Pre-flight'),
  battery: stepBlock('Run the battery'),
  usage: stepBlock('Neuron usage'),
  cleanup: stepBlock('Cleanup, remove the test root'),
  fail: stepBlock('Fail the run if the battery had a failing check'),
};
const STG = 'datewise-coach-staging';
const HOST = `https://${STG}.acme.workers.dev`;

/** Runs a step script in a scratch repo copy. `fakes`: { npx, curl, node, sleep } bash bodies. */
function run(script, { env = {}, fakes = {}, cwd, setup } = {}) {
  const d = mkdtempSync(join(tmpdir(), 'live-step-'));
  const bin = join(d, 'bin');
  mkdirSync(bin);
  const tmp = join(d, 'tmp');
  mkdirSync(tmp);
  const work = cwd ?? join(d, 'work');
  if (!cwd) mkdirSync(work);
  const calls = join(d, 'calls.log');
  writeFileSync(calls, '');
  const put = (name, body) => {
    writeFileSync(join(bin, name), `#!/bin/bash\necho "${name} $*" >> "${calls}"\n${body}\n`);
    chmodSync(join(bin, name), 0o755);
  };
  put('sleep', 'exit 0');
  for (const [n, b] of Object.entries(fakes)) put(n, b);
  writeFileSync(join(d, 'out'), '');
  writeFileSync(join(d, 'summary'), '');
  writeFileSync(join(d, 'step.sh'), script);
  if (setup) setup({ d, tmp, work });
  const r = spawnSync('bash', ['--noprofile', '--norc', '-e', '-o', 'pipefail', join(d, 'step.sh')], {
    cwd: work,
    env: {
      PATH: `${bin}:${process.env.PATH}`, HOME: d, RUNNER_TEMP: tmp, GITHUB_OUTPUT: join(d, 'out'), GITHUB_STEP_SUMMARY: join(d, 'summary'),
      WRANGLER_VERSION: '4.158.0', WORKER_NAME: 'datewise-photo-coach', STAGING_WORKER_NAME: STG, REVIEWED_BRANCH: 'main',
      PER_DAY: '16', NEURON_CAP: '2000', RESERVE_NEURONS: '210', ...env,
    },
    encoding: 'utf8',
  });
  return {
    code: r.status, log: r.stdout + r.stderr, out: readFileSync(join(d, 'out'), 'utf8'), summary: readFileSync(join(d, 'summary'), 'utf8'),
    calls: readFileSync(calls, 'utf8').trim().split('\n').filter(Boolean), tmp, work, d,
  };
}

// A curl that routes by URL; `routes` is a bash `case` body using $url, and sets $body and $status.
const curl = (routes) => `
out=""; w=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2;; -w) w=$2; shift 2;; -H|--max-time|-X|--data) shift 2;; -*) shift;; *) url=$1; shift;; esac; done
status=200; body='{}'
case "$url" in
${routes}
esac
if [ -n "$out" ]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
if [ -n "$w" ]; then printf '%s' "$status"; fi
`;
const goodRoutes = `*/workers/subdomain) body='{"result":{"subdomain":"acme"}}';;
*"/?version") body='{"version":"chat-v7-cost-guard"}';;
*"/?staging-neurons") body='{"day":"2026-11-25","spent":100,"cap":2000,"overCap":false}';;`;

function seedAuth(tmp, tokens = 'tok.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBB') {
  mkdirSync(join(tmp, 'staging_auth'));
  writeFileSync(join(tmp, 'staging_auth', 'root.b64'), 'MIIBrootcert+/AAAA==\n');
  writeFileSync(join(tmp, 'staging_auth', 'tokens'), `${tokens}\n`, { mode: 0o600 });
}

// --- workflow shape --------------------------------------------------------------------
test('workflow shape: manual only, one gated job, secrets only where Cloudflare is called, no ${{ }} in scripts', () => {
  const on = WF_TEXT.slice(WF_TEXT.indexOf('\non:'), WF_TEXT.indexOf('\npermissions:'));
  assert.match(on, /workflow_dispatch:/);
  assert.ok(!/schedule:|push:|pull_request|workflow_call|repository_dispatch/.test(on), 'only workflow_dispatch');
  assert.match(WF_TEXT, /environment: production-worker/);
  assert.equal((WF_TEXT.match(/environment:/g) || []).length, 1, 'exactly one gated job');
  assert.match(WF_TEXT, /group: deploy-worker/);
  // Scripts take values through env only (never interpolated).
  for (const [name, script] of Object.entries(STEP)) assert.ok(!script.includes('${{'), `${name} step interpolates \${{ }} into a script`);
  // Secrets: only the guard (repo-level check), deploy, URL lookup and cleanup steps. Never the battery step.
  const secretSteps = [...WF_TEXT.matchAll(/- name: ([^\n]+)\n(?:(?!\n      - ).)*?secrets\.CLOUDFLARE/gs)].map((m) => m[1]);
  for (const s of secretSteps) assert.ok(/Repository-level|Deploy the staging|Find the staging URL|Cleanup/.test(s), `secret in step: ${s}`);
  assert.ok(!/DW_TEST_JWS: \$\{\{/.test(WF_TEXT));
  // Every wrangler call that changes a Worker names --env staging; production is only dry-run.
  for (const m of WF_TEXT.matchAll(/wrangler@\$\{WRANGLER_VERSION\}" (deploy[^\n|]*)/g)) {
    assert.ok(m[1].includes('--env staging') || m[1].includes('--dry-run'), `unsafe wrangler call: ${m[1]}`);
  }
  assert.ok(!/--force-v6|chat-v6|secrets-file|wrangler secret/.test(WF_TEXT));
});

// --- steps ------------------------------------------------------------------------------
test('guard: repository-level Cloudflare secrets are refused', () => {
  assert.equal(run(STEP.guard, { env: { REPO_CF_TOKEN: '', REPO_CF_ACCOUNT: '' } }).code, 0);
  assert.equal(run(STEP.guard, { env: { REPO_CF_TOKEN: 'x', REPO_CF_ACCOUNT: '' } }).code, 1);
  assert.equal(run(STEP.guard, { env: { REPO_CF_TOKEN: '', REPO_CF_ACCOUNT: 'y' } }).code, 1);
});

test('inputs: only a single-digit day and tier 1 to 3', () => {
  const ok = run(STEP.plan, { env: { IN_DAY: '3', IN_TIER: '2', GITHUB_SHA: 'a'.repeat(40) } });
  assert.equal(ok.code, 0, ok.log);
  assert.match(ok.out, /day=3\ntier=2/);
  for (const [day, tier, sha] of [['0', '3', 'a'.repeat(40)], ['10', '3', 'a'.repeat(40)], ['1; rm -rf /', '3', 'a'.repeat(40)], ['', '3', 'a'.repeat(40)], ['1', '4', 'a'.repeat(40)], ['1', '', 'a'.repeat(40)], ['1', '3', 'xyz'], ['1\n2', '3', 'a'.repeat(40)]]) {
    const r = run(STEP.plan, { env: { IN_DAY: day, IN_TIER: tier, GITHUB_SHA: sha } });
    assert.equal(r.code, 1, JSON.stringify([day, tier, sha]));
    assert.equal(r.out, '');
  }
});

test("commit check: a commit on main passes; one only on another branch is refused", () => {
  const g = (cwd, ...a) => { const r = spawnSync('git', a, { cwd, encoding: 'utf8' }); assert.equal(r.status, 0, r.stderr); return r.stdout.trim(); };
  const setup = ({ d, work }) => {
    const origin = join(d, 'origin.git');
    g(d, 'init', '--bare', '-b', 'main', origin);
    g(work, 'init', '-b', 'main');
    g(work, 'config', 'user.email', 't@t'); g(work, 'config', 'user.name', 't'); g(work, 'config', 'commit.gpgsign', 'false');
    g(work, 'remote', 'add', 'origin', origin);
    writeFileSync(join(work, 'f'), '1'); g(work, 'add', '.'); g(work, 'commit', '-m', 'one');
    g(work, 'push', 'origin', 'main');
    writeFileSync(join(work, 'f'), '2'); g(work, 'commit', '-am', 'branch only');
    g(work, 'branch', 'feature');
  };
  const cases = {};
  for (const which of ['main', 'feature']) {
    const d = mkdtempSync(join(tmpdir(), 'live-git-'));
    const work = join(d, 'w'); mkdirSync(work);
    setup({ d, work });
    const sha = which === 'main' ? g(work, 'rev-parse', 'HEAD~1') : g(work, 'rev-parse', 'HEAD');
    g(work, 'checkout', '-q', sha);
    cases[which] = run(STEP.main, { env: { GITHUB_SHA: sha }, cwd: work });
  }
  assert.equal(cases.main.code, 0, cases.main.log);
  assert.equal(cases.feature.code, 1, cases.feature.log);
  assert.match(cases.feature.log, /is not on main/);
});

test('config guard: the real wrangler.toml passes; stray files and unsafe staging settings fail', () => {
  const toml = readFileSync(join(ROOT, 'backend/wrangler.toml'), 'utf8');
  const withToml = (t, extra = () => {}) => ({ work }) => { mkdirSync(join(work, 'backend')); writeFileSync(join(work, 'backend/wrangler.toml'), t); extra(work); };
  const ok = run(STEP.config, { setup: withToml(toml) });
  assert.equal(ok.code, 0, ok.log);
  const bad = (t, re, extra) => { const r = run(STEP.config, { setup: withToml(t, extra) }); assert.equal(r.code, 1, r.log); assert.match(r.log, re); };
  bad(toml, /\.env must not exist/, (w) => writeFileSync(join(w, '.env'), 'X=1'));
  bad(toml, /backend\/package\.json must not exist/, (w) => writeFileSync(join(w, 'backend/package.json'), '{}'));
  bad(toml.replace('DAILY_NEURON_BUDGET = "2000"', 'DAILY_NEURON_BUDGET = "2001"'), /DAILY_NEURON_BUDGET must be 1\.\.2000/);
  bad(toml.replace('DAILY_NEURON_BUDGET = "2000"', 'DAILY_NEURON_BUDGET = "10000"'), /must be 1\.\.2000/);
  bad(toml.replace('SANDBOX_DAILY_LIMIT = "20"\nSANDBOX_NEURON_BUDGET = "2000"', 'SANDBOX_DAILY_LIMIT = "40"\nSANDBOX_NEURON_BUDGET = "2000"'), /SANDBOX_DAILY_LIMIT exceeds production/);
  bad(toml.replace('main = "staging_entry.js"', 'main = "worker.js"'), /staging main must be staging_entry\.js/);
  bad(toml.replace('main = "worker.js"\ncompat', 'main = "staging_entry.js"\ncompat'), /production main must be worker\.js/);
  bad(toml.replace('PER_MINUTE_LIMIT = "12"\nMAX_CONCURRENT = "2"\nMAX_INPUT_TOKENS = "6000"\nMAX_OUTPUT_TOKENS = "800"\nIP', 'PER_MINUTE_LIMIT = "99"\nMAX_CONCURRENT = "2"\nMAX_INPUT_TOKENS = "6000"\nMAX_OUTPUT_TOKENS = "800"\nIP'), /PER_MINUTE_LIMIT must equal production/);
  bad(toml.replace('[env.staging.vars]\n', '[env.staging.vars]\nSTAGING_TEST_ROOT_CERT_B64 = "AAAA"\n'), /never be committed/);
  bad(`${toml}\n[env.staging.build]\ncommand = "x"\n`, /must not have a build key/);
  bad(`${toml}\n[env.other]\nname = "x"\n`, /only \[env\.staging\] is allowed/);
});

test('production bundle step: clean bundle passes; staging test-trust code in it fails; production is only dry-run', () => {
  const npx = (content) => `
while [ $# -gt 0 ]; do case "$1" in --outdir) outdir=$2; shift 2;; *) shift;; esac; done
mkdir -p "$outdir"; printf '%s' '${content}' > "$outdir/worker.js"`;
  // The step cds into backend via working-directory in GitHub; here we run it from work/backend.
  const inBackend = (fakes) => { const d = mkdtempSync(join(tmpdir(), 'live-prod-')); mkdirSync(join(d, 'backend')); return run(STEP.prod, { cwd: join(d, 'backend'), fakes }); };
  const ok = inBackend({ npx: npx('export default {}') });
  assert.equal(ok.code, 0, ok.log);
  assert.ok(ok.calls.some((c) => /^npx --yes wrangler@4\.158\.0 deploy --dry-run --outdir /.test(c)));
  assert.ok(ok.calls.every((c) => !c.includes('--env')), 'the PRODUCTION config: no --env');
  for (const marker of ['STAGING_TEST_ROOT_CERT_B64', 'staging-neurons', 'MAX_TEST_ROOT_LIFETIME_MS']) {
    const r = inBackend({ npx: npx(`x ${marker} y`) });
    assert.equal(r.code, 1, marker);
    assert.match(r.log, /contains staging test-trust code/);
  }
  assert.equal(inBackend({ npx: 'exit 1' }).code, 1);
});

test('day check: day 1 to the last day exists, beyond it is refused before any deploy', () => {
  const env = (day, tier = '3') => ({ DAY: day, TIER: tier });
  const r = run(STEP.day, { cwd: ROOT, env: env('1') });
  assert.equal(r.code, 0, r.log);
  assert.match(r.log, /day 1 of 7: 16 scenario\(s\) of 106/);
  assert.equal(run(STEP.day, { cwd: ROOT, env: env('7') }).code, 0);
  const late = run(STEP.day, { cwd: ROOT, env: env('8') });
  assert.equal(late.code, 1);
});

test('mint step: public root and 0600 tokens only, no key material, tokens masked and never printed otherwise', () => {
  const r = run(STEP.mint, { cwd: ROOT });
  assert.equal(r.code, 0, r.log);
  const dir = join(r.tmp, 'staging_auth');
  assert.deepEqual(readdirSync(dir).sort(), ['root.b64', 'tokens']);
  assert.equal(statSync(join(dir, 'tokens')).mode & 0o777, 0o600);
  const tok = readFileSync(join(dir, 'tokens'), 'utf8').trim();
  const masks = r.log.split('\n').filter((l) => l.startsWith('::add-mask::'));
  assert.deepEqual(masks, [`::add-mask::${tok}`], 'the token is masked');
  assert.ok(!r.log.split('\n').filter((l) => !l.startsWith('::add-mask::')).join('\n').includes(tok), 'the token is printed nowhere else');
  assert.ok(!/PRIVATE|BEGIN/.test(r.log) && !existsSync(join(r.tmp, 'ca.key')));
  // Nothing else on the runner temp folder holds key material.
  const all = readdirSync(r.tmp, { recursive: true }).map(String);
  assert.deepEqual(all.sort(), ['staging_auth', 'staging_auth/root.b64', 'staging_auth/tokens']);
});

test('deploy step: always --env staging with only the PUBLIC root as a var; refuses without credentials or with a bad root', () => {
  const env = { CLOUDFLARE_API_TOKEN: 't', CLOUDFLARE_ACCOUNT_ID: 'a' };
  const ok = run(STEP.deploy, { env, fakes: { npx: 'echo "Uploaded"' }, setup: ({ tmp }) => seedAuth(tmp) });
  assert.equal(ok.code, 0, ok.log);
  assert.deepEqual(ok.calls, ['npx --yes wrangler@4.158.0 deploy --env staging --var STAGING_TEST_ROOT_CERT_B64:MIIBrootcert+/AAAA==']);
  assert.ok(!ok.calls.join('\n').includes('tok.'), 'no token on the command line');
  assert.equal(run(STEP.deploy, { env: { ...env, CLOUDFLARE_API_TOKEN: '' }, fakes: { npx: 'true' }, setup: ({ tmp }) => seedAuth(tmp) }).code, 1);
  assert.equal(run(STEP.deploy, { env: { ...env, CLOUDFLARE_ACCOUNT_ID: '' }, fakes: { npx: 'true' }, setup: ({ tmp }) => seedAuth(tmp) }).code, 1);
  const badRoot = run(STEP.deploy, { env, fakes: { npx: 'true' }, setup: ({ tmp }) => { seedAuth(tmp); writeFileSync(join(tmp, 'staging_auth', 'root.b64'), 'x y; rm -rf /\n'); } });
  assert.equal(badRoot.code, 1);
  assert.deepEqual(badRoot.calls.filter((c) => c.startsWith('npx')), []);
  // A failing wrangler fails the step (pipefail through the log filter).
  assert.equal(run(STEP.deploy, { env, fakes: { npx: 'echo boom; exit 1' }, setup: ({ tmp }) => seedAuth(tmp) }).code, 1);
});

test('URL step: finds the staging workers.dev host and waits for chat-v7; fails on no subdomain or a wrong version', () => {
  const env = { CLOUDFLARE_API_TOKEN: 't', CLOUDFLARE_ACCOUNT_ID: 'a' };
  const ok = run(STEP.url, { env, fakes: { curl: curl(goodRoutes) } });
  assert.equal(ok.code, 0, ok.log);
  assert.match(ok.out, new RegExp(`url=${HOST.replace(/\./g, '\\.')}\\n`));
  assert.equal(run(STEP.url, { env, fakes: { curl: curl(goodRoutes.replace('"subdomain":"acme"', '"subdomain":""')) } }).code, 1);
  assert.equal(run(STEP.url, { env, fakes: { curl: curl(goodRoutes.replace('"version":"chat-v7-cost-guard"', '"version":"chat-v5"')) } }).code, 1);
  assert.equal(run(STEP.url, { env, fakes: { curl: curl(goodRoutes.replace('"subdomain":"acme"', '"subdomain":"a.evil.com/x"')) } }).code, 1);
});

test('pre-flight: refuses a rejected token, an unreadable or over-cap counter and a day already near the cap', () => {
  const pre = (neurons, status = 200, url = HOST) => run(STEP.pre, {
    env: { URL: url },
    fakes: { curl: curl(`*"/?staging-neurons") body='${neurons}'; status=${status};;`) },
    setup: ({ tmp }) => seedAuth(tmp),
  });
  const j = (o) => JSON.stringify({ day: '2026-11-25', cap: 2000, overCap: false, spent: 0, ...o });
  const ok = pre(j({ spent: 1790 })); // 1790 + 210 = 2000: allowed
  assert.equal(ok.code, 0, ok.log);
  assert.match(ok.log, /used today: 1790 of 2000/);
  assert.equal(pre(j({ spent: 1791 })).code, 1);
  assert.equal(pre(j({ spent: 2000 })).code, 1);
  assert.equal(pre(j({ spent: null, overCap: true })).code, 1);
  assert.equal(pre(j({ cap: 4000 })).code, 1, 'a Worker cap above the owner cap');
  assert.equal(pre(j({}), 403).code, 1, 'token not accepted');
  assert.equal(pre('not json').code, 1);
  assert.equal(pre(j({}), 200, 'https://datewise-photo-coach.acme.workers.dev').code, 1, 'production host refused');
  assert.equal(pre(j({}), 200, 'https://evil.example.com').code, 1);
  const tok = 'tok.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBB';
  assert.ok(!ok.log.replace(`::add-mask::${tok}`, '').includes(tok));
});

test('battery step: live mode against the staging host with the token in the environment only; always exits 0 and records the code', () => {
  const tok = 'tok.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBB';
  const node = (rc) => `echo "TOKEN_SEEN=\${DW_TEST_JWS:+yes}" >> "$RUNNER_TEMP/seen"; exit ${rc}`;
  for (const rc of [0, 1, 2, 3]) {
    const r = run(STEP.battery, { env: { URL: HOST, DAY: '2', TIER: '3' }, fakes: { node: node(rc) }, setup: ({ tmp }) => seedAuth(tmp, tok) });
    assert.equal(r.code, 0, r.log);
    assert.match(r.out, new RegExp(`rc=${rc}\\n`));
    const call = r.calls.find((c) => c.startsWith('node tool/live/live_chat_test.mjs'));
    assert.ok(call.includes('--battery all --mode live --confirm-live'));
    assert.ok(call.includes(`--base-url ${HOST}`) && call.includes('--tier 3 --day 2 --per-day 16'), call);
    assert.ok(!call.includes('tok.'), 'the token is never on a command line');
    assert.match(readFileSync(join(r.tmp, 'seen'), 'utf8'), /TOKEN_SEEN=yes/);
    assert.ok(!r.log.replace(`::add-mask::${tok}`, '').includes(tok));
    if (rc === 3) assert.match(r.log, /::warning::Stopped early for capacity/);
  }
  assert.equal(run(STEP.battery, { env: { URL: 'https://datewise-photo-coach.acme.workers.dev', DAY: '1', TIER: '3' }, fakes: { node: 'exit 0' }, setup: ({ tmp }) => seedAuth(tmp) }).code, 1);
});

test('usage step: prints the neuron counter and survives an unavailable Worker', () => {
  const ok = run(STEP.usage, { env: { URL: HOST, RC: '0' }, fakes: { curl: curl(`*"/?staging-neurons") body='{"day":"2026-11-25","spent":1850,"cap":2000}';;`) }, setup: ({ tmp }) => seedAuth(tmp) });
  assert.equal(ok.code, 0, ok.log);
  assert.match(ok.log, /staging neurons used today \(UTC 2026-11-25\): 1850 of 2000/);
  assert.match(ok.summary, /1850 of 2000/);
  const down = run(STEP.usage, { env: { URL: HOST, RC: '3' }, fakes: { curl: 'exit 7' }, setup: ({ tmp }) => seedAuth(tmp) });
  assert.equal(down.code, 0, down.log);
  assert.match(down.log, /unavailable/);
});

test('cleanup: redeploys staging WITHOUT the test root, proves the token is refused, deletes the CA files', () => {
  const env = { CLOUDFLARE_API_TOKEN: 't', URL: HOST, DEPLOY_OUTCOME: 'success' };
  const refused = curl(`*"/?staging-neurons") status=403; body='{"code":"SUBSCRIPTION_INVALID"}';;`);
  const ok = run(STEP.cleanup, { env, fakes: { npx: 'echo done', curl: refused }, setup: ({ tmp }) => seedAuth(tmp) });
  assert.equal(ok.code, 0, ok.log);
  const deploys = ok.calls.filter((c) => c.startsWith('npx'));
  assert.deepEqual(deploys, ['npx --yes wrangler@4.158.0 deploy --env staging']);
  assert.ok(!deploys[0].includes('--var'), 'no test root any more');
  assert.match(ok.log, /no longer accepts the test token \(HTTP 403\)/);
  assert.ok(!existsSync(join(ok.tmp, 'staging_auth')));
  // The redeploy fails: the step fails loudly, but the CA files are still deleted.
  const failed = run(STEP.cleanup, { env, fakes: { npx: 'exit 1', curl: refused }, setup: ({ tmp }) => seedAuth(tmp) });
  assert.equal(failed.code, 1);
  assert.match(failed.log, /expires by itself within 2 hours/);
  assert.ok(!existsSync(join(failed.tmp, 'staging_auth')));
  // The token still works after cleanup: a warning (it expires by itself), files deleted.
  const still = run(STEP.cleanup, { env, fakes: { npx: 'true', curl: curl(`*"/?staging-neurons") status=200; body='{}';;`) }, setup: ({ tmp }) => seedAuth(tmp) });
  assert.equal(still.code, 0);
  assert.match(still.log, /::warning::After cleanup/);
  // The deploy never ran: no Wrangler call at all, files still deleted.
  const skipped = run(STEP.cleanup, { env: { ...env, DEPLOY_OUTCOME: 'skipped' }, fakes: { npx: 'true', curl: refused }, setup: ({ tmp }) => seedAuth(tmp) });
  assert.equal(skipped.code, 0, skipped.log);
  assert.deepEqual(skipped.calls.filter((c) => c.startsWith('npx')), []);
  assert.ok(!existsSync(join(skipped.tmp, 'staging_auth')));
  assert.ok(!ok.log.replace('::add-mask::tok.AAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBB', '').includes('tok.AAAA'));
});

test('final step: exit codes 0 and 3 pass, anything else fails the run', () => {
  for (const rc of ['0', '3']) assert.equal(run(STEP.fail, { env: { RC: rc } }).code, 0, rc);
  for (const rc of ['1', '2', '', '137']) assert.equal(run(STEP.fail, { env: { RC: rc } }).code, 1, JSON.stringify(rc));
});
