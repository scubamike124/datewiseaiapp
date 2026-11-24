"""Upload the App Store review screenshot for the DateWise subscription (owner-approved write).

Run only by the gated `review-screenshot` job in .github/workflows/asc-verify.yml (commit message contains
[asc-screenshot] and the owner approves the run in the app-store-connect-write environment).

What it does, and nothing else:
  1. Finds the subscription PRODUCT_ID in the app with BUNDLE_ID.
  2. If it already has a review screenshot that finished processing, it stops (idempotent).
  3. Otherwise it reserves the screenshot, uploads the PNG in Apple's chunks, commits it with its MD5 checksum,
     and waits until Apple reports the asset as COMPLETE.
It never deletes, edits prices, territories, offers or any other setting, and it never prints secrets.
A missing review screenshot keeps a subscription in MISSING_METADATA, and StoreKit does not serve such a
product to TestFlight or the sandbox.
"""

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT, with cryptography for ES256

API = "https://api.appstoreconnect.apple.com"
MAX_BYTES = 10 * 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # never send the token elsewhere
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def call(method, path, token, payload=None, params=None):
    url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with OPENER.open(req, timeout=60) as r:
            raw = r.read().decode()
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode() or "{}")
        except Exception:
            body = {}
        return e.code, body


def errors(body):
    return "; ".join(f"{e.get('code')}: {e.get('detail') or e.get('title')}" for e in body.get("errors") or [])[:400]


def main():
    key_id, issuer, p8 = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_P8"]
    bundle, product, path = os.environ["BUNDLE_ID"], os.environ["PRODUCT_ID"], os.environ["SCREENSHOT"]
    blob = open(path, "rb").read()
    if not blob.startswith(b"\x89PNG") or len(blob) > MAX_BYTES:
        sys.exit("screenshot must be a PNG under 10 MB")
    now = int(time.time())
    token = jwt.encode({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}, p8,
                       algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})

    s, b = call("GET", "/v1/apps", token, params={"filter[bundleId]": bundle, "limit": "2"})
    apps = [a for a in b.get("data") or [] if a["attributes"].get("bundleId") == bundle]
    if s != 200 or len(apps) != 1:
        sys.exit(f"app {bundle} not found (HTTP {s})")
    s, b = call("GET", f"/v1/apps/{apps[0]['id']}/subscriptionGroups", token,
                params={"include": "subscriptions", "limit": "50", "limit[subscriptions]": "50"})
    subs = [x for x in b.get("included") or [] if x.get("type") == "subscriptions" and x["attributes"].get("productId") == product]
    if s != 200 or len(subs) != 1:
        sys.exit(f"subscription {product} not found (HTTP {s})")
    sub = subs[0]
    print(f"subscription {product}: state {sub['attributes'].get('state')}")

    s, b = call("GET", f"/v1/subscriptions/{sub['id']}/appStoreReviewScreenshot", token)
    existing = (b.get("data") or None) if s == 200 else None
    if existing:
        state = ((existing["attributes"].get("assetDeliveryState") or {}).get("state"))
        print(f"a review screenshot already exists (delivery {state})")
        if state == "COMPLETE":
            print("nothing to do")
            return
        sys.exit("an existing screenshot is not COMPLETE; inspect it in App Store Connect (this script never deletes)")

    name = os.path.basename(path)
    s, b = call("POST", "/v1/subscriptionAppStoreReviewScreenshots", token, {
        "data": {"type": "subscriptionAppStoreReviewScreenshots",
                 "attributes": {"fileName": name, "fileSize": len(blob)},
                 "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub["id"]}}}}})
    if s != 201:
        sys.exit(f"reserve failed: HTTP {s} {errors(b)}")
    shot = b["data"]
    ops = shot["attributes"].get("uploadOperations") or []
    print(f"reserved screenshot, {len(ops)} upload part(s)")
    for op in ops:
        part = blob[op["offset"]: op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        req = urllib.request.Request(op["url"], data=part, method=op.get("method", "PUT"), headers=headers)
        with urllib.request.urlopen(req, timeout=120) as r:  # Apple's pre-signed upload URL; no token is sent
            if r.status not in (200, 201, 204):
                sys.exit(f"upload part failed: HTTP {r.status}")
    md5 = hashlib.md5(blob).hexdigest()
    s, b = call("PATCH", f"/v1/subscriptionAppStoreReviewScreenshots/{shot['id']}", token, {
        "data": {"type": "subscriptionAppStoreReviewScreenshots", "id": shot["id"],
                 "attributes": {"uploaded": True, "sourceFileChecksum": md5}}})
    if s != 200:
        sys.exit(f"commit failed: HTTP {s} {errors(b)}")
    for _ in range(30):
        s, b = call("GET", f"/v1/subscriptionAppStoreReviewScreenshots/{shot['id']}", token)
        state = ((b.get("data") or {}).get("attributes", {}).get("assetDeliveryState") or {}).get("state")
        print(f"delivery state: {state}")
        if state == "COMPLETE":
            break
        if state == "FAILED":
            sys.exit(f"Apple rejected the file: {json.dumps(((b.get('data') or {}).get('attributes', {}).get('assetDeliveryState') or {}).get('errors'))[:400]}")
        time.sleep(10)
    else:
        sys.exit("Apple has not finished processing the screenshot after 5 minutes; re-run the check later")
    s, b = call("GET", f"/v1/subscriptions/{sub['id']}", token)
    print(f"subscription state now: {(b.get('data') or {}).get('attributes', {}).get('state')} (Apple can take a few minutes to update it)")


if __name__ == "__main__":
    main()
