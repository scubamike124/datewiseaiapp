> **Superseded by DateWise v2 (one $19.99/month plan).** DateWise v2 has a single auto-renewable subscription, `datewise_premium_monthly`, with no free tier and no free trial. Plans, prices, tiers or free-launch notes below are historical; see `docs/appstore/metadata.md` for the current offer.

# DateWise launch-readiness checklist

Last checked 2026-11-22 for #20. Each line says what was verified and how. "Owner" means it waits on an owner action or decision. Do not start advertising or spend money until every **Required** item is ✅ and the owner approves.

**Status key:** ✅ done and verified · 🟡 built, waiting for review or approval · 🔨 in progress · ❌ not done · ⛔ blocked on the owner

## 1. Working AI coaching (Required)
| Item | Status | Evidence / next step |
|---|---|---|
| Live coach backend answers | ❌ **DOWN** | Live probe on 2026-11-22: `?version` returns `chat-v5`. A chat request returns **HTTP 502** "@cf/meta/llama-3.1-8b-instruct-fp8 was deprecated on 2026-11-20". App users get "trouble reaching the coach". |
| Fix for the retired model | 🟡 #17 | Replaces it with `llama-3.3-70b-instruct-fp8-fast`, with offline tests. **Owner:** merge #17 and deploy chat-v6 (`f5b0401`) by a path in `docs/launch/WORKER_DEPLOY_RUNBOOK.md` §7 (release checklist D0). Then `?version` must return `chat-v6` or later. |
| Four coaches, EN/ES, in the app | 🟡 #21 | 35 tests, iPhone and iPad layouts, independent review APPROVE, CI green. |
| Server-side coach prompts and abuse limits | 🟡 #23 | chat-v7: server-built coach prompts, a per-IP limit (binding off until enabled), and the `REQUIRE_COACH_ID` switch for old apps. 18 tests. |
| Live English and Spanish conversations verified | ❌ | Possible only once #17 or #23 is deployed. Then run the live checks in section 6. |
| Model quality measured (EN/ES) | ❌ | Plan A3: #18/#19 scenarios and the #12 scorer. Research on stronger models is in progress. |

## 2. Professional website and mobile experience (Required)
| Item | Status | Evidence / next step |
|---|---|---|
| Premium dark-purple redesign (web, onboarding, picker, chat, account) | 🔨 | Branch `claude/datewise-premium-redesign`, with screenshots per screen. |
| Phone, tablet and desktop layouts without overflow | 🟡 | Coach flow tested at 320–1280 px wide, including 1.3× text (#21). Re-run for the redesign. |
| Website live | 🟡 | GitHub Pages is published only by a manual run of deploy.yml from `main` (no deploy on push since 2026-11-23). The custom domain `datewiseai.com` is referenced in code but not verified here. |

## 3. Signup and onboarding (Required)
| Item | Status | Evidence / next step |
|---|---|---|
| Accounts (Supabase) | ⛔ | `docs/qa/APP_STORE_1_0_2_RELEASE.md` records `cprnegusibbmcyltylzk.supabase.co` as **NXDOMAIN**. **Owner:** recreate the project, run `backend/supabase_schema.sql`, and update `SupabaseConfig`. Without it the app works without accounts, with data kept on the device. |
| Onboarding (age, gender, goal, app) and coach choice | ✅ | In the app today, plus the #21 picker. |

## 4. Subscriptions and payments (Required before charging)
| Item | Status | Evidence / next step |
|---|---|---|
| Billing | ❌ | `AppFlags.freeLaunch = true`. `MockPurchaseService` "succeeds" without charging. **Owner:** decide the pricing; create App Store Connect / Play products; then real `in_app_purchase`, receipt validation, then `freeLaunch=false`. |
| Payment testing (sandbox) | ❌ | Depends on the line above. |

## 5. Privacy, security, legal (Required)
| Item | Status | Evidence / next step |
|---|---|---|
| Privacy policy, terms, 18+ rule | ✅ | `lib/content/legal_text.dart`, hosted at `datewiseai.com/privacy-policy` and `/terms-of-service` (live URLs not checked here). |
| Account and data deletion | ✅ / ⛔ | In-app deletion exists. Server-side deletion needs Supabase (section 3). |
| AI disclosure | 🟡 | Coaches never claim to be human (#21/#23 prompts). Add an "AI coach" label on the coach cards in the redesign. |
| Backend abuse protection | 🟡 | #23. The open proxy is closed only after `REQUIRE_COACH_ID=1` and the rate-limit binding are enabled. |
| Camera, microphone, voice, avatars | — | Not built. When built: off by default, with explicit consent (plan A5). |

## 6. Live end-to-end QA (Required)
To run after deployment:
1. `GET <worker>/?version` returns the deployed version.
2. Each coach, Emily, James, Isabella and Mateo, answers two real questions. Isabella and Mateo must answer in Spanish even when the user writes in English, and Emily and James must answer in English.
3. A photo analysis (single photo, and a batch of 2–4).
4. Onboarding to first reply on iPhone SE and Pro Max sizes, on web.
5. The error path: Worker down → a friendly, localized message.
6. Abuse checks: a request without `coachId` gets a 426 once the switch is on; a burst of requests gets a 429 once the limiter is on.

## 7. Customer support and error handling
| Item | Status | Evidence / next step |
|---|---|---|
| Support contact | ✅ | `support@datewiseai.com` in the app and the legal text. **Owner:** confirm the mailbox is monitored. |
| Friendly errors in the user's language | ✅ | #21 localises the connection, image and limit errors for Spanish coaches. |

## 8. Independent QA (Required)
| Item | Status |
|---|---|
| Code review of each PR | ✅ #21, #22, #23 (independent review APPROVE). Redesign: pending. |
| Automated tests in CI | ✅ Flutter tests on PRs (#21). Backend tests on PRs (#23). |
| Human test on a real iPhone and Android device | ❌ Owner or tester. |

## 9. App Store
| Item | Status |
|---|---|
| 1.0.2 build (points at the working Worker) | ⛔ Needs macOS/Xcode or Codemagic, plus owner approval (release doc). The live v1.0 still uses the old Worker URL. |
| New version with coaches and redesign | ❌ After #21 and the redesign are approved. |

## 10. Marketing (advertising stays off until the owner approves)
| Item | Status |
|---|---|
| Marketing website (landing page) | 🔨 Part of the redesign. |
| Store screenshots and ad creatives | ❌ Generate from the redesigned app's screenshots once approved. |
| Analytics and conversion tracking | ❌ None in the app today. Needs an owner decision (privacy-friendly tool, consent). |

## Owner approvals needed now, in order
1. **Merge #17 and deploy the Worker. This restores live coaching, which is currently down.**
2. Merge #21 (this also deploys the web app).
3. Approve #23, then enable the rate-limit binding, then set `REQUIRE_COACH_ID=1` after the new app version is out.
4. Recreate Supabase (accounts).
5. Pricing and billing setup; App Store build pipeline (Mac/Codemagic).
