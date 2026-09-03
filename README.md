# Devin Mobile

A native iOS client for [Devin](https://devin.ai): see which sessions need you, read the transcript, reply, and kick off new work from your phone.

```
DevinKit/       Swift package — v3 API client, models, Keychain store. Unit-tested, builds on Linux.
DevinMobile/    SwiftUI app (iOS 17+). Onboarding → Inbox → Session detail / New session / Settings.
project.yml     XcodeGen spec; the .xcodeproj is generated, not committed.
```

## Build

```sh
brew install xcodegen
xcodegen generate
open DevinMobile.xcodeproj        # pick your team under Signing, run on a device or simulator
```

Package tests run anywhere Swift 6 does:

```sh
cd DevinKit && swift test
```

## Sign in

Paste a Personal Access Token (`cog_…`) from **Devin → Settings → Devin API**. The app calls `GET /v3/self` to find your organization, verifies it can list sessions, and stores the token in the Keychain. Enterprise tokens aren't bound to an org — tap **I have an enterprise token** and enter the `org-…` ID.

## How it works

- Inbox polls `GET /v3/organizations/{org}/sessions` every 10s while visible and groups sessions into **Needs you / Working / Finished / Sleeping / Failed** from `status` + `status_detail`.
- Session detail polls the session and `/messages` (5s while active, 30s otherwise). Replies go through `POST /messages`; **Sleep & archive** hits `/archive`; **Terminate** is a `DELETE`.
- New session posts `prompt`, `repos`, `devin_mode`, `playbook_id`, `max_acu_limit`, `tags`.

There is no push channel in the API today, so status changes arrive by polling. A small relay + APNs is the natural next step for lock-screen "Devin needs you" alerts.

## Roadmap

- [ ] Local notifications on Working → Needs you while backgrounded (BGAppRefresh)
- [ ] Home-screen widget with the Needs-you count
- [ ] App Intents: "Ask Devin to …", "What's Devin waiting on?"
- [ ] Share Sheet: send a GitHub URL / text to a new session
- [ ] Live Activity for a session in progress
