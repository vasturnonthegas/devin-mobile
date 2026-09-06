import Foundation

/// Mirrors `SessionInsightsResponse` in the Devin v3 OpenAPI schema, reduced to the fields that are
/// not already on `Session`. `analysis` is nil until Devin has finished analysing the session.
public struct SessionInsights: Codable, Hashable, Sendable {
    public enum Size: String, Codable, Sendable, CaseIterable {
        case xs, s, m, l, xl

        public var displayName: String {
            switch self {
            case .xs: "Tiny"
            case .s: "Small"
            case .m: "Medium"
            case .l: "Large"
            case .xl: "Huge"
            }
        }
    }

    public let sessionID: String
    public let numUserMessages: Int
    public let numDevinMessages: Int
    public let size: Size?
    public let analysis: SessionInsightsAnalysis?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case numUserMessages = "num_user_messages"
        case numDevinMessages = "num_devin_messages"
        case size = "session_size"
        case analysis
    }

    public init(sessionID: String, numUserMessages: Int = 0, numDevinMessages: Int = 0, size: Size? = nil, analysis: SessionInsightsAnalysis? = nil) {
        self.sessionID = sessionID
        self.numUserMessages = numUserMessages
        self.numDevinMessages = numDevinMessages
        self.size = size
        self.analysis = analysis
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        numUserMessages = try c.decodeIfPresent(Int.self, forKey: .numUserMessages) ?? 0
        numDevinMessages = try c.decodeIfPresent(Int.self, forKey: .numDevinMessages) ?? 0
        size = try? c.decodeIfPresent(Size.self, forKey: .size)
        analysis = try c.decodeIfPresent(SessionInsightsAnalysis.self, forKey: .analysis)
    }

    public var hasAnalysis: Bool { analysis != nil }
}

/// `SessionInsightsAnalysis`: what the web app renders in the "Insights" panel.
public struct SessionInsightsAnalysis: Codable, Hashable, Sendable {
    public let issues: [SessionInsightsIssue]
    public let timeline: [SessionInsightsTimelineEvent]
    public let actionItems: [SessionInsightsActionItem]
    public let suggestedPrompt: SessionInsightsSuggestedPrompt?

    enum CodingKeys: String, CodingKey {
        case issues, timeline
        case actionItems = "action_items"
        case suggestedPrompt = "suggested_prompt"
    }

    public init(issues: [SessionInsightsIssue] = [], timeline: [SessionInsightsTimelineEvent] = [],
                actionItems: [SessionInsightsActionItem] = [], suggestedPrompt: SessionInsightsSuggestedPrompt? = nil) {
        self.issues = issues
        self.timeline = timeline
        self.actionItems = actionItems
        self.suggestedPrompt = suggestedPrompt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issues = try c.decodeIfPresent([SessionInsightsIssue].self, forKey: .issues) ?? []
        timeline = try c.decodeIfPresent([SessionInsightsTimelineEvent].self, forKey: .timeline) ?? []
        actionItems = try c.decodeIfPresent([SessionInsightsActionItem].self, forKey: .actionItems) ?? []
        suggestedPrompt = try c.decodeIfPresent(SessionInsightsSuggestedPrompt.self, forKey: .suggestedPrompt)
    }

    public var isEmpty: Bool {
        issues.isEmpty && timeline.isEmpty && actionItems.isEmpty && suggestedPrompt == nil
    }
}

public struct SessionInsightsIssue: Codable, Hashable, Sendable, Identifiable {
    /// The API may send an empty `id`; `id` falls back to the title so lists stay stable.
    public let issueID: String
    public let title: String
    public let issue: String
    public let impact: String
    public let label: String

    public var id: String { issueID.isEmpty ? title : issueID }

    enum CodingKeys: String, CodingKey {
        case issueID = "id"
        case title, issue, impact, label
    }

    public init(issueID: String = "", title: String = "", issue: String, impact: String, label: String) {
        self.issueID = issueID
        self.title = title
        self.issue = issue
        self.impact = impact
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issueID = try c.decodeIfPresent(String.self, forKey: .issueID) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        issue = try c.decode(String.self, forKey: .issue)
        impact = try c.decode(String.self, forKey: .impact)
        label = try c.decode(String.self, forKey: .label)
    }

    public var displayTitle: String { title.isEmpty ? label : title }
}

public struct SessionInsightsTimelineEvent: Codable, Hashable, Sendable {
    public let title: String
    public let description: String
    /// Free-form colour name from the analyser (e.g. "red", "green"); not an enum in the spec.
    public let color: String
    public let issueID: String?

    enum CodingKeys: String, CodingKey {
        case title, description, color
        case issueID = "issue_id"
    }

    public init(title: String, description: String, color: String = "", issueID: String? = nil) {
        self.title = title
        self.description = description
        self.color = color
        self.issueID = issueID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? ""
        issueID = try c.decodeIfPresent(String.self, forKey: .issueID)
    }
}

public struct SessionInsightsActionItem: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case machineSetup = "machine_setup"
        case repoConfig = "repo_config"
        case knowledge
        case promptImprovement = "prompt_improvement"
        case external
        case other

        public var displayName: String {
            switch self {
            case .machineSetup: "Machine setup"
            case .repoConfig: "Repo config"
            case .knowledge: "Knowledge"
            case .promptImprovement: "Prompt"
            case .external: "External"
            case .other: "Other"
            }
        }
    }

    /// `.other` when omitted (the spec's default); nil when the API sends a kind this build doesn't know.
    public let kind: Kind?
    public let actionItem: String
    public let issueID: String?

    enum CodingKeys: String, CodingKey {
        case kind = "type"
        case actionItem = "action_item"
        case issueID = "issue_id"
    }

    public init(kind: Kind? = .other, actionItem: String, issueID: String? = nil) {
        self.kind = kind
        self.actionItem = actionItem
        self.issueID = issueID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.contains(.kind) ? try? c.decode(Kind.self, forKey: .kind) : .other
        actionItem = try c.decode(String.self, forKey: .actionItem)
        issueID = try c.decodeIfPresent(String.self, forKey: .issueID)
    }
}

public struct SessionInsightsSuggestedPrompt: Codable, Hashable, Sendable {
    public let originalPrompt: String
    public let suggestedPrompt: String
    public let feedbackItems: [SessionInsightsFeedbackItem]

    enum CodingKeys: String, CodingKey {
        case originalPrompt = "original_prompt"
        case suggestedPrompt = "suggested_prompt"
        case feedbackItems = "feedback_items"
    }

    public init(originalPrompt: String, suggestedPrompt: String, feedbackItems: [SessionInsightsFeedbackItem] = []) {
        self.originalPrompt = originalPrompt
        self.suggestedPrompt = suggestedPrompt
        self.feedbackItems = feedbackItems
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originalPrompt = try c.decode(String.self, forKey: .originalPrompt)
        suggestedPrompt = try c.decode(String.self, forKey: .suggestedPrompt)
        feedbackItems = try c.decodeIfPresent([SessionInsightsFeedbackItem].self, forKey: .feedbackItems) ?? []
    }
}

public struct SessionInsightsFeedbackItem: Codable, Hashable, Sendable {
    public let summary: String
    public let excerpt: String
    public let details: String
    public let issueID: String?

    enum CodingKeys: String, CodingKey {
        case summary, excerpt, details
        case issueID = "issue_id"
    }

    public init(summary: String, excerpt: String, details: String, issueID: String? = nil) {
        self.summary = summary
        self.excerpt = excerpt
        self.details = details
        self.issueID = issueID
    }
}

/// Mirrors `SessionInsightsGenerateResponse`. `status` is a free-form string in the spec; the only
/// documented value is `already_exists`, everything else means generation was kicked off.
public struct SessionInsightsGeneration: Codable, Hashable, Sendable {
    public let sessionID: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case status
    }

    public init(sessionID: String, status: String) {
        self.sessionID = sessionID
        self.status = status
    }

    public var alreadyExists: Bool { status == "already_exists" }
}
