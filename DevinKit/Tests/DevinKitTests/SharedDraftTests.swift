import Foundation
import XCTest
@testable import DevinKit

final class GitHubLinkTests: XCTestCase {
    private func link(_ raw: String) -> GitHubLink? { GitHubLink(url: URL(string: raw)!) }

    func testRepositoryURLMapsToHostPrefixedRepoPath() {
        let repo = link("https://github.com/vasturnonthegas/devin-mobile")
        XCTAssertEqual(repo?.repoPath, "github.com/vasturnonthegas/devin-mobile")
        XCTAssertEqual(repo?.kind, .repository)
        XCTAssertEqual(link("https://github.com/owner/repo/")?.kind, .repository)
        XCTAssertEqual(link("https://www.github.com/owner/repo.git")?.repoPath, "github.com/owner/repo")
        XCTAssertEqual(link("HTTP://GitHub.com/owner/repo")?.repoPath, "github.com/owner/repo")
    }

    func testPullRequestAndIssueURLsKeepTheirNumber() {
        XCTAssertEqual(link("https://github.com/owner/repo/pull/123")?.kind, .pullRequest(123))
        XCTAssertEqual(link("https://github.com/owner/repo/pull/123/files#diff-abc")?.kind, .pullRequest(123))
        XCTAssertEqual(link("https://github.com/owner/repo/pull/123")?.repoPath, "github.com/owner/repo")
        XCTAssertEqual(link("https://github.com/owner/repo/issues/7?foo=bar")?.kind, .issue(7))
        XCTAssertEqual(link("https://github.com/owner/repo/pull/not-a-number")?.kind, .other)
        XCTAssertEqual(link("https://github.com/owner/repo/blob/main/README.md")?.kind, .other)
        XCTAssertEqual(link("https://github.com/owner/repo/tree/main")?.kind, .other)
    }

    func testRejectsNonRepositoryURLs() {
        for raw in [
            "https://github.com",
            "https://github.com/",
            "https://github.com/owner",
            "https://github.com/orgs/acme/projects/1",
            "https://github.com/settings/profile",
            "https://github.com/topics/swift",
            "https://gist.github.com/owner/abc123",
            "https://gitlab.com/owner/repo",
            "https://api.github.com/repos/owner/repo",
            "ftp://github.com/owner/repo",
            "https://github.com/owner/re po",
        ] {
            XCTAssertNil(link(raw), raw)
        }
    }

    func testFindsLinksInFreeTextOnce() {
        let text = """
        Please look at https://github.com/owner/repo/pull/12, then https://github.com/owner/repo.
        Also (https://github.com/other/thing) and a non-repo https://github.com/explore page.
        """
        let links = GitHubLink.links(in: text)
        XCTAssertEqual(links.map(\.repoPath), ["github.com/owner/repo", "github.com/owner/repo", "github.com/other/thing"])
        XCTAssertEqual(links.map(\.kind), [.pullRequest(12), .repository, .repository])
        XCTAssertEqual(GitHubLink.links(in: "nothing here"), [])
    }
}

final class SharedDraftTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        suite = "SharedDraftTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: compose

    func testRepositoryURLFillsReposOnly() {
        let draft = SharedDraft.compose(urls: [URL(string: "https://github.com/owner/repo")!])
        XCTAssertEqual(draft.repos, ["github.com/owner/repo"])
        XCTAssertEqual(draft.prompt, "")
        XCTAssertFalse(draft.isEmpty)
    }

    func testPullRequestURLFillsReposAndStaysInPrompt() {
        let url = "https://github.com/owner/repo/pull/42"
        let draft = SharedDraft.compose(urls: [URL(string: url)!])
        XCTAssertEqual(draft.repos, ["github.com/owner/repo"])
        XCTAssertEqual(draft.prompt, url)
    }

    func testTextComesFirstAndURLsAreNotRepeated() {
        let url = "https://github.com/owner/repo/issues/9"
        let draft = SharedDraft.compose(text: "  Fix this: \(url)\n", urls: [URL(string: url)!])
        XCTAssertEqual(draft.prompt, "Fix this: \(url)")
        XCTAssertEqual(draft.repos, ["github.com/owner/repo"])

        let titled = SharedDraft.compose(text: "Some article", urls: [URL(string: "https://example.com/post")!])
        XCTAssertEqual(titled.prompt, "Some article\n\nhttps://example.com/post")
        XCTAssertEqual(titled.repos, [])
    }

    func testReposFromTextAndURLsAreDeduplicated() {
        let draft = SharedDraft.compose(
            text: "See https://github.com/owner/repo and https://github.com/other/lib",
            urls: [URL(string: "https://github.com/owner/repo")!]
        )
        XCTAssertEqual(draft.repos, ["github.com/owner/repo", "github.com/other/lib"])
    }

    func testEmptyShareIsEmpty() {
        XCTAssertTrue(SharedDraft.compose(text: "  \n").isEmpty)
        XCTAssertTrue(SharedDraft().isEmpty)
    }

    // MARK: persistence

    func testSaveLoadClearRoundTripWithAttachmentFiles() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let attachment = try SharedDraft.Attachment.write(bytes, filename: "shot.png", mime: "image/png", to: directory)
        XCTAssertTrue(attachment.id.hasSuffix(".png"))
        XCTAssertEqual(attachment.byteCount, 4)
        XCTAssertTrue(attachment.isImage)

        let stray = directory.appendingPathComponent("stray.bin")
        try Data([1]).write(to: stray)

        let draft = SharedDraft(prompt: "Look at this", repos: ["github.com/owner/repo"], attachments: [attachment],
                                createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try draft.save(to: defaults, directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path), "files outside the draft are swept")

        let loaded = SharedDraft.load(from: defaults, directory: directory, now: Date(timeIntervalSince1970: 1_700_000_100))
        XCTAssertEqual(loaded, draft)
        XCTAssertEqual(try loaded?.attachments.first?.data(in: directory), bytes)

        SharedDraft.clear(in: defaults, directory: directory)
        XCTAssertNil(SharedDraft.load(from: defaults, directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.fileURL(in: directory).path))
    }

    func testStaleDraftIsDroppedOnLoad() throws {
        let attachment = try SharedDraft.Attachment.write(Data([1, 2]), filename: "a.txt", mime: "text/plain", to: directory)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        try SharedDraft(prompt: "old", attachments: [attachment], createdAt: created).save(to: defaults, directory: directory)

        XCTAssertNotNil(SharedDraft.load(from: defaults, directory: directory, now: created + SharedDraft.maxAge - 1))
        XCTAssertNil(SharedDraft.load(from: defaults, directory: directory, now: created + SharedDraft.maxAge + 1))
        XCTAssertNil(defaults.data(forKey: "pendingSharedDraft"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.fileURL(in: directory).path))
    }

    func testDirectoryFallsBackWithoutContainer() {
        let url = SharedDraft.directory(in: nil)
        XCTAssertEqual(url.lastPathComponent, "SharedDraft")
        XCTAssertEqual(SharedDraft.directory(in: URL(fileURLWithPath: "/tmp/group")).path, "/tmp/group/SharedDraft")
    }
}
