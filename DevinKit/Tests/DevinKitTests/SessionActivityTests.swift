import Foundation
import XCTest
@testable import DevinKit

final class SessionActivityTests: XCTestCase {
    private func session(_ status: SessionStatus, _ detail: SessionStatusDetail?, title: String? = "Fix flaky CI", acus: Double = 1.25) -> Session {
        Session(sessionID: "devin-abc123", orgID: "org-xyz", status: status, statusDetail: detail, title: title,
                url: URL(string: "https://app.devin.ai/sessions/devin-abc123")!, acusConsumed: acus,
                createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200))
    }

    func testFinalOnlyWhenFinishedOrVMIsGone() {
        XCTAssertTrue(session(.running, .finished).isFinal)
        XCTAssertTrue(session(.suspended, .finished).isFinal)
        XCTAssertTrue(session(.exit, .finished).isFinal)
        XCTAssertTrue(session(.exit, .userRequest).isFinal, "terminated")
        XCTAssertTrue(session(.exit, nil).isFinal)
        XCTAssertTrue(session(.error, .error).isFinal)

        XCTAssertFalse(session(.running, .working).isFinal)
        XCTAssertFalse(session(.running, .waitingForUser).isFinal)
        XCTAssertFalse(session(.running, .waitingForApproval).isFinal)
        XCTAssertFalse(session(.resuming, nil).isFinal)
        XCTAssertFalse(session(.new, nil).isFinal)
        XCTAssertFalse(session(.suspended, .inactivity).isFinal, "a message wakes it")
        XCTAssertFalse(session(.suspended, nil).isFinal)
    }

    func testStateMirrorsSessionDisplayFields() {
        let captured = Date(timeIntervalSince1970: 1_000)
        let state = SessionActivityAttributes.State(session(.running, .waitingForApproval, acus: 2.5), updatedAt: captured)

        XCTAssertEqual(state.title, "Fix flaky CI")
        XCTAssertEqual(state.bucket, .needsYou)
        XCTAssertEqual(state.statusSummary, "Needs approval")
        XCTAssertEqual(state.acusConsumed, 2.5)
        XCTAssertEqual(state.updatedAt, captured)
        XCTAssertFalse(state.isFinal)
        XCTAssertEqual(state.staleDate, captured.addingTimeInterval(SessionActivityAttributes.staleAfter))

        let untitled = SessionActivityAttributes.State(session(.exit, .finished, title: nil))
        XCTAssertEqual(untitled.title, "devin-abc123")
        XCTAssertEqual(untitled.bucket, .finished)
        XCTAssertTrue(untitled.isFinal)
        XCTAssertNil(untitled.staleDate, "a final state never goes stale")
    }

    func testDiffersVisiblyIgnoresOnlyTheTimestamp() {
        let base = SessionActivityAttributes.State(session(.running, .working), updatedAt: Date(timeIntervalSince1970: 1_000))
        let later = SessionActivityAttributes.State(session(.running, .working), updatedAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertFalse(later.differsVisibly(from: base), "same content, newer poll")

        XCTAssertTrue(SessionActivityAttributes.State(session(.running, .waitingForUser)).differsVisibly(from: base))
        XCTAssertTrue(SessionActivityAttributes.State(session(.running, .working, acus: 1.5)).differsVisibly(from: base))
        XCTAssertTrue(SessionActivityAttributes.State(session(.running, .working, title: "Renamed")).differsVisibly(from: base))
        XCTAssertTrue(SessionActivityAttributes.State(session(.exit, .finished)).differsVisibly(from: base))
    }

    func testAttributesAndStateRoundTripThroughCodable() throws {
        let attributes = SessionActivityAttributes(sessionID: "devin-abc123")
        XCTAssertEqual(attributes.deepLink.url.absoluteString, "devinmobile://session/devin-abc123")
        XCTAssertEqual(try JSONDecoder().decode(SessionActivityAttributes.self, from: JSONEncoder().encode(attributes)), attributes)

        let state = SessionActivityAttributes.State(session(.error, .error), updatedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(try JSONDecoder().decode(SessionActivityAttributes.State.self, from: JSONEncoder().encode(state)), state)
    }
}
