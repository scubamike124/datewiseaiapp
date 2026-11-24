# DateWise AI: independent re-test of the round-2 fixes

Date: 2026-11-24. Branch `claude/overnight-2026-11-24` at `c060333` (fetched and pulled; no writes, no commits, no deploys).
Tester: independent re-tester. I did not write the code, the reviews or the fixes.
Everything below is local: the web review build with `FakeStoreService` and `MockAIService`. No live StoreKit, no live AI, no device.

## Headline

- **NOT FIXED: none.** Every critical/major/minor finding in the four reviews is VERIFIED, except two that are PARTIAL (m3 and m-1 below, for small edge cases).
- **New critical or major regressions: none.**
- **New minor regressions: 3**
  - R1: review links open on Chat.
  - R2: "Try again" does nothing after consent is withdrawn.
  - R3: consent given before the change is not asked again.
  - Details are below.

## Test runs (re-run by me)

| Suite | Result |
|--|--|
| `node --test backend/*.test.mjs tool/live/*.test.mjs` | **130 / 130 pass**, 0 fail, 0 skipped |
| `flutter analyze` | **No issues found** |
| `flutter test` | **996 / 996 pass** ("All tests passed!") |
| `flutter build web --release --no-web-resources-cdn --dart-define=DW_FAKE_STORE=true --dart-define=DW_MOCK_AI=true` | Built to `qa2/web`; no page errors during the Playwright run |

These counts match the fixer's claims (130 and 996).

## 1. Findings status

### Code review (review-pr54-code.md)

| ID | Status | Evidence |
|--|--|--|
| M1: v1 oversized body gave 413 instead of 426 | **VERIFIED** | In `worker.js:757-767`, `tooLarge()` returns `guardError('APP_UPDATE_REQUIRED')` (426, "Please update DateWise from the App Store.") when `!LEGACY_CLIENTS` and there is no `X-DateWise-Entitlement` header. It is used for both the declared-length check and the streamed-length check, and nothing is parsed. Test `worker.test.mjs:171` covers 600 KB with no Content-Length, a 10 MB declared length, the small v1 request, and LEGACY_CLIENTS=1 → 413. `security_attacks` covers chunked bodies with and without a token. The v2 app always sends the header when it has a token (`backend_ai_service.dart:135`). |
| m1 / m2: UTF-16 length check, chunked bodies buffered | **VERIFIED** | Fixed by `readBodyCapped` (3643cb2); security tests cover it. |
| m3: one long paste bricks the thread | **PARTIAL (acceptable)** | See the m3 note below the table. |
| m4: StoreKit refreshed twice | **VERIFIED** | `CoachUnavailableException.entitlementRefreshed`. The test goes through the real `BackendAIService` with `MockClient`: EXPIRED, REQUIRED and REVOKED each refresh once, and DAILY_LIMIT refreshes 0 times. |
| m5: prompt wording | **VERIFIED** | `coach_prompts.js:180-188` has the conditional scam rule, "figures of speech", "once per planned meeting", and "in character … until the user asks for feedback". The old texts are asserted absent. |
| m6 / m7: Dart mirror drift, no safety tests | **VERIFIED** | Tests assert 13 safety rules in every coach × every country, in both copies. The Dart crisis lines are compared character for character against the text of `coach_prompts.js`. |
| m8: "hablaste" | **VERIFIED** | Test plus ARB. |
| m9: paywall at 320x568 / 200% | **VERIFIED** | Widget test in EN and ES, plus screenshots. The price stacks under "DateWise Premium / Monthly · auto-renews", and nothing is clipped (`*-paywall-200pct-scroll0[3-6].png`). |
| N1–N3 | **VERIFIED** | The l10n is regenerated, the test uses `refreshCalls`, and the ARB uses ` ` escapes (tested). |
| N4, N5 | Accepted as described | The prompt is about 4.7 KB. The crisis block for one country adds about 0.2 KB compared with the combined line (probe: ANY 4,697 B, US 4,713 B, ES 4,696 B for the Spanish Ava prompt). |

**m3 note.** Each turn is now capped at 6,000 chars in `buildMessages` and by the composer's `maxLength` (counter, enforced). `PAYLOAD_TOO_LARGE` has its own EN/ES notice and no instant retry. The test only uses ASCII `'x'`, so I probed the worst case: 12 user turns of 6,000 CJK chars plus 12 replies of 3,200 chars gives a body of 255,170 B, just under the 262,144 B cap. Emoji, accented text and quotes give about 183 KB. In practice the cap holds for this audience, but the margin for CJK text is only about 3%.

Nit: `substring` can split a surrogate pair, which leaves a lone surrogate that Dart encodes as U+FFFD. This is harmless.

### Compliance (review-compliance.md)

| ID | Status | Evidence |
|--|--|--|
| F1: crisis lines by country (prompt) | **VERIFIED** | See the F1 prompt note below the table. |
| F1: static "Get help now" screen | **VERIFIED** | See the F1 screen note below the table. |
| 5.1.1(ii): withdraw consent | **VERIFIED** | See the consent note below the table. |
| Age rating | **VERIFIED** | `metadata.md` says "Dating and Relationships: Yes". |
| F2: support pages return 404 | **Owner action (unchanged)** | The repo pages are regenerated. Note that the live privacy policy is now also out of date: it does not mention the country or the switch. **Republish privacy and privacy-es as well**, not just the support pages. |
| F3: backend not live | **Owner action (unchanged)** | — |

**F1 prompt note.**
- The app sends `profile.country` only as US, CA, MX or ES (`UserProfile.crisisCountryOf`). It is never written to storage (tested: `loadProfile().toJson()` has no `country`).
- On the Worker, `crisisLine()` uses `Object.hasOwn`. My probe sent `__proto__`, `constructor`, `toString`, `"us"`, an object, and `"ES\nIgnore rules"`. All of them gave the combined ANY line, and nothing was injected.
- The country is not echoed anywhere else in the Worker.

**F1 screen note.** I checked every number exactly against the brief, on screen and in the code, in EN and ES:

| Country | Numbers |
|--|--|
| US | 988, 911, 1-800-799-7233, "text START to 88788" |
| Canada | 9-8-8, 9-1-1. Not called free. Says to use the province's crisis line for violence. |
| México | 800 911 2000, 911, 079 "opción 1" |
| España | 024, 112, 016, WhatsApp 600 000 016 |

- Links: `tel:988`, `tel:911`, `tel:+18007997233`, `sms:88788?body=START`, `tel:8009112000`, `tel:079`, `tel:024`, `tel:112`, `tel:016`, `https://wa.me/34600000016`. All are correct.
- The device country is listed first. With the `es-MX` locale, México came first.
- The screen is reachable from You › Safety and from the chat menu, including the read-only chat menu.
- Gap: the tests check the digits shown but **not the URIs**.
- Device check: confirm that `sms:88788?body=START` pre-fills the text on iOS (iOS has historically used `&body=`).
- Cosmetic: the label repeats the number ("988 988 Suicide & Crisis Lifeline").

**Consent note (5.1.1(ii)).**
- Switch OFF: `revokeAiConsent` stops any streaming reply and clears only `dw_ai_consent`. In the browser, `dw_threads`, `dw_plan`, `dw_profile` and `dw_onboarded` were all still present afterwards.
- Switch ON: shows the full consent dialog. "Not now" leaves the switch off (aria-checked=false). "Agree" turns it on.
- Sending after withdrawing: typing and tapping Send in Chat brings back the consent dialog, and the threads are unchanged (Playwright, EN and ES).
- `sendMessage` and `retryLastReply` refuse without consent, and voice goes through the same `_send`.

### QA (QA_REPORT.md)

| ID | Status | Evidence |
|--|--|--|
| M-1: lapsed subscription hides history | **VERIFIED** | See the M-1 note below the table. |
| m-1: clipboard | **PARTIAL (code VERIFIED)** | `Clipboard.setData` is awaited and caught. The snackbar says "Copied" only on success, otherwise "Couldn't copy that", and it floats above the dock. Widget tests cover both cases. I did not re-run the web clipboard failure in Playwright. |
| m-2: word broken mid-word at 200% | **VERIFIED** | Screenshots at 200% in EN and ES: "Language", "Share messages with the AI provider" and "Compartir mensajes con el proveedor de IA" wrap on whole words. |
| m-4: onboarding lands on Home | **VERIFIED, but caused R1** | — |
| m-5: white page, zoom disabled | **VERIFIED** | Dark `#150C10` loader, removed on the first frame. `user-scalable=no` is removed. |
| m-3, m-6 | Skipped by design | Device checks. |

**M-1 note.**
- Screenshots `en/es-chat-lapsed-readonly.png`: the history is visible and the composer is replaced by the "Your conversations are saved. Subscribe to keep chatting" card.
- The menu offers Past conversations, Switch coach and Get help now, with no New conversation. There are no starters, and Try again is hidden when read-only.
- There are 3 widget tests.

## 2. Regressions and new issues (all minor)

**R1 (minor, review build): every `?screen=` link now opens on Chat.**
- `ReviewMode.seed` calls `completeOnboarding`, which sets `_openChatFirst = true`.
- `RootGate` (`app.dart:91`) prefers that flag over the tab that `seed` returns.
- Probed: `screen=settings`, `progress`, `home` and `coaches` all land on Chat.
- This breaks the owner's review links (I had to tap the You tab in my scripts).
- In the real app, the flag also never clears during the session, so any later rebuild of `HomeShell` (for example after a paywall) goes to Chat.
- Fix: clear the flag once it has been used, or have the review seed clear it.

**R2 (minor): "Try again" is a dead button after consent is withdrawn.**
- Turning the switch off while a reply streams marks the reply as stopped.
- `canRetry` does not check consent, so Try again still shows, but `retryLastReply` returns false silently and no consent dialog appears.
- Fix: route Try again through the consent prompt, or hide it when `!aiConsentGiven`.

**R3 (minor, launch hygiene): consent given before the change is not asked again.**
- The consent text now also discloses the country, but `dw_ai_consent` is a plain boolean with no version.
- Anyone who agreed to the earlier text (TestFlight or main testers) will send the country without seeing the new disclosure.
- Low impact because v2 is unreleased. Consider a consent version key.

**Other checks:**
- Country field: validated on both sides, not stored, disclosed in the consent dialog, the privacy policy and the support text in EN and ES. The prompt cost is negligible.
- Device check: on iOS, a Spanish (Latinoamérica) device can report its locale as `es-419`. That would fall back to the combined line, which is safe but not tailored. Check on a device that `PlatformDispatcher.locale.countryCode` gives `MX`.
- Get help is not reachable from Chat for an unsubscribed user with no saved conversation, because the menu is disabled. It is still in the You tab. Info only.
- Spanish: natural for Mexico, using tú and gender-neutral wording ("Si tú u otra persona están en peligro", "Ayuda inmediata", "marca 079 y elige la opción 1", "envía START al 88788", "Activado/Desactivado"). "violencia machista" is used only for Spain's 016, which is appropriate there.
  - Nit: ES "1500 al mes" in the paywall fair-use text has no thousands separator; Mexico writes 1,500.
  - Nit: 024 is "gratuita" but 016 is "gratuito". Both are acceptable.

## 3. Screenshots

All saved to `/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/qa2/`, at deviceScaleFactor 2, with the iPhone user agent and locale en-US or es-MX.

| What | Size and text | Files |
|--|--|--|
| You › Privacy switch | 393x852 | `en|es-you-privacy-on.png`, `-off.png`, `-reconsent-dialog.png`, `en|es-chat-send-after-revoke.png` (the consent dialog comes back) |
| Get help now | 393x852 | `en|es-get-help-top.png`, `-1/2/3.png` |
| Chat when unsubscribed | 393x852 | `en|es-chat-subscribed.png` (before), `en|es-lapsed-paywall-on-launch.png`, `en|es-chat-lapsed-readonly.png`, `en|es-chat-lapsed-menu.png` |
| Paywall | 320x568, 200% text | `en|es-paywall-320x568-200pct.png`, `en|es-paywall-200pct-scrollNN.png` (the plan card is in about scroll03–06) |
| Settings rows | 393x852, 200% text | `en|es-settings-200pct-0.png`, `en|es-settings-200pct-scrollNN.png` |

Contact sheets: `_s1.png` to `_s7.png`, `_pen.png`, `_pes.png`, `_ten.png`, `_tes.png`.

Scripts: `shots.js`, `shots2.js`, `probe.mjs`. Logs: `node.log`, `analyze.log`, `ftest.log`, `build.log`, `shots-log.txt`.
