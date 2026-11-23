# DateWise: moving v1 users to v2 (summary)

Status: **plan only**, 2026-11-23. Nothing has been changed or deployed. The
full working plan is kept outside this public repository.

## Which build uses which backend
| Build | Status | Coach backend |
|---|---|---|
| 1.0 (1.0.0+1) | On the App Store | The backend set up for the original 1.0 release. The current owner does not operate it. |
| 1.0.1 (1.0.1+2) | No evidence it was submitted | Same as 1.0 |
| 1.0.2 (1.0.2+3, `main`) | Whether it shipped is to be confirmed in App Store Connect | The owner's Worker `datewise-photo-coach` (current Cloudflare account) |
| 2.0.0 (v2) | Not released | The owner's Worker, chat-v7-cost-guard, ideally on a dedicated DateWise account (`CLOUDFLARE_ACCOUNT_SEPARATION_PLAN.md`) |

v2 needs iOS 15 or later. Users on iOS 12–14 stay on the last build their
device supports.

## Update and retire timeline (R = v2 App Store release date)
| When | Action |
|---|---|
| Now | Deploy chat-v6 to the owner's Worker to fix 1.0.2's chat (HTTP 502), using `WORKER_DEPLOY_RUNBOOK.md`. Confirm in App Store Connect whether 1.0.2 shipped. |
| Before R | v2 keeps the same app record and bundle ID, so existing users are offered it as a normal update. Add the privacy-policy note about earlier versions and a one-time in-app notice for upgraders. |
| R | Release v2 with a 7-day phased release. "What's New" asks users to update to keep using the coach. |
| R + 30 days | Check active devices per version in App Analytics. |
| R + 90 days | Ask for the original 1.0 backend to be handed over or retired. Switch the owner's legacy Worker to a "please update" responder that makes no AI calls. |
| R + 180 days | Delete the owner's legacy Worker once v1 traffic is near zero. |

## Forced-update reply
v1 shows any streamed text, but shows every error status as "trouble reaching
the coach" (it cannot read error codes or HTTP 426). So the retirement
responder streams a single normal reply in v1's format:

> "Please update DateWise in the App Store to keep using your coach."

Support reply for users who ask why chat stopped on an old version:

> "Please update DateWise from the App Store to version 2.0. The previous
> version's coach service is being retired. If your iPhone can't install 2.0
> (it needs iOS 15 or later), the old version's coach may stop working. We're
> sorry for the inconvenience."
