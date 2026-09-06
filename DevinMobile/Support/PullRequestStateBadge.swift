import SwiftUI
import DevinKit

/// Same visual language as `StatusBadge` (dot + caption) and the same palette: blue = in progress,
/// green = done, red = stopped, gray = dormant, secondary = anything we don't recognise.
struct PullRequestStateBadge: View {
    let state: PullRequestState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.displayName)
                .font(.caption2.bold())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pull request \(state.displayName)")
    }

    private var color: Color {
        switch state {
        case .open: .blue
        case .merged: .green
        case .closed: .red
        case .draft: .gray
        case .unknown: .secondary
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(["open", "draft", "merged", "closed", "locked_by_bot", nil], id: \.self) { raw in
            PullRequestStateBadge(state: PullRequestState(rawValue: raw))
        }
    }
    .padding()
}
