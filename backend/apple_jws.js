/**
 * Offline verification of App Store signed data (StoreKit 2 transaction JWS and
 * App Store Server Notifications v2), with WebCrypto only: free, no network,
 * no App Store Connect key.
 *
 * It follows what Apple's App Store Server Library does in
 * `SignedDataVerifier.verifyAndDecodeTransaction` (offline mode):
 *   1. header `alg` is ES256 and `x5c` holds [leaf, intermediate, root];
 *   2. the root is byte-identical to Apple Root CA - G3 (pinned by SHA-256);
 *   3. root signed the intermediate, the intermediate signed the leaf;
 *   4. every certificate is valid at the payload's `signedDate`;
 *   5. the leaf carries Apple's marker OID 1.2.840.113635.100.6.11.1 and the
 *      intermediate 1.2.840.113635.100.6.2.1;
 *   6. basicConstraints: the intermediate is a CA, the leaf is not, the root
 *      is not marked "not a CA"; no certificate has an unknown critical extension;
 *   7. the leaf key verifies the JWS signature.
 * Online OCSP revocation checks are not done (offline by design).
 *
 * Apple Root CA - G3: https://www.apple.com/certificateauthority/ (AppleRootCA-G3.cer)
 * SHA-256 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
 */

export const APPLE_ROOT_CA_G3_SHA256 =
  '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179';

const OID_LEAF_MARKER = '1.2.840.113635.100.6.11.1';
const OID_INTERMEDIATE_MARKER = '1.2.840.113635.100.6.2.1';
const OID_BASIC_CONSTRAINTS = '2.5.29.19';
// Extensions this verifier understands; any other extension marked critical is refused (RFC 5280 4.2).
const KNOWN_EXTENSIONS = new Set([
  OID_BASIC_CONSTRAINTS,
  '2.5.29.15', // keyUsage
  '2.5.29.37', // extKeyUsage
  '2.5.29.14', // subjectKeyIdentifier
  '2.5.29.35', // authorityKeyIdentifier
  '2.5.29.32', // certificatePolicies
  '2.5.29.31', // cRLDistributionPoints
  '1.3.6.1.5.5.7.1.1', // authorityInfoAccess
  OID_LEAF_MARKER,
  OID_INTERMEDIATE_MARKER,
]);
const SIG_ALGS = {
  '1.2.840.10045.4.3.2': 'SHA-256',
  '1.2.840.10045.4.3.3': 'SHA-384',
};
const CURVES = {
  '1.2.840.10045.3.1.7': { name: 'P-256', size: 32 },
  '1.3.132.0.34': { name: 'P-384', size: 48 },
};

export class JwsError extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

// --- base64 helpers -------------------------------------------------------
function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function b64urlToBytes(s) {
  if (!/^[A-Za-z0-9_-]*$/.test(s)) throw new JwsError('bad_base64url');
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/');
  return b64ToBytes(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
}
const utf8 = new TextDecoder();
export async function sha256Hex(bytes) {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return [...d].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// --- minimal DER reader (just enough for X.509 v3 with EC keys) -------------
function readTlv(buf, pos) {
  if (pos + 2 > buf.length) throw new JwsError('der_truncated');
  const tag = buf[pos];
  let len = buf[pos + 1];
  let hdr = 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n < 1 || n > 3 || pos + 2 + n > buf.length) throw new JwsError('der_length');
    len = 0;
    for (let i = 0; i < n; i++) len = (len << 8) | buf[pos + 2 + i];
    hdr += n;
  }
  const start = pos + hdr;
  const end = start + len;
  if (end > buf.length) throw new JwsError('der_truncated');
  return { tag, start, end, hdrStart: pos };
}
function children(buf, tlv) {
  const out = [];
  let p = tlv.start;
  while (p < tlv.end) {
    const c = readTlv(buf, p);
    out.push(c);
    p = c.end;
  }
  return out;
}
function oidToString(bytes) {
  const parts = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let v = 0;
  for (let i = 1; i < bytes.length; i++) {
    v = v * 128 + (bytes[i] & 0x7f);
    if (!(bytes[i] & 0x80)) {
      parts.push(v);
      v = 0;
    }
  }
  return parts.join('.');
}
function readOid(buf, tlv) {
  if (tlv.tag !== 0x06) throw new JwsError('der_expected_oid');
  return oidToString(buf.subarray(tlv.start, tlv.end));
}
function readTime(buf, tlv) {
  const s = utf8.decode(buf.subarray(tlv.start, tlv.end));
  let m;
  if (tlv.tag === 0x17 && (m = s.match(/^(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)Z$/))) {
    const yy = +m[1];
    return Date.UTC(yy < 50 ? 2000 + yy : 1900 + yy, +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  }
  if (tlv.tag === 0x18 && (m = s.match(/^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)Z$/))) {
    return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  }
  throw new JwsError('der_time');
}

/** Parses the parts of an X.509 certificate this verifier needs. */
export function parseCertificate(der) {
  const cert = readTlv(der, 0);
  if (cert.tag !== 0x30 || cert.end !== der.length) throw new JwsError('cert_shape');
  const [tbs, sigAlg, sigVal] = children(der, cert);
  if (!tbs || !sigAlg || !sigVal || sigVal.tag !== 0x03) throw new JwsError('cert_shape');
  const tbsKids = children(der, tbs);
  let i = 0;
  if (tbsKids[0].tag === 0xa0) i = 1; // [0] version
  // serial, signature, issuer, validity, subject, spki, [extensions]
  const validity = children(der, tbsKids[i + 3]);
  const spki = tbsKids[i + 5];
  const spkiAlg = children(der, children(der, spki)[0]);
  const keyAlg = readOid(der, spkiAlg[0]);
  if (keyAlg !== '1.2.840.10045.2.1') throw new JwsError('cert_key_not_ec');
  const curve = CURVES[readOid(der, spkiAlg[1])];
  if (!curve) throw new JwsError('cert_curve');
  const extOids = [];
  let isCa = null; // null: no basicConstraints extension
  const extWrap = tbsKids.slice(i + 6).find((t) => t.tag === 0xa3);
  if (extWrap) {
    const exts = children(der, children(der, extWrap)[0]);
    for (const e of exts) {
      const parts = children(der, e); // extnID, [critical BOOLEAN], extnValue OCTET STRING
      const id = readOid(der, parts[0]);
      const critical = parts.length === 3 && parts[1].tag === 0x01 && der[parts[1].start] !== 0;
      if (critical && !KNOWN_EXTENSIONS.has(id)) throw new JwsError('unknown_critical_extension');
      if (id === OID_BASIC_CONSTRAINTS) {
        const value = parts[parts.length - 1];
        const bc = readTlv(der, value.start); // SEQUENCE { cA BOOLEAN DEFAULT FALSE, pathLen INTEGER OPTIONAL }
        const first = children(der, bc)[0];
        isCa = Boolean(first && first.tag === 0x01 && der[first.start] !== 0);
      }
      extOids.push(id);
    }
  }
  const sigBits = der.subarray(sigVal.start + 1, sigVal.end); // skip unused-bits byte
  return {
    tbs: der.subarray(tbs.hdrStart, tbs.end),
    sigHash: SIG_ALGS[readOid(der, children(der, sigAlg)[0])],
    signature: sigBits,
    notBefore: readTime(der, validity[0]),
    notAfter: readTime(der, validity[1]),
    spki: der.subarray(spki.hdrStart, spki.end),
    curve,
    extOids,
    isCa,
  };
}

// DER ECDSA signature (SEQUENCE { r INTEGER, s INTEGER }) -> raw r||s for WebCrypto.
function derSigToRaw(sig, size) {
  const seq = readTlv(sig, 0);
  const [r, s] = children(sig, seq);
  const out = new Uint8Array(size * 2);
  const put = (tlv, off) => {
    let b = sig.subarray(tlv.start, tlv.end);
    while (b.length > size && b[0] === 0) b = b.subarray(1);
    if (b.length > size) throw new JwsError('sig_int_too_long');
    out.set(b, off + size - b.length);
  };
  put(r, 0);
  put(s, size);
  return out;
}

async function importKey(cert) {
  return crypto.subtle.importKey('spki', cert.spki, { name: 'ECDSA', namedCurve: cert.curve.name }, false, ['verify']);
}

async function verifySignedBy(child, issuer) {
  if (!child.sigHash) throw new JwsError('cert_sig_alg');
  const key = await importKey(issuer);
  const ok = await crypto.subtle.verify(
    { name: 'ECDSA', hash: child.sigHash },
    key,
    derSigToRaw(child.signature, issuer.curve.size),
    child.tbs,
  );
  if (!ok) throw new JwsError('chain_signature');
}

/**
 * Verifies a compact JWS signed by the App Store and returns its decoded payload.
 * Throws JwsError (with `.reason`) on any failure; never returns unverified data.
 *
 * options.trustedRootSha256: list of accepted root fingerprints (default: Apple Root CA - G3 only).
 * options.now: current time in ms (for the not-from-the-future check).
 * options.maxLength: longest accepted JWS (default 16,000 characters; a
 *   notification nests two signed JWS, so its caller allows 64,000).
 */
export async function verifyAppleJws(jws, options = {}) {
  const roots = options.trustedRootSha256 || [APPLE_ROOT_CA_G3_SHA256];
  const now = options.now ?? Date.now();
  const maxLength = options.maxLength ?? 16_000;
  if (typeof jws !== 'string' || jws.length > maxLength) throw new JwsError('jws_shape');
  const parts = jws.split('.');
  if (parts.length !== 3 || parts.some((p) => !p)) throw new JwsError('jws_shape');
  let header;
  let payload;
  try {
    header = JSON.parse(utf8.decode(b64urlToBytes(parts[0])));
    payload = JSON.parse(utf8.decode(b64urlToBytes(parts[1])));
  } catch {
    throw new JwsError('jws_json');
  }
  if (!header || header.alg !== 'ES256') throw new JwsError('jws_alg');
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) throw new JwsError('jws_x5c');
  if (!payload || typeof payload !== 'object') throw new JwsError('jws_json');

  let ders;
  try {
    ders = header.x5c.map((c) => b64ToBytes(String(c)));
  } catch {
    throw new JwsError('jws_x5c');
  }
  const rootFp = await sha256Hex(ders[2]);
  if (!roots.includes(rootFp)) throw new JwsError('untrusted_root');

  const [leaf, intermediate, root] = ders.map(parseCertificate);
  if (!leaf.extOids.includes(OID_LEAF_MARKER)) throw new JwsError('leaf_marker');
  if (!intermediate.extOids.includes(OID_INTERMEDIATE_MARKER)) throw new JwsError('intermediate_marker');
  if (leaf.isCa === true) throw new JwsError('leaf_is_ca');
  if (intermediate.isCa !== true) throw new JwsError('intermediate_not_ca');
  // The root is pinned by fingerprint; it must not say it is not a CA.
  // (Apple Root CA - G3 has CA:TRUE; Apple's library test root has no extensions.)
  if (root.isCa === false) throw new JwsError('root_not_ca');
  await verifySignedBy(intermediate, root);
  await verifySignedBy(leaf, intermediate);

  // Apple validates the chain at signedDate when online checks are off.
  const signedDate = Number(payload.signedDate);
  if (!Number.isFinite(signedDate)) throw new JwsError('no_signed_date');
  if (signedDate > now + 5 * 60_000) throw new JwsError('signed_in_future');
  for (const c of [leaf, intermediate, root]) {
    if (signedDate < c.notBefore || signedDate > c.notAfter) throw new JwsError('cert_validity');
  }
  if (leaf.curve.name !== 'P-256') throw new JwsError('leaf_curve');

  const ok = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    await importKey(leaf),
    b64urlToBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new JwsError('jws_signature');
  return payload;
}
