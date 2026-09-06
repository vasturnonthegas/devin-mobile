import SwiftUI
import DevinKit

/// A PR link with its Devin Review status underneath and a button to queue (or re-run) a review.
struct PullRequestReviewRow: View {
    @State private var model: PRReviewModel
    let pullRequest: PullRequest

    init(store: SessionStore, pullRequest: PullRequest) {
        self.pullRequest = pullRequest
        _model = State(initialValue: PRReviewModel(store: store, prURL: pullRequest.url))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PullRequestLink(pullRequest: pullRequest)
                .font(.subheadline)

            if !model.isForbidden {
                HStack(spacing: 6) {
                    PRReviewBadge(review: model.review, hasLoaded: model.hasLoaded)
                    Spacer()
                    Button {
                        Task { await model.trigger() }
                    } label: {
                        if model.isTriggering {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label(buttonTitle, systemImage: "sparkles")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .disabled(!model.canTrigger)
                    .accessibilityLabel("\(buttonTitle) with Devin Review")
                }
                .padding(.leading, 22)

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, 22)
                }
            }
        }
        .task(id: pullRequest.url) { await model.load() }
        .onDisappear { model.stopPolling() }
    }

    private var buttonTitle: String {
        model.review?.isFinished == true ? "Re-review" : "Review"
    }
}

private struct PRReviewBadge: View {
    let review: PRReview?
    let hasLoaded: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let review, !review.isFinished {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: symbol)
                    .font(.caption2)
            }
            Text(title)
                .font(.caption)
                .lineLimit(1)
            if let review {
                Text(review.shortSHA)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Devin Review: \(title)")
    }

    private var title: String {
        guard hasLoaded else { return "Devin Review…" }
        guard let review else { return "Not reviewed" }
        return review.statusSummary
    }

    private var symbol: String {
        switch review?.status {
        case .completed: "checkmark.seal.fill"
        case .errored: "xmark.seal"
        case .cancelled, .skipped: "minus.circle"
        case .pending, .running: "clock"
        case nil: review == nil ? "seal" : "questionmark.circle"
        }
    }

    private var color: Color {
        switch review?.status {
        case .completed: .green
        case .errored: .red
        case .pending, .running: .blue
        case .cancelled, .skipped, nil: .secondary
        }
    }
}
