import DevinKit
import SwiftUI
import WidgetKit

struct NeedsYouWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch entry.content {
        case .signedOut:
            PlaceholderView(symbol: "person.crop.circle.badge.questionmark", title: "Sign in to Devin",
                            detail: "Open the app and paste your API token.")
        case .awaitingFirstLoad:
            PlaceholderView(symbol: "tray", title: "No sessions yet", detail: "Open Devin to load your inbox.")
        case .sessions(let snapshot):
            if family == .systemMedium {
                MediumSnapshotView(snapshot: snapshot)
            } else {
                SmallSnapshotView(snapshot: snapshot)
                    .widgetURL(snapshot.topEntries(1).first?.deepLink.url)
            }
        }
    }
}

// MARK: - Families

private struct SmallSnapshotView: View {
    let snapshot: SessionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NeedsYouCount(count: snapshot.needsYouCount, style: .compact)
            Spacer(minLength: 0)
            if snapshot.entries.isEmpty {
                Text("Inbox is empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(snapshot.topEntries()) { entry in
                        SessionRow(entry: entry, showsStatus: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumSnapshotView: View {
    let snapshot: SessionSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                NeedsYouCount(count: snapshot.needsYouCount, style: .regular)
                Spacer(minLength: 0)
                Text("Updated \(snapshot.capturedAt, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 112, alignment: .leading)

            if snapshot.entries.isEmpty {
                Text("Inbox is empty")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.topEntries()) { entry in
                        Link(destination: entry.deepLink.url) {
                            SessionRow(entry: entry, showsStatus: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Pieces

private struct NeedsYouCount: View {
    enum Style { case compact, regular }

    let count: Int
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(count, format: .number)
                .font(.system(size: style == .compact ? 34 : 40, weight: .bold, design: .rounded))
                .foregroundStyle(count > 0 ? Color.orange : Color.secondary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(count == 1 ? "session needs you" : "sessions need you")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SessionRow: View {
    let entry: SessionSnapshot.Entry
    let showsStatus: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(entry.bucket.color)
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(showsStatus ? .footnote : .caption)
                    .fontWeight(entry.bucket == .needsYou ? .semibold : .regular)
                    .lineLimit(1)
                if showsStatus {
                    Text(entry.statusSummary)
                        .font(.caption2)
                        .foregroundStyle(entry.bucket == .needsYou ? entry.bucket.color : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlaceholderView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(title)
                .font(.headline)
                .lineLimit(2)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension Session.Bucket {
    /// Mirrors `StatusBadge` in the app; the widget can't import app code.
    var color: Color {
        switch self {
        case .needsYou: .orange
        case .working: .blue
        case .finished: .green
        case .sleeping: .gray
        case .failed: .red
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    NeedsYouWidget()
} timeline: {
    SnapshotEntry(date: .now, content: .sessions(.sample))
    SnapshotEntry(date: .now, content: .signedOut)
    SnapshotEntry(date: .now, content: .awaitingFirstLoad)
}

#Preview("Medium", as: .systemMedium) {
    NeedsYouWidget()
} timeline: {
    SnapshotEntry(date: .now, content: .sessions(.sample))
    SnapshotEntry(date: .now, content: .sessions(SessionSnapshot(sessions: [])))
    SnapshotEntry(date: .now, content: .signedOut)
}
