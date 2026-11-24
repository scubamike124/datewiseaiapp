// Runs the real ID_HASH_SALT steps of .github/workflows/deploy-worker.yml under the same shell GitHub uses
// (bash -e -o pipefail) against a fake `npx` standing in for Wrangler. Guards the rules: an existing salt is never
// replaced; a missing salt is generated into an owner-only file and never printed; an unreadable or malformed secret
// list stops the deploy. (Regression: exit code 1 from the list check once ended the step under `bash -e`.)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, chmodSync, existsSync, statSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const wf = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', '.github/workflows/deploy-worker.yml'), 'utf8').split('\n');

function stepRun(namePrefix) {
  const i = wf.findIndex((l) => l.trimStart().startsWith(`- name: ${namePrefix}`));
  assert.ok(i >= 0, `step "${namePrefix}" not found`);
  let j = i + 1;
  while (j < wf.length && !/^\s+run: \|\s*$/.test(wf[j])) {
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

const PROD = stepRun('ID_HASH_SALT is kept');
const STG = stepRun('Staging ID_HASH_SALT');

const FAKE = {
  nosalt: `echo '[{"name":"OTHER","type":"secret_text"}]'`,
  empty: `echo '[]'`,
  hassalt: `echo '[{"name":"ID_HASH_SALT","type":"secret_text"}]'`,
  malformed: `echo warning; echo '[{"name":"ID_HASH_SALT"}]'`,
  wrapped: `echo '{"result":[{"name":"ID_HASH_SALT"}]}'`,
  prodNotFound: `echo 'Worker "datewise-photo-coach" not found' >&2; exit 1`,
  stgNotFound: `echo 'Worker "datewise-coach-staging" not found' >&2; exit 1`,
  apiError: `echo 'authentication error' >&2; exit 1`,
};

function run(script, fake, envSalt = '') {
  const d = mkdtempSync(join(tmpdir(), 'salt-step-'));
  mkdirSync(join(d, 'bin'));
  writeFileSync(join(d, 'bin', 'npx'), `#!/bin/bash\n${FAKE[fake]}\n`);
  chmodSync(join(d, 'bin', 'npx'), 0o755);
  writeFileSync(join(d, 'out'), '');
  writeFileSync(join(d, 'step.sh'), script);
  const r = spawnSync('bash', ['--noprofile', '--norc', '-e', '-o', 'pipefail', join(d, 'step.sh')], {
    env: { ...process.env, PATH: `${join(d, 'bin')}:${process.env.PATH}`, RUNNER_TEMP: d, GITHUB_OUTPUT: join(d, 'out'),
      WRANGLER_VERSION: '4.158.0', STAGING_WORKER_NAME: 'datewise-coach-staging', ID_HASH_SALT: envSalt },
    encoding: 'utf8',
  });
  const file = join(d, 'salt.json');
  const has = existsSync(file);
  const out = readFileSync(join(d, 'out'), 'utf8');
  const value = has ? JSON.parse(readFileSync(file, 'utf8')).ID_HASH_SALT : null;
  return { code: r.status, out, has, mode: has ? statSync(file).mode & 0o777 : null, value, log: r.stdout + r.stderr };
}

function generated(r, envSalt = '') {
  assert.equal(r.code, 0, r.log);
  assert.match(r.out, /with_salt=true/);
  assert.equal(r.mode, 0o600);
  if (envSalt) assert.equal(r.value, envSalt);
  else assert.match(r.value, /^[0-9a-f]{64}$/);
  assert.ok(!r.log.includes(r.value) && !r.out.includes(r.value), 'the salt must never be printed');
}
const kept = (r) => { assert.equal(r.code, 0, r.log); assert.match(r.out, /with_salt=false/); assert.equal(r.has, false); };
const stopped = (r) => { assert.equal(r.code, 1, r.log); assert.equal(r.has, false); assert.ok(!/with_salt=true/.test(r.out)); };

test('production: a Worker without a salt gets a random one (secret list without it, empty list, Worker not found)', () => {
  generated(run(PROD, 'nosalt'));
  generated(run(PROD, 'empty'));
  generated(run(PROD, 'prodNotFound'));
});
test('production: the environment secret is used when set and the Worker has none', () => generated(run(PROD, 'nosalt', 'owner-chosen-salt'), 'owner-chosen-salt'));
test('production: an existing salt is kept, even if an environment secret is set', () => { kept(run(PROD, 'hassalt')); kept(run(PROD, 'hassalt', 'other')); });
test('production: an unreadable, malformed or errored secret list stops the deploy', () => {
  stopped(run(PROD, 'malformed'));
  stopped(run(PROD, 'wrapped'));
  stopped(run(PROD, 'apiError'));
});
test('staging: same rules with its own random salt', () => {
  generated(run(STG, 'nosalt'));
  generated(run(STG, 'stgNotFound'));
  kept(run(STG, 'hassalt'));
  stopped(run(STG, 'malformed'));
  stopped(run(STG, 'apiError'));
});
