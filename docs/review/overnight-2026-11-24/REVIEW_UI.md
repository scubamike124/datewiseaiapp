# DateWise AI - UI/UX + accessibility review (web review build, 2026-11-24)

Reviewer: independent, read-only. Build: /home/user/datewiseaiapp/build/web (DW_FAKE_STORE + DW_MOCK_AI), served locally.
Evidence dir: /tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad/overnight/ui/
- 78 captures: `<screen>_<en|es>_<se|i15|pm>.png` (375x667, 393x852, 440x956 @2x), 13 screens x 2 langs x 3 sizes
- Side-by-side sheets: `sheets/<screen>.png` (SE EN, SE ES, 15 EN, 15 ES), `sheets/pm_es.png` (Pro Max)
- Large text (200%, root font-size 32px; Flutter web honoured it): `large200_*_es_se.png`, `sheets/large1.png`, `sheets/large2.png`
- Scroll checks: `scroll_*` and `sheets/scroll.png`
- Semantics dumps (iPhone 15): `semantics_en-es.json`

Caveat: this is the Flutter **web** renderer in Chromium, not iOS. Web visual density, image decode timing and the
semantics→ARIA mapping differ from native VoiceOver. A virtual keyboard cannot be shown in headless Chromium, so the
keyboard item is code review only.

## Overall
The premium dark design is consistent and holds up well: no stretched/distorted images (all portraits use BoxFit.cover,
lib/widgets/dw.dart:384-386), no text overflow/clipping at any of the 3 sizes in EN or ES, every tall screen scrolls,
WCAG contrast of theme tokens is strong (text 16.9:1, textMuted 9.4:1, faint 5.9:1, gold 10.1:1, danger 8.4:1 on
background; disabled Continue ~6:1; rose CTA white-on-#BE466C 4.56:1, borderline but passes AA), every button has a
label, tabs expose selected state, large text scales without breakage. No Critical or High issues found.

## Findings

| # | Screen | Size | Lang | Issue | Evidence | Likely code | Severity | Suggested fix |
|---|---|---|---|---|---|---|---|---|
| 1 | Paywall price card | all (worst SE) | EN+ES | Price column sits in the middle of the card with an empty band on the right; the left column only gets half the width, so "Monthly · auto-renews" breaks as "auto-/renews" on SE and ES wraps to 2 lines | paywall_en_se.png, paywall_en_i15.png, sheets/paywall.png, sheets/scroll.png | lib/screens/paywall_screen.dart:180-215 (`Expanded` + `Flexible` = 50/50 split; end-aligned Column inside a loose Flexible shrinks and is placed mid-row) | Medium (visual, on the money screen) | Give the text column more flex (e.g. `Expanded(flex: 3)`) and the price `Flexible(flex: 2, fit: FlexFit.tight)` wrapping an `Align(alignment: Alignment.centerRight)`, or `mainAxisAlignment: spaceBetween` |
| 2 | Chat (revoked/limit state) | all | EN+ES | After the server refuses with "purchase refunded or revoked", the composer and Send stay fully active, so the user can keep typing messages that will be refused again; locally the app still thinks Premium is active (Settings shows "Active") | chat-limit_*.png | lib/screens/chat_screen.dart:~690-700 (`entitled` gates the composer only on local `state.canChat`) | Medium (UX) | When the last error is `CoachLimitCode.subscriptionRevoked` (or a hard limit), disable/replace the composer with the "See DateWise Premium" action, and refresh entitlement so Settings matches |
| 3 | Paywall links (Restore / Terms / Privacy) | all | EN+ES | Tap targets measure 36pt tall in semantics (below 44pt) | semantics_en-es.json (paywall: 123x36, 91x36, 55x36) | lib/screens/paywall_screen.dart:322-331 sets `minimumSize: Size(44,44)` but web uses compact VisualDensity (-8). On iOS this is likely 44pt | Low (web-only likely; verify on device) | Add `visualDensity: VisualDensity.standard` (as chat_screen.dart:575 already does) and `tapTargetSize: MaterialTapTargetSize.padded` |
| 4 | Welcome / hero images | SE (cold load) | EN | First capture of welcome EN SE rendered with no portrait (blank hero) after 4.5s; it appears later. Hero JPEGs are 1784x2376, ~560-635 KB, with no precache or fade-in, so the portrait pops in | welcome_en_se.png vs scroll_welcome_en_se_top.png (7s) | lib/widgets/dw.dart:369-396 (`Image` without `frameBuilder`); no `precacheImage` anywhere in lib/ | Low (mostly web; native decode is faster) | `precacheImage` the selected coach's hero at startup/onboarding, add a `frameBuilder` fade-in on a surface-coloured placeholder; consider ~1200px-tall hero assets |
| 5 | Home hero | 15 / SE | EN | Greeting body text ("...Pick up where...") overlaps Ava's eye/face; still readable, but crowds the portrait and lowers local contrast | sheets/zoom_home_en.png, home_en_i15.png | lib/screens/home_screen.dart:68-73 (portrait `right:-36, width:300`) vs text maxWidth 240 (~line 122) | Low (visual) | Narrow the phone text column to ~215, or shift portrait right (`right: -60`), or strengthen the left gradient stop (0.48→0.55) |
| 6 | Onboarding step 1 (goals) / step 3 (age) | all | EN+ES | Multi-select goals and the "I am 18 or older" confirmation are exposed as buttons with `selected`, not as checkboxes; VoiceOver will say "selected" but not "checkbox, checked", and the "up to three" rule is not announced | semantics dump (onboarding step=1: role=button, aria-current) | lib/screens/onboarding_screen.dart:312-314 (`Semantics(selected: ...)`) | Low (a11y) | Use `Semantics(checked: selected)` for goals and age; for language use `inMutuallyExclusiveGroup: true` + `checked`; announce when the 3-goal limit blocks a 4th tap |
| 7 | Chat header + intro card | all | EN+ES | The portrait is announced several times: header avatar "Portrait of Ava" right beside the "Ava" heading, then the intro card group plus its image again | semantics dump (chat: 3 portrait labels) | lib/screens/chat_screen.dart:776 and :988 | Low (a11y noise) | Pass `semanticLabel: null` for the header avatar (CoachAvatar docs already allow this next to the name); exclude the intro image semantics since the group label names the coach |
| 8 | Chat message list | all | both | No swipe-to-dismiss keyboard; list is `shrinkWrap: true` + `reverse: true`, which lays out every message on each rebuild (costly in long threads, and while typing) | code | lib/screens/chat_screen.dart:957-963 | Low | Add `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`; drop `shrinkWrap` for long threads (keep the short-thread top alignment by using it only under N items) |
| 9 | Keyboard vs composer | n/a | n/a | Code review only (no virtual keyboard in headless Chromium). Looks OK: the shell `Scaffold` keeps the default `resizeToAvoidBottomInset: true` (lib/screens/shell.dart:72-90), the composer is the last child of the chat Column under an `Expanded` reversed list (chat_screen.dart:~690-700), so it should sit directly above the keyboard with the newest message visible; snackbars are lifted above the dock (chat_screen.dart:245-250). | - | - | Info | Verify on a real iPhone SE (smallest height) with the keyboard + QuickType bar open and a 5-line draft |
| 10 | Bottom tab bar | all (large text) | both | Tab labels are clamped to 1.15x text scale, so they do not grow at 200% | sheets/large1.png | lib/screens/shell.dart:119 | Info (matches iOS tab-bar behaviour) | Optional: iOS shows a large-label HUD on long-press for accessibility sizes; acceptable as is |
| 11 | Coaches tab header | all | both | Title block is centre-aligned, while Progress and You tab titles are left-aligned serif headings | sheets/coaches.png vs sheets/progress.png | lib/screens/coaches_screen.dart | Info (consistency) | Pick one alignment for tab titles |
| 12 | Coach CTAs | all | both | Coach cards use rose/pink "Chat with ..." buttons while every other primary action is gold; intentional accent, but it reads as a second brand colour | sheets/coaches.png, onboarding-s4 | lib/screens/coaches_screen.dart / widgets | Info | Keep it if that is the intent; otherwise use gold outline buttons |
| 13 | chat-limit review screen | - | - | The `chat-limit` review mode shows the refunded/revoked lock, not the daily/monthly fair-use limit notice ("150 replies a day") | chat-limit_*.png; lib/dev/review_mode.dart:48-49 | - | Info (review coverage) | Add a `chat-cap` review screen for the fair-use limit notice so it can be checked visually too |

## Checked and fine
- No clipped or overlapping text or buttons at 375/393/440 in EN or ES; Spanish strings wrap cleanly (onboarding headings, settings rows, plan items).
- All screens that run past the fold scroll (welcome SE, paywall SE, onboarding at 200%, home, settings).
- Large text 200%: headings use whole-word fitting, chat header subtitle ellipsizes, composer grows to 2 lines, progress tiles stack. No overflow stripes.
- Semantics: every interactive control has a label (Back, Close, Send/Enviar, "Copy Playful reply: ...", Try again, tabs "Home tab"/"Pestaña Inicio" with `aria-current`); the composer textarea is labelled "Message Ava…"/"Escríbele a Sofía…"; portraits have localized alt text; plan items are checkboxes; Coach memory is a switch.
- Touch targets ≥44pt everywhere except #3 (send 48, tabs 76x48, options 44, onboarding Back 46).
- Coach identity is consistent: Ava (red hair) in EN, Sofía (dark hair, hoops) in ES, across welcome, home, paywall, chat header, avatars. Brown eyes preserved in all renders seen.
- Fonts and icons are consistent (serif display + sans body, outlined icon set, gold active states).
