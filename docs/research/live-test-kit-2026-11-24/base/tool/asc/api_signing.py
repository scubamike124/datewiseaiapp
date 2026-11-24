"""App Store Connect API signing for .github/workflows/ios-build.yml (signing: api).

Two commands, run on the macOS runner with PyJWT and cryptography in a venv
(the same approach as tool/asc/verify_asc.py on claude/asc-verify):

  create   POST a new Apple Distribution certificate for a CSR made on the
           runner, look up the existing bundle id (never creates one), POST an
           IOS_APP_STORE profile for it, and write the certificate (DER) and
           the profile into OUT_DIR. Each created id is saved to STATE_FILE as
           soon as Apple returns it, so cleanup can undo a partial run.
  cleanup  DELETE the profile, and revoke (DELETE) the certificate when
           REVOKE_CERT is "true", using the ids in STATE_FILE.

Only ids, types and HTTP status / Apple error codes are printed. The .p8, the
token, the CSR, the certificate and the profile contents are never printed.
"""

import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT, with cryptography for ES256

API = "https://api.appstoreconnect.apple.com"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # never send the token elsewhere
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)


def token():
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
    p8 = os.environ.get("ASC_KEY_P8", "").replace("\\n", "\n")
    if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
        fail("APP_STORE_CONNECT_API_KEY_ID must be the 10-character Key ID.")
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", issuer):
        fail("APP_STORE_CONNECT_ISSUER_ID must be the Issuer ID (UUID form).")
    if "BEGIN PRIVATE KEY" not in p8:
        fail("APP_STORE_CONNECT_API_KEY_P8 must be the full .p8 text, including the BEGIN/END lines.")
    now = int(time.time())
    try:
        # Apple accepts at most 20 minutes; a fresh token is made per request.
        return jwt.encode({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                          p8, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})
    except Exception as e:
        fail(f"the .p8 is not a valid ES256 key ({type(e).__name__}).")


def call(method, path, params=None, body=None):
    url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token()}"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with OPENER.open(req, timeout=60) as r:
            raw = r.read().decode()
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except Exception:
            return e.code, {}
    except Exception as e:  # network error: report the type only
        return 0, {"errors": [{"code": type(e).__name__}]}


def codes(body):
    errs = body.get("errors") or []
    return ",".join(str(x.get("code", "?"))[:60] for x in errs[:3]) or "none"


def load_state(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save_state(path, state):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(state, f)


def create():
    bundle = os.environ["BUNDLE_ID"]
    csr_file = os.environ["CSR_FILE"]
    out_dir = os.environ["OUT_DIR"]
    state_file = os.environ["STATE_FILE"]
    profile_name = os.environ["PROFILE_NAME"]
    if not re.fullmatch(r"[A-Za-z0-9 _-]{1,50}", profile_name):
        fail("PROFILE_NAME may use only letters, digits, space, _ and -.")
    state = load_state(state_file)

    # 1. The existing bundle id (never created here).
    status, body = call("GET", "/v1/bundleIds", {"filter[identifier]": bundle, "limit": "200",
                                                 "fields[bundleIds]": "identifier,platform"})
    if status != 200:
        fail(f"GET /v1/bundleIds: HTTP {status} {codes(body)}")
    ids = [b for b in body.get("data") or []
           if b.get("attributes", {}).get("identifier") == bundle
           and b.get("attributes", {}).get("platform") in ("IOS", "UNIVERSAL")]
    if len(ids) != 1:
        fail(f"Bundle id {bundle} not found for iOS ({len(ids)} exact matches). Register it in "
             "Certificates, Identifiers & Profiles; this workflow does not create it.")
    bundle_res = ids[0]["id"]
    print(f"bundleId: id={bundle_res} platform={ids[0]['attributes'].get('platform')}")

    # 2. A new Apple Distribution certificate for the runner's CSR.
    with open(csr_file, encoding="ascii") as f:
        csr = f.read()
    status, body = call("POST", "/v1/certificates", body={"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION", "csrContent": csr}}})
    if status != 201:
        hint = " The team may be at Apple's limit of distribution certificates; revoke an unused one." if status == 409 else ""
        hint += " The key's role may not allow creating certificates." if status == 403 else ""
        fail(f"POST /v1/certificates (DISTRIBUTION): HTTP {status} {codes(body)}.{hint}")
    cert = body["data"]
    state["certificate_id"] = cert["id"]
    save_state(state_file, state)
    print(f"certificate: created id={cert['id']} type={cert['attributes'].get('certificateType')} HTTP {status}")
    with open(os.path.join(out_dir, "dist.cer"), "wb") as f:
        f.write(base64.b64decode(cert["attributes"]["certificateContent"]))

    # 3. A new App Store profile for the bundle id and that certificate.
    status, body = call("POST", "/v1/profiles", body={"data": {
        "type": "profiles",
        "attributes": {"name": profile_name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_res}},
            "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
        }}})
    if status != 201:
        fail(f"POST /v1/profiles (IOS_APP_STORE): HTTP {status} {codes(body)}")
    prof = body["data"]
    state["profile_id"] = prof["id"]
    save_state(state_file, state)
    print(f"profile: created id={prof['id']} type={prof['attributes'].get('profileType')} "
          f"state={prof['attributes'].get('profileState')} HTTP {status}")
    with open(os.path.join(out_dir, "profile.mobileprovision"), "wb") as f:
        f.write(base64.b64decode(prof["attributes"]["profileContent"]))


def cleanup():
    state_file = os.environ["STATE_FILE"]
    revoke = os.environ.get("REVOKE_CERT", "true") == "true"
    state = load_state(state_file)
    problems = []
    pid = state.get("profile_id")
    if pid:
        status, body = call("DELETE", f"/v1/profiles/{pid}")
        print(f"profile: delete id={pid} HTTP {status}")
        if status not in (204, 404):
            problems.append(f"profile {pid} not deleted (HTTP {status} {codes(body)})")
    cid = state.get("certificate_id")
    if cid and revoke:
        status, body = call("DELETE", f"/v1/certificates/{cid}")
        print(f"certificate: revoke id={cid} HTTP {status}")
        if status not in (204, 404):
            problems.append(f"certificate {cid} not revoked (HTTP {status} {codes(body)})")
    elif cid:
        print(f"::warning::Certificate {cid} was kept (revoke_api_cert=false). It counts toward Apple's "
              "distribution certificate limit until revoked in Certificates, Identifiers & Profiles.")
    if not pid and not cid:
        print("Nothing was created; nothing to clean up.")
    if problems:
        fail("Cleanup incomplete, remove by hand in Certificates, Identifiers & Profiles: " + "; ".join(problems))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "create":
        create()
    elif cmd == "cleanup":
        cleanup()
    else:
        fail("usage: api_signing.py create|cleanup")
