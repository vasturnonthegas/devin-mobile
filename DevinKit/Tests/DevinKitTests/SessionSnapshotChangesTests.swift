import Foundation
import XCTest
@testable import DevinKit

final class SessionSnapshotChangesTests: XCTestCase {
    private func session(_ id: String, _ status: SessionStatus, _ detail: SessionStatusDetail?, updated: TimeInterval = 100, title: String? = nil, archived: Bool = false) -> Session {
        Session(sessionID: id, orgID: "org-xyz", status: status, statusDetail: detail, title: title,
                url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                createdAt: Date(timeIntervalSince1970: updated - 60), updatedAt: Date(timeIntervalSince1970: updated),
                isArchived: archived)
    }

    private func snapshot(_ sessions: [Session], at t: TimeInterval) -> SessionSnapshot {
        SessionSnapshot(sessions: sessions, capturedAt: Date(timeIntervalSince1970: t))
    }

    func testReportsOnlySessionsKnownToBothSnapshotsWhoseBucketMoved() {
        let before = snapshot([
            session("a", .running, .working),
            session("b", .running, .working),
            session("c", .running, .waitingForUser),
            session("gone", .running, .working),
        ], at: 1_000)
        let after = snapshot([
            session("a", .running, .waitingForUser, updated: 200, title: "Fix CI"),
            session("b", .running, .working, updated: 300),
            session("c", .exit, .finished, updated: 400),
            session("brand-new", .exit, .finished, updated: 500),
        ], at: 2_000)

        let changes = after.changes(since: before)

        XCTAssertEqual(changes.map(\.id), ["a", "c"], "b is unchanged; brand-new and gone have no counterpart")
        XCTAssertEqual(changes[0].from, .working)
        XCTAssertEqual(changes[0].to, .needsYou)
        XCTAssertEqual(changes[0].entry.title, "Fix CI")
        XCTAssertEqual(changes[0].entry.deepLink, .session(id: "a"))
        XCTAssertEqual(changes[1].from, .needsYou)
        XCTAssertEqual(changes[1].to, .finished)
        XCTAssertTrue(changes.allSatisfy(\.isNotable))
    }

    func testNotableRuleIsWorkingToNeedsYouOrAnythingToFinished() {
        let before = snapshot([
            session("work→needs", .running, .working),
            session("sleep→needs", .suspended, .inactivity),
            session("work→sleep", .running, .working),
            session("work→fail", .running, .working),
            session("sleep→finish", .suspended, .inactivity),
            session("needs→work", .running, .waitingForApproval),
            session("fail→finish", .error, .error),
        ], at: 1_000)
        let after = snapshot([
            session("work→needs", .running, .waitingForApproval),
            session("sleep→needs", .running, .waitingForUser),
            session("work→sleep", .suspended, .inactivity),
            session("work→fail", .error, .error),
            session("sleep→finish", .exit, .finished),
            session("needs→work", .running, .working),
            session("fail→finish", .exit, .finished),
        ], at: 2_000)

        XCTAssertEqual(after.changes(since: before).count, 7)
        XCTAssertEqual(Set(after.notableChanges(since: before).map(\.id)), ["work→needs", "sleep→finish", "fail→finish"])
    }

    func testNoChangesAgainstItselfOrAnEmptySnapshot() {
        let now = snapshot([session("a", .running, .working), session("b", .exit, .finished)], at: 1_000)

        XCTAssertTrue(now.changes(since: now).isEmpty)
        XCTAssertTrue(now.changes(since: snapshot([], at: 0)).isEmpty, "first launch: nothing to compare against")
    }

    func testArchivedSessionsAreInvisibleToTheDiff() {
        let before = snapshot([session("a", .running, .working)], at: 1_000)
        let after = snapshot([session("a", .exit, .finished, archived: true)], at: 2_000)

        XCTAssertTrue(after.changes(since: before).isEmpty)
    }

    func testChangesFollowSnapshotOrder() {
        let before = snapshot([
            session("finished-later", .running, .working, updated: 10),
            session("needs-later-old", .running, .working, updated: 20),
            session("needs-later-new", .running, .working, updated: 30),
        ], at: 1_000)
        let after = snapshot([
            session("finished-later", .exit, .finished, updated: 900),
            session("needs-later-old", .running, .waitingForUser, updated: 100),
            session("needs-later-new", .running, .waitingForUser, updated: 200),
        ], at: 2_000)

        XCTAssertEqual(after.notableChanges(since: before).map(\.id), ["needs-later-new", "needs-later-old", "finished-later"])
    }
}
