import Foundation
import XCTest
@testable import DevinKit

final class MemberDirectoryTests: XCTestCase {
    private var transport: MockTransport!
    private var directory: MemberDirectory!

    override func setUp() {
        transport = MockTransport()
        directory = MemberDirectory(client: DevinClient(token: "cog_test", transport: transport), org: "org-xyz")
    }

    func testFetchesOnceAndServesLookupsFromCache() async {
        transport.stub(json: Fixtures.membersPage1)
        transport.stub(json: Fixtures.membersPage2)

        let initial = await directory.state
        XCTAssertEqual(initial, .unknown)

        let first = await directory.member(id: "user-1")
        XCTAssertEqual(first?.displayName, "Taj Vasudeva")
        XCTAssertEqual(transport.requests.count, 2, "both pages fetched on first lookup")

        let third = await directory.member(id: "user-3")
        XCTAssertEqual(third?.userID, "user-3")
        let missing = await directory.member(id: "user-nope")
        XCTAssertNil(missing)
        XCTAssertEqual(transport.requests.count, 2, "cache hit and miss must not refetch")

        let state = await directory.state
        XCTAssertEqual(state, .available)
        let names = await directory.members.map(\.displayName)
        XCTAssertEqual(names, ["sam@example.com", "Taj Vasudeva", "user-3"])
    }

    func testConcurrentLookupsShareOneFetch() async {
        transport.stub(json: Fixtures.membersPage2)

        async let a = directory.member(id: "user-3")
        async let b = directory.member(id: "user-3")
        let (ra, rb) = await (a, b)

        XCTAssertEqual(ra?.userID, "user-3")
        XCTAssertEqual(rb?.userID, "user-3")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testForbiddenIsStickyAndHidesMembers() async {
        transport.stub(403, json: Fixtures.problem403)

        let member = await directory.member(id: "user-1")
        XCTAssertNil(member)
        let state = await directory.state
        XCTAssertEqual(state, .forbidden)

        let again = await directory.member(id: "user-1")
        XCTAssertNil(again)
        let reload = await directory.load()
        XCTAssertEqual(reload, .forbidden)
        XCTAssertEqual(transport.requests.count, 1, "403 must not be retried")
    }

    func testTransientFailureRetriesNextTime() async {
        transport.stub(500, json: "{}")
        transport.stub(json: Fixtures.membersPage2)

        let failed = await directory.load()
        XCTAssertEqual(failed, .unknown)

        let member = await directory.member(id: "user-3")
        XCTAssertEqual(member?.userID, "user-3")
        XCTAssertEqual(transport.requests.count, 2)
    }
}
