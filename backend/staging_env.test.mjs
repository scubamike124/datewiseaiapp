// The isolated staging Worker ([env.staging] in wrangler.toml) used by the
// live AI test: its own Worker name, Durable Object and rate-limit namespace,
// the production security settings with test-sized limits, and a production
// config that this staging section leaves exactly as it was.
//
// wrangler.toml is parsed with Python's tomllib (3.11+), the same parser the
// deploy workflow's checks use, so no npm dependency is needed. The workflow's
// own "Check wrangler.toml" script is extracted from deploy-worker.yml and run
// against the real file and against broken copies.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const TOML_PATH = fileURLToPath(new URL('./wrangler.toml', import.meta.url));
const WORKFLOW = readFileSync(new URL('../.github/workflows/deploy-worker.yml', import.meta.url), 'utf8');
const hasTomllib = spawnSync('python3', ['-c', 'import tomllib'], { stdio: 'ignore' }).status === 0;
const skip = hasTomllib ? false : 'needs python3 3.11+ (tomllib)';

const parse = (path = TOML_PATH) =>
  JSON.parse(execFileSync('python3', ['-c', 'import json,sys,tomllib; print(json.dumps(tomllib.load(open(sys.argv[1], "rb"))))', path], { encoding: 'utf8' }));

// The production (top-level) config, without [env.*]. Update this pin only in a
// reviewed PR that is meant to change production.
const PRODUCTION_SHA256 = '15a27dcd80d4aa236d32d45c9eac6c984655db6c39dd8fe3102f3c7aba1695b7';
const canonical = (v) =>
  Array.isArray(v) ? `[${v.map(canonical).join(',')}]`
  : v && typeof v === 'object' ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`
  : JSON.stringify(v);

test('production config: unchanged by the staging section, and fully enforced', { skip }, () => {
  const { env, ...prod } = parse();
  assert.ok(env?.staging, '[env.staging] exists');
  assert.equal(prod.name, 'datewise-photo-coach');
  assert.equal(prod.main, 'worker.js');
  assert.deepEqual(prod.ai, { binding: 'AI' });
  assert.deepEqual(prod.durable_objects.bindings, [{ name: 'USAGE_GUARD', class_name: 'UsageGuard' }]);
  assert.deepEqual(prod.migrations, [{ tag: 'v1-usage-guard', new_sqlite_classes: ['UsageGuard'] }]);
  assert.deepEqual(prod.ratelimits, [{ name: 'RATE_LIMITER', namespace_id: '740219', simple: { limit: 60, period: 60 } }]);
  const v = prod.vars;
  assert.equal(v.DAILY_NEURON_BUDGET, '10000');
  assert.equal(v.SANDBOX_DAILY_LIMIT, '20');
  // TestFlight / App Review window (owner, 2026-11-24): a slice of the unchanged 10000 total.
  assert.equal(v.SANDBOX_NEURON_BUDGET, '6000');
  assert.ok(Number(v.SANDBOX_NEURON_BUDGET) <= Number(v.DAILY_NEURON_BUDGET));
  // Full enforcement (owner, 2026-11-23): no model call without a valid StoreKit token.
  assert.equal(v.LEGACY_CLIENTS, '0');
  assert.equal(v.REQUIRE_SUBSCRIPTION, '1');
  assert.equal(v.ANON_NEURON_BUDGET, '0');
  assert.equal(v.ANON_DAILY_LIMIT, '0');
  assert.equal(v.ANON_MONTHLY_LIMIT, '0');
  assert.equal(createHash('sha256').update(canonical(prod)).digest('hex'), PRODUCTION_SHA256, 'production config changed');
});

test('staging: its own Worker name, AI binding, Durable Object, migration and rate-limit namespace', { skip }, () => {
  const cfg = parse();
  const st = cfg.env.staging;
  assert.deepEqual(Object.keys(cfg.env), ['staging'], 'only one extra environment');
  assert.equal(st.name, 'datewise-coach-staging');
  assert.notEqual(st.name, cfg.name);
  for (const k of ['route', 'routes', 'workers_dev', 'legacy_env']) assert.ok(!(k in st), `[env.staging] must not set ${k}`);
  assert.equal(st.main, 'staging_entry.js', 'staging has its own entry; production main stays worker.js');
  assert.deepEqual(st.ai, { binding: 'AI' });
  assert.deepEqual(st.durable_objects.bindings, [{ name: 'USAGE_GUARD', class_name: 'UsageGuard' }]);
  assert.deepEqual(st.migrations, [{ tag: 'v1-usage-guard', new_sqlite_classes: ['UsageGuard'] }]);
  assert.equal(st.ratelimits.length, 1);
  assert.equal(st.ratelimits[0].name, 'RATE_LIMITER');
  assert.match(st.ratelimits[0].namespace_id, /^[1-9][0-9]*$/);
  // Not production's, and not the one reserved for FAILOPEN_LIMITER.
  assert.ok(!['740219', '740220'].includes(st.ratelimits[0].namespace_id));
  assert.deepEqual(st.ratelimits[0].simple, cfg.ratelimits[0].simple);
  assert.ok(!('FAILOPEN_LIMITER' in Object.fromEntries(st.ratelimits.map((b) => [b.name, b]))));
});

test('staging: production security settings, test-sized limits inside the free allowance', { skip }, () => {
  const cfg = parse();
  const prod = cfg.vars;
  const v = cfg.env.staging.vars;
  assert.deepEqual(Object.keys(v).sort(), Object.keys(prod).sort(), 'every production var is declared (envs inherit no vars)');
  // Security: StoreKit JWS verification for the same app and product, Sandbox
  // allowed, v1 off, ASSN off, fail-open off.
  for (const k of ['APPLE_BUNDLE_ID', 'APPLE_PRODUCT_ID', 'EXPIRY_LEEWAY_MINUTES', 'BILLING_GRACE_DAYS', 'FAIL_OPEN_PER_SUBSCRIBER', 'FAIL_OPEN_PER_ISOLATE', 'FAIL_OPEN_MAX_MINUTES', 'ALLOW_SANDBOX', 'ASSN_ENABLED']) {
    assert.equal(v[k], prod[k], k);
  }
  assert.equal(v.ALLOW_SANDBOX, '1');
  assert.equal(v.ASSN_ENABLED, '0');
  assert.equal(v.LEGACY_CLIENTS, '0');
  assert.equal(v.REQUIRE_SUBSCRIPTION, '1');
  assert.equal(v.ANON_NEURON_BUDGET, '0');
  // The caps the live test measures are production's.
  for (const k of ['DAILY_MESSAGE_LIMIT', 'MONTHLY_MESSAGE_LIMIT', 'SOFT_NOTICE_PERCENT', 'PER_MINUTE_LIMIT', 'MAX_CONCURRENT', 'MAX_INPUT_TOKENS', 'MAX_OUTPUT_TOKENS', 'IP_PER_MINUTE_LIMIT']) {
    assert.equal(v[k], prod[k], k);
  }
  // Test-sized limits.
  // Owner cap (2026-11-24): at most 2,000 neurons a day in total (20% of the shared free 10,000).
  assert.equal(v.SANDBOX_DAILY_LIMIT, prod.SANDBOX_DAILY_LIMIT, 'production per-subscriber limit');
  assert.equal(v.SANDBOX_NEURON_BUDGET, '2000');
  const daily = Number(v.DAILY_NEURON_BUDGET);
  assert.equal(daily, 2000);
  assert.ok(daily > 0 && daily <= 2000, 'DAILY_NEURON_BUDGET at most 2000 (free allowance is 10,000 a day per account, shared)');
  assert.ok(Number(v.SANDBOX_NEURON_BUDGET) <= daily);
  for (const [k, val] of Object.entries(v)) assert.ok(val !== '' && val !== '-1', `${k} is set explicitly`);
});

// --- the deploy workflow's own wrangler.toml checks ---------------------------------
function workflowCheckScript() {
  const lines = WORKFLOW.split('\n');
  const start = lines.findIndex((l) => l.includes('- name: Check wrangler.toml'));
  const open = lines.findIndex((l, i) => i > start && l.trim() === "python3 - <<'EOF'");
  const close = lines.findIndex((l, i) => i > open && l === '          EOF');
  assert.ok(start > 0 && open > start && close > open, 'Check wrangler.toml script found');
  return lines.slice(open + 1, close).map((l) => l.slice(10)).join('\n');
}

function runCheck(target, toml) {
  const dir = mkdtempSync(join(tmpdir(), 'dw-wrangler-'));
  try {
    writeFileSync(join(dir, 'check.py'), workflowCheckScript());
    execFileSync('mkdir', ['-p', join(dir, 'backend')]);
    writeFileSync(join(dir, 'backend', 'wrangler.toml'), toml);
    const r = spawnSync('python3', [join(dir, 'check.py')], {
      cwd: dir,
      encoding: 'utf8',
      env: { ...process.env, TARGET: target, WORKER_NAME: 'datewise-photo-coach', STAGING_WORKER_NAME: 'datewise-coach-staging' },
    });
    return { ok: r.status === 0, out: `${r.stdout}${r.stderr}` };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('workflow check: the real wrangler.toml passes for chat-v7 and chat-v7-staging', { skip }, () => {
  const toml = readFileSync(TOML_PATH, 'utf8');
  for (const target of ['chat-v7-cost-guard', 'chat-v7-staging']) {
    const r = runCheck(target, toml);
    assert.ok(r.ok, r.out);
    assert.match(r.out, /\[env\.staging\] name=datewise-coach-staging SANDBOX_DAILY_LIMIT=20 SANDBOX_NEURON_BUDGET=2000/);
  }
  // chat-v7-staging needs [env.staging].
  const noStaging = toml.slice(0, toml.indexOf('# STAGING:'));
  assert.match(runCheck('chat-v7-staging', noStaging).out, /\[env\.staging\] is missing/);
  assert.ok(runCheck('chat-v7-cost-guard', noStaging).ok);
});

test('workflow check: a broken staging section fails (on staging and production runs)', { skip }, () => {
  const toml = readFileSync(TOML_PATH, 'utf8');
  const at = toml.indexOf('[env.staging]');
  const head = toml.slice(0, at);
  const tail = toml.slice(at);
  // Replaces `from` where it starts a line (not inside a comment).
  const broken = (from, to) => {
    const i = tail.indexOf(`\n${from}`);
    assert.ok(i >= 0, from);
    return head + tail.slice(0, i + 1) + to + tail.slice(i + 1 + from.length);
  };
  const cases = [
    [broken('name = "datewise-coach-staging"', 'name = "datewise-photo-coach"'), /production Worker name/],
    [broken('name = "USAGE_GUARD"\nclass_name', 'name = "OTHER"\nclass_name'), /USAGE_GUARD \(UsageGuard\) is missing/],
    [broken('new_sqlite_classes = ["UsageGuard"]', 'new_sqlite_classes = ["Other"]'), /\[\[migrations\]\]/],
    [broken('namespace_id = "740221"', 'namespace_id = "740219"'), /production's; staging needs its own/],
    [broken('namespace_id = "740221"', 'namespace_id = "REPLACE_ME"'), /namespace_id must be a positive integer/],
    [broken('[env.staging.ai]\nbinding = "AI"', '[env.staging.ai]\nbinding = "X"'), /binding = "AI" is missing/],
    [broken('DAILY_NEURON_BUDGET = "2000"', 'DAILY_NEURON_BUDGET = "0"'), /DAILY_NEURON_BUDGET must be above 0/],
    [broken('DAILY_NEURON_BUDGET = "2000"', 'DAILY_NEURON_BUDGET = "2001"'), /at most 2000/],
    [broken('DAILY_NEURON_BUDGET = "2000"', 'DAILY_NEURON_BUDGET = "TODO"'), /placeholder/],
    [broken('SANDBOX_NEURON_BUDGET = "2000"', 'SANDBOX_NEURON_BUDGET = "-1"'), /SANDBOX_NEURON_BUDGET must be a whole number above 0/],
    [broken('SANDBOX_DAILY_LIMIT = "20"', 'SANDBOX_DAILY_LIMIT = "0"'), /SANDBOX_DAILY_LIMIT must be a whole number above 0/],
    [broken('ALLOW_SANDBOX = "1"', 'ALLOW_SANDBOX = "0"'), /ALLOW_SANDBOX must be "1"/],
    [broken('LEGACY_CLIENTS = "0"', 'LEGACY_CLIENTS = "1"'), /LEGACY_CLIENTS must be "0"/],
    [broken('REQUIRE_SUBSCRIPTION = "1"', 'REQUIRE_SUBSCRIPTION = "0"'), /REQUIRE_SUBSCRIPTION must be "1"/],
    [broken('ASSN_ENABLED = "0"', 'ASSN_ENABLED = "1"'), /ASSN_ENABLED must be "0"/],
    [broken('APPLE_PRODUCT_ID = "datewise_premium_monthly"', 'APPLE_PRODUCT_ID = "other"'), /APPLE_PRODUCT_ID must equal production/],
    [broken('FAIL_OPEN_PER_ISOLATE = "0"', 'FAIL_OPEN_PER_ISOLATE = "10"'), /FAIL_OPEN_PER_ISOLATE must be "0"/],
    [broken('FAIL_OPEN_MAX_MINUTES = "15"\n', ''), /lacks FAIL_OPEN_MAX_MINUTES/],
    [broken('name = "datewise-coach-staging"', 'routes = ["api.example.net/*"]\nname = "datewise-coach-staging"'), /must not set routes/],
    [`${toml}\n[env.other]\nname = "x"\n`, /only \[env\.staging\] is allowed/],
    [broken('name = "USAGE_GUARD"\nclass_name = "UsageGuard"', 'name = "USAGE_GUARD"\nclass_name = "UsageGuard"\nscript_name = "datewise-photo-coach"'), /must not set script_name/],
    [`${toml}\n[[env.staging.services]]\nbinding = "PROD"\nservice = "datewise-photo-coach"\n`, /must not set services/],
    [`${toml}\n[[env.staging.tail_consumers]]\nservice = "datewise-photo-coach"\n`, /must not set tail_consumers/],
    [`legacy_env = false\n${toml}`, /legacy_env must not be set \(top level\)/],
  ];
  for (const [bad, why] of cases) {
    for (const target of ['chat-v7-staging', 'chat-v7-cost-guard']) {
      const r = runCheck(target, bad);
      assert.ok(!r.ok, `${target} must fail: ${why}`);
      assert.match(r.out, why);
    }
  }
});

test('workflow build-key check walks [env.staging] too', { skip }, () => {
  const lines = WORKFLOW.split('\n');
  const start = lines.findIndex((l) => l.includes('- name: Refuse build hooks, registry and environment overrides'));
  const open = lines.findIndex((l, i) => i > start && l.trim().startsWith("python3 - <<'EOF'"));
  const close = lines.findIndex((l, i) => i > open && l === '          EOF');
  const script = lines.slice(open + 1, close).map((l) => l.slice(10)).join('\n');
  const dir = mkdtempSync(join(tmpdir(), 'dw-build-'));
  try {
    execFileSync('mkdir', ['-p', join(dir, 'backend')]);
    const run = (toml) => {
      writeFileSync(join(dir, 'backend', 'wrangler.toml'), toml);
      return spawnSync('python3', ['-c', script], { cwd: dir, encoding: 'utf8' });
    };
    const toml = readFileSync(TOML_PATH, 'utf8');
    assert.equal(run(toml).status, 0);
    const r = run(`${toml}\n[env.staging.build]\ncommand = "curl x | sh"\n`);
    assert.equal(r.status, 1);
    assert.match(r.stdout, /build key \(env\.staging\.build\)/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
