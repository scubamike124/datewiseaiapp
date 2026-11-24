"""Read-only App Store Connect check for DateWise (run by .github/workflows/asc-verify.yml).

GET requests only. Secret values are never printed: the output names each check
and its result, plus public facts (app name, product id, period, state, price).
Exit code 1 if any required check fails.
"""

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
SUMMARY = os.environ.get("GITHUB_STEP_SUMMARY")
lines = []
failed = []


def out(text):
    print(text)
    lines.append(text)


def check(name, ok, detail=""):
    mark = "PASS" if ok else "FAIL"
    out(f"- {mark}: {name}{(' - ' + detail) if detail else ''}")
    if not ok:
        failed.append(name)
    return ok


def note(name, detail):
    out(f"- INFO: {name} - {detail}")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # never send the token elsewhere
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def get(path, token, params=None):
    url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with OPENER.open(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode() or "{}")
        except Exception:
            body = {}
        return e.code, body
    except Exception as e:  # network error: report the type only
        return 0, {"errors": [{"code": type(e).__name__}]}


def err_code(body):
    errs = body.get("errors") or []
    return ",".join(str(x.get("code", "?"))[:60] for x in errs[:3]) or "none"


def finish():
    if SUMMARY:
        with open(SUMMARY, "a", encoding="utf-8") as f:
            f.write("### App Store Connect check (read-only)\n\n" + "\n".join(lines) + "\n")
    if failed:
        print(f"::error::{len(failed)} check(s) failed: " + "; ".join(failed))
        sys.exit(1)
    sys.exit(0)


def main():
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
    p8 = os.environ.get("ASC_KEY_P8", "")
    team = os.environ.get("APPLE_TEAM_ID", "").strip()
    bundle = os.environ["BUNDLE_ID"]
    product = os.environ["PRODUCT_ID"]
    expected_usd = os.environ["EXPECTED_USD"]

    # 1. Shapes (no values printed).
    check("APP_STORE_CONNECT_API_KEY_ID set, 10 capital letters/digits", bool(re.fullmatch(r"[A-Z0-9]{10}", key_id)))
    check("APP_STORE_CONNECT_ISSUER_ID set, UUID form",
          bool(re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", issuer)))
    check("APPLE_TEAM_ID set, 10 capital letters/digits", bool(re.fullmatch(r"[A-Z0-9]{10}", team)))
    p8 = p8.replace("\\n", "\n")
    check("APP_STORE_CONNECT_API_KEY_P8 set, PEM private key", "BEGIN PRIVATE KEY" in p8 and "END PRIVATE KEY" in p8)
    if failed:
        return finish()

    # 2. The key signs a token Apple accepts.
    try:
        now = int(time.time())
        token = jwt.encode({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                           p8, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})
    except Exception as e:
        check("the .p8 is a valid ES256 key", False, type(e).__name__)
        return finish()
    check("the .p8 is a valid ES256 key", True)

    status, body = get("/v1/apps", token, {"filter[bundleId]": bundle, "fields[apps]": "name,bundleId,sku,primaryLocale"})
    if not check("Apple accepts the key (Key ID + Issuer ID + .p8 match)", status == 200, f"HTTP {status} {err_code(body) if status != 200 else ''}".strip()):
        return finish()
    apps = body.get("data") or []
    if not check(f"app record with bundle {bundle} exists", len(apps) == 1, f"{len(apps)} found"):
        return finish()
    app = apps[0]
    note("app", f"{app['attributes'].get('name')} (Apple ID {app['id']})")

    # 3. The subscription: one group, one product, monthly, $19.99 in the US, no free trial.
    status, body = get(f"/v1/apps/{app['id']}/subscriptionGroups", token,
                       {"include": "subscriptions", "limit": "50", "limit[subscriptions]": "50"})
    if not check("subscription groups readable", status == 200, f"HTTP {status} {err_code(body)}" if status != 200 else ""):
        return finish()
    groups = body.get("data") or []
    subs = [x for x in (body.get("included") or []) if x.get("type") == "subscriptions"]
    note("subscription groups", str(len(groups)))
    note("subscriptions", ", ".join(f"{s['attributes'].get('productId')} [{s['attributes'].get('subscriptionPeriod')}, {s['attributes'].get('state')}]" for s in subs) or "none")
    mine = [s for s in subs if s["attributes"].get("productId") == product]
    if not check(f"subscription {product} exists", len(mine) == 1):
        return finish()
    check("it is the only subscription (no annual or other plans)", len(subs) == 1, f"{len(subs)} subscriptions")
    sub = mine[0]
    check("period is one month", sub["attributes"].get("subscriptionPeriod") == "ONE_MONTH", str(sub["attributes"].get("subscriptionPeriod")))
    note("state", str(sub["attributes"].get("state")))

    status, body = get(f"/v1/subscriptions/{sub['id']}/prices", token,
                       {"filter[territory]": "USA", "include": "subscriptionPricePoint", "limit": "50"})
    if check("US price readable", status == 200, f"HTTP {status} {err_code(body)}" if status != 200 else ""):
        points = {x["id"]: x for x in (body.get("included") or []) if x.get("type") == "subscriptionPricePoints"}
        prices = []
        for p in body.get("data") or []:
            pp = (p.get("relationships", {}).get("subscriptionPricePoint", {}).get("data") or {}).get("id")
            cp = points.get(pp, {}).get("attributes", {}).get("customerPrice")
            prices.append((p["attributes"].get("startDate"), cp))
        current = [cp for start, cp in prices if not start or start <= time.strftime("%Y-%m-%d")]
        note("US price schedule", ", ".join(f"{cp} from {start or 'start'}" for start, cp in prices) or "none")
        check(f"US price is ${expected_usd}", bool(current) and current[-1] is not None and f"{float(current[-1]):.2f}" == expected_usd,
              f"current {current[-1] if current else 'none'}")

    status, body = get(f"/v1/subscriptions/{sub['id']}/introductoryOffers", token, {"limit": "50"})
    if check("introductory offers readable", status == 200, f"HTTP {status} {err_code(body)}" if status != 200 else ""):
        offers = body.get("data") or []
        check("no free trial or introductory offer", len(offers) == 0, f"{len(offers)} offer(s)")

    # TestFlight builds (read-only): newest uploads, processing state, expiry, and beta review state.
    status, body = get("/v1/builds", token, {"filter[app]": app["id"], "sort": "-uploadedDate", "limit": "5",
                                              "fields[builds]": "version,uploadedDate,processingState,expired,expirationDate,minOsVersion",
                                              "include": "preReleaseVersion,buildBetaDetail",
                                              "fields[preReleaseVersions]": "version",
                                              "fields[buildBetaDetails]": "internalBuildState,externalBuildState"})
    if status == 200:
        inc = {(x["type"], x["id"]): x["attributes"] for x in body.get("included") or []}
        for b in body.get("data") or []:
            a = b["attributes"]
            rv = (b.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}).get("id")
            bd = (b.get("relationships", {}).get("buildBetaDetail", {}).get("data") or {}).get("id")
            ver = inc.get(("preReleaseVersions", rv), {}).get("version", "?")
            beta = inc.get(("buildBetaDetails", bd), {})
            note(f"build {ver} ({a.get('version')})", f"uploaded {str(a.get('uploadedDate'))[:16]}, processing {a.get('processingState')}, expired {a.get('expired')}, internal testing {beta.get('internalBuildState')}, external {beta.get('externalBuildState')}")
    else:
        note("TestFlight builds", f"HTTP {status} {err_code(body)}")
    status, body = get(f"/v1/apps/{app['id']}/betaGroups", token, {"fields[betaGroups]": "name,isInternalGroup,publicLinkEnabled,hasAccessToAllBuilds", "limit": "20"})
    groups = body.get("data") or [] if status == 200 else []
    note("TestFlight groups", ", ".join(f"{g['attributes'].get('name')} ({'internal' if g['attributes'].get('isInternalGroup') else 'external'})" for g in groups) or f"none (HTTP {status})")

    # 4. Informational: can this key manage signing (needed for cloud signing)?
    status, body = get("/v1/certificates", token, {"limit": "1"})
    note("key can read signing certificates (cloud signing needs this)", f"HTTP {status}" + ("" if status == 200 else f" {err_code(body)}"))
    status, body = get("/v1/bundleIds", token, {"filter[identifier]": bundle, "limit": "5"})
    found = status == 200 and any(x["attributes"].get("identifier") == bundle for x in body.get("data") or [])
    note(f"bundle ID {bundle} registered", "yes" if found else f"no / HTTP {status}")
    return finish()


if __name__ == "__main__":
    main()
