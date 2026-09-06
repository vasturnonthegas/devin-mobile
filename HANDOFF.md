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
  Models/   Session, SessionMessage, Playbook, Principal, Page<T>, NewSessionRequest/SessionQuery, JSONValue
  Storage/  CredentialStore protocol; KeychainCredentialStore (iOS), InMemoryCredentialStore (tests/previews)

DevinMobile (SwiftUI, iOS 17, @Observable + @MainActor, no third-party deps)
  App/          AppModel (auth state machine), SessionStore (list + polling), RecentRepos
  Features/     Onboarding, Inbox, SessionDetail (+ SessionDetailModel), NewSession, Settings
  Support/      StatusBadge, PullRequestLink (+ PullRequestStateBadge, ExternalLink),
                Markdown/ (MarkdownDocument block tree + MarkdownView)
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
- **Simulator without a PAT.** Launch with `-MockAPI` (DEBUG only) to run against an in-process
  fake API (`DevinMobile/Support/MockAPI.swift`, 130 sessions) backed by `InMemoryCredentialStore`.
- **Attachment bytes go through `DevinClient.attachmentData`.** `GET …/sessions/{id}/attachments`
  returns a bare array (not the cursor envelope). Attachment URLs point at the API, which 307s to a
  presigned URL; the client sends the Bearer token only to `baseURL.host` and URLSession drops it on
  the redirect. Never hand an attachment URL to `AsyncImage`/`Link` — it would 401 or leak the token.
  Downloads are cached per `SessionDetailView` (`SessionAttachmentsModel`) and files land in `tmp/`.
- **Credentials only in Keychain** (`ai.devin.mobile` / `credentials`). Nothing is stored until
  `GET /v3/self` + `GET /sessions?first=1` both succeed.
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
- [ ] **Session insights** — `GET …/sessions/{id}/insights` (+ `POST …/insights/generate`):
      issues, timeline, action items, suggested prompt. Web shows this as a summary panel.
      "Suggested prompt → start new session" is a nice one-tap flow.
- [x] **Pull request states** — `PullRequestState` typed from `pr_state`, badges via
      `PullRequestStateBadge`; `ExternalLink.open` prefers the Universal-Link app (GitHub) over Safari.
- [ ] **Devin Review** — `POST/GET …/pr-reviews` to trigger/see review status for a PR URL.
- [x] **Better transcript rendering** — `MarkdownMessageBody` renders headings, lists, quotes,
      tables, links, inline code and fenced code (monospaced, horizontally scrollable, copy button)
      from `AttributedString(markdown:)` `.full` syntax, no dependency. Messages over ~14 lines or
      1 200 characters start collapsed behind "Show more" (`MarkdownDocument.isLong`).
- [ ] **Wake a sleeping session** — sending a message to a suspended session resumes it (that's what
      the composer placeholder promises). Verify the API actually does this for `suspended`
      sessions; if not, hide the composer for non-resumable ones.
- [ ] **Rename** — web allows editing title. No `PATCH session` exists in v3 as of the last spec
      pull; check again before promising it.

### 4.3 New session parity

- [ ] **Repo picker from the API** — `GET /v3beta1/organizations/{org}/repositories`
      (`first`, `after`, `filter_name`; returns `repo_name`, `repo_path`, `repo_language`,
      `repo_description`). Replace the `RecentRepos` UserDefaults hack with a searchable picker;
      keep recents as a "pinned" section.
- [ ] **Knowledge & secrets attach** — `knowledge_ids` (`GET …/knowledge/notes`,
      `…/knowledge/folders`) and `secret_ids` (`GET …/secrets`) on `SessionCreateRequest`.
- [ ] **Structured output schema** — `structured_output_schema` text field (advanced section).
- [ ] **`bypass_approval`, `resumable`, `platform`** toggles in an "Advanced" disclosure.
- [ ] **Attachments** on create (see 4.2).
- [ ] **Session links** (`session_links`) — link to a parent/related session.
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

- [ ] **Local notifications**: `BGAppRefreshTask` every ~15 min; diff buckets vs last poll; notify on
      `working → needsYou` and `→ finished`. Store last-known buckets in the app group container.
- [ ] **Widget** (WidgetKit, App Group + shared Keychain access group — `KeychainCredentialStore`
      already takes an `accessGroup`): "Needs you: N" + top 3 sessions; tap → deep link
      `devinmobile://session/<id>`. Add URL scheme handling in `DevinMobileApp`.
- [ ] **App Intents / Siri / Shortcuts**: `StartDevinSessionIntent(prompt, repo?)`,
      `ReplyToDevinIntent(session, message)`, `WhatIsDevinWaitingOnIntent`. Reuse `DevinKit`
      directly from the intent extension.
- [ ] **Share Extension**: share a GitHub URL / text / image → prefilled New Session sheet.
- [ ] **Live Activity** for a session you're watching (status + ACUs on the lock screen).
- [ ] **Push via a relay** (optional, needs a server): tiny service that polls the API per user and
      sends APNs. Only worth it if background refresh proves too laggy.
- [ ] **iPad / macOS (Catalyst or Designed-for-iPad)**: `NavigationSplitView` for inbox + detail.
- [ ] Haptics on state changes, Dynamic Type audit, VoiceOver labels on `StatusBadge`.

## 5. Conventions for Devin sessions working here

- Branch `devin/<unix-ts>-<slug>` off `main`; one feature per PR; PR body follows the repo's default
  template (Summary; pseudo-diffs > prose).
- Run `cd DevinKit && swift test` before pushing. On macOS also build the app locally; CI greps for
  `warning:` and `error:`, so fix warnings before pushing.
- New Swift files under `DevinMobile/` are picked up automatically by XcodeGen (`sources: DevinMobile`);
  no `project.yml` edits needed unless you add a target (widget/intents/share extension — those
  need new `targets:` entries plus entitlements for App Groups + Keychain sharing).
- Don't add third-party packages without asking; the app is intentionally dependency-free.
- Never log tokens. `DevinClient` builds the `Authorization` header in one place — keep it that way.
- If the OpenAPI spec disagrees with this doc, the spec wins. Re-fetch it at session start.

## 6. Open questions for the owner (tracked in #14)

1. Is a small markdown dependency acceptable for transcript rendering, or stay dependency-free?
   (B1 shipped dependency-free on Foundation's CommonMark parser; revisit only if it falls short.)
2. Push notifications: OK to run a relay server, or stick with background refresh?
3. Which org-management screens (4.4) matter on mobile? Suggested: none until 4.1–4.3 + 4.5 ship.
4. App identity: bundle ID is `ai.devin.mobile` and accent colour is a placeholder; final name/icon?

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
