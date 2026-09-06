# Handoff: Devin Mobile (iOS)

Written for the next Devin session (or human) picking this up. Goal of the project: a native iOS
client that mirrors the Devin web app (app.devin.ai) closely enough that a developer can run their
agents from a phone. Read this, then `README.md`, then the code — it's small.

## 1. Where things stand

| Area | State |
| --- | --- |
| `DevinKit/` Swift package (API client, models, Keychain) | Done for the session/message/playbook surface. 13 XCTest cases, pass on Linux + macOS. |
| `DevinMobile/` SwiftUI app | Compiles cleanly for iOS Simulator on CI (`xcodebuild`, zero warnings). **Never run against the live API yet** — no PAT was available. Expect first-run bugs. |
| CI (`.github/workflows/ci.yml`) | `swift test` on `swift:6.0-jammy` + `macos-15`; `xcodegen generate` + simulator build. Green on `main`. |
| TestFlight (`.github/workflows/testflight.yml`) | Tag `vX.Y.Z` → Release archive, App Store Connect export, `altool` upload. **Needs the owner's signing secrets** (§6 item 5); until they exist the job fails at its first step listing what is missing. Never run end-to-end yet. |
| Devin environment | Devin macOS sessions have Xcode (26.x) and iPhone simulators; `brew install xcodegen` is needed before `xcodegen generate`. Linux sessions only run `cd DevinKit && swift test`. |
| Repo | `github.com/vasturnonthegas/devin-mobile`, trunk `main`. Work is tracked as GitHub issues (epics #3–#9) and `Sprint N` milestones — see §7. |

### Build locally (macOS)

```sh
brew install xcodegen
xcodegen generate                # .xcodeproj is gitignored; regenerate after adding/removing files
open DevinMobile.xcodeproj       # Signing & Capabilities → pick team → Run
cd DevinKit && swift test        # package tests, also fine on Linux
```

Sign in with a PAT (`cog_…`, Devin → Settings → Devin API). Enterprise PATs need the `org-…` ID.

## 2. Architecture (keep it this way)

```
DevinKit (no UI, platform-agnostic, unit-tested with MockTransport)
  Client/   DevinClient (async/await, Bearer, RFC 9457 → DevinError), HTTPTransport (injectable)
  Models/   Session, SessionMessage, Playbook, Principal, Repository, Page<T>, NewSessionRequest/SessionQuery/RepositoryQuery, JSONValue,
            KnowledgeNote/KnowledgeFolder(Tree), OrgSecret (metadata only)
  Storage/  CredentialStore protocol; KeychainCredentialStore (iOS), InMemoryCredentialStore (tests/previews)
  Sharing/  AppGroup (ids shared with extensions), DeepLink (devinmobile:// URLs), SessionSnapshot (last-known buckets,
            + `changes(since:)` bucket diff, `spokenSummary` for Siri, `entries(matching:)` title search),
            WidgetContent (signed-out / awaiting-first-load / sessions, from Keychain + snapshot),
            GitHubLink (github.com URL → `repos` path), SharedDraft (share-sheet payload parked in the App Group),
            SessionActivityAttributes (Live Activity attributes + State; ActivityKit conformance is iOS-only)

DevinMobile (SwiftUI, iOS 17, @Observable + @MainActor, no third-party deps)
  App/          AppModel (auth state machine), SessionStore (list + polling), RecentRepos (cache),
                DeepLinkRouter + DeepLinkNavigation (URL scheme → inbox navigation),
                BackgroundRefresh (BGAppRefreshTask) + SessionNotifier (local notifications) +
                NotificationDelegate (UNUserNotificationCenter delegate, owns the DeepLinkRouter),
                WidgetTimeline (publishes SessionSnapshot + reloads WidgetKit),
                SharedDraftFlow (pending SharedDraft → prefilled NewSessionView on activation),
                SessionLiveActivity (the one pinned Live Activity: start/stop/update/refresh),
                DiagnosticsCollector (MetricKit subscriber → on-device JSON, see §8)
  Features/     Onboarding, Inbox (+ InboxDetailColumn for the iPad split view), SessionDetail (+ SessionDetailModel),
                NewSession (+ RepoPicker), Settings
  Support/      StatusBadge, PullRequestLink (+ PullRequestStateBadge, ExternalLink),
                Markdown/ (MarkdownDocument block tree + MarkdownView)

DevinWidget (WidgetKit extension, `ai.devin.mobile.widget`, same App Group; embedded in the app)
  NeedsYouWidget (small + medium): "N sessions need you" + top 3 rows → devinmobile://session/<id>
  SessionActivityWidget: lock screen + Dynamic Island for the pinned session (status, ACUs, freshness)

DevinIntents (App Intents extension, `ai.devin.mobile.intents`, same App Group; embedded under Extensions/)
  StartDevinSessionIntent(prompt, repo?) · ReplyToDevinIntent(session, message) · WhatIsDevinWaitingOnIntent
  SessionEntity (+ SessionEntityQuery over the snapshot), DevinShortcuts (Siri phrases), SignedInDevin (Keychain → DevinClient)

DevinShareExtension (share sheet, `ai.devin.mobile.share`, same App Group; embedded in the app)
  ShareViewController → ShareItemLoader (URL / text / images) → ShareModel + ShareDraftView → SharedDraft.save

AppStore/       PrivacyQuestionnaire.md (ASC answers derived from the manifests), Metadata.md (listing copy,
                owner decisions), screenshots.sh (iPhone set from a booted Simulator + -MockAPI)
```

Rules of thumb that the existing code follows:

- **All API knowledge lives in DevinKit.** Views never see JSON keys or status strings; they use
  `Session.bucket`, `statusSummary`, `needsAttention`, `displayTitle`.
- **New API calls = client method + fixture + test.** Copy the pattern in `DevinClientTests.swift`
  (assert URL, query, headers, body; decode a realistic fixture). Fixtures include unknown enum
  values on purpose — decoding must tolerate them (`try?` on optional enums).
- **Polling, not push.** The API has no webhook/SSE for session status. `SessionStore` polls the
  list every 10 s while the inbox is visible; `SessionDetailModel` polls 5 s (active) / 30 s.
- **Cursor pagination.** `SessionStore` loads `first=50` pages and follows `end_cursor` via
  `SessionQuery.after` (`loadMore()`, prefetched when the last 10 inbox rows appear). Polling
  re-fetches only page 1 and upserts by `session_id` (`[Session].merging`) so deeper pages stay put.
- **Member names are in-memory only.** `MemberDirectory` (DevinKit actor) fetches the whole
  members list once per launch and caches `user_id → OrgMember`; a 403 is sticky and the inbox
  simply omits owner chips (shown in Everyone scope only). Nothing about members is persisted.
- **Wake-on-message.** Per the spec, `POST …/sessions/{id}/messages` "will automatically resume
  [the session] if suspended" (`suspended → resuming → running`), so the composer stays enabled
  for every `suspended` session regardless of `status_detail`. `exit` (VM destroyed: terminated or
  created with `resumable: false`) and `error` sessions cannot receive messages, so the composer is
  replaced by an explanation. `Session.messaging` (`Session+Messaging.swift`) is the single source
  of truth; `SessionResponse` has no `resumable` flag, so a disposable session that is still
  `suspended` looks wakeable until the API rejects the message (409) — that error is shown as-is.
- **Repositories come from the API; recents are a cache.** `RepoPickerModel` searches
  `GET /v3beta1/…/repositories` server-side (`filter_name`, 300 ms debounce, latest request wins)
  and pages by cursor; `RecentRepos` (UserDefaults) only pins rows on top and seeds filter
  suggestions — it is never the list's source. `Repository.fullPath` (host-prefixed
  `github.com/owner/repo`) is what goes into `NewSessionRequest.repos`; `repo_path` alone may omit
  the host. A 403/404 from the repositories endpoint is sticky per picker: the list is hidden and
  the user types a path instead.
- **Simulator without a PAT.** Launch with `-MockAPI` (DEBUG only) to run against an in-process
  fake API (`DevinMobile/Support/MockAPI.swift`, 130 sessions, 120 repositories) backed by
  `InMemoryCredentialStore`. `POST …/messages` to a suspended mock session flips it to `resuming`;
  to an exited one returns 409.
  `POST …/sessions` appends to an in-memory `created` list (served by list + detail for the rest of
  the launch); `…/insights` has analysis for every third session and "arrives" 5 s after `generate`.
- **Insights are generated, not fetched.** `GET …/sessions/{id}/insights` returns `analysis: null`
  until `POST …/insights/generate` has run server-side, so `SessionInsightsModel` polls the GET every
  4 s (≤ 150 s) after Generate. `SessionInsightsPanel` is shown only for non-`working` sessions; a 403
  on either call is sticky and removes the panel (`isForbidden`). "Use this prompt" opens
  `NewSessionView(initialPrompt:)` via `.suggestedPromptSessionFlow` and pushes the created session.
- **Attachment bytes go through `DevinClient.attachmentData`.** `GET …/sessions/{id}/attachments`
  returns a bare array (not the cursor envelope). Attachment URLs point at the API, which 307s to a
  presigned URL; the client sends the Bearer token only to `baseURL.host` and URLSession drops it on
  the redirect. Never hand an attachment URL to `AsyncImage`/`Link` — it would 401 or leak the token.
  Downloads are cached per `SessionDetailView` (`SessionAttachmentsModel`) and files land in `tmp/`.
- **Secrets are metadata only.** `GET …/secrets` never returns values and `OrgSecret` has no field
  for one; pickers render `key`/`note`/type. `SessionResourcesModel` loads notes + secrets once per
  New Session sheet and a 403 on either endpoint hides that list (both → the section disappears).
  `-MockForbidKnowledge` / `-MockForbidSecrets` (with `-MockAPI`) exercise those paths.
- **Credentials only in Keychain** (`ai.devin.mobile` / `credentials`). Nothing is stored until
  `GET /v3/self` + `GET /sessions?first=1` both succeed.
- **One App Group, `group.ai.devin.mobile`, is the only shared identifier** (`AppGroup.identifier`).
  It is the App Groups entitlement *and* the Keychain access group (iOS accepts app groups there
  without the team prefix), so `AppGroup.credentialStore` and `AppGroup.defaults` are what a widget
  / intent / share extension uses — every extension target must list the same group in `project.yml`.
  At launch `adoptingCredentials(from:)` moves a pre-App-Group Keychain item into the shared store and
  falls back to the private store if the entitlement is missing (`errSecMissingEntitlement`).
- **`SessionSnapshot` is the extension-facing view of the inbox.** `SessionStore` writes it to
  `AppGroup.defaults` after every successful *unfiltered* refresh (ids, titles, buckets, no token).
  Extensions read it instead of calling the API; anything richer needs its own story.
- **A snapshot exists only while signed in.** `WidgetTimeline` (app) saves it on refresh and
  removes it in `AppModel.signOut`, so `WidgetContent.resolve` treats a present snapshot as proof of
  a signed-in user even when the shared Keychain can't be read (locked device, `-MockAPI`'s in-memory
  credentials). Keychain credentials without a snapshot = "open Devin to load"; neither = signed out.
  `WidgetCenter.reloadAllTimelines()` is called only when the rows changed or the last publish is
  ≥ 5 min old — the 10 s poll must not eat the WidgetKit refresh budget. The snapshot (and so the
  widget) counts the whole unfiltered list, not the inbox's Mine/Everyone scope.
- **Deep links are `devinmobile://session/<id>`** (`DeepLink`; extensions build URLs with
  `DeepLink.url`). `DevinMobileApp.onOpenURL` parks the link in `DeepLinkRouter`; the inbox's
  `.followsDeepLinks` replaces the navigation path once signed in, fetching the session by ID when it
  isn't on the loaded pages. `-OpenURL <url>` (DEBUG) simulates a cold start alongside `-MockAPI`.
- **Background refresh = one poll of page 1, diffed against the snapshot.** `BackgroundRefresh`
  (`BGAppRefreshTask` `ai.devin.mobile.refresh`, ~15 min, bound with `.backgroundTask(.appRefresh)`
  and re-armed on every run and whenever a signed-in app backgrounds) fetches the unfiltered first
  page, builds a `SessionSnapshot`, and posts one local notification per
  `SessionSnapshot.notableChanges(since:)` — `working → needsYou` and `* → finished`, only for
  sessions present in both snapshots (DevinKit, unit-tested). The new snapshot is saved *after*
  the diff, so a failed fetch keeps the baseline. Notification requests are keyed `session-<id>`
  (a later transition replaces the earlier banner); more than `SessionNotifier.summaryThreshold`
  changes collapse into one summary. `userInfo["deepLink"]` carries the `devinmobile://` URL and
  `NotificationDelegate` (a `@UIApplicationDelegateAdaptor`, set as the center's delegate in
  `willFinishLaunching`) feeds taps into the same `DeepLinkRouter` as `onOpenURL`. The permission
  prompt lives in onboarding (toggle, requested right after sign-in) and Settings
  (`NotificationSettingsSection`). Simulate a run in the debugger with
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"ai.devin.mobile.refresh"]`,
  or launch with `-MockAPI -SimulateBackgroundRefresh` (DEBUG), which flips three mock sessions
  4 s after launch and runs one pass. `BGTaskScheduler.submit` fails silently in the Simulator.
- **Siri / Shortcuts run out of process.** `DevinIntents` is an ExtensionKit App Intents extension
  (`EXExtensionPointIdentifier: com.apple.appintents-extension`), so intents and the
  `AppShortcutsProvider` (allowed in an extension since iOS 17) run without launching the app.
  `SignedInDevin.current()` reads `AppGroup.credentialStore` and builds a `DevinClient` per run;
  every failure becomes a `DevinIntentError` (`CustomLocalizedStringResourceConvertible`) so Siri
  speaks it and Shortcuts shows it as an alert. `SessionEntity` is built from `SessionSnapshot.Entry`:
  the picker (`suggestedEntities` / `entities(matching:)`) answers from the saved snapshot when it is
  < 10 min old and otherwise refreshes page 1 (falling back to the stale snapshot offline);
  `entities(for:)` fetches ids the snapshot no longer has. `WhatIsDevinWaitingOnIntent` polls page 1,
  saves the snapshot (so the widget / background diff see what Siri just said) and speaks
  `SessionSnapshot.spokenSummary`; if the API is unreachable it reads the saved snapshot with its
  age. `-MockAPI` is in-process, so the extension cannot see mock data — in the Simulator it reports
  "not signed in" unless a real PAT is in the shared Keychain.
  **Simulator limitation:** the Devin tiles show up in Shortcuts, but tapping one fails with "Unable
  to run App Shortcut" because `linkd` refuses the ad-hoc-signed extension's phrase fetch
  (`Unable to get teamId from ai.devin.mobile.intents … Rejecting invalid client due to
  requiresValidBundle`, then `Couldn't find AppShortcutsProvider`). Neither `DEVELOPMENT_TEAM` nor a
  `com.apple.developer.team-identifier` entitlement helps — it needs a real signing certificate, i.e.
  a device build. Run `xcrun simctl spawn booted log show --last 2m --predicate 'process == "linkd"
  OR process == "DevinIntents"'` to see it; anything else in that log is a real bug.
- **The share extension never creates a session; it parks a `SharedDraft`.** `ShareItemLoader` maps
  the share sheet's items (GitHub URL / text / up to 5 images) onto the form — `GitHubLink` turns any
  `github.com/owner/repo[/pull/N|/issues/N|…]` URL into a `repos` entry, a bare repo URL stays out of the
  prompt, PR/issue/other URLs and text go in — and `SharedDraft.save` writes JSON to `AppGroup.defaults`
  plus image bytes to `<group container>/SharedDraft/`. Opening the app from a share extension is
  best-effort (`NSExtensionContext.open` is Today-only on iOS; the responder-chain `openURL:` fallback
  is what everyone ships), so the draft is *always* saved first and `SharedDraftFlow` picks it up on the
  next `scenePhase == .active` while signed in, uploads the images through `ComposerAttachments`
  (same B3 path as the picker) and opens `NewSessionView(initialPrompt:initialRepos:initialAttachments:)`.
  Taking the draft deletes it; drafts older than `SharedDraft.maxAge` (24 h) are dropped. Simulate one
  with `-MockAPI -SharedDraft "<text>" [-SharedDraftImage]` (DEBUG).
- **One Live Activity, and ActivityKit is its only store.** `SessionLiveActivity` (app, `@MainActor`)
  pins a session from the detail `⋯` menu ("Watch on Lock Screen"); starting another ends the first.
  Which session is pinned is read back from `Activity<SessionActivityAttributes>.activities` — nothing
  in defaults, because activities outlive the process. Content is pushed wherever a fresh `Session`
  appears: the detail view's poll (`.syncsLiveActivity`, skipped unless a visible field changed or
  60 s passed) and `BackgroundRefresh.run` (one `GET …/sessions/{id}` per run, before the inbox page).
  A session that `isFinal` (`finished`, `exit`, `error` — *not* `suspended`) ends the activity with that
  state left on the lock screen; Stop / Terminate / Sleep & archive end it immediately. `staleDate` is
  `updatedAt + 20 min`, so a missed refresh renders "May be out of date". `Activity` is not `Sendable`:
  every ActivityKit call lives in a `nonisolated` helper keyed by session ID. The app's Info.plist needs
  `NSSupportsLiveActivities` (set in `project.yml`); the extension needs nothing extra.
- **iPad = `NavigationSplitView`, iPhone = `NavigationStack`; the idiom decides, not the size class.**
  `InboxView` keeps both containers behind one `inbox` column body; a multitasking resize collapses
  the split view instead of swapping containers (which would drop navigation state). The sidebar
  selects by `Session.ID` (a value-hashed `Session` selection stops matching once polling rewrites
  the row) and has no `navigationDestination`, so rows are plain there and `NavigationLink`s only on
  iPhone. `InboxDetailColumn` owns the detail column's stack — child / related-session links push
  inside it and it resets on every selection change — and injects `dismissSplitDetail`, which
  `SessionDetailView.close()` prefers over `dismiss` (the column root has nothing to pop). Deep links
  use `followsDeepLinks(store:onSession:)` to set the selection. Hardware keyboard: ⌘N new session,
  ⌘R focus the composer, ⌘↩ send (the send button's shortcut, so it obeys `canSend`).
- **No crash-reporting or analytics SDK, no telemetry.** Crashes and hangs come from Xcode
  Organizer (Apple's opt-in collection, TestFlight testers included) plus `DiagnosticsCollector`, a
  MetricKit subscriber that keeps `MXDiagnosticPayload` JSON in the app container — nothing leaves
  the device. Decision and revisit triggers in §8; the App Store privacy label stays "Data Not
  Collected" as long as this holds.
- Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY=complete` — keep things `Sendable`.
- Comments are sparse by design. Don't document the diff; document the invariant.

## 3. First thing to do: run it for real

The app has only been compiled, not executed. Before adding features, get a PAT (ask the user — offer
session-only vs saved secret) and:

1. Sign in → confirm `/v3/self` returns `org_id` for a personal PAT. If it's null the org override
   path kicks in; verify that flow too.
2. Inbox → check every session decodes. Likely soft spots: `created_at`/`updated_at` are epoch
   **integers** (seconds) per the OpenAPI spec; the decoder accepts seconds or ISO-8601 — confirm
   the values aren't milliseconds. Check `pull_requests[].pr_state` values against `PullRequestState`
   (unknown strings render as a neutral badge, so nothing breaks — but add new cases if the API grows).
3. Detail → transcript order, markdown rendering (`MarkdownView` regroups Foundation's `.full`
   CommonMark parse by `presentationIntent`; check real Devin messages for constructs it flattens).
4. Reply to a waiting session, archive one, terminate one, create one.
5. Log anything that's wrong in a `## Known bugs` section here and fix in one PR.

On a macOS Devin session, build and run in the Simulator (`xcodegen generate && xcodebuild -scheme
DevinMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`, then `xcrun simctl`
to install/launch and `simctl io booted screenshot`; pass `-MockAPI` to `simctl launch` when there
is no PAT). Attach screenshots and the manual test steps
to the PR; the user verifies on device only for things the Simulator can't do (push, camera,
widgets on a real home screen).

## 4. Roadmap — mirror the web UI

Ordered by value to a mobile user. Each item lists the API it needs; all endpoints below are in the
public v3 OpenAPI spec (`https://docs.devin.ai/v3-openapi.json` — fetch it, it's the source of
truth; the summary below was taken from it).

### 4.1 Sessions list parity (web "Sessions" page)

- [ ] **Filters**: by repo (`repo_names`), by user (`user_ids`), tags (`tags`), origin
      (`origins`), playbook (`playbook_id`), date ranges (`created_after/before`,
      `updated_after/before`), archived toggle (`is_archived`). All are query params on
      `GET …/sessions`; add them to `SessionQuery`. Surface as a filter sheet + chips above the list.
- [ ] **Archived tab + Unarchive** — `POST …/sessions/{id}/unarchive`.
- [ ] **Tag editing** — `GET/PUT/POST …/sessions/{id}/tags`. Web lets you add tags inline.
- [x] **Pagination** — `SessionStore.loadMore()` follows `end_cursor`; prefetch on the last 10 rows
      plus an explicit "Load more" footer.
- [ ] **"Mine" vs "Everyone"** toggle using `Principal.userID` vs `Session.userID`.
- [ ] **Child sessions** — `parent_session_id` filter; show a "children" disclosure on a parent.
- [ ] **Show `category`/`subcategory`, `origin`, `automation_id`** as secondary metadata.

### 4.2 Session detail parity

- [x] **Attachments (view)** — listed per session; images inline (tap → full-screen zoom/share),
      other files open in QuickLook. Attachments are pinned under the first message quoting their
      URL, otherwise shown in the header card.
- [ ] **Attachments (upload)** — from Photos/Files/camera via
      `POST …/attachments` (multipart `file`) then pass `attachment_urls` to
      `POST …/messages` or to session creation. This is the most mobile-native win
      ("send Devin a screenshot of the bug").
- [x] **Structured output** — `Session.structuredOutput` is an opaque `JSONValue` (schema is
      caller-defined); `StructuredOutputSection` renders a collapsible tree / pretty JSON with copy.
- [x] **Session insights** — `GET …/sessions/{id}/insights` (+ `POST …/insights/generate`):
      `SessionInsightsPanel` (collapsible, in the detail header) shows issues, timeline, action
      items and the suggested prompt; "Use this prompt" prefills New Session. Not yet exercised
      against the live API (no PAT).
- [x] **Pull request states** — `PullRequestState` typed from `pr_state`, badges via
      `PullRequestStateBadge`; `ExternalLink.open` prefers the Universal-Link app (GitHub) over Safari.
- [x] **Devin Review** — `POST/GET …/pr-reviews` to trigger/see review status for a PR URL.
      `PullRequestReviewRow` polls `pollPRReview` (pinned to the returned `commit_sha`) until a
      terminal status; 404 = "not reviewed", 403 hides the row's controls.
- [x] **Better transcript rendering** — `MarkdownMessageBody` renders headings, lists, quotes,
      tables, links, inline code and fenced code (monospaced, horizontally scrollable, copy button)
      from `AttributedString(markdown:)` `.full` syntax, no dependency. Messages over ~14 lines or
      1 200 characters start collapsed behind "Show more" (`MarkdownDocument.isLong`).
- [x] **Wake a sleeping session** — confirmed against the spec: messaging a `suspended` session
      resumes it. `Session.messaging` drives the composer (wake hint for `suspended`, replaced by
      an explanation for `exit`/`error`). Not yet exercised against the live API (no PAT).
- [ ] **Rename** — web allows editing title. No `PATCH session` exists in v3 as of the last spec
      pull; check again before promising it.

### 4.3 New session parity

- [x] **Repo picker from the API** — `RepoPickerView`/`RepoPickerModel` over
      `DevinClient.repositories(org:query:)` (`RepositoryQuery`: `first`, `after`, `filter_name`,
      `load_indexing_status=false`). Multi-select, debounced server search, cursor pagination,
      recents pinned on top, typed `owner/repo` fallback. Not yet exercised against the live API
      (no PAT) — verify the `repo_path` shape and that `repos` accepts `Repository.fullPath`.
- [x] **Knowledge & secrets attach** — `knowledge_ids` (`GET …/knowledge/notes`,
      `…/knowledge/folders`) and `secret_ids` (`GET …/secrets`) on `NewSessionRequest`; searchable
      multi-select pickers (`KnowledgeNotePickerView`, `SecretPickerView`) grouped by folder.
- [x] **Structured output schema** — `structured_output_schema` text field (advanced section).
      `StructuredOutputSchema.parse` (DevinKit) enforces the spec's constraints — JSON object,
      ≤ 64 KB, no external `$ref` — and its error blocks Start with a message under the field.
- [x] **`bypass_approval`, `resumable`, `platform`** toggles in an "Advanced" disclosure
      (`NewSessionAdvancedOptions`). Fields are encoded only when they differ from the API default.
- [x] **Attachments** on create — `NewSessionAttachmentsSection` reuses `ComposerAttachments`
      (same picker/upload/preview as the composer); uploaded URLs go out as `attachment_urls` on
      `POST …/sessions`. Start stays disabled until every upload finishes.
- [x] **Session links** (`session_links`) — session detail `⋯ → Start related session` opens the
      New Session sheet with a "Related session" toggle; `NewSessionRequest.links(to:)` sends each
      session's web URL (`Session.url`). The spec types the entries as bare strings, so URL-vs-ID
      is unverified against the live API — if it wants IDs, only `links(to:)` changes.
- [ ] **Prompt templates** — playbook body preview (`GET …/playbooks/{id}`) before starting.

### 4.4 Org management (web "Settings" pages) — lower priority on mobile, but cheap

- [ ] Playbooks CRUD — `…/playbooks` (GET/POST/PUT/DELETE). Read-only list + detail first.
- [ ] Knowledge notes CRUD — `…/knowledge/notes`, `…/knowledge/folders`.
- [ ] Secrets — list/create/delete (`…/secrets`). Never display values (API doesn't return them).
- [ ] Automations & schedules — `…/automations`, `…/schedules` (list, enable/disable, run
      history via `automation_ids`/`schedule_id` session filters).
- [ ] Usage — `…/metrics/usage`, `…/consumption/daily` for an ACU burn chart (Swift Charts).
- [ ] Code scans — `…/code-scans/*` list + findings; remediate = starts a session.
- [x] Members — `/v3beta1/…/members/users` to resolve `user_id` → name in the inbox.

Permissions: PATs act as the user. Service-user keys are RBAC-gated (`ViewOrgSessions`,
`ManageOrgSessions`, `UseDevinSessions`, `ManageOrgPlaybooks`, …). Map 403 → hide the feature,
don't crash. `DevinError.forbidden` already exists.

### 4.5 Mobile-native (not in the web UI, but the reason this app exists)

- [x] **Local notifications**: `BackgroundRefresh` (`BGAppRefreshTask` every ~15 min) diffs the
      `SessionSnapshot` in the App Group and `SessionNotifier` posts on `working → needsYou` and
      `→ finished`; tap → `devinmobile://session/<id>`. Not yet observed against the live API (no
      PAT); iOS decides the real cadence.
- [x] **Shared plumbing** — App Group entitlement, `AppGroup.credentialStore` (Keychain access
      group), `SessionSnapshot` in the group container, `devinmobile://session/<id>` handled from
      cold start. Extensions still need their own `targets:` entry in `project.yml`.
- [x] **Widget** (WidgetKit): `DevinWidget/` target, small + medium `NeedsYouWidget` fed by
      `WidgetContent.resolve` (never the API); rows link to `SessionSnapshot.Entry.deepLink.url`.
      Not yet seen on a real home screen — only the Simulator.
- [x] **App Intents / Siri / Shortcuts**: `DevinIntents/` extension with `StartDevinSessionIntent(prompt, repo?)`,
      `ReplyToDevinIntent(session, message)`, `WhatIsDevinWaitingOnIntent` and `DevinShortcuts` phrases
      ("What is Devin waiting on", "Start a Devin session", "Reply to Devin"). Uses `DevinKit` directly.
      Not yet exercised against the live API (no PAT); running the intents needs a device (see §2).
- [ ] **Share Extension**: share a GitHub URL / text / image → prefilled New Session sheet.
- [ ] **App Intents / Siri / Shortcuts**: `StartDevinSessionIntent(prompt, repo?)`,
      `ReplyToDevinIntent(session, message)`, `WhatIsDevinWaitingOnIntent`. Reuse `DevinKit`
      directly from the intent extension.
- [x] **Share Extension**: `DevinShareExtension/` target; GitHub URL → `repos`, text/URL → prompt,
      images → attachments uploaded by the app. Not yet driven from a real share sheet on device — only
      compiled, registered (`pluginkit -m`) and exercised through the App Group handoff in the Simulator.
- [x] **Live Activity** for a session you're watching (status + ACUs on the lock screen):
      `SessionLiveActivity` + `SessionActivityWidget`, fed by the detail poll and `BackgroundRefresh`.
      Push-to-start / remote updates wait for a relay (see below). Not yet seen on a real lock screen.
- [ ] **Push via a relay** (optional, needs a server): tiny service that polls the API per user and
      sends APNs. Only worth it if background refresh proves too laggy.
- [x] **iPad**: `NavigationSplitView` for inbox + detail (both orientations, balanced columns) with
      ⌘N / ⌘R / ⌘↩ keyboard shortcuts. macOS (Catalyst or Designed-for-iPad) is still open.
- [x] **Haptics + accessibility**: `bucketChangeHaptics(for:)` on the inbox column (stack root on
      iPhone, sidebar on iPad) taps once per poll that moves a session between buckets (`.error` for
      failed, `.warning` for needs-you, `.success` for finished). `StatusBadge` is one VoiceOver element
      ("Needs you: Waiting for you"), inbox rows are one stop each, and `DevinMobileUITests` runs
      Accessibility Inspector's audit (`performAccessibilityAudit`) over the inbox and detail at default
      size and XXXL.

## 5. Conventions for Devin sessions working here

- Branch `devin/<unix-ts>-<slug>` off `main`; one feature per PR; PR body follows the repo's default
  template (Summary; pseudo-diffs > prose).
- Run `cd DevinKit && swift test` before pushing. On macOS also build the app locally; CI greps for
  `warning:` and `error:`, so fix warnings before pushing.
- New Swift files under `DevinMobile/` are picked up automatically by XcodeGen (`sources: DevinMobile`);
  no `project.yml` edits needed unless you add a target (widget/intents/share extension — those
  need new `targets:` entries plus an `entitlements:` block listing `group.ai.devin.mobile`; copy
  `DevinWidget`, or `DevinIntents` for an ExtensionKit `extensionkit-extension`). Extension sources
  live in their own top-level folder (`DevinWidget/`, `DevinIntents/`), never under
  `DevinWidget` or `DevinShareExtension`). A non-WidgetKit extension also needs
  `LM_SKIP_METADATA_EXTRACTION: YES`, or the App Intents metadata step logs a `warning:` CI flags.
  Extension sources live in their own top-level folder (`DevinWidget/`), never under
  `DevinMobile/`, which the app target compiles wholesale. `Info.plist` / `.entitlements` files are
  generated by XcodeGen from `project.yml`; don't commit them.
- **Every target ships a `PrivacyInfo.xcprivacy`** (`DevinMobile/`, `DevinWidget/`, `DevinIntents/`,
  `DevinShareExtension/`; XcodeGen copies it as a resource, extensions don't inherit the app's). Nothing is collected and the only required-reason
  API is `UserDefaults` (`CA92.1` private, `1C8F.1` App Group). Adding a required-reason API (file
  timestamps, `systemUptime`, disk space, `activeInputModes`), an analytics/crash SDK, or any host other
  than `api.devin.ai` means updating every manifest and `AppStore/PrivacyQuestionnaire.md` in the same PR;
  §4 there has the `rg` + `nm` audit that mirrors App Store Connect's ITMS-91053 scan.
- Simulator builds that must exercise the App Group (widget, shared Keychain) need entitlements, so
  build them *without* `CODE_SIGNING_ALLOWED=NO` (ad-hoc signing needs no team). CI's unsigned build
  only proves the targets compile.
- Accessibility: keep `DevinMobileUITests/AccessibilityAuditTests` green on a booted simulator
  (`xcodebuild test -scheme DevinMobile -only-testing:DevinMobileUITests -destination 'platform=iOS
  Simulator,name=iPhone 17 Pro'`; CI is build-only, so this is a local gate). New status-like colour
  as *text* on a plain background needs ~4.5:1 — system orange does not pass, use `Color.needsYou`
  (`Color.onNeedsYou` for text on top of it). Prefer `@ScaledMetric` over fixed sizes, and avoid
  `.tertiary` for text.
- **App identity lives in `project.yml` + `DevinMobile/Assets.xcassets`.** Display name `Devin`, bundle ID
  `ai.devin.mobile` (the App Group, Keychain group, URL scheme and BG task ID are all derived from it —
  renaming means migrating stored credentials), `AccentColor` (`#2F5BEA`, dark `#6F8FFF`). The icon PNGs
  (`AppIcon` light/dark/tinted, 1024 pt single-size — actool derives every device size) and the launch
  screen's `LaunchGlyph` are rendered by `swift Scripts/make-app-icon.swift`; edit the script, re-run,
  commit both. Never hand-edit the PNGs. The launch screen is `UILaunchScreen` in `project.yml`
  (`LaunchBackground` = `systemBackgroundColor`, so it blends into `RootView`).
- **Versions are build settings, not per-target literals.** `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
  in `project.yml`'s `settings.base` feed `CFBundleShortVersionString` / `CFBundleVersion` of the app
  *and* every extension (App Store Connect rejects mismatches). Nobody bumps them by hand: pushing a
  tag `vX.Y.Z` (a `-suffix` is stripped) runs `testflight.yml`, which passes `MARKETING_VERSION=X.Y.Z
  CURRENT_PROJECT_VERSION=<run number>` to `xcodebuild archive` and fails if either archived
  Info.plist disagrees. `workflow_dispatch` (optional `version`, `upload=false` for a dry run) exists
  for testing the pipeline without a tag. Keep the iPad orientation list complete (all four) — the
  Release archive warns and App Store Connect rejects otherwise.
- Don't add third-party packages without asking; the app is intentionally dependency-free.
- Never log tokens. `DevinClient` builds the `Authorization` header in one place — keep it that way.
- If the OpenAPI spec disagrees with this doc, the spec wins. Re-fetch it at session start.

## 6. Open questions for the owner (tracked in #14)

1. Is a small markdown dependency acceptable for transcript rendering, or stay dependency-free?
   (B1 shipped dependency-free on Foundation's CommonMark parser; revisit only if it falls short.)
2. Push notifications: OK to run a relay server, or stick with background refresh?
3. Which org-management screens (4.4) matter on mobile? Suggested: none until 4.1–4.3 + 4.5 ship.
4. App identity: shipped as `Devin` / `ai.devin.mobile` with a generated prompt-and-cursor icon and a
   blue accent (§5). The bundle ID is effectively final (App Group + Keychain depend on it); the artwork
   and colour are Devin's defaults — swap them by editing `Scripts/make-app-icon.swift` and
   `AccentColor.colorset` if the owner wants different branding.
5. TestFlight signing: add repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8`
   (App Store Connect API key, App Manager/Admin with cloud-managed distribution certificate access;
   raw PEM or base64) and `APPLE_TEAM_ID`; optionally `DISTRIBUTION_CERTIFICATE_P12_BASE64` +
   `DISTRIBUTION_CERTIFICATE_PASSWORD` to skip cloud signing. Register `ai.devin.mobile`,
   `ai.devin.mobile.widget`, `ai.devin.mobile.intents` and `ai.devin.mobile.share` (all in App Group
   `group.ai.devin.mobile`) in App Store Connect, then push `v0.1.0`.

## 7. Process

Scrum, one-week sprints, tracked on GitHub:

- **Epics** are issues labelled `epic` (#3 Sprint 0, #4 sessions list, #5 session detail, #6 new
  session, #7 mobile-native, #8 release, #9 org management) with a task list of their stories.
- **Stories** are issues labelled `story`/`bug`/`chore` with acceptance criteria, an estimate in
  points (1/2/3/5/8) and a `Sprint N` milestone. `ready-for-devin` means a session can pick it up
  without further clarification.
- **One story → one branch → one PR** with `Closes #N` and the manual Simulator test steps from the
  PR template. Merging closes the story.
- **Sprint review** happens on the milestone: everything closed is demoed from a Simulator build;
  anything open rolls to the next milestone with a one-line reason on the issue.
- **Retro** is a comment on the sprint's tracking issue; changes to conventions land here in §5.

## 8. Decision log

### 8.1 Crash reporting & analytics — MetricKit + Xcode Organizer, no analytics (Sprint 5, #48)

**Decision.** Ship dependency-free: Apple's crash/hang collection viewed in Xcode Organizer, plus an
in-app MetricKit subscriber (`DiagnosticsCollector`) that persists diagnostic payloads on the device.
No product analytics, no third-party crash SDK, no upload of anything from the app.

**Options weighed.**

| Option | Verdict |
| --- | --- |
| Xcode Organizer only (Crashes, Hangs, Disk Writes, Energy) | Baseline — zero code; only sees users who opted in to "Share with App Developers" (TestFlight testers are opted in by default). Symbolicated automatically when the archive is uploaded with dSYMs. |
| MetricKit subscriber in-app | Chosen add-on — ~50 lines, same payloads as Organizer (`MXCrashDiagnostic`, `MXHangDiagnostic`, `MXCPUExceptionDiagnostic`, `MXDiskWriteExceptionDiagnostic`) delivered on the next launch regardless of opt-in. Stored as JSON, not uploaded; unsymbolicated call-stack trees, so a dSYM from the matching archive is needed to read them. |
| Third-party crash SDK (Sentry, Firebase Crashlytics, Bugsnag) | Rejected for now — a dependency (§5 says none without asking), a network endpoint the privacy manifest (#47) would have to declare, and a backend to run. Reconsider only if Organizer proves too slow for the field bugs §3 expects. |
| Product analytics (TelemetryDeck, Firebase, Mixpanel) | Rejected — a one-user developer tool has nothing to A/B test; usage questions are answered by asking the owner. Adding any means an App Privacy label change and a tracking review. |

**Consequences.**

- `DiagnosticsCollector.install()` runs from `NotificationDelegate.willFinishLaunching`. Payloads
  land in `Library/Application Support/Diagnostics/<timeStampEnd>-<uuid>.json` (excluded from
  backup, newest 20 kept). Pull them with Xcode → Devices and Simulators → Download Container, or
  `xcrun simctl get_app_container booted ai.devin.mobile data` in the Simulator. An in-app "export
  diagnostics" share sheet is a follow-up if TestFlight testers ever need to send one by hand.
- Xcode → Debug → Simulate MetricKit Payloads… exercises the collector on Simulator or device.
- Release builds must keep `DEBUG_INFORMATION_FORMAT=dwarf-with-dsym` (Xcode's default for Release)
  and upload dSYMs with the archive (#46) so Organizer symbolicates.
- No privacy-manifest impact: MetricKit is not a required-reason API and the app contacts only
  `api.devin.ai`. `NSPrivacyTracking` stays `false` and `NSPrivacyCollectedDataTypes` empty in #47.

**Revisit when** (a) the app ships to more than the owner's org and Organizer's opt-in coverage
is too thin, (b) a relay server exists anyway (§4.5 push), which would make forwarding payloads
cheap, or (c) a field crash cannot be reproduced from an Organizer log. Any of those → open a
story on epic #8, and expect the privacy label and manifest to change with it.
