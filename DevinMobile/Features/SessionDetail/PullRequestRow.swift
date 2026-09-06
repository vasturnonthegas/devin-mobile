import SwiftUI
import DevinKit

/// A PR link plus its Devin Review status and a trigger button. Lives in the detail header.
struct PullRequestRow: View {
    let pullRequest: PullRequest
    @State private var model: PRReviewModel

    init(store: SessionStore, pullRequest: PullRequest) {
        self.pullRequest = pullRequest
        _model = State(initialValue: PRReviewModel(store: store, prURL: pullRequest.url))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PullRequestLink(pullRequest: pullRequest)
                .font(.subheadline)

            if model.isAvailable {
                PRReviewStatusLine(model: model)
                    .padding(.leading, 22)
            }
        }
        .task { await model.load() }
        .onDisappear { model.stopWatching() }
    }
}

private struct PRReviewStatusLine: View {
    let model: PRReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let review = model.review {
                    PRReviewBadge(review: review)
                } else if model.hasLoaded {
                    Label("No Devin Review", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Devin Review", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView().controlSize(.mini)
                }

                Spacer()

                Button {
                    Task { await model.request() }
                } label: {
                    if model.isRequesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(model.review?.isFinished == true ? "Re-review" : "Review")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .disabled(!model.canRequest)
                .accessibilityLabel("Request Devin Review")
            }

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .animation(.snappy(duration: 0.2), value: model.review)
    }
}

private struct PRReviewBadge: View {
    let review: PRReview

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(review.statusSummary)
                .foregroundStyle(review.isInProgress ? color : .secondary)
            if review.isInProgress {
                ProgressView().controlSize(.mini)
            } else {
                Text(review.shortCommitSHA)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Devin Review: \(review.statusSummary), commit \(review.shortCommitSHA)")
    }

    private var symbol: String {
        switch review.status {
        case .pending: "clock"
        case .running: "sparkles"
        case .completed: "checkmark.seal.fill"
        case .errored: "xmark.seal"
        case .cancelled: "slash.circle"
        case .skipped: "forward.end"
        case nil: "questionmark.circle"
        }
    }

    private var color: Color {
        switch review.status {
        case .pending: .orange
        case .running: .blue
        case .completed: .green
        case .errored: .red
        case .cancelled, .skipped, nil: .secondary
        }
    }
}
