# DateWise UI and StoreKit correction fixes (2026-11-24)

These fixes are on branch `claude/overnight-2026-11-24`, draft PR #54. The commits were pushed. Nothing was merged, deployed or submitted.

**Test results on the final head (`2d8f286`):**
- `flutter analyze`: no issues. Each intermediate commit was also analyzed separately, with no issues.
- `flutter test`: **1,096 passed**, 0 failed, 0 skipped. That is the earlier 1,051 plus 45 new tests. No existing test was changed.
- `node --test backend/*.test.mjs tool/live/*.test.mjs`: **130 passed**, 0 failed, 0 skipped.

**Commits:**
- `518e765`: UI fixes for status bar, headings, Welcome portrait and paywall height (items 7/8, 9, 10, 11-13)
- `a5fe122`: contrast fixes (item 14)
- `134c984`: StoreKit review minors (H)
- `2d8f286`: locked-chat greeting preview, thread titles in the UI language (items 21, 22), and `test/ui_corrections_test.dart`

The UI tests for the first two commits are in `test/ui_corrections_test.dart`, which landed with the last commit.

| Item | Change | Commit | Tests |
|---|---|---|---|
| A. Status bar / safe areas (7/8) | Added `StatusBarScrim` in `lib/widgets/dw.dart`, from the audit's design with `StackFit.passthrough`. It wraps the scroll view on Home, Coaches, Progress, You, Welcome and the Paywall. It is clear at rest, so the hero photos still run under the clock, and solid after scrolling by the top inset. It ignores touches. Home indicator: Welcome's bottom padding changed from `bottom+20` to `bottom+8`. The tab bar, paywall and onboarding already pad by the bottom inset. Chat, onboarding, legal and Get help already had an opaque header. | 518e765 | Group "status bar scrim": 6 screens, checked at rest, at half fade, solid, and after scrolling back to the top, with real insets (59/34 and the SE's 20/0). Also covers touches passing through and Welcome's last button clearing the home indicator. |
| B. Headings (9) | `display` 40→34 and `title` 32→28 (iOS Large Title / Title 1). Home greeting 34→30. Plain font sizes, no clamp. | 518e765 | Group "headings": token sizes. The Home greeting is exactly 39 pt at 1.3x and above 45 pt at 2.0x. `LargeTitle` is 56 pt at 2.0x. |
| C. Welcome portrait (10) | On phones the portrait is a centered 4:5 column, `min(width, hero*0.8)` wide and the full hero height. Its sides fade out (stops 0.18/0.82) and it is aligned at `(0,-0.9)`, so the head shows from hair to chin. The hero height is unchanged. | 518e765 | Group "Welcome portrait": 375x667 EN, 393x852 ES (Sofía), 430x932. Checks width, centering, the 4:5 ratio and the alignment. |
| D. Spacing and paywall (11-13) | Paywall hero is `clamp(0.21*h, 150, 230) + top`, and three spacers were trimmed (16→12, 18→14, 16→12). Onboarding: scroll top padding 16→8, tile gap 10→8, minimum tile height 60→56. No content was removed or reordered, so the Apple disclosure layout is unchanged. | 518e765 | Group "paywall above the fold": price and Subscribe are visible with no scrolling at 375x667 1.0x, 393x852 1.0x and 1.3x, and 430x932, in EN and ES. Also checks the 150 pt hero minimum and that onboarding step 1 has no scroll on the SE. |
| E. Contrast (14) | Unselected radio / 18+ indicator: `line2` → `faint`, 5.5:1 on the tile (was 1.75:1). Disabled rose and ghost `DwButton`: full opacity, `textMuted` on a `0x0AFFFFFF` fill with a `line2` border, over 9:1. Enabled buttons are unchanged. | a5fe122 | Group "contrast": the icon color is ≥3:1. Disabled rose and ghost buttons have opacity 1, text ≥4.5:1, and are announced as disabled. An enabled rose button is unchanged. |
| F. Language (22) | `AppState.threadTitle(title, l)` is used in Past conversations and in Home's resume line, so an untouched title shows in the UI language whatever the coach's language. Stored titles are unchanged, so old data still works. Note: Past conversations already did this at 7829fc3; the Home line did not. | 2d8f286 | Group "New conversation": a Spanish UI with Ava shows "Nueva conversación" on Home and in history. An English UI with Sofía shows "New conversation". A title from the user's own message is shown as it is. |
| G. Preview (21) | The locked chat shows the coach's built-in greeting as a read-only coach bubble under "How {name} starts a conversation" (EN/ES), **below** the premium card. That keeps See Premium above the fold; the first attempt, which put the bubble above the card, pushed it off screen and failed `flows_test`. There is no composer, no send, no thread and no AI call. | 2d8f286 | Group "locked chat": Ava (EN) and Sofía (ES) show their exact greeting, with no composer, send or talk button, no thread, and `canChat` false. The CTA is above the fold and above the preview. |
| H. StoreKit minors | 1) `_queryProduct` calls `notifyListeners()` at the end, guarded after dispose. 2) Restore: a sync `PlatformException` whose details contain userCancelled or paymentCancelled sets `lastRestoreCanceled`. It shows no paywall message and no You snackbar. A subscription StoreKit already holds still restores; other failures still give `restoreFailed`. 3) The Store status sheet is localized EN/ES: title, Copy, Query again / Querying…, 15 labels, the value words, and the "no StoreKit" line. Copy keeps the English readout for support. | 134c984 | `storekit_product_retry_test.dart`, group "review minors" (11 tests): `isSyncCanceled`; a late answer after the 10 s timeout notifies and redraws the paywall (both tests fail if the notify is removed, which was checked); canceled; canceled but held; canceled with a product error; other failure; paywall and You show no message; Spanish sheet with and without StoreKit. |

## Screenshots

- **AFTER:** `/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/ui-audit/after2/`. This has 350 PNGs: the same 16 screens × 3 sizes × 3 text scales × 2 languages as BEFORE, plus the scrolled shots and `metrics.json`. There were 0 layout exceptions in all 288 renders. The harness ran unchanged in a scratch copy of the repo (`ui-audit/repo_after2/`), not in the repo itself.
- **Side by side:** `/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/ui-audit/before-after.jpg`. It covers welcome, onboarding1, paywall, home, coaches, progress, you and chatlocked, in EN at 393x852, at 1.0x and 2.0x.

**Paywall Subscribe button bottom edge, from the harness metrics (before → after):**

| Device and text size | Before | After | Space available |
|---|---|---|---|
| 375x667, 1.0x | 686 | 586 | 667 |
| 393x852, 1.0x | 725 | 654 | 818 |
| 393x852, 1.3x, EN | 905 | 787 | 818 |
| 393x852, 1.3x, ES | 932 | 814 | 818 |

**Scroll needed on other screens:** Welcome on the SE went from 32 to 8 pt. Onboarding step 1 on the SE went from 38 to 0 pt.

## Not changed

- The optional coach-card 1.05 ratio from item 11 was not applied, because it is a design call.
- At 375x667 with 1.3x text the paywall's Subscribe button still sits below the fold (bottom edge 771 pt, down from 878). That case was not in the brief.
- At 200% text on narrow phones, the Home greeting still shrinks a word that is too wide for its column. That is the existing `WholeWordsText` behavior; there is no clamp.
