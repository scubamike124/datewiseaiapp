#!/usr/bin/env node
// Throwaway StoreKit-shaped test authentication for the STAGING Worker only
// (docs/qa/STAGING_TEST_AUTH_THREAT_MODEL.md). One run:
//   1. generates a new CA (root -> intermediate -> leaf, Apple-shaped, backend/test/helpers.mjs) in memory;
//   2. writes the PUBLIC root certificate (DER, base64) to <out-dir>/root.b64;
//   3. signs --count test tokens (the same payload shape and the real bundle id, product id and Sandbox
//      environment, a fresh originalTransactionId each) and writes them, one per line, to <out-dir>/tokens (mode 0600);
//   4. exits. The private keys exist only in this process's memory: they are never written anywhere, never printed,
//      and are gone when the process ends.
// Validity: the root is valid for exactly 2 hours from now (the staging entry refuses a longer-lived root), and every
// token expires 50 minutes from now (the Worker accepts a token 60 minutes after expiresDate, so 110 minutes at most),
// i.e. everything stops working by itself inside 2 hours.
import { mkdirSync, writeFileSync, chmodSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { makePki, txPayload } from '../../backend/test/helpers.mjs';

export const ROOT_LIFETIME_MS = 2 * 60 * 60_000;
export const TOKEN_LIFETIME_MS = 50 * 60_000;
export const BUNDLE_ID = 'com.datewise.datewiseAi';
export const PRODUCT_ID = 'datewise_premium_monthly';

/** Returns { rootB64, rootSha256, notAfter, tokens: [jws] }. `now` is for tests. */
export async function makeStagingAuth({ count = 1, now = Date.now() } = {}) {
  if (!Number.isInteger(count) || count < 1 || count > 5) throw new Error('--count must be 1 to 5');
  const notBefore = now - 60_000; // a minute of clock skew; signedDate must lie inside the certificates' validity
  const notAfter = notBefore + ROOT_LIFETIME_MS;
  const pki = await makePki({ validFrom: notBefore, validTo: notAfter });
  const tokens = [];
  for (let i = 0; i < count; i++) {
    const id = `2000000${String(Math.floor(Math.random() * 1e9)).padStart(9, '0')}${i}`;
    tokens.push(
      await pki.sign(
        txPayload({
          bundleId: BUNDLE_ID,
          productId: PRODUCT_ID,
          environment: 'Sandbox',
          transactionId: id,
          originalTransactionId: id,
          purchaseDate: now - 60_000,
          originalPurchaseDate: now - 60_000,
          signedDate: now - 30_000,
          expiresDate: now + TOKEN_LIFETIME_MS,
        }),
      ),
    );
  }
  return { rootB64: Buffer.from(pki.certs.root).toString('base64'), rootSha256: pki.rootSha256, notAfter, tokens };
}

async function main(argv) {
  const { values } = parseArgs({ args: argv, options: { 'out-dir': { type: 'string' }, count: { type: 'string', default: '1' } } });
  if (!values['out-dir']) throw new Error('usage: staging_auth.mjs --out-dir DIR [--count N]');
  const dir = resolve(values['out-dir']);
  const a = await makeStagingAuth({ count: Number(values.count) });
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  writeFileSync(join(dir, 'root.b64'), a.rootB64 + '\n');
  writeFileSync(join(dir, 'tokens'), a.tokens.join('\n') + '\n', { mode: 0o600 });
  chmodSync(join(dir, 'tokens'), 0o600);
  // Public information only.
  console.log(`test root sha256 ${a.rootSha256}, valid until ${new Date(a.notAfter).toISOString()}; ${a.tokens.length} token(s) written (never printed)`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((e) => {
    console.error(`staging_auth: ${e.message}`);
    process.exit(2);
  });
}
