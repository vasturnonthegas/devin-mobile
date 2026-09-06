import XCTest

/// Accessibility Inspector's audit, run from code (`XCUIApplication.performAccessibilityAudit`) against
/// the mock API at the default text size and at XXXL. Not part of CI's build-only job; run it on a
/// booted simulator with
/// `xcodebuild test -scheme DevinMobile -only-testing:DevinMobileUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
///
/// Two audit types depend on what happens to be scrolled under the bottom search bar, so they are only
/// meaningful when the list fits on screen:
/// - `.textClipped` and `.contrast` flag every text of a row that is partially covered by the search
///   bar (or half off the bottom edge). The full-list tests skip them; the single-row tests, which
///   filter the inbox down to one row, run the complete audit.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    /// Everything except the two scroll-position-dependent checks.
    private static let layoutIndependent: XCUIAccessibilityAuditType = [
        .dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .trait,
    ]

    /// The detail screen's markdown renderer (code spans, bullets, collapsed blocks) is outside this
    /// story; it is audited for what VoiceOver reads, not for how it is drawn.
    private static let labelsOnly: XCUIAccessibilityAuditType = [
        .elementDetection, .sufficientElementDescription, .trait,
    ]

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-MockAPI"]
    }

    // MARK: Inbox

    func testInboxAudit() throws {
        app.launch()
        try waitForInbox()
        try audit(Self.layoutIndependent)
    }

    func testInboxAuditAtXXXL() throws {
        useXXXL()
        app.launch()
        try waitForInbox()
        try audit(Self.layoutIndependent)
        attachScreenshot("inbox-xxxl")
    }

    func testInboxRowAudit() throws {
        app.launch()
        try waitForInbox()
        try filterInbox(to: "main #24")
        try audit(.all)
    }

    func testInboxRowAuditAtXXXL() throws {
        useXXXL()
        app.launch()
        try waitForInbox()
        try filterInbox(to: "main #24")
        try audit(.all)
        attachScreenshot("inbox-row-xxxl")
    }

    // MARK: Session detail

    func testSessionDetailAudit() throws {
        app.launch()
        try waitForInbox()
        try openFirstSession()
        try audit(Self.labelsOnly)
    }

    func testSessionDetailAuditAtXXXL() throws {
        useXXXL()
        app.launch()
        try waitForInbox()
        try openFirstSession()
        try audit(Self.labelsOnly)
        attachScreenshot("detail-xxxl")
    }

    // MARK: Helpers

    private func useXXXL() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
    }

    private func waitForInbox() throws {
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 20), "inbox rows did not load from the mock API")
    }

    /// Types `query` into the search bar and dismisses the keyboard, so the audit sees the app, not the keyboard.
    private func filterInbox(to query: String) throws {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "search field not found")
        search.tap()
        search.typeText(query + "\n")
        XCTAssertTrue(app.cells.buttons.firstMatch.waitForExistence(timeout: 5), "no row matched \(query)")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "keyboard still up")
    }

    private func openFirstSession() throws {
        // Section headers are cells too; the row is the cell's (only) button.
        app.cells.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.buttons["Actions"].waitForExistence(timeout: 10),
                      "detail toolbar did not appear")
    }

    /// One `XCTFail` per issue, naming the offending element so the failure is actionable from the log.
    /// "Nearly passed" is what Accessibility Inspector shows as a yellow warning (system `.secondary`
    /// text on a light background lands there); it is logged, not failed.
    private func audit(_ types: XCUIAccessibilityAuditType) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element.map { "\($0.elementType.rawValue) label=\"\($0.label)\" frame=\($0.frame)" } ?? "<no element>"
            let message = "[\(issue.auditType.rawValue)] \(issue.compactDescription) — \(element)\n\(issue.detailedDescription)"
            if issue.compactDescription.hasSuffix("nearly passed") {
                XCTContext.runActivity(named: "warning: \(message)") { _ in }
            } else {
                XCTFail(message)
            }
            return true
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
