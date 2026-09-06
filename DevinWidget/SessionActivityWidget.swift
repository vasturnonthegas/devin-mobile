import ActivityKit
import DevinKit
import SwiftUI
import WidgetKit

/// Lock-screen / Dynamic Island rendering of the pinned session (`SessionActivityAttributes`). Reads
/// nothing itself — the app pushes every state through `SessionLiveActivity`. Tapping anywhere opens
/// the session via `devinmobile://session/<id>`.
struct SessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionActivityLockScreenView(state: context.state, isStale: context.isStale)
                .padding(14)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .widgetURL(context.attributes.deepLink.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BucketMark(bucket: context.state.bucket, isFinal: context.state.isFinal)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ACUText(acus: context.state.acusConsumed)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    StatusLine(state: context.state, isStale: context.isStale)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                BucketMark(bucket: context.state.bucket, isFinal: context.state.isFinal)
            } compactTrailing: {
                ACUText(acus: context.state.acusConsumed)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                BucketMark(bucket: context.state.bucket, isFinal: context.state.isFinal)
            }
            .widgetURL(context.attributes.deepLink.url)
            .keylineTint(context.state.bucket.color)
        }
    }
}

// MARK: - Lock screen

struct SessionActivityLockScreenView: View {
    let state: SessionActivityAttributes.State
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text("Devin")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                }
                .labelStyle(.titleAndIcon)
                Spacer()
                ACUText(acus: state.acusConsumed)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(state.title)
                .font(.headline)
                .lineLimit(2)

            StatusLine(state: state, isStale: isStale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pieces

/// Status dot + summary, then how fresh it is: "Updated 3 min ago", "may be out of date" once
/// `staleDate` has passed, or "Ended" for the final state left on the lock screen.
private struct StatusLine: View {
    let state: SessionActivityAttributes.State
    let isStale: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.bucket.color)
                .frame(width: 8, height: 8)
            Text(state.statusSummary)
                .font(.subheadline.weight(state.bucket == .needsYou ? .semibold : .regular))
                .foregroundStyle(state.bucket == .needsYou ? state.bucket.color : .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            freshness
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var freshness: some View {
        if state.isFinal {
            Text("Ended \(state.updatedAt, style: .time)")
        } else if isStale {
            Label("May be out of date", systemImage: "clock.arrow.circlepath")
        } else {
            Text("Updated \(Text(state.updatedAt, style: .relative)) ago")
        }
    }
}

private struct ACUText: View {
    let acus: Double

    var body: some View {
        Text("\(acus, format: .number.precision(.fractionLength(0...2))) ACU")
            .contentTransition(.numericText())
    }
}

/// One glyph per bucket for the Dynamic Island, where there is no room for text.
private struct BucketMark: View {
    let bucket: Session.Bucket
    let isFinal: Bool

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(bucket.color)
            .accessibilityLabel(bucket.title)
    }

    private var symbol: String {
        switch bucket {
        case .needsYou: "hand.raised.fill"
        case .working: "gearshape.2.fill"
        case .finished: "checkmark.circle.fill"
        case .sleeping: "moon.zzz.fill"
        case .failed: isFinal ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Previews

#Preview("Lock screen", as: .content, using: SessionActivityAttributes(sessionID: "sample-1")) {
    SessionActivityWidget()
} contentStates: {
    SessionActivityAttributes.State.sampleWorking
    SessionActivityAttributes.State.sampleNeedsYou
    SessionActivityAttributes.State.sampleFinished
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: SessionActivityAttributes(sessionID: "sample-1")) {
    SessionActivityWidget()
} contentStates: {
    SessionActivityAttributes.State.sampleWorking
    SessionActivityAttributes.State.sampleNeedsYou
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: SessionActivityAttributes(sessionID: "sample-1")) {
    SessionActivityWidget()
} contentStates: {
    SessionActivityAttributes.State.sampleWorking
    SessionActivityAttributes.State.sampleFinished
}

extension SessionActivityAttributes.State {
    private static func sample(_ status: SessionStatus, _ detail: SessionStatusDetail?, acus: Double, secondsAgo: TimeInterval = 0) -> SessionActivityAttributes.State {
        let session = Session(sessionID: "sample-1", orgID: "org-sample", status: status, statusDetail: detail,
                              title: "Fix flaky CI on main", url: URL(string: "https://app.devin.ai/sessions/sample-1")!,
                              acusConsumed: acus, createdAt: .now.addingTimeInterval(-3_600), updatedAt: .now)
        return SessionActivityAttributes.State(session, updatedAt: .now.addingTimeInterval(-secondsAgo))
    }

    static let sampleWorking = sample(.running, .working, acus: 1.25, secondsAgo: 180)
    static let sampleNeedsYou = sample(.running, .waitingForApproval, acus: 2.5)
    static let sampleFinished = sample(.exit, .finished, acus: 3.75)
}
