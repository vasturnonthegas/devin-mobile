import SwiftUI
import UIKit
import DevinKit

struct PullRequestLink: View {
    let pullRequest: PullRequest
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            ExternalLink.open(pullRequest.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.pull")
                Text(pullRequest.shortLabel)
                    .lineLimit(1)
                PullRequestStateBadge(state: pullRequest.stateKind)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHint("Opens in GitHub if installed, otherwise Safari")
        .contextMenu {
            Button("Open in Safari", systemImage: "safari") { openURL(pullRequest.url) }
            ShareLink(item: pullRequest.url) { Label("Share link", systemImage: "square.and.arrow.up") }
            Button("Copy link", systemImage: "doc.on.doc") {
                UIPasteboard.general.url = pullRequest.url
            }
        }
    }
}
