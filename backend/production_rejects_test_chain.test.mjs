// PRODUCTION isolation: the production Worker (main = worker.js, the production [vars]) must refuse a token signed by
// a throwaway test chain, whatever the environment carries. This file imports ONLY worker.js, never staging_entry.js
// (node:test runs each file in its own process, so no staging trust leaks in).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';
import { makePki, txPayload } from './test/helpers.mjs';
import { chatRequest, makeEnv, parseToml, tomlSkip } from './test/staging_env_helpers.mjs';
import { makeStagingAuth } from '../tool/live/staging_auth.mjs';

const here = dirname(fileURLToPath(import.meta.url));

test('production config: a test-chain token is refused with SUBSCRIPTION_INVALID and no model call', { skip: tomlSkip }, async () => {
  const pki = await makePki();
  const jws = await pki.sign(txPayload({ environment: 'Sandbox' }));
  const env = makeEnv('production');
  const res = await worker.fetch(chatRequest(jws), env, {});
  assert.equal(res.status, 403);
  assert.equal((await res.json()).code, 'SUBSCRIPTION_INVALID');
  assert.equal(env.AI.calls.length, 0);
});

test('production config: a token minted by the live-test tool (valid, Sandbox, right ids) is refused, even if the environment names its root', { skip: tomlSkip }, async () => {
  const a = await makeStagingAuth();
  for (const extra of [{}, { STAGING_TEST_ROOT_CERT_B64: a.rootB64 }, { STAGING_TEST_ROOT_SHA256: a.rootSha256, TEST_ROOT: a.rootB64 }]) {
    const env = makeEnv('production', extra);
    const res = await worker.fetch(chatRequest(a.tokens[0]), env, {});
    assert.equal(res.status, 403, JSON.stringify(Object.keys(extra)));
    assert.equal((await res.json()).code, 'SUBSCRIPTION_INVALID');
    assert.equal(env.AI.calls.length, 0);
  }
});

test('production config: /?staging-neurons does not exist on the production Worker', { skip: tomlSkip }, async () => {
  const a = await makeStagingAuth();
  const res = await worker.fetch(new Request('https://worker.invalid/?staging-neurons', { headers: { 'X-DateWise-Entitlement': a.tokens[0] } }), makeEnv('production'), {});
  const text = await res.text();
  assert.ok(!/"cap"|"spent"|overCap/.test(text), text);
});

test('production wiring: main is worker.js, and nothing reachable from it knows the staging test root', { skip: tomlSkip }, () => {
  assert.equal(parseToml().main, 'worker.js');
  // Transitive local imports of worker.js.
  const seen = new Set();
  const walk = (file) => {
    if (seen.has(file)) return;
    seen.add(file);
    const src = readFileSync(join(here, file), 'utf8');
    for (const m of src.matchAll(/(?:import|export)[^'"]*?from\s+'(\.\/[^']+)'/g)) walk(m[1].slice(2));
  };
  walk('worker.js');
  assert.ok(seen.has('cost_guard.js') && seen.has('apple_jws.js'));
  assert.ok(!seen.has('staging_entry.js'));
  for (const f of seen) {
    const src = readFileSync(join(here, f), 'utf8');
    assert.ok(!/STAGING_TEST_ROOT|staging-neurons|staging_entry/.test(src), `${f} must not mention the staging test root`);
  }
});

test('the verifier-root override is used only by the staging entry (and tests)', () => {
  const users = readdirSync(here)
    .filter((f) => f.endsWith('.js'))
    .filter((f) => readFileSync(join(here, f), 'utf8').includes('_setTrustedRootsForTests'))
    .sort();
  assert.deepEqual(users, ['cost_guard.js', 'staging_entry.js']);
});
