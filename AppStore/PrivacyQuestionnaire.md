# App Privacy questionnaire (App Store Connect)

Human-readable form of the four privacy manifests. Every answer below is derived from
`DevinMobile/PrivacyInfo.xcprivacy` (app + linked DevinKit) and the extensions' copies —
`DevinWidget/`, `DevinIntents/` (Siri / Shortcuts) and `DevinShareExtension/` `PrivacyInfo.xcprivacy`.
When the manifests change, change this file in the same PR.

## 1. What leaves the device

| Data | Sent to | Why | Kept where |
| --- | --- | --- | --- |
| Personal Access Token (`cog_…`) | `api.devin.ai` only, as the `Authorization` header (`DevinClient`) | Authenticates every API call | Device Keychain (`ai.devin.mobile`, access group `group.ai.devin.mobile`) — never logged, never sent elsewhere |
| Enterprise `org-…` ID | `api.devin.ai` (URL path) | Scopes API calls | Keychain, next to the token |
| Prompts, replies, tags, repository names, playbook/knowledge/secret **ids** | `api.devin.ai` | The user's own Devin sessions | Devin's servers (the product); not stored by the app beyond the in-memory model |
| Attachments the user picks (photos, camera, files) | `api.devin.ai` (`POST …/attachments`) | Attached to a message or a new session by the user's explicit action | Uploaded only when the user taps Send/Start |
| Local notifications | Stay on device (`UNUserNotificationCenter`) | "Devin needs you" while backgrounded | — |
| `SessionSnapshot` (ids, titles, status buckets) | Stays on device (App Group `UserDefaults`) | Widget, Siri ("What is Devin waiting on") + background diff | App Group container; removed on sign-out |
| `SharedDraft` (shared URL / text / images from the share sheet) | Stays on device (App Group `UserDefaults` + group container) | Prefills New Session in the app; images are uploaded to `api.devin.ai` only when the user taps Start | Deleted when the app takes it, or after 24 h |
| Live Activity content (session title, status, ACUs) | Stays on device (ActivityKit) | Lock-screen status for one watched session | Ends with the session or when the user stops it |
| Recent repositories, inbox scope | Stay on device (`UserDefaults.standard`) | Convenience cache | Private container |

There is **no** analytics, crash reporting, advertising, tracking SDK or first-party telemetry
endpoint. `NSAppTransportSecurity.NSAllowsArbitraryLoads` is `false`. Downloads of attachments follow
the API's 307 to a presigned URL; the token is sent only to `api.devin.ai` (see `HANDOFF.md` §2).

## 2. Answers for the App Store Connect "App Privacy" section

| Question | Answer | Manifest key |
| --- | --- | --- |
| Do you or your third-party partners collect data from this app? | **No — "Data Not Collected"** | `NSPrivacyCollectedDataTypes = []` |
| Is data used to track users across apps/websites? | **No** | `NSPrivacyTracking = false` |
| Tracking domains | none | `NSPrivacyTrackingDomains = []` |

Rationale. Apple counts data as *collected* when it is transmitted off-device in a way that lets the
**developer or their third-party partners** access it beyond servicing the request. This app is a
thin client to the user's own Devin account: nothing goes to the app developer, and Devin
(`api.devin.ai`) is the service the user signed up for, not a partner/SDK of the app — the same
position taken by third-party mail, Git and Mastodon clients that ship "Data Not Collected". The
token itself is a credential the user pastes in; it is stored only in the Keychain and only ever
presented to `api.devin.ai`.

Two things would change the answer — re-run this section before submitting if either happens:

- **Cognition publishes the app itself.** Then `api.devin.ai` is a first-party server and everything
  in §1 that reaches it is "collected, linked to the user, for App Functionality": *User ID*
  (`user_id`/`org_id` from `GET /v3/self`), *Name* (`user_name`), *Other User Content* (prompts,
  messages, tags), *Photos or Videos* + *Other Data Types* (attachments). None is used for tracking.
- **Crash reporting / analytics is added (#48).** Declare *Crash Data* / *Performance Data* /
  *Other Diagnostic Data* (not linked, not for tracking) in `NSPrivacyCollectedDataTypes` and, if a
  third-party SDK is used, ship its own `PrivacyInfo.xcprivacy` and add any tracking domains.

## 3. Required-reason APIs (`NSPrivacyAccessedAPITypes`)

| Category | Reasons | Where |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (app-private defaults) | `RecentRepos`, `InboxScope` (`UserDefaults.standard`), `DeepLinkRouter` (`-OpenURL` launch argument), `AppGroup.defaults` fallback to `.standard` |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `1C8F.1` (App Group `group.ai.devin.mobile`) | `AppGroup.defaults` → `SessionSnapshot.load/save/clear`, `WidgetContent.resolve`, `SharedDraft.load/save/clear` (app, widget, App Intents and share extensions) |

Not used anywhere (audited, see §4): file timestamp APIs (`creationDate`, `modificationDate`,
`stat`/`fstat`, `getattrlist`, `NSURLContentModificationDateKey`…), system boot time
(`systemUptime`, `mach_absolute_time`), disk space (`volumeAvailableCapacity`, `statfs`), active
keyboard (`activeInputModes`). `UIPasteboard` **writes** (copy session id / code / URL) are not a
required-reason API. Each extension (widget, App Intents, share) declares the same UserDefaults category because
extensions do not inherit the app's manifest.

DevinKit is a local source package compiled into each target, so its `UserDefaults` use is covered
by the app's and the extensions' manifests; it does not need one of its own.

## 4. How to re-audit

Run after adding any Foundation/UIKit API that reads system or file metadata:

```sh
# Source level — every hit must map to a row in §3 or be a non-required API.
rg -n 'UserDefaults|systemUptime|mach_absolute_time|creationDate|modificationDate|contentModificationDate|attributesOfItem|getattrlist|fstat|\bstat\(|volumeAvailableCapacity|statfs|activeInputModes' \
   DevinKit/Sources DevinMobile DevinWidget DevinIntents DevinShareExtension

# Binary level — what App Store Connect actually scans (ITMS-91053). Build first (see HANDOFF.md §1).
APP=.derived/Build/Products/Debug-iphonesimulator/DevinMobile.app
for bin in "$APP/DevinMobile.debug.dylib" "$APP/PlugIns/DevinWidget.appex/DevinWidget.debug.dylib" \
           "$APP/PlugIns/DevinShareExtension.appex/DevinShareExtension.debug.dylib" \
           "$APP/Extensions/DevinIntents.appex/DevinIntents.debug.dylib"; do
  nm -u "$bin" | grep -iE 'NSUserDefaults|systemUptime|mach_absolute_time|creationDate|modificationDate|getattrlist|fstat|lstat|statfs|volumeAvailableCapacity|activeInputModes|NSFileSystemFreeSize'
done
plutil -lint "$APP/PrivacyInfo.xcprivacy" "$APP"/PlugIns/*.appex/PrivacyInfo.xcprivacy "$APP"/Extensions/*.appex/PrivacyInfo.xcprivacy
```

Expected today: only `_OBJC_CLASS_$_NSUserDefaults` in all four binaries. Xcode's *Product → Archive →
Generate Privacy Report* produces the same table as §2–§3 from the built archive.

## 5. Related review items (not part of the manifest)

| Item | State |
| --- | --- |
| Privacy policy URL (required in App Store Connect) | **Owner decision** — needs a hosted page; §1 of this file is the content |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` in `project.yml` (HTTPS only, standard exemption) |
| Usage descriptions | `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` in `project.yml`; notifications are requested with a plain-language toggle in onboarding + Settings |
| Sign in with Apple (guideline 4.8) | Not required — the app has no third-party social login and creates no account; it accepts a token the user already owns |
| App Review demo access (guideline 2.1) | Reviewers need a PAT for a demo org — **owner supplies one in the App Review notes**. `-MockAPI` is DEBUG-only and is not available in the App Store build |
| Account deletion (guideline 5.1.1(v)) | Not applicable — no account is created in the app; Settings → Sign out removes the token from the Keychain and the widget snapshot |
