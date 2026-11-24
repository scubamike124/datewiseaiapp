# DateWise AI: UI and accessibility audit (TestFlight build 196 report)

- Audited: branch `claude/overnight-2026-11-24`, commit `7829fc3`. `lib/services/store_service.dart` and
  `lib/screens/paywall_screen.dart` are the **committed** versions. The other engineer's uncommitted edits to them
  were not used. All `file:line` references are to that commit.
- Read only: nothing in `/home/user/datewiseaiapp` was edited, committed or pushed.
- Folder below: `/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/ui-audit/`
  - `before/`: 349 PNGs. That is 16 screens x 3 sizes x 3 text scales x 2 languages (288), plus 61 `_scrolled` shots
    taken at 1.0x after scrolling 140 pt. `before/metrics.json` has, for every render, the viewport height, the
    scroll extent, the on-screen rects of key buttons, and any layout exceptions. There were none in all 288 renders.
  - `after/`: the same harness run on a second scratch copy (`repo_after/`) with the changes proposed below applied.
    It covers welcome, paywall, home, coaches, progress, you, and onboarding steps 1 and 4. These shots check that
    the proposals work.
  - The harness is `repo/test/zz_ui_audit_screens_test.dart`. Regenerate with:
    `UI_AUDIT_OUT=<dir> [UI_AUDIT_ONLY=welcome,paywall] flutter test --no-pub test/zz_ui_audit_screens_test.dart`
- File names: `<screen>_<WxH>_<scale>x_<lang>[_scrolled].png`. The screens are welcome, onboarding1-4, underage,
  paywall, home, coaches, chat, chatlocked, progress, you, privacy, terms and gethelp.

---

## 7/8. Scrolling content shows under the status bar and clock

**Finding: confirmed on 6 screens.** Each of these screens puts its own `SingleChildScrollView` at the very top of
the screen and pads the first item by `MediaQuery.paddingOf(context).top`. Nothing opaque sits behind the status
bar, so once the page scrolls, titles, rows and cards slide under the clock and the Dynamic Island.

| Screen | Cause | Screenshot evidence |
|---|---|---|
| Home | `home_screen.dart:58` (scroll view); the hero starts at `top + 12` (`:115`) | `before/home_375x667_1.0x_en_scrolled.png` |
| Coaches | `coaches_screen.dart:77-79` (`padding: top + 16` inside the scroll view) | `before/coaches_393x852_1.0x_en_scrolled.png`: the subtitle sits under the clock |
| Progress | `progress_screen.dart:26-27` | `before/progress_393x852_1.0x_en_scrolled.png`: "Progress" runs into "9:41" |
| You / Settings | `settings_screen.dart:93-94` | `before/you_393x852_1.0x_en_scrolled.png`: the Language row sits under the clock |
| Welcome | `welcome_screen.dart:29` (the hero runs under the status bar on purpose) | `before/welcome_375x667_1.0x_en_scrolled.png`. Scroll extent is 166-598 pt at 1.3x-2.0x |
| Paywall | `paywall_screen.dart:110` (the same kind of hero) | `before/paywall_393x852_1.0x_en_scrolled.png`, and see 12/13 |

Screens that are already correct: Chat (opaque header with a hairline, `chat_screen.dart:667-684`); onboarding (a
fixed `SizedBox(height: top)` plus the progress header outside the scroll view, `onboarding_screen.dart:98-134`);
Privacy, Terms and Get help (`AppBar` + `SafeArea`, `legal_screen.dart:133-134`, `get_help_screen.dart:84-85`); and
Underage (`SafeArea`, `onboarding_screen.dart:374`).

Bottom inset (home indicator): no screen hides content there at rest.
- The tab screens end above `DwTabBar`, which pads itself by the bottom inset (`shell.dart:130`).
- Welcome and the paywall add `bottom` to their last padding (`welcome_screen.dart:79`, `paywall_screen.dart:159`).
- Onboarding pads its action `bottom + 16` (`onboarding_screen.dart:143`).

Content passing under the home indicator *while* scrolling is normal iOS behaviour. No change is needed.

**Proposed change (one shared widget, applied the same way on all 6 screens).** Add this to `lib/widgets/dw.dart`.
It is a strip of the page colour, exactly the height of the top inset, that fades in as the page scrolls:
- At rest it is fully transparent, so the hero photos on Home, Welcome and the Paywall still run under the clock as
  they do today.
- After `top` points of scroll it is solid, so no text ever sits under the clock.

```dart
class StatusBarScrim extends StatefulWidget {
  const StatusBarScrim({super.key, required this.child, this.color = AppColors.background});
  final Widget child;
  final Color color;
  @override
  State<StatusBarScrim> createState() => _StatusBarScrimState();
}

class _StatusBarScrimState extends State<StatusBarScrim> {
  final _opacity = ValueNotifier<double>(0);
  @override
  void dispose() { _opacity.dispose(); super.dispose(); }

  bool _onScroll(ScrollNotification n, double top) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical && top > 0) {
      _opacity.value = (n.metrics.pixels / top).clamp(0.0, 1.0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) => _onScroll(n, top),
      child: Stack(children: [
        widget.child,
        if (top > 0)
          Positioned(
            top: 0, left: 0, right: 0, height: top,
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _opacity,
                builder: (_, o, _) => o == 0
                    ? const SizedBox.shrink()
                    : ColoredBox(key: const ValueKey('status-bar-scrim'), color: widget.color.withValues(alpha: o)),
              ),
            ),
          ),
      ]),
    );
  }
}
```

Then wrap each top-level scroll view: `StatusBarScrim(child: SingleChildScrollView(...))` at
- `welcome_screen.dart:29`
- `paywall_screen.dart:110`
- `home_screen.dart:58`
- `coaches_screen.dart:77` (inside the existing radial-gradient `DecoratedBox`)
- `progress_screen.dart:26`
- `settings_screen.dart:93`

Verified in `after/*_scrolled.png`: `after/progress_393x852_1.0x_en_scrolled.png`, `after/you_…`,
`after/coaches_…` and `after/paywall_…` all show a clean bar behind the clock. The at-rest shots (`after/home_…`,
`after/welcome_…`) are unchanged. Suggested test: scroll each screen by 100 pt and expect
`find.byKey(ValueKey('status-bar-scrim'))`, then check that no `Text` rect has `top < padding.top`.

---

## 9. Default headings are too large on a 375-pt phone

The heading styles are in `lib/theme/app_theme.dart` and the places that use them.

| Style | Size now | Used by | On a 375 x 667 phone |
|---|---|---|---|
| `AppText.display` (`app_theme.dart:91-98`) | 40 / line height 1.04 | Welcome title (`welcome_screen.dart:88-90`) | 2 lines, 85 pt, larger than the iOS Large Title (34). 80 pt per line at 2.0x |
| Home greeting (`home_screen.dart:133`) | 34 (display override) | "Good afternoon." | Fits, but sits over the portrait's eye at 393 (`before/home_393x852_1.0x_en.png`) |
| `AppText.title` (`app_theme.dart:100-107`), shown through `LargeTitle` (`dw.dart:502`) | 32 / 1.08 | Onboarding 1-4, Coaches, Progress, You, Underage, paywall headline (`paywall_screen.dart:167`) | "What would you like help with?" and the paywall headline take 2 lines. "Choose your dating coach" fills the whole width. 64 pt at 2.0x (`before/coaches_375x667_2.0x_en.png`) |
| `AppText.name` (`app_theme.dart:109-115`) | 26 | Coach card names; locked title at 24 (`chat_screen.dart:1517`) | Acceptable |

**Proposed change.** Map the styles to the iOS text-style sizes. Keep plain `TextStyle` sizes, so Flutter's
`TextScaler` still scales them linearly with Dynamic Type up to 200%. Add no `clamp`.

- `app_theme.dart:93-94`: `fontSize: 40, height: 1.04` becomes `fontSize: 34, height: 1.06` (iOS Large Title)
- `app_theme.dart:102-103`: `fontSize: 32, height: 1.08` becomes `fontSize: 28, height: 1.1` (iOS Title 1)
- `home_screen.dart:133`: `fontSize: tablet ? 42 : 34, height: 1.05` becomes `fontSize: tablet ? 42 : 30, height: 1.08`
- Leave `AppText.name` as it is.

Verified: `after/welcome_375x667_1.0x_en.png`, `after/onboarding1_375x667_1.0x_en.png` and
`after/paywall_375x667_1.0x_en.png`. There were no layout exceptions at 2.0x in the after renders.
`WholeWordsText` still shrinks single long words, as before.

Existing tests that pin these sizes or line counts are listed under "Test impact" at the end.

---

## 10. The Welcome portrait crops the head

**Cause, with numbers:**
- `welcome_screen.dart:23-24` sets the hero height to `0.42 x 667 = 280 pt` on an SE (`0.5 x h` on taller phones).
- `CoachImage` (`dw.dart:384-387`) draws the 1784 x 2376 hero with `BoxFit.cover` at full width, so the image is
  375 x 500 pt and only 56% of its height can show.
- The vertical alignment is Ava's `heroFocus: Alignment(0, -0.35)` (`coach.dart:120`). Sofía's is `(0, -0.3)`
  (`coach.dart:175`).
- So the visible rows are about 14%-70% of the photo. Ava's hair starts at about 3% and her chin is at about 72%;
  Sofía's are about 10% and 70%.
- Result: the top of the head is cut off, and the chin falls under the bottom fade (`welcome_screen.dart:58-59`,
  stop 0.86). The BrandMark (`:63`) also sits on the forehead. See `before/welcome_375x667_1.0x_en.png`: the face
  runs from forehead to lips only.

At full width, **no alignment can fix the SE.** Showing the head from hair to chin takes about 69% of the image
height, and the hero has room for 56%. On 393 x 852 and 430 x 932 the crop is mild: about 16 pt of hair is lost, and
the Dynamic Island sits on the hair (`before/welcome_393x852_1.0x_es.png`).

**Proposed change.** On phones, show the portrait in a 4:5 column centred in the hero, with its sides fading into the
page. This reuses the iPad treatment that is already at `welcome_screen.dart:41-50`. Replace the `else` branch at
`welcome_screen.dart:51-52` (and add `import 'dart:math' as math;`):

```dart
else
  Center(
    child: SizedBox(
      width: math.min(size.width, heroHeight * 0.8),
      child: ShaderMask(
        key: const ValueKey('welcome-hero-phone-fade'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0, 0.18, 0.82, 1],
        ).createShader(rect),
        child: CoachImage(coach: coach, semanticLabel: l.welcomePortrait(coach.name),
            alignment: const Alignment(0, -0.9)),
      ),
    ),
  ),
```

- SE: the column is 224 pt wide, and the photo shows from the top of the hair to below the chin, above the fade.
- 393 / 430: the columns are 341 / 373 pt wide, and the full head shows with the shoulders.
- The hero height does not change, so nothing below it moves.

Verified: compare `after/welcome_375x667_1.0x_en.png` with the before shot, and `after/welcome_393x852_1.0x_es.png`
(Sofía). The face and the approved portraits are untouched; only the crop changes.

---

## 11. Too much vertical space and needless scrolling

These numbers come from `before/metrics.json`. "Scroll" is how far the page scrolls at 1.0x in English.

| Screen | 375x667 | 393x852 | What pushes content below the fold | Proposed change |
|---|---|---|---|---|
| Welcome | 32 pt (ES 67): the footnote is off screen | 27 pt | `display` at 40 (`welcome_screen.dart:90`); the bottom padding `bottom + 20` (`:79`) adds 54 pt at 393 | The size change in item 9. Change the `:79` bottom to `bottom + 8`. After: 20 / 13 pt (`after/welcome_*`) |
| Onboarding step 1 | 38 pt: the 5th goal is cut off (`before/onboarding1_375x667_1.0x_en.png`) | 0 | Scroll padding top 16 (`onboarding_screen.dart:137`); 10 pt gap per tile (`:311`); 60 pt minimum height (`:325`); title at 32 | `:137` top 16 becomes 8; `:311` 10 becomes 8; `:325` 60 becomes 56 (still 44 pt or more); item 9. **After: 0 pt** (`after/onboarding1_375x667_1.0x_en.png`) |
| Paywall | Subscribe at y = 632-686, below the fold | Subscribe at 671-725 | Hero `230 + top` (`paywall_screen.dart:116`) | See 12/13 |
| Home | 143 pt: the second row of tiles | 21 pt | Hero `330 + top` (`home_screen.dart:72`) with a 22 pt gap (`:120`) | Acceptable as a scrolling dashboard. Item 9 saves 4 pt |
| Coaches / onboarding step 4 | 276 / 248 pt | 175 / 124 pt | Cards are 1.2 x width tall (`coach_card.dart:57`), in a 2 x 2 grid | Optional: a 1.05 ratio on phones saves about 50 pt. That is a design call, so it was not applied |
| Progress | 189 pt | 67 pt | Four stat tiles plus the plan card | No change needed |

---

## 12/13. The subscription card and the Subscribe button (for the paywall engineer)

**Measured, committed paywall, default text, bottom inset 34 (usable height 818 on 393 x 852):**

| Device and text size | Price | Subscribe | Visible without scrolling? |
|---|---|---|---|
| 393x852, 1.0x | 591-620 | 671-725 | Yes, with about 93 pt to spare |
| 393x852, 1.3x | 758-795 | 851-905 | **No** |
| 375x667, 1.0x | 552-581 | 632-686 | **No** |

So at commit 7829fc3, with default text on a 393 x 852 phone, both are already above the fold. If build 196 hid them
on the owner's phone, the likely causes are:
- larger text (Settings > Display > Text Size), or
- an older paywall build, or
- an error line (`paywall_screen.dart:259-264`) or "Price from App Store" taking extra height.

**Minimal change.** The only edit is the hero height at `paywall_screen.dart:116`:

```dart
// was: height: 230 + top,
height: (MediaQuery.sizeOf(context).height * 0.22).clamp(150.0, 230.0) + top,
```

Together with `AppText.title` at 28 (item 9), the after renders (`after/metrics.json`) show:

| Device and text size | Subscribe after the change | Visible? |
|---|---|---|
| 393x852, 1.0x | 620-674 | Yes |
| 393x852, 1.3x | 753-807 | **Yes, now visible** |
| 375x667, 1.0x | 544-598 | **Yes, now visible** |
| 430x932, 1.0x | 638-692 | Yes |

The coach portrait still shows the face, cropped by `heroFocus` (`after/paywall_393x852_1.0x_en.png`). The
disclosure, Restore, Terms and Privacy stay right below the button. No content is removed and nothing is reordered,
so the Apple disclosure layout is unchanged.

---

## 14. Contrast (WCAG AA 4.5:1 for normal text)

Calculated from the `app_theme.dart` tokens, blending alpha over the real surface (script: `contrast.py`):

| Pair | Ratio | Result |
|---|---|---|
| `textMuted` #C2B2A8 on background #150C10 (body, link buttons) | 9.37 | Pass |
| `faint` #9C8B82 on background (`AppText.small`: paywall disclosure, fair-use line, welcome footnote) | 5.89 | Pass |
| `faint` on surface #1E1518 (plan "Next", progress status, composer hint) | 5.47 | Pass |
| `faint` on surface2 #2A1E21 (dialogs, sheets) | 4.92 | Pass, with little margin |
| Disabled gold button: label `0xB3F0D3A3` on `0x1FDDB67F` over background (`dw.dart:159-164`) | 6.06 | Pass |
| Inactive tab label: `faint` on the tab bar `0xD1120C0E` | 5.92 | Pass |
| `textMuted` on the plan card / selected tile #2E2019 | 7.65 | Pass |
| Home body text over the portrait's cheek (sampled from `before/home_393x852_1.0x_en.png`) | 5.16 | Pass, little margin |
| **Disabled rose or ghost `DwButton`** (whole button at `Opacity(0.5)`, `dw.dart:192-193`) | rose 3.81 / ghost 4.80 | **Rose fails.** WCAG exempts inactive controls, but it is hard to read |
| **Unchecked radio / age indicator**, `AppColors.line2` on surface (`onboarding_screen.dart:350`) | 1.75 | **Fails non-text 3:1 (1.4.11)**. The "I am 18 or older" choice is hard to see |

No text token fails AA. The existing token checks are in `test/a11y_test.dart:65-96`.

**Proposed changes:**
- `onboarding_screen.dart:350`: `AppColors.line2` becomes `AppColors.faint` for the unselected icon (5.47:1).
- `dw.dart:193`: apply the `quietGold` approach to rose and ghost buttons too. Keep opacity 1 and use
  `fg = AppColors.textMuted` on `bg = Color(0x0AFFFFFF)` with the `line2` border. That is 9:1 or better.

Note: the gold buttons render with a hard dark band under them in these PNGs. That is the test renderer drawing
`BoxShadow` blur unblurred (`dw.dart:138`). It is not a device bug.

---

## 15/16. Every screen at three sizes, three text scales and two languages

- Done. The 288 renders and 61 scrolled shots are in `before/`.
- The real fonts are loaded: Inter, Newsreader, and the MaterialIcons font from the Flutter SDK.
- Locale: `localesTestValue`. Text scale: `textScaleFactorTestValue`.
- A clock, battery and Dynamic Island are painted on top, so overlap is visible.
- Insets:
  - 393x852 and 430x932: top 59 / bottom 34.
  - 375x667: top 20 / bottom 0. That is the real iPhone SE, which has no notch; 47 or 59 would not be realistic there.
- No `RenderFlex` overflow or other layout exception occurred in any render (the `errors` array in `metrics.json`).
- Visual issues found are covered by items 7-14.
- At 2.0x on the SE every screen stays readable. The chat header subtitle is clamped to 1.4x on purpose
  (`chat_screen.dart:776-783`), and the tab labels to 1.15x (`shell.dart:119`).

---

## 18. Age confirmation requires an explicit choice: verified

- `_adult = false` at the start (`onboarding_screen.dart:28`). The tile shows the empty radio
  (`before/onboarding3_375x667_1.0x_en.png`).
- Continue is disabled until the user taps the tile (`:243 onPressed: _adult ? _next : null`).
- `AppState.completeOnboarding` refuses when `adultConfirmed` is false (`app_state.dart:128`).
- "I am under 18" asks for confirmation first (`onboarding_screen.dart:49`).
- Tests: `test/qa_sweep_onboarding_test.dart:40-53` (plus the untracked `test/age_confirmation_explicit_test.dart`
  added by the other engineer).
- The one problem is visibility: the unselected indicator is at 1.75:1. Fix it as in item 14.

## 19. Under-18 users cannot reach coaching, even after a restart: verified

- `markUnderage` saves `dw_underage` (`app_state.dart:86-89`).
- `_load` reads it back, and `onboarded = hasOnboarded && !underage` (`app_state.dart:285-287`).
- `RootGate` checks `underageBlocked` before anything else (`app.dart:82`).
- "Delete my data" keeps the block (`storage_service.dart:229-235`).
- `completeOnboarding` refuses (`app_state.dart:128`).
- Tests: `privacy_store_test.dart:55-90` (restart) and `qa_privacy_test.dart:143-152`.
- Caveat for the owner's awareness: SharedPreferences is iOS UserDefaults, which is erased when the app is deleted.
  Reinstalling therefore clears the block. That is normal for a self-declared age gate. Storing the flag in the
  Keychain would survive a reinstall, if wanted.

## 20. All four onboarding steps: verified

| Step | What it does | Code | Screenshots |
|---|---|---|---|
| 1. Goals | 1 to 3 choices; Continue is disabled with none | `onboarding_screen.dart:153-186` | `before/onboarding1_*` |
| 2. Language | Switches the UI language at once | `:187-217`, `_setLanguage` at `:35-38` | `before/onboarding2_*_es.png` is in Spanish |
| 3. 18+ | See 18 | `:218-258` | `before/onboarding3_*` |
| 4. Coach | `CoachGrid` with voice preview; "Chat with X" calls `completeOnboarding` and closes the route | `:259-279`, `:64-77` | `before/onboarding4_*` |

The back gesture moves back one step (`:88-92`). The only layout problem is step 1 on the SE (item 11).

## 22. Language switching: mostly complete

- `app_en.arb` and `app_es.arb` have identical key sets (checked).
- Strings that are the same in both are intentional: brand, "Coaching", "Chat", "Coaches".
- The subscription disclosures are translated: `paywallDisclosure`, `paywallDisclosureNoPrice`, `paywallFairUse`
  and `monthlyAutoRenews` (`app_es.arb:133-151`). See `before/paywall_*_es.png`.
- Legal pages switch to Spanish, with a note that the English version governs (`legal_screen.dart:33-42`).

Hard-coded or language-locked text found:
1. `app_state.dart:706-707`: `defaultThreadTitle` follows the **coach's** language, not the UI language. A Spanish UI
   with Ava lists "New conversation" in Past conversations.
   - Proposed: build the title from the UI language (or l10n) where it is displayed, and keep the stored value
     language-neutral.
2. Coach greeting, starters and `chatLabel` (`coach.dart`) are in the coach's language. This is by design (the coach
   speaks its own language), so a Spanish UI with Ava shows English starters (`before/chat_*_es.png` uses Sofía).
   Owner decision only.
3. `lib/widgets/store_status_sheet.dart:43,64,70` ("Store status", "Copy", "Query again") and the labels at
   `store_service.dart:81-95`. These are in the other engineer's **uncommitted** diagnostics sheet, reached by a hidden
   long-press. English is acceptable for a diagnostics view, but note it.
4. `lib/dev/entitlement_export.dart`: debug builds only. Acceptable.
5. "English" and "Español" are intentionally written in their own language (`onboarding_screen.dart:201,209`,
   `coach_card.dart:85-87`).

## 23. Closing the paywall never grants access: verified

- `onClose` is `state.dismissPaywall`, which only sets a flag for the session (`app.dart:85-86`,
  `app_state.dart:62-67`).
- `canChat` is `store.isEntitled` (`app_state.dart:54`).
- `sendMessage` returns early when `!canChat` (`app_state.dart:450`), as does retry (`:650`).
- The chat shows `_Locked` (`chat_screen.dart:653, 718`).
- The backend also refuses without a StoreKit token: 403 SUBSCRIPTION_REQUIRED (`backend/cost_guard.js:592,656`).
- Test: `flows_test.dart:122-135`.

## 25. Privacy and Terms links

- **In the app**, Terms and Privacy open the bundled `LegalScreen`, not a URL: `paywall_screen.dart:275-276` (HEAD
  `_openLegal(LegalDoc.terms / .privacy)`) and `settings_screen.dart:266,274`. Each opens the right document.
- `privacyPolicyUrl`, `termsUrl` and `supportUrl` in `lib/app_links.dart:16-23` are not used anywhere in `lib/`.
  They are the App Store Connect URLs.
- Fetched today (2026-11-24):

| URL | Status |
|---|---|
| `https://datewise-legal.lovable.app/privacy-policy` | 200, "Privacy Policy — DateWise AI" |
| `https://datewise-legal.lovable.app/terms-of-service` | 200, "Terms of Use — DateWise AI" |
| `/privacy-es.html` | 200 |
| `/terms-es.html` | 200 (text identical to `web/terms-es.html`) |
| **`https://datewise-legal.lovable.app/support.html` (`AppLinks.supportUrl`, the App Store Connect Support URL)** | **404**. `/support` and `/support-es.html` are also 404 |
| Apple standard EULA | 200 |

- **The live privacy policy is out of date (EN and ES).** It is dated "November 23, 2026". The app's bundled policy
  (`web/privacy.html`, `lib/content/legal_text.dart`) is dated Nov 24 and adds two things:
  - the "Your permission before anything is shared" (AI consent) section, and the right to withdraw it;
  - the device-country sharing for crisis lines.
  This matters for App Review: the app asks for AI-sharing consent, and the published policy does not describe it.
- The live pages also show an "Edit with Lovable" badge.

**Owner actions (no code):**
1. Republish `web/privacy.html`, `web/privacy-es.html` and `web/support.html` / `support-es.html` on the Lovable site.
2. Remove the Lovable badge.
3. Re-check that `support.html` returns 200 before App Review.

## 26. Usage limits in the app vs backend enforcement

- The per-subscriber limits match:
  - App: `lib/config/fair_use.dart:15-27` gives 150/day, 1500/month, 12/min, 2 at once, notice at 80%.
  - Backend: `backend/wrangler.toml:64-68` gives the same values, and the defaults in `backend/cost_guard.js:42-46`
    agree.
  - `test/fair_use_test.dart` enforces this.
- **Mismatches the owner should know about:**
  1. **TestFlight / sandbox:** `SANDBOX_DAILY_LIMIT = "20"` (`wrangler.toml:102`; `cost_guard.js:654` uses it for
     sandbox). The owner, testing build 196, is told "up to 150 a day" but is stopped at **20 a day**. All sandbox
     testers also share `SANDBOX_NEURON_BUDGET = 6000`, about 42 replies a day (`wrangler.toml:103-108`).
  2. **Service-wide budget:** `DAILY_NEURON_BUDGET = "10000"` (`wrangler.toml:55`) is about 70 replies a day for the
     whole service, going by the file's own figure of about 42 replies per 6000 neurons, and the sandbox slice comes
     out of it. One subscriber can therefore never reach the advertised 150 a day while spending stays at $0.
     - The wording "up to" is technically true. In practice users will hit `SERVICE_BUDGET_EXHAUSTED`
       (`cost_guard.js:731-734`) long before.
     - Owner decision: either a disclosure, or a `DAILY_MESSAGE_LIMIT` that the budget can actually serve. No code
       change is proposed without approval.

## 21. A free preview of all four coaches before paying

**What exists today, with no payment and no AI calls:**
- Onboarding step 4 and the Coaches tab show all four coaches: portrait, language, description, and a
  **spoken intro** (`voiceIntro`) played with on-device text-to-speech (`coaches_screen.dart:13-38`,
  `coach_card.dart:94-110`).
- After closing the paywall, "Chat with X" opens the locked chat, which shows that coach's intro card and the
  Premium card (`chat_screen.dart:1495-1530`; `before/chatlocked_*`).

**What is missing:** a sample of how each coach talks in the chat itself.

**Minimal change (local only, no coaching, no backend):** in `_Locked` (`chat_screen.dart:1505-1508`), after
`_IntroCard(coach: coach),` add the coach's built-in greeting as a coach bubble:

```dart
_Bubble(
  message: ChatMessage(id: 'preview-greeting', role: MessageRole.coach, text: coach.greeting, createdAt: DateTime(2026)),
  coach: coach,
  showOptions: false,
),
```

Optionally relabel the coach-card button to "Meet {name}" when the user is not entitled. With this, a
non-subscriber can open each of the four coaches from the Coaches tab and see their greeting, profile and voice
intro. Nothing can be sent, because `sendMessage` still refuses (item 23).

---

## Test impact of the proposals

The full existing suite (`test/*_test.dart`, 1017 tests) was run against `repo_after/`. That copy has the
StatusBarScrim on 6 screens, the heading sizes 34/28/30, the Welcome portrait column, the paywall hero clamp and the
onboarding spacing. Result: **all 1017 tests passed** (`after_suite.txt`). None of the existing tests pin the old
sizes.

The changes for 14 (radio colour, disabled rose and ghost buttons), 21 (greeting bubble) and 22 (thread title) were
not applied in `repo_after/`. They are small and separate.
