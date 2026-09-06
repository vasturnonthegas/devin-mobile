import Foundation
import MetricKit

/// The app's only crash / hang reporting: a MetricKit subscriber that keeps the diagnostic payloads
/// iOS hands back after a crash, hang, CPU or disk-write exception as JSON files on the device.
/// Nothing is uploaded and no third-party SDK is involved (see HANDOFF §8); the files exist so a
/// TestFlight build whose crashes never reach Xcode Organizer (tester opted out of sharing
/// analytics) still has something to pull from the app container.
///
/// Files land in `Library/Application Support/Diagnostics/<end-timestamp>-<uuid>.json` (one per
/// payload, `MXDiagnosticPayload.jsonRepresentation`), excluded from backups, newest `retained` kept.
final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = DiagnosticsCollector()
    static let retained = 20

    /// Registers the subscriber. Call once at launch; payloads from a previous run arrive shortly after.
    static func install() {
        MXMetricManager.shared.add(shared)
    }

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    /// `2024-05-01T120000Z` — sortable and free of `:` so the name is safe on any file system.
    private static let stamp = Date.ISO8601FormatStyle().year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted).timeSeparator(.omitted)

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let directory = Self.directory
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var target = directory
            try target.setResourceValues(values)
        } catch {
            return
        }
        for payload in payloads {
            let name = "\(payload.timeStampEnd.formatted(Self.stamp))-\(UUID().uuidString).json"
            try? payload.jsonRepresentation().write(to: directory.appending(path: name), options: .atomic)
        }
        Self.trim(in: directory, keeping: Self.retained)
    }

    /// Oldest files go first; names start with an ISO-8601 timestamp, so lexical order is chronological.
    static func trim(in directory: URL, keeping limit: Int) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path()) else { return }
        for name in names.filter({ $0.hasSuffix(".json") }).sorted().dropLast(limit) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
