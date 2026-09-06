#if DEBUG
import Foundation
import DevinKit

/// Transcript served by `MockAPI` for `GET …/sessions/{id}/messages`. Exercises every markdown
/// construct the transcript renderer supports, plus one message long enough to collapse.
extension MockAPI {
    static func messages(for sessionID: String) -> [SessionMessage] {
        let start = Date(timeIntervalSince1970: 1_756_890_000)
        return transcript.enumerated().map { index, entry in
            SessionMessage(
                eventID: "\(sessionID)-msg\(index)",
                source: entry.source,
                message: entry.text,
                createdAt: start.addingTimeInterval(Double(index) * 95)
            )
        }
    }

    private static let transcript: [(source: MessageSource, text: String)] = [
        (.user, "Fix the flaky `InboxView` test on `main` and open a PR. Use **small** commits."),
        (.devin, """
        ## Plan

        1. Reproduce the failure locally with `swift test --filter InboxViewTests`
        2. Find the race in `SessionStore.poll()`
        3. Add a regression test
           - cover the empty-page case
           - cover the *cursor reset* case

        > The flake only shows up when the first page returns fewer than 50 rows.

        I'll start with step 1 — see the [failing run](https://github.com/acme/app/actions/runs/1) for the baseline.
        """),
        (.devin, """
        Found it. `merging(_:)` dropped rows when `end_cursor` was `nil`:

        ```swift
        extension Array where Element == Session {
            func merging(_ page: [Session], replacingFirstPage: Bool) -> [Session] {
                guard replacingFirstPage else { return self + page }
                let incoming = Set(page.map(\\.sessionID))
                return page + filter { !incoming.contains($0.sessionID) }   // was: page only
            }
        }
        ```

        Verified with `swift test` — 14 tests, 0 failures.

        | Test | Before | After |
        |---|---|---|
        | `testMergeKeepsDeeperPages` | ❌ | ✅ |
        | `testMergeReplacesFirstPage` | ✅ | ✅ |
        """),
        (.user, "Looks right. Can you also show me the full diff before you push?"),
        (.devin, """
        ### Full diff

        ```diff
        --- a/DevinKit/Sources/DevinKit/Models/SessionListMerge.swift
        +++ b/DevinKit/Sources/DevinKit/Models/SessionListMerge.swift
        @@ -3,9 +3,12 @@ extension Array where Element == Session {
             func merging(_ page: [Session], replacingFirstPage: Bool) -> [Session] {
        -        guard replacingFirstPage else { return self + page }
        -        return page
        +        guard replacingFirstPage else { return self + page }
        +        let incoming = Set(page.map(\\.sessionID))
        +        return page + filter { !incoming.contains($0.sessionID) }
             }
         }
        --- a/DevinKit/Tests/DevinKitTests/DevinClientTests.swift
        +++ b/DevinKit/Tests/DevinKitTests/DevinClientTests.swift
        @@ -120,4 +120,22 @@ final class DevinClientTests: XCTestCase {
        +    func testMergeKeepsDeeperPages() throws {
        +        let deeper = [Session.fixture(id: "a"), .fixture(id: "b")]
        +        let first = [Session.fixture(id: "c")]
        +        XCTAssertEqual(deeper.merging(first, replacingFirstPage: true).map(\\.sessionID), ["c", "a", "b"])
        +    }
        ```

        ### Notes

        - The `Set` allocation is per poll (every 10 s) and bounded by page size, so it is not worth caching.
        - `SessionStore.loadMore()` is unaffected: it passes `replacingFirstPage: false`.
        - I kept the public signature so `InboxView` does not change.
        - CI is green on the branch: [Linux](https://github.com/acme/app/actions/runs/2) · [macOS](https://github.com/acme/app/actions/runs/3)

        ---

        Ready to push when you say so.
        """),
        (.user, "Push it."),
        (.devin, "Pushed and opened [acme/app#142](https://github.com/acme/app/pull/142). ~~Waiting on CI~~ CI passed."),
    ]
}
#endif
