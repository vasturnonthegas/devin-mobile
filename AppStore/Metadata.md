# App Store listing metadata

Draft copy for App Store Connect. Fields marked **owner** need the repo owner (they depend on the
Apple Developer account, a hosted URL, or the identity decision in #45 / HANDOFF.md §6.4).

## Identity

| Field | Value |
| --- | --- |
| Name | Devin Mobile (**owner** — "Devin" alone is Cognition's mark; `CFBundleDisplayName` is currently `Devin`) |
| Subtitle (30) | Run your Devin sessions anywhere |
| Bundle ID | `ai.devin.mobile` (extensions: widget `ai.devin.mobile.widget`, App Intents `ai.devin.mobile.intents`, share `ai.devin.mobile.share`) |
| Primary category | Developer Tools |
| Secondary category | Productivity |
| Price | Free |
| Age rating | 4+ (no objectionable content, no unrestricted web access, no gambling/contests, no user-generated content shown to *other* users) |
| Privacy policy URL | **owner** — content in `AppStore/PrivacyQuestionnaire.md` §1 |
| Support URL | **owner** — e.g. the GitHub repo issues page |
| Marketing URL | optional |
| Copyright | **owner** |

## Promotional text (170)

See which Devin sessions need you, read the transcript, reply, and start new work — from your phone.

## Description

Devin Mobile is a native iOS client for Devin, the AI software engineer. Sign in with a Personal
Access Token and your sessions are one tap away.

• Inbox — sessions grouped into Needs you, Working, Finished, Sleeping and Failed, filtered by
  repository, tag, owner and date. Mine vs. Everyone for team orgs.
• Session detail — the full transcript with Markdown and code, pull requests with their review
  state, structured output, attachments, insights and child sessions. Reply to unblock Devin, wake a
  sleeping session, archive or terminate.
• New session — pick repositories from your org, attach knowledge notes and secrets, choose a
  playbook, set an ACU limit, add screenshots from Photos or the camera.
• Devin Review — trigger and follow a review on any pull request Devin opened.
• Notifications — a local alert when a session moves from Working to Needs you or finishes, even
  while the app is in the background.
• Home-screen widget — how many sessions need you, and the top three.

Your token stays in the device Keychain and is only ever sent to api.devin.ai. The app collects no
analytics and includes no third-party SDKs.

Requires a Devin account and a Personal Access Token (Devin → Settings → Devin API).

## Keywords (100)

devin,ai,agent,coding,software engineer,pull request,github,sessions,developer,ci

## What's New (first release)

First release: inbox, session detail with replies, new sessions with attachments, Devin Review,
background notifications and a home-screen widget.

## App Review notes

- The app needs a Devin Personal Access Token to do anything. **Owner**: create a PAT on a demo org
  with a handful of sessions and paste it into the review notes (sign-in field on the first screen).
- No account can be created in the app; "Sign out" in Settings deletes the token from the Keychain.
- Background refresh uses `BGAppRefreshTask` (`ai.devin.mobile.refresh`); notifications are local.

## Screenshots

App Store Connect needs one iPhone set (6.9" 1320×2868 or 6.5" 1284×2778; 6.3" 1206×2622 from
`iPhone 17 Pro` is also accepted) and, because `TARGETED_DEVICE_FAMILY = 1,2`, one iPad 13" set
(2064×2752). `AppStore/screenshots.sh` captures the iPhone set from a booted Simulator against the
in-process mock API (`-MockAPI`, DEBUG only — the Simulator status bar is normalised to 9:41, full
battery, full signal):

| # | File | Screen | How the script gets there |
| --- | --- | --- | --- |
| 1 | `01-inbox.png` | Inbox grouped by bucket, Needs-you first | launch `-MockAPI` |
| 2 | `02-session.png` | Session detail: transcript, PR badges, composer | launch `-MockAPI -OpenURL devinmobile://session/devin-mock000` |
| 3 | `03-finished.png` | Finished session with structured output + insights | `-OpenURL devinmobile://session/devin-mock002` |
| 4 | `04-onboarding.png` | Sign-in screen (token in Keychain copy) | launch without `-MockAPI` after a sign-out / fresh install |

New session, Settings and the widget need taps (toolbar buttons / home screen) — take those by hand with
`xcrun simctl io booted screenshot <file>` after navigating, or from Xcode's widget preview.

```sh
xcodegen generate
xcodebuild build -project DevinMobile.xcodeproj -scheme DevinMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug -derivedDataPath .derived
AppStore/screenshots.sh .derived/Build/Products/Debug-iphonesimulator/DevinMobile.app out/
```

Screenshots are not committed to the repository; upload them straight to App Store Connect.
