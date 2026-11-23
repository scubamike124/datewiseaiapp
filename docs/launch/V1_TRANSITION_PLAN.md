# DateWise: moving v1 users off the former developer's backend

Status: **plan only**, written 2026-11-23. Nothing has been sent, changed or deployed.

This plan does not assume wrongdoing by anyone. The original build was set up by the former developer on infrastructure they created, which was a normal arrangement at the time. The aim is only to make sure that every DateWise user's data goes to infrastructure the current owner controls, and that the hand-over is orderly.

Labels:
- **MEASURED**: code at a named commit, or a recorded probe.
- **ASSUMPTION**: an estimate.
- **UNKNOWN**: needs App Store Connect or the former developer.

## 1. Which build talks to which backend

| Build | Released | Coach chat + photo coach | Accounts | Minimum iOS | Evidence |
|---|---|---|---|---|---|
| **1.0** (1.0.0+1) | App Store, 2026-06-24 (MEASURED, iTunes lookup recorded 2026-09-01) | **`https://datewise-photo-coach.kaowserprobd.workers.dev`**: the former developer's Cloudflare Worker (ownership inferred from the name, not confirmed) | Supabase project `cprnegusibbmcyltylzk` (did not resolve on 2026-09-01) | 12.0 | `lib/services/ai_config.dart:27` at `1a814c3` and `d618423`; `docs/qa/APP_STORE_1_0_2_RELEASE.md`. The exact commit built is UNKNOWN; every candidate commit uses this URL |
| 1.0.1 (1.0.1+2) | No evidence it was submitted | same as 1.0 | same | 12.0 | `d618423` |
| **1.0.2** (1.0.2+3) = `main` | **UNKNOWN** whether it shipped (App Store Connect → version history) | `https://datewise-photo-coach.scubamike124.workers.dev`: **owner's Worker** | Supabase (same dead project, still inline) | 12.0 | `main:lib/services/ai_config.dart:29`, `main:lib/services/supabase_config.dart:36` |
| **2.0.0** (v2) | Not released | Owner's Worker. It later moves to a dedicated account: see `CLOUDFLARE_ACCOUNT_SEPARATION_PLAN.md` | none (no accounts in v2) | **15.0** | `lib/services/ai_config.dart:14`, `ios/Runner.xcodeproj` @ `9c0aea1` |

### What a 1.0 install sends to its backend (MEASURED from the 1.0-era code)
- **Chat:** the conversation history, plus a system prompt that includes the profile summary: age, gender, who they're interested in, dating goal, dating app and city (`lib/services/persona.dart`, `lib/models/user_profile.dart` @ `1a814c3`).
- **Photo coach:** the photos the user chose to have reviewed, sent as base64 images.
- **Accounts (if used):** email and password, sent to Supabase. That project no longer resolves, so sign-up and sign-in can't work today.

On 2026-09-01, the former developer's Worker answered photo requests but returned HTTP 502 for chat. Its current state could not be checked from here (UNKNOWN).

## 2. What the owner can and cannot control

| | Owner can | Owner cannot |
|---|---|---|
| The former developer's Worker | Ask for a hand-over or shutdown in writing | Change, read, monitor, switch off or redirect it. It's on another person's Cloudflare account |
| 1.0 binaries already on phones | Offer an update in the App Store (same app, 6780110141) | Force an update. Change the URL inside an installed build. Remove old versions from users' devices |
| The owner's Worker (used by 1.0.2 and v2) | Everything: code, limits, an "update the app" reply, shutdown | — |
| Users on iOS 12–14 | Nothing in v2: it needs iOS 15 | Give them v2. The App Store will keep offering them the last compatible version (1.0 or 1.0.2) |

### Risks while 1.0 is in use (possibilities, not allegations)
| Risk | Why it's possible | Mitigation |
|---|---|---|
| Visibility of user data | Whoever runs a Worker can choose to log what it receives (chats, profile summary, photos). Nothing shows this is happening. | Move users to v2; ask for written confirmation that no request data is kept, and deletion of any that is |
| Switched off | The account owner can delete or disable it at any time, or the account can lapse | Expected over time. v1 chat already fails, so the user impact is small. The real fix is the v2 update |
| Changed | The code can be changed without notice, including its replies | Ask for a shutdown, or a hand-over of the Worker, after the adoption window |
| Cost or abuse | Abuse of that Worker is on the former developer's account, not the owner's | None needed from the owner |

## 3. Plan

### 3.1 Ship v2 as an update to the same app
- v2 keeps bundle ID `com.datewise.datewiseAi` and app 6780110141 (`pubspec.yaml` `2.0.0+100`), so every 1.0 user on **iOS 15 or later** is offered v2 as a normal App Store update. **Do not create a new app record**, or 1.0 users would never be offered the update.
- **Phased release** (App Store Connect → the version → Phased Release for Automatic Updates): 7 days, which is the default. It only paces **automatic** updates; anyone can update manually right away. Pause it if the new backend misbehaves.
- **Minimum OS:** v2 requires iOS 15 and v1 supported iOS 12. Users on iOS 12–14 stay on their current build.
  - Lowering v2's target isn't recommended without testing (StoreKit 2 entitlement reading needs iOS 15).
  - Accept that this group stays on 1.0 until the former developer's Worker is shut down, after which their chat (already failing) and photo coach stop.
  - The size of this group is visible in App Store Connect → App Analytics → Metrics, filtered by version and platform version (UNKNOWN today).
- **App Store "What's New" text** (suggested): "DateWise 2.0: four new AI coaches in English and Spanish, voice replies, and a new private backend. Your conversations stay on your phone. Update to keep chatting with your coach."

### 3.2 In v2: a one-time notice and the privacy policy
- **In-app notice (to build, reusing the existing localized notice strings; EN/ES):** show once to users upgrading from 1.0.x. v2 already detects v1 data: the legacy profile keys and v1 photo messages in `lib/models/user_profile.dart` and `chat_message.dart`. Suggested text:
  > "DateWise has been updated. Your coach now runs on DateWise's own secure server, and your chats stay on this phone. Photos and accounts from the previous version are no longer used. You can delete everything at any time in Settings."
- **Privacy policy** (`web/privacy.html`, `web/privacy-es.html`, `lib/content/legal_text.dart`): add a short "Earlier versions" paragraph.
  > "Versions 1.0 and 1.0.1 of the app sent coaching messages, profile details and photos you chose to review to a server operated for the app at that time. Version 2.0 sends messages only to DateWise's own server, which keeps no conversation content. If you used an earlier version and have a question about your data, contact support@datewiseai.com."

  Have the owner or counsel confirm the wording. It should be factual and name no one.

### 3.3 The owner's own Worker (for 1.0.2 users, if 1.0.2 shipped)
- **Now:** chat-v6 on the owner's Worker fixes 1.0.2's HTTP 502 (`CLOUDFLARE_ACCOUNT_SEPARATION_PLAN.md`, step 1).
- **After the adoption window:** replace it with a responder that streams one text reply in v1's format. v1 shows any streamed text, but shows any error status as "trouble reaching the coach", and it doesn't understand HTTP 426. Suggested reply: "Please update DateWise in the App Store to keep using your coach." After that, delete the Worker.

### 3.4 Ask the former developer: hand-over or shutdown, and data deletion
Send in writing (email), and keep a copy. A neutral draft:

> Subject: DateWise AI: wrapping up the original backend
>
> Hi [name],
>
> Thank you again for building the first version of DateWise AI. We're about to release version 2.0 as an update to the same App Store app. It uses a new backend that I run myself.
>
> The 1.0 build still sends coaching requests to the Cloudflare Worker you set up (datewise-photo-coach.kaowserprobd.workers.dev). To finish the hand-over cleanly, could you help with the following?
>
> 1. **Until [date: release + 90 days]:** please keep the Worker as it is, so 1.0 users aren't cut off before they update. If you'd prefer to transfer the Worker to me instead, I'm happy to arrange that.
> 2. **After that date:** please either transfer the Worker to my Cloudflare account or delete it. If it's easier, you could first replace it with a short message asking users to update the app; I can send you the code.
> 3. **User data:** please confirm whether the Worker, its logs (Workers Logs, Logpush or tail), or any other system kept chat messages, profile details or photos from DateWise users. If any were kept, please delete them and let me know when that's done.
> 4. **Other access:** if you still have access to anything else for DateWise (App Store Connect, the Apple developer account, the Supabase project `cprnegusibbmcyltylzk`, the datewiseai.com domain or email, or any API keys), please let me know so we can transfer or remove it.
>
> A short written reply to each point is all I need. Thanks for your help.
>
> [owner name]

Before sending, the owner fills in the date and checks point 4 against App Store Connect → Users and Access, since some access may already have been removed.

### 3.5 What to tell users
- **App Store "What's New"** (3.1) and the **in-app notice** (3.2).
- **Support replies** (support@datewiseai.com) for users who ask why chat stopped on the old version:
  > "Please update DateWise from the App Store to version 2.0. The previous version's coach service is being retired. If your iPhone can't install 2.0 (it needs iOS 15 or later), the old version's coach may stop working. We're sorry for the inconvenience."
- **No mass email:** v1 accounts depended on a Supabase project that no longer exists, so there is no reliable user list. Don't try to rebuild one.

### 3.6 Timeline (from v2's App Store release date, R)
| When | Action | Owner |
|---|---|---|
| Now | chat-v6 on the owner's Worker (fixes 1.0.2). Confirm in App Store Connect whether 1.0.2 shipped, and check active devices per version. | Owner |
| Before R | Send the message in 3.4 (only points 1 and 4 need an answer before release). Privacy-policy paragraph live on datewiseai.com. In-app notice in the v2 build. | Owner / agent |
| R | v2 release with 7-day phased release; "What's New" text | Owner |
| R + 7 days | Phased release done. Check crash and usage metrics. | Owner |
| R + 30 days | Check active devices on 1.0.x (App Analytics). Send a gentle reminder to the former developer if needed. | Owner |
| R + 90 days (adoption window) | Former developer transfers or shuts down their Worker and confirms deletion. Owner's Worker switches to the "please update" responder. | Former developer / owner |
| R + 180 days | Delete the owner's legacy Worker if v1 traffic is near zero. Close the transition in `docs/launch/LAUNCH_READINESS.md`. | Owner |

## 4. Open questions for the owner
1. Did 1.0.2 ship? (App Store Connect → the app → App Store → version history.)
2. How many active devices are on 1.0 and 1.0.2, and how many are on iOS 12–14?
3. Does the former developer still have any App Store Connect, Apple developer, domain, email or Supabase access?
4. Who should sign and send the message in 3.4? (A personal email from the owner is fine.)
