import SwiftUI
import DevinKit

struct PullRequestLink: View {
    let pullRequest: PullRequest

    var body: some View {
        Link(destination: pullRequest.url) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.pull")
                Text(label)
                    .lineLimit(1)
                if let state = pullRequest.state {
                    Text(state.capitalized)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stateColor(state).opacity(0.15), in: Capsule())
                        .foregroundStyle(stateColor(state))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// `owner/repo#123` for GitHub-style URLs, otherwise the host + path.
    private var label: String {
        let parts = pullRequest.url.pathComponents.filter { $0 != "/" }
        if parts.count >= 4, parts[2] == "pull" || parts[2] == "pulls" || parts[2] == "merge_requests" {
            return "\(parts[0])/\(parts[1])#\(parts[3])"
        }
        return (pullRequest.url.host ?? "") + pullRequest.url.path
    }

    private func stateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "open": .green
        case "merged": .purple
        case "closed": .red
        default: .secondary
        }
    }
}
