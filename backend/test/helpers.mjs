// Test helpers for the chat-v7 Worker: an in-memory Durable Object namespace
// that serializes requests per object (as Cloudflare does), and a throwaway
// test PKI shaped like Apple's (root -> intermediate -> leaf, with Apple's
// marker OIDs) to sign StoreKit-style JWS. Nothing here touches the network.
import { UsageGuard } from '../cost_guard.js';
import { sha256Hex } from '../apple_jws.js';

// --- Durable Objects ---------------------------------------------------------
export function fakeDoNamespace({ fail = false } = {}) {
  const objects = new Map();
  const ns = {
    requests: 0,
    objects,
    idFromName: (name) => name,
    get(id) {
      if (!objects.has(id)) {
        const data = new Map();
        const storage = {
          async get(k) {
            await null;
            return data.has(k) ? structuredClone(data.get(k)) : undefined;
          },
          async put(k, v) {
            await null;
            data.set(k, structuredClone(v));
          },
        };
        objects.set(id, { instance: new UsageGuard({ storage }), queue: Promise.resolve(), data });
      }
      const o = objects.get(id);
      return {
        fetch(url, init) {
          ns.requests++;
          if (fail) return Promise.reject(new Error('DO unavailable'));
          // One request at a time per object, like a real Durable Object.
          const run = o.queue.then(() => o.instance.fetch(new Request(url, init)));
          o.queue = run.catch(() => {});
          return run;
        },
      };
    },
  };
  return ns;
}

// --- Workers AI --------------------------------------------------------------
export const SSE = 'data: {"response":"Hola"}\n\ndata: {"response":"!"}\n\ndata: {"response":"","usage":{"prompt_tokens":900,"completion_tokens":12}}\n\ndata: [DONE]\n\n';

export function fakeAi(reply = () => new Response(SSE).body) {
  const calls = [];
  return {
    calls,
    async run(model, input) {
      calls.push({ model, input });
      return reply(model, input);
    },
  };
}

// A stream that stays open until release() is called (to hold requests in flight).
export function heldStream() {
  let release;
  const gate = new Promise((r) => (release = r));
  const enc = new TextEncoder();
  const body = new ReadableStream({
    async start(controller) {
      controller.enqueue(enc.encode('data: {"response":"…"}\n\n'));
      await gate;
      controller.enqueue(enc.encode('data: [DONE]\n\n'));
      controller.close();
    },
  });
  return { body, release };
}

// --- a throwaway PKI shaped like Apple's ----------------------------------------
const OIDS = {
  ecPublicKey: '1.2.840.10045.2.1',
  ecdsaSha256: '1.2.840.10045.4.3.2',
  ecdsaSha384: '1.2.840.10045.4.3.3',
  cn: '2.5.4.3',
  leafMarker: '1.2.840.113635.100.6.11.1',
  intermediateMarker: '1.2.840.113635.100.6.2.1',
  basicConstraints: '2.5.29.19',
};

const cat = (...parts) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
};
function len(n) {
  if (n < 0x80) return Uint8Array.of(n);
  const b = [];
  while (n) {
    b.unshift(n & 0xff);
    n >>= 8;
  }
  return Uint8Array.of(0x80 | b.length, ...b);
}
const tlv = (tag, body) => cat(Uint8Array.of(tag), len(body.length), body);
const seq = (...items) => tlv(0x30, cat(...items));
function oid(s) {
  const p = s.split('.').map(Number);
  const out = [40 * p[0] + p[1]];
  for (const v of p.slice(2)) {
    const b = [v & 0x7f];
    let x = Math.floor(v / 128);
    while (x) {
      b.unshift(0x80 | (x & 0x7f));
      x = Math.floor(x / 128);
    }
    out.push(...b);
  }
  return tlv(0x06, Uint8Array.from(out));
}
function int(bytes) {
  let b = bytes;
  while (b.length > 1 && b[0] === 0 && !(b[1] & 0x80)) b = b.subarray(1);
  if (b[0] & 0x80) b = cat(Uint8Array.of(0), b);
  return tlv(0x02, b);
}
const name = (cn) => seq(tlv(0x31, seq(oid(OIDS.cn), tlv(0x0c, new TextEncoder().encode(cn)))));
function utcTime(ms) {
  const d = new Date(ms).toISOString(); // 2026-11-22T10:00:00.000Z
  const s = d.slice(2, 4) + d.slice(5, 7) + d.slice(8, 10) + d.slice(11, 13) + d.slice(14, 16) + d.slice(17, 19) + 'Z';
  return tlv(0x17, new TextEncoder().encode(s));
}

async function genKey(curve) {
  return crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: curve }, true, ['sign', 'verify']);
}

async function makeCert({ subject, issuer, publicKey, signKey, signHash, signCurveSize, markers = [], notBefore, notAfter, ca, criticalUnknown }) {
  const spki = new Uint8Array(await crypto.subtle.exportKey('spki', publicKey));
  const sigAlg = seq(oid(signHash === 'SHA-384' ? OIDS.ecdsaSha384 : OIDS.ecdsaSha256));
  const exts = [
    ...markers.map((m) => seq(oid(m), tlv(0x04, Uint8Array.of(0x05, 0x00)))),
    ...(ca ? [seq(oid(OIDS.basicConstraints), tlv(0x01, Uint8Array.of(0xff)), tlv(0x04, seq(tlv(0x01, Uint8Array.of(0xff)))))] : []),
    ...(criticalUnknown ? [seq(oid('1.2.3.4.5'), tlv(0x01, Uint8Array.of(0xff)), tlv(0x04, Uint8Array.of(0x05, 0x00)))] : []),
  ];
  const tbs = seq(
    tlv(0xa0, int(Uint8Array.of(2))),
    int(crypto.getRandomValues(new Uint8Array(8))),
    sigAlg,
    name(issuer),
    seq(utcTime(notBefore), utcTime(notAfter)),
    name(subject),
    spki,
    ...(exts.length ? [tlv(0xa3, seq(...exts))] : []),
  );
  const raw = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: signHash }, signKey, tbs));
  const sig = seq(int(raw.subarray(0, signCurveSize)), int(raw.subarray(signCurveSize)));
  return seq(tbs, sigAlg, tlv(0x03, cat(Uint8Array.of(0), sig)));
}

const b64 = (bytes) => Buffer.from(bytes).toString('base64');
const b64url = (bytes) => Buffer.from(bytes).toString('base64url');

/**
 * A test PKI: root (P-384) -> intermediate (P-384, SHA-384) -> leaf (P-256,
 * SHA-256), like Apple's. Options drop a marker OID or shift validity.
 */
export async function makePki({ leafMarker = true, intermediateMarker = true, leafCa = false, intermediateCa = true, criticalUnknown = false, validFrom = Date.now() - 365 * 86_400_000, validTo = Date.now() + 365 * 86_400_000 } = {}) {
  const rootKey = await genKey('P-384');
  const intKey = await genKey('P-384');
  const leafKey = await genKey('P-256');
  const common = { notBefore: validFrom, notAfter: validTo };
  const root = await makeCert({ ...common, subject: 'Test Root', issuer: 'Test Root', publicKey: rootKey.publicKey, signKey: rootKey.privateKey, signHash: 'SHA-384', signCurveSize: 48, ca: true });
  const intermediate = await makeCert({ ...common, subject: 'Test WWDR', issuer: 'Test Root', publicKey: intKey.publicKey, signKey: rootKey.privateKey, signHash: 'SHA-384', signCurveSize: 48, markers: intermediateMarker ? [OIDS.intermediateMarker] : [], ca: intermediateCa });
  const leaf = await makeCert({ ...common, subject: 'Test StoreKit', issuer: 'Test WWDR', publicKey: leafKey.publicKey, signKey: intKey.privateKey, signHash: 'SHA-384', signCurveSize: 48, markers: leafMarker ? [OIDS.leafMarker] : [], ca: leafCa, criticalUnknown });
  const rootSha256 = await sha256Hex(root);
  async function sign(payload, header = {}) {
    const h = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', x5c: [b64(leaf), b64(intermediate), b64(root)], ...header })));
    const p = b64url(new TextEncoder().encode(JSON.stringify(payload)));
    const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, leafKey.privateKey, new TextEncoder().encode(`${h}.${p}`)));
    return `${h}.${p}.${b64url(sig)}`;
  }
  return { rootSha256, sign, certs: { root, intermediate, leaf } };
}

/** A StoreKit 2-style signed transaction payload (JWSTransactionDecodedPayload fields). */
export function txPayload(over = {}) {
  const now = Date.now();
  return {
    transactionId: '2000000123456789',
    originalTransactionId: '2000000000000001',
    bundleId: 'com.datewise.datewiseAi',
    productId: 'datewise_premium_monthly',
    purchaseDate: now - 86_400_000,
    originalPurchaseDate: now - 30 * 86_400_000,
    expiresDate: now + 29 * 86_400_000,
    type: 'Auto-Renewable Subscription',
    inAppOwnershipType: 'PURCHASED',
    signedDate: now - 60_000,
    environment: 'Production',
    ...over,
  };
}
