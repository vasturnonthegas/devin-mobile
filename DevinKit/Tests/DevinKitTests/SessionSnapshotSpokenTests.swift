import Foundation
import XCTest
@testable import DevinKit

final class SessionSnapshotSpokenTests: XCTestCase {
    private func session(_ id: String, _ status: SessionStatus, _ detail: SessionStatusDetail?, updated: TimeInterval = 100, archived: Bool = false) -> Session {
        Session(sessionID: id, orgID: "org-xyz", status: status, statusDetail: detail, title: id,
                url: URL(string: "https://app.devin.ai/sessions/\(id)")!,
                createdAt: Date(timeIntervalSince1970: updated - 60), updatedAt: Date(timeIntervalSince1970: updated),
                isArchived: archived)
    }

    private func summary(_ sessions: [Session]) -> String {
        SessionSnapshot(sessions: sessions, capturedAt: Date(timeIntervalSince1970: 1_000)).spokenSummary
    }

    func testNothingWaitingReportsWorkingCount() {
        XCTAssertEqual(summary([]), "Nothing is waiting on you right now. Devin isn't working on anything.")
        XCTAssertEqual(summary([session("a", .running, .working)]),
                       "Nothing is waiting on you right now. Devin is working on one session.")
        XCTAssertEqual(summary([session("a", .running, .working), session("b", .running, nil), session("c", .exit, .finished)]),
                       "Nothing is waiting on you right now. Devin is working on 2 sessions.")
    }

    func testNamesEachWaitingSessionWithItsStatus() {
        XCTAssertEqual(summary([session("Fix CI", .running, .waitingForUser), session("bg", .running, .working)]),
                       "One session needs you: “Fix CI” (waiting for you).")
        XCTAssertEqual(summary([
            session("Fix CI", .running, .waitingForUser, updated: 300),
            session("Dark mode", .running, .waitingForApproval, updated: 200),
        ]), "2 sessions need you: “Fix CI” (waiting for you) and “Dark mode” (needs approval).")
    }

    func testMoreThanThreeAreCountedNotListed() {
        let sessions = (1...5).map { session("s\($0)", .running, .waitingForUser, updated: TimeInterval(1_000 - $0)) }
        XCTAssertEqual(summary(sessions),
                       "5 sessions need you, including “s1” (waiting for you), “s2” (waiting for you) and “s3” (waiting for you).")
    }

    func testArchivedSessionsAreIgnored() {
        XCTAssertEqual(summary([session("old", .running, .waitingForUser, archived: true)]),
                       "Nothing is waiting on you right now. Devin isn't working on anything.")
    }

    func testEntriesMatchingIsWordwiseAndCaseInsensitive() {
        let snapshot = SessionSnapshot(sessions: [
            session("Fix CI on main", .running, .waitingForUser, updated: 300),
            session("Dark mode for Settings", .running, .working, updated: 200),
            session("Café menu", .suspended, .inactivity, updated: 100),
        ], capturedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(snapshot.entries(matching: "").map(\.title), ["Fix CI on main", "Dark mode for Settings", "Café menu"])
        XCTAssertEqual(snapshot.entries(matching: "dark settings").map(\.title), ["Dark mode for Settings"])
        XCTAssertEqual(snapshot.entries(matching: "cafe").map(\.title), ["Café menu"])
        XCTAssertEqual(snapshot.entries(matching: "ci dark"), [])
        XCTAssertEqual(snapshot.entry(id: "Café menu")?.title, "Café menu")
        XCTAssertNil(snapshot.entry(id: "missing"))
    }

    func testSpokenList() {
        XCTAssertEqual(SessionSnapshot.spokenList([]), "")
        XCTAssertEqual(SessionSnapshot.spokenList(["a"]), "a")
        XCTAssertEqual(SessionSnapshot.spokenList(["a", "b"]), "a and b")
        XCTAssertEqual(SessionSnapshot.spokenList(["a", "b", "c"]), "a, b and c")
    }
}
