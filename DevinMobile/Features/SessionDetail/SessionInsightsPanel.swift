import SwiftUI
import DevinKit

/// "Insights" disclosure in the detail header: issues, timeline, action items and the suggested
/// prompt from `GET …/insights`, with an on-demand Generate button. Renders nothing at all once
/// the API answers 403, so principals without the permission never see the feature.
struct SessionInsightsPanel: View {
    @State private var model: SessionInsightsModel
    @State private var isExpanded = false
    var onUseSuggestedPrompt: (String) -> Void

    init(store: SessionStore, sessionID: String, onUseSuggestedPrompt: @escaping (String) -> Void) {
        _model = State(initialValue: SessionInsightsModel(store: store, sessionID: sessionID))
        self.onUseSuggestedPrompt = onUseSuggestedPrompt
    }

    var body: some View {
        if !model.isForbidden {
            DisclosureGroup(isExpanded: $isExpanded) {
                content
                    .padding(.top, 6)
            } label: {
                Label {
                    HStack(spacing: 6) {
                        Text("Insights")
                        if let summary {
                            summary
                                .foregroundStyle(.secondary)
                        }
                        if model.isGenerating {
                            ProgressView().controlSize(.mini)
                        }
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { isExpanded.toggle() } }
            }
            .task { await model.load() }
            .onDisappear { model.cancelGeneration() }
        }
    }

    private var summary: Text? {
        guard let analysis = model.analysis else { return nil }
        let issues = analysis.issues.count
        return issues == 0 ? Text("No issues") : Text("^[\(issues) issue](inflect: true)")
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if let analysis = model.analysis {
            analysisBody(analysis)
        } else if model.hasLoaded || model.error != nil {
            emptyState
        }

        if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isGenerating
                 ? "Devin is analysing this session. This usually takes a minute or two."
                 : "No insights yet. Devin can review this session for issues, a timeline and a better prompt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                model.generate()
            } label: {
                if model.isGenerating {
                    Label { Text("Generating…") } icon: { ProgressView().controlSize(.small) }
                } else {
                    Label("Generate insights", systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.canGenerate)
        }
    }

    private func analysisBody(_ analysis: SessionInsightsAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let insights = model.insights {
                metrics(insights)
            }

            if analysis.isEmpty {
                Text("Devin didn't find anything worth flagging in this session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !analysis.issues.isEmpty {
                section("Issues", systemImage: "exclamationmark.bubble") {
                    ForEach(analysis.issues) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }

            if !analysis.timeline.isEmpty {
                section("Timeline", systemImage: "clock") {
                    ForEach(Array(analysis.timeline.enumerated()), id: \.offset) { index, event in
                        TimelineRow(event: event, isLast: index == analysis.timeline.count - 1)
                    }
                }
            }

            if !analysis.actionItems.isEmpty {
                section("Action items", systemImage: "checklist") {
                    ForEach(Array(analysis.actionItems.enumerated()), id: \.offset) { _, item in
                        ActionItemRow(item: item)
                    }
                }
            }

            if let prompt = analysis.suggestedPrompt {
                section("Suggested prompt", systemImage: "text.badge.plus") {
                    SuggestedPromptCard(prompt: prompt) {
                        onUseSuggestedPrompt(prompt.suggestedPrompt)
                    }
                }
            }
        }
    }

    private func metrics(_ insights: SessionInsights) -> some View {
        HStack(spacing: 10) {
            Label("\(insights.numUserMessages)", systemImage: "person")
            Label("\(insights.numDevinMessages)", systemImage: "cpu")
            if let size = insights.size {
                Text(size.displayName + " session")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insights.numUserMessages) messages from you, \(insights.numDevinMessages) from Devin")
    }

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

private struct IssueRow: View {
    let issue: SessionInsightsIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(issue.displayTitle)
                    .font(.subheadline.weight(.medium))
                if !issue.label.isEmpty, issue.displayTitle != issue.label {
                    Text(issue.label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(issue.issue)
                .font(.footnote)
            if !issue.impact.isEmpty {
                Text(issue.impact)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TimelineRow: View {
    let event: SessionInsightsTimelineEvent
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                Text(event.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 10)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The analyser sends a loose colour word; anything unrecognised gets the accent colour.
    private var color: Color {
        switch event.color.lowercased() {
        case "red": .red
        case "orange", "amber": .orange
        case "yellow": .yellow
        case "green": .green
        case "blue": .blue
        case "purple", "violet": .purple
        case "gray", "grey": .gray
        default: .accentColor
        }
    }
}

private struct ActionItemRow: View {
    let item: SessionInsightsActionItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if let kind = item.kind {
                    Text(kind.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Text(item.actionItem)
                    .font(.footnote)
            }
        }
    }
}

private struct SuggestedPromptCard: View {
    let prompt: SessionInsightsSuggestedPrompt
    let onUse: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.suggestedPrompt)
                .font(.footnote)
                .lineLimit(isExpanded ? nil : 6)
                .textSelection(.enabled)
                .onTapGesture { withAnimation(.snappy) { isExpanded.toggle() } }

            if !prompt.feedbackItems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(prompt.feedbackItems.enumerated()), id: \.offset) { _, item in
                        Label(item.summary, systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button(action: onUse) {
                Label("Start new session with this prompt", systemImage: "plus.bubble")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Suggested prompt → New session

/// Prefilled New Session sheet plus the push to the created session. Lives on the detail view
/// (outside the transcript's lazy stack) so the navigation destination is always registered.
struct SuggestedPromptDraft: Identifiable, Hashable {
    let id = UUID()
    let prompt: String
}

private struct SuggestedPromptSessionFlow: ViewModifier {
    let store: SessionStore
    @Binding var draft: SuggestedPromptDraft?
    @State private var created: Session?

    func body(content: Content) -> some View {
        content
            .sheet(item: $draft) { draft in
                NewSessionView(store: store, initialPrompt: draft.prompt) { session in
                    created = session
                }
            }
            .navigationDestination(item: $created) { session in
                SessionDetailView(store: store, sessionID: session.id)
            }
    }
}

extension View {
    func suggestedPromptSessionFlow(store: SessionStore, draft: Binding<SuggestedPromptDraft?>) -> some View {
        modifier(SuggestedPromptSessionFlow(store: store, draft: draft))
    }
}
