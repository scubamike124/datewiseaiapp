# Independent full-application verification (2026-11-24, head df88297)

Independent QA agent, fresh worktree, nothing changed. Logs: scratchpad `app-verify/`.
Automated and simulated results only; nothing here is device-verified.

## Results
| Check | Result |
|---|---|
| `flutter analyze` | no issues |
| `flutter test --concurrency=2` | 1,099 passed, 0 failed, 0 skipped |
| Backend `node --test backend/*.test.mjs tool/live/*.test.mjs` | 130/130 |
| CI on head | test, worker, staging dry run passed; unsigned iOS build cancelled (superseded); signed build manual; StoreKit E2E running |

## Blockers (release-critical)
1. Production Worker still reports `chat-v5` (no subscription check, retired model). chat-v7 deploy run 4 stopped
   before upload: `CLOUDFLARE_ACCOUNT_ID` is empty in the `production-worker` environment (owner fixing).
   `ID_HASH_SALT` on production not yet checked (the deploy checks it before uploading).
2. Not yet done on a physical iPhone: Sandbox purchase, restore, renewal on TestFlight build 203.
3. Owner items: legal approval of the hosted privacy and terms pages; confirmation of the crisis numbers.

## Major
- Coach safety is prompt-only (no output moderation); `backend/coach_prompts.js:208` accepts earlier coach turns sent
  by the app, so a modified client can fabricate history.
- Production `SANDBOX_NEURON_BUDGET` is 6000 (60% of the day) until set back to 1000 after App Review.
- Staging Worker answers Cloudflare error 1042 (not deployed), so the live AI test and the 66-scenario battery have
  not run.

## Passes (code review with citations in the agent log)
- Subscription: one monthly product at 19.99, no trial, no annual or free plan; fake store only on web/debug
  (`store_service.dart:856`); chat gated on entitlement (`app_state.dart:55,451`, `app.dart:85`); StoreKit 2 verified
  entitlements, signed transaction sent as `X-DateWise-Entitlement`; restore and refund handling; Apple disclosures
  EN/ES; Restore, Terms, Privacy on the paywall; 18+ gate and under-18 block.
- chat-v7: Apple signature chain, bundle, product, environment, revocation and expiry checked; fail-closed defaults;
  413 on oversized requests; no message text in logs; client retries at most twice with EN/ES errors.
- Privacy: nothing sent to the AI before consent; consent withdrawable; Delete my data clears everything; on-device
  speech recognition. Only a public Supabase anon key in `scripts/production-e2e-probe.mjs:13`.
- UI (widget tests): safe areas, headings, contrast, tap targets, 200% text, iPad, paywall on iPhone SE.

## Minor
- Fake store and mock AI allowed in web release builds.
- Under-18 block does not survive reinstall (rely on the 18+ App Store rating).
- Chats stored unencrypted in app preferences.
- Worker 502 returns upstream error detail to the app.
- Doc count drift: 110 vs 130 backend tests; 2,417 vs 2,019 neurons.

## Device-only (cannot be verified here)
Real purchase, restore and renewal; a live chat-v7 conversation; coaches' safety replies; tel/sms links; speech and
avatar timing; VoiceOver and Dynamic Type; notch and Dynamic Island.
