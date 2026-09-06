import XCTest
@testable import DevinKit

final class RepositoryTypedPathTests: XCTestCase {
    func testStripsSchemeGitSuffixAndTrailingSlashes() {
        XCTAssertEqual(Repository.typedPath("https://github.com/acme/app.git/"), "github.com/acme/app")
        XCTAssertEqual(Repository.typedPath("HTTP://github.com/acme/app"), "github.com/acme/app")
        XCTAssertEqual(Repository.typedPath("  acme/app\n"), "acme/app")
        XCTAssertEqual(Repository.typedPath("github.com/acme/app"), "github.com/acme/app")
    }

    func testRejectsAnythingThatIsNotOwnerSlashRepo() {
        for raw in ["", "acme", "acme/", "/app", "acme//app", "acme/my app", "https://github.com/"] {
            XCTAssertNil(Repository.typedPath(raw), raw)
        }
    }
}
