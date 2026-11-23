> **Superseded by DateWise v2 (one $9.99/month plan).** DateWise v2 has a single auto-renewable subscription, `datewise_premium_monthly`, with no free tier and no free trial. Plans, prices, tiers or free-launch notes below are historical; see `docs/appstore/metadata.md` for the current offer.

# DateWise AI 1.0.2 — App Store release package

**Bundle:** `com.datewise.datewiseAi`  
**App Store ID:** `6780110141`  
**Build:** `1.0.2+3` (CFBundleShortVersionString 1.0.2 / CFBundleVersion 3)

## Why this build is required

Live App Store **v1.0** (released 2026-06-24) ships the Worker URL  
`https://datewise-photo-coach.kaowserprobd.workers.dev`.

Production probe (2026-09-01):
- Photo coach on that Worker: **works**
- Chat / messaging coach on that Worker: **HTTP 502** (broken for App Store customers)

Owner Worker `https://datewise-photo-coach.scubamike124.workers.dev` has working chat + photo (`chat-v5`).

This build points the client at the working Worker and wires the App Store rate link.

## What’s in the build

1. `PHOTO_COACH_URL` → `datewise-photo-coach.scubamike124.workers.dev`
2. `AppLinks.iosAppStoreId` → `6780110141`
3. Friendly AI-unavailable copy (no silent mock coaching)
4. Worker: JPEG/PNG validation (JSON 400 for bad files), AI binding via `wrangler.toml`

## Still blocked (owner / Apple)

| Item | Action |
|--|--|
| iOS IPA build | Needs macOS / Xcode / Codemagic — cannot build iOS on Windows |
| App Store Connect submit | Owner approval + certificates |
| Supabase `cprnegusibbmcyltylzk.supabase.co` | **NXDOMAIN** — recreate project, run `backend/supabase_schema.sql`, update `SupabaseConfig` |
| Real Apple IAP | `freeLaunch=true` + `MockPurchaseService` — create ASC products, replace mock, set `freeLaunch=false` |
| Screenshot OCR product | Not in current spec/code — conversation paste works; dedicated OCR workflow not implemented |

## Build commands (on Mac)

```bash
flutter pub get
flutter build ipa --release \
  --build-name=1.0.2 --build-number=3
```

Upload the IPA via Transporter / Xcode Organizer to App Store Connect for the existing app **DateWise AI - Dating Coach** (`6780110141`). Do **not** create a new app.
