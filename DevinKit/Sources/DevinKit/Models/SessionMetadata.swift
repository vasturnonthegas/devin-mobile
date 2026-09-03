import Foundation

/// Use-case category assigned by Devin's categoriser. Only populated on get/list endpoints.
public enum SessionCategory: String, Codable, Sendable, CaseIterable {
    case bugFixing = "bug_fixing"
    case ciCdAndDevops = "ci_cd_and_devops"
    case codeQualityAndSecurity = "code_quality_and_security"
    case codeReview = "code_review"
    case codeReviewAndAnalysis = "code_review_and_analysis"
    case dataAndAutomation = "data_and_automation"
    case documentationAndContent = "documentation_and_content"
    case featureDevelopment = "feature_development"
    case migrationsAndUpgrades = "migrations_and_upgrades"
    case other
    case productionInvestigation = "production_investigation"
    case refactoringAndOptimization = "refactoring_and_optimization"
    case researchAndExploration = "research_and_exploration"
    case security
    case unitTestGeneration = "unit_test_generation"

    public var displayName: String {
        switch self {
        case .bugFixing: "Bug fixing"
        case .ciCdAndDevops: "CI/CD & DevOps"
        case .codeQualityAndSecurity: "Code quality & security"
        case .codeReview: "Code review"
        case .codeReviewAndAnalysis: "Code review & analysis"
        case .dataAndAutomation: "Data & automation"
        case .documentationAndContent: "Documentation & content"
        case .featureDevelopment: "Feature development"
        case .migrationsAndUpgrades: "Migrations & upgrades"
        case .other: "Other"
        case .productionInvestigation: "Production investigation"
        case .refactoringAndOptimization: "Refactoring & optimization"
        case .researchAndExploration: "Research & exploration"
        case .security: "Security"
        case .unitTestGeneration: "Unit test generation"
        }
    }
}

public extension SessionOrigin {
    var displayName: String {
        switch self {
        case .webapp: "Web"
        case .slack: "Slack"
        case .teams: "Teams"
        case .api: "API"
        case .linear: "Linear"
        case .jira: "Jira"
        case .automation: "Automation"
        case .cli: "CLI"
        case .desktop: "Desktop"
        case .codeScan: "Code scan"
        case .other: "Other"
        }
    }
}

public extension Session {
    /// "Category › Subcategory", omitting the subcategory when it merely repeats the category
    /// or is the API's "Other" placeholder.
    var categorySummary: String? {
        guard let category else { return nil }
        let name = category.displayName
        guard let subcategory, !subcategory.isEmpty,
              subcategory.caseInsensitiveCompare("other") != .orderedSame,
              subcategory.caseInsensitiveCompare(name) != .orderedSame
        else { return name }
        return "\(name) › \(subcategory)"
    }

    /// Compact secondary metadata for a row or header: category, origin, automation.
    var metadataSummary: [String] {
        var parts: [String] = []
        if let categorySummary { parts.append(categorySummary) }
        if let origin { parts.append(origin.displayName) }
        if automationID != nil { parts.append("Automation") }
        return parts
    }
}
