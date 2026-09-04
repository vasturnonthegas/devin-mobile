import SwiftUI
import DevinKit

/// One-line "Category › Subcategory · Origin · Automation" summary. Renders nothing when the
/// session carries no secondary metadata so callers can place it unconditionally.
struct SessionMetadataLine: View {
    let session: Session
    var font: Font = .caption

    var body: some View {
        if !session.metadataSummary.isEmpty {
            HStack(spacing: 4) {
                if let category = session.categorySummary {
                    Label(category, systemImage: "tag")
                }
                if let origin = session.origin {
                    separator(after: session.categorySummary != nil)
                    Label(origin.displayName, systemImage: originSymbol(origin))
                }
                if session.automationID != nil {
                    separator(after: session.categorySummary != nil || session.origin != nil)
                    Label("Automation", systemImage: "bolt.badge.clock")
                }
            }
            .labelStyle(.titleAndIcon)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(session.metadataSummary.joined(separator: ", "))
        }
    }

    @ViewBuilder
    private func separator(after hasPrevious: Bool) -> some View {
        if hasPrevious {
            Text("·").foregroundStyle(.tertiary)
        }
    }

    private func originSymbol(_ origin: SessionOrigin) -> String {
        switch origin {
        case .webapp: "globe"
        case .slack: "number"
        case .teams: "person.2"
        case .api: "chevron.left.forwardslash.chevron.right"
        case .linear, .jira: "checklist"
        case .automation: "bolt"
        case .cli: "terminal"
        case .desktop: "desktopcomputer"
        case .codeScan: "shield.lefthalf.filled"
        case .other: "questionmark.circle"
        }
    }
}
