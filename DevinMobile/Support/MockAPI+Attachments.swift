#if DEBUG
import Foundation
import UIKit
import DevinKit

/// Attachments and a short transcript for every mock session, so the detail screen can be driven
/// without a PAT. Files are rendered on first use and served from
/// `/v3/organizations/org-mock/attachments/{uuid}/{name}`, mirroring the real download route
/// (minus the 307).
extension MockAPI {
    struct File {
        let uuid: String
        let name: String
        let contentType: String?
        let source: MessageSource
        let bytes: @Sendable () -> Data

        var url: String { "https://api.devin.ai/v3/organizations/org-mock/attachments/\(uuid)/\(name)" }
    }

    static let files: [File] = [
        File(uuid: "a1d3f0", name: "login-bug.png", contentType: "image/png", source: .user) { image("Login screen", tint: .systemRed) },
        File(uuid: "b2e4a1", name: "fix-preview.PNG", contentType: nil, source: .devin) { image("After fix", tint: .systemGreen) },
        File(uuid: "c3f5b2", name: "build.log", contentType: "text/plain", source: .devin) { Data(buildLog.utf8) },
        File(uuid: "d4a6c3", name: "test-report.pdf", contentType: "application/pdf", source: .devin) { pdf() },
    ]

    static func attachmentsJSON(for sessionID: String) -> Data {
        let index = Int(sessionID.suffix(3)) ?? 0
        let subset = index.isMultiple(of: 3) ? [files[0]] : files
        let items = subset.map { file -> String in
            let type = file.contentType.map { "\"\($0)\"" } ?? "null"
            return #"{"attachment_id":"att-\#(file.uuid)","name":"\#(file.name)","source":"\#(file.source.rawValue)","url":"\#(file.url)","content_type":\#(type)}"#
        }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    static func attachmentBody(uuid: String, name: String) -> Data? {
        files.first { $0.uuid == uuid && $0.name == name }?.bytes() ?? uploadedBody(uuid: uuid, name: name)
    }

    /// Messages that quote attachment URLs, so `SessionAttachmentsModel.placement(in:)` pins the
    /// files under them. Appended to the markdown transcript by `MockAPI.messages(for:)`.
    static func attachmentMessages(for sessionID: String, startingAt created: Date) -> [SessionMessage] {
        let index = Int(sessionID.suffix(3)) ?? 0
        var messages = [
            SessionMessage(eventID: "\(sessionID)-m1", source: .user,
                           message: "The login button overlaps the footer on small phones. Screenshot: \(files[0].url)",
                           createdAt: created),
            SessionMessage(eventID: "\(sessionID)-m2", source: .devin,
                           message: "Reproduced on iPhone SE. The footer uses a fixed height; switching it to a safe-area inset should fix it.",
                           createdAt: created.addingTimeInterval(90)),
        ]
        if !index.isMultiple(of: 3) {
            messages.append(SessionMessage(eventID: "\(sessionID)-m3", source: .devin,
                                           message: "Fixed and verified — here's how it looks now: \(files[1].url)\n\nFull build output and the test report are attached.",
                                           createdAt: created.addingTimeInterval(600)))
        }
        return messages
    }

    private static func image(_ caption: String, tint: UIColor) -> Data {
        let size = CGSize(width: 780, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { context in
            let colors = [tint.withAlphaComponent(0.85).cgColor, UIColor.systemIndigo.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor.white.withAlphaComponent(0.9).setFill()
            UIBezierPath(roundedRect: CGRect(x: 60, y: 200, width: 660, height: 800), cornerRadius: 40).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            (caption as NSString).draw(at: CGPoint(x: 100, y: 260), withAttributes: attributes)
        }
    }

    private static func pdf() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24, weight: .semibold)]
            ("Test report — 128 passed, 0 failed" as NSString).draw(at: CGPoint(x: 48, y: 64), withAttributes: attributes)
        }
    }

    private static let buildLog = (1...60).map { "[\(String(format: "%03d", $0))] Compiling LoginView.swift … ok" }.joined(separator: "\n")
}
#endif
