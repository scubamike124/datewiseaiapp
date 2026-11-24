# Review fixes, round 2 — branch claude/overnight-2026-11-24 (PR #54, draft; not merged, not deployed)

Step 0: merged origin/claude/security-tests-2026-11-24 (fast-forward to 3643cb2, no conflicts).

Commits: 4ac0d44 (M1), 8d6c371 (prompt / crisis lines / mirror), c060333 (app, compliance, QA). Pushed.

Final test runs (before push): backend `node --test backend/*.test.mjs tool/live/*.test.mjs` 130/130 pass, 0 skipped
(127 from the security branch + 3 new). Flutter `flutter test` 996/996 pass, 0 skipped (957 before + 39 new in
test/review_r2_fixes_test.dart). `flutter analyze`: no issues.

## A. Code review (review-pr54-code.md)
| Finding | Status | Commit | Test |
|--|--|--|--|
| M1 oversized v1 request -> 413 | Fixed: over-cap body with no X-DateWise-Entitlement and LEGACY_CLIENTS=0 gets 426 APP_UPDATE_REQUIRED "Please update DateWise from the App Store." (nothing parsed). With a token: 413. | 4ac0d44 | worker.test.mjs "an oversized v1-signature request (no token) gets the 426 update notice…"; security_attacks chunked-body test extended (token -> 413, no token -> 426, both bounded) |
| m1 / m2 UTF-16 length, chunked buffering | Already fixed by readBodyCapped (security S-1, 3643cb2); verified | 3643cb2 | security_attacks "body cap counts UTF-8 bytes…", "a body without Content-Length…" |
| m3 long paste bricks thread | Fixed: buildMessages caps each turn at 6,000 chars; composer maxLength 6,000 (counter near limit); PAYLOAD_TOO_LARGE -> coachLimitTooLong (EN/ES), no instant retry | c060333 | review_r2 "message length (m3)" group (3 tests) |
| m4 double StoreKit refresh | Fixed: CoachUnavailableException.entitlementRefreshed; AppState skips its re-read when the service already refreshed | c060333 | review_r2 "no double StoreKit refresh (m4)" (4 cases through BackendAIService + MockClient) |
| m5 prompt wording | Fixed in both copies (conditional scam warning; figures of speech not risk, ask gently once; safety once per planned meeting; role-play in character until asked/practice ends) | 8d6c371 | cost_guard.test.mjs rule list; review_r2 per-coach rule tests |
| m6 / m7 Dart drift, no safety tests | Fixed: persona.dart mirrors coach_prompts.js line for line; tests assert every safety rule in every coach prompt (both copies, every country) and every server line exists in Dart | 8d6c371 | "every coach prompt carries the … safety rules, mirrored in persona.dart", "persona.dart mirrors every rule line of the server prompt (code review m6)", review_r2 coach-prompt group |
| m8 daysTotal | Fixed: "hablaste" | c060333 | review_r2 "daysTotal uses the Mexican preterite" |
| m9 paywall at 320x568 / 200% | Fixed: price stacks under the plan name when the name would get < 140 pt x text scale; WholeWordsText for name | c060333 | review_r2 "paywall plan card fits 320x568 at 200% text (EN/ES) (m9)" + regular-phone test |
| N1 hand-edited l10n | Fixed: regenerated with flutter gen-l10n | c060333 | — |
| N2 _CountingStore | Fixed: uses FakeStoreService.refreshCalls | c060333 | coach_limit_ui_test |
| N3 literal NBSP in ARB | Fixed:   escapes (EN+ES) | c060333 | review_r2 "ARB files keep non-breaking spaces as   escapes (N3)" |
| N4, N5 | N4 not changed (chunked path now covered explicitly by security tests). N5: prompt is +~290 bytes vs before (crisis blocks shortened to limit cost); full live plan estimate 2,417 -> 2,497 neurons, docs updated. |

## B. Compliance (review-compliance.md)
| Finding | Status | Commit | Test |
|--|--|--|--|
| F1 country crisis lines | Fixed: app sends profile.country from the device locale region (US/CA/MX/ES only, never stored); Worker validates as enum, includes only the matching block; unknown -> combined line. Canada not called free. Privacy policy + consent text disclose the country. | 8d6c371, c060333 | "crisis lines are chosen by the profile country…" (JS), review_r2 country/payload tests |
| F1 static "Get help now" | Fixed: lib/screens/get_help_screen.dart, You › Safety and chat menu, EN/ES, device country first, tap to call/text | c060333 | review_r2 "Get help now (F1)" (digits EN/ES, Canada wording, order, You tab, chat menu) |
| 5.1.1(ii) withdraw consent | Fixed: You › Privacy switch; revokeAiConsent keeps all data; turning on reuses the consent dialog; legal/support text EN/ES + regenerated web pages | c060333 | review_r2 "Share messages with the AI provider switch" (state + EN/ES widget + text) |
| Age rating | Fixed: docs/appstore/metadata.md "Dating and Relationships: Yes" (18+), "Shared location: No" | c060333 | review_r2 age-rating test |
| F2 support page 404 | Owner action (Lovable). Repo source web/support.html and support-es.html are generated from lib/content/support_text.dart by tool/legal_pages.dart, regenerated and up to date (legal_pages_test passes). Not published. | — | legal_pages_test |
| F3 backend not live | Owner action (deploy approval); not touched. | — | — |

## C. QA (QA_REPORT.md)
| Finding | Status | Commit | Test |
|--|--|--|--|
| M-1 lapsed: history hidden | Fixed: saved conversations read-only, premium card above the locked composer, menu (history, single delete) usable, no New conversation/starters/Try again; no saved conversation -> full premium card | c060333 | review_r2 "lapsed subscription keeps saved conversations readable" (3 tests) |
| m-1 clipboard | Fixed: awaited + caught, "Copied" only on success, failure notice, floating above the dock | c060333 | review_r2 "copy a reply option (QA m-1)" (2 tests) |
| m-2 word break | Fixed: WholeWordsText for _Row and _SwitchRow titles | c060333 | review_r2 m-2 test |
| m-4 lands on Home | Fixed: AppState.openChatFirst (session only) -> RootGate opens Chat | c060333 | review_r2 m-4 test |
| m-5 web white page, zoom | Fixed: dark #150C10 background + loading ring removed on flutter-first-frame; user-scalable/maximum-scale removed; manifest colours | c060333 | review_r2 index.html test |
| m-3 web link height, m-6 web Tab order | Skipped as instructed (web-only artefacts; check m-3 on device with Accessibility Inspector, m-6 VoiceOver order on device) | — | — |

## Notes for the owner
- Spanish strings are Mexican Spanish, tú, gender-neutral ("Si tú u otra persona están en peligro…").
- Nothing deployed; production Worker still needs the owner's deploy approval for the server-side changes (M1, crisis lines).

## D. Independent re-test (qa2/RETEST.md) fixes
| Finding | Fix | Commit | Test |
|--|--|--|--|
| R1 review links / rebuilds land on Chat | `AppState.takeOpenChatFirst()` consumes the flag once in RootGate; `ReviewMode.seed` clears it | 8b2c513 | review_r3 "open Chat after onboarding is used once (R1)": paywall rebuild opens Home; ?screen=settings/progress/home/coaches/chat open their own tab |
| R2 dead "Try again" after consent withdrawn | Try again routes through the consent dialog (same as Send); Not now sends nothing, Agree retries | 8b2c513 | review_r3 R2 (3 widget tests) |
| R3 consent not versioned | `dw_ai_consent_version` (StorageService.aiConsentVersion = 2, text with country); unversioned/older consent = not given, re-asked; revoke removes both keys | 8b2c513 | review_r3 R3 (3 tests); test prefs updated to the current version |
| m3 headroom (CJK) | Older turns capped at 8,000 JSON-escaped UTF-8 bytes on whole code points, newest turn in full; no surrogate split at 6,000 chars | 8b2c513 | review_r3 m3: CJK, emoji, quotes, control chars x 24 turns < 90% of 256 KB |
| iOS launch placeholder | Brand mark (AppIcon tile) 120 pt @1x/2x/3x on #150C10 | 4026e65 | launch_screen_test.dart |

Runs: backend 130/130 pass, 0 skipped; flutter analyze no issues; flutter test 1016/1016 pass (996 + 20 new). Pushed to origin/claude/overnight-2026-11-24. Not merged or deployed. Launch screen not checked on a device/Xcode build.
