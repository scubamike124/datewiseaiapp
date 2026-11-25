#!/usr/bin/env python3
"""Read-only check of the DateWise subscription's App Store Connect metadata.

Reads only (GET). Uses the existing App Store Connect client in api_signing.py (the same key secrets as the iOS
build). Prints a short report: the subscription's state, and exactly which metadata is missing. Never prints a
token, key or response body.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (same as api_signing.py).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from api_signing import call  # noqa: E402

BUNDLE_ID = "com.datewise.datewiseAi"
PRODUCT_ID = "datewise_premium_monthly"


def data(body):
    d = body.get("data", [])
    return d if isinstance(d, list) else [d] if d else []


def main():
    status, body = call("GET", "/v1/apps", {"filter[bundleId]": BUNDLE_ID, "limit": "2"})
    apps = data(body)
    if status != 200 or not apps:
        print(json.dumps({"ok": False, "step": "find app", "http": status, "apps": len(apps)}))
        return 1
    app_id = apps[0]["id"]

    status, body = call("GET", f"/v1/apps/{app_id}/subscriptionGroups", {"limit": "50"})
    groups = data(body)
    found = None
    for g in groups:
        s, b = call("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptions", {"limit": "50"})
        for sub in data(b) if s == 200 else []:
            if sub.get("attributes", {}).get("productId") == PRODUCT_ID:
                found = sub
                break
        if found:
            break

    report = {"bundleId": BUNDLE_ID, "productId": PRODUCT_ID, "subscriptionGroups": len(groups)}
    if not found:
        report["found"] = False
        report["missing"] = ["the subscription product does not exist in App Store Connect"]
        print(json.dumps(report, indent=2))
        return 0

    sub_id = found["id"]
    attrs = found.get("attributes", {})
    report.update({"found": True, "state": attrs.get("state"), "name": attrs.get("name"),
                   "period": attrs.get("subscriptionPeriod")})

    s, b = call("GET", f"/v1/subscriptions/{sub_id}/subscriptionLocalizations", {"limit": "50"})
    locs = data(b) if s == 200 else []
    report["localizations"] = sorted({x.get("attributes", {}).get("locale", "?") for x in locs})

    s, b = call("GET", f"/v1/subscriptions/{sub_id}/prices", {"limit": "5"})
    report["prices"] = len(data(b)) if s == 200 else f"http {s}"

    s, _ = call("GET", f"/v1/subscriptions/{sub_id}/appStoreReviewScreenshot")
    report["reviewScreenshot"] = "present" if s == 200 else ("missing" if s == 404 else f"http {s}")

    missing = []
    if not locs:
        missing.append("localization (display name and description) for at least one locale")
    if report["prices"] == 0:
        missing.append("price for the territory(s)")
    if report["reviewScreenshot"] != "present":
        missing.append("review screenshot for the subscription")
    if attrs.get("state") == "MISSING_METADATA" and not missing:
        missing.append("state is MISSING_METADATA but no missing field was found: check the review information")
    report["missing"] = missing
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
