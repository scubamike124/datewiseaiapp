// Shared by the staging-auth tests: wrangler.toml vars, an env for the Worker, and a chat request.
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { fakeAi, fakeDoNamespace } from './helpers.mjs';

const TOML = fileURLToPath(new URL('../wrangler.toml', import.meta.url));
export const hasTomllib = spawnSync('python3', ['-c', 'import tomllib'], { stdio: 'ignore' }).status === 0;
export const tomlSkip = hasTomllib ? false : 'needs python3 3.11+ (tomllib)';

export const parseToml = () =>
  JSON.parse(execFileSync('python3', ['-c', 'import json,sys,tomllib; print(json.dumps(tomllib.load(open(sys.argv[1], "rb"))))', TOML], { encoding: 'utf8' }));

/** Worker env with the real [vars] of production ('production') or [env.staging.vars] ('staging'). */
export function makeEnv(which, extra = {}) {
  const cfg = parseToml();
  const vars = which === 'staging' ? cfg.env.staging.vars : cfg.vars;
  return { ...vars, ID_HASH_SALT: 'test-salt', AI: fakeAi(), USAGE_GUARD: fakeDoNamespace(), ...extra };
}

export const chatRequest = (jws, path = '/') =>
  new Request(`https://worker.invalid${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-DateWise-Entitlement': jws },
    body: JSON.stringify({ coachId: 'ava', profile: { language: 'en' }, messages: [{ role: 'user', content: 'Hi' }] }),
  });
