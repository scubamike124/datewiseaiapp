# RESUME (2026-11-24) — state for the next AI

Owner rules: AGENTS.md. $0 spend. No public release, no main merge, no prod deploy without owner approval.

## Done (branch claude/overnight-2026-11-24, PR #54 draft)
- Conversation screen v3 (smaller avatar, collapse option, caption fixes) — reviewed, merged.
- Speech pacing/lip-rate tuning (device confirmation pending), lapse-paywall fix, StoreKit simulator E2E (simulator only).
- Owner-only premium access (backend/owner_access.js, docs/OWNER_ACCESS.md): needs secret OWNER_ACCESS_SECRET on the Worker (owner sets it). Feature off without it.
- Production Worker chat-v7 live. PR #57 (deploy health-check retry) awaits owner merge.

## Decisions
- Frame-based avatar engine: FROZEN, fallback only. Hosted avatar = Anam (Simli rejected: irrevocable AI-training licence, ToS 2.6).
- Anam terms/SDK notes: scratchpad pilot-terms (TERMS_REPORT, SDK_NOTES, QUESTIONS_FOR_VENDORS) — copy into docs/research if lost. Free tier = no commercial use; "dating services" AUP line needs written vendor confirmation before production.

## In flight / blocked
- Anam API key: owner has not supplied (form denied twice). Harness on branch claude/avatar-pilot (Worker /v1/avatar/session, AvatarEngine, HostedAvatarView; AVATAR_PROVIDER off by default).
- TestFlight build from ios-build.yml (signed_build, signing=api, upload_testflight). Never submit for App Store review without owner.
- Release review agent: security of owner access.

## Unverified on a real device
Sandbox purchase/restore/renew/cancel/refund, Spanish chat, voice pace/quality, lip sync, keyboard behaviour, live hosted avatar.

## Next
1. Owner: Anam key + approval of terms; then run the pilot (docs/avatar/PILOT_RUNBOOK.md on the avatar-pilot branch).
2. Voice: device TTS only today; natural-voice upgrade needs owner approval of cost.
3. Merge order: #57, #54, then claude/staging-live-test.
