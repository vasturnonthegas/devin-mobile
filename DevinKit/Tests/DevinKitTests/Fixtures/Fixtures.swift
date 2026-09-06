import Foundation

enum Fixtures {
    static let sessionRunningWaiting = """
    {
      "session_id": "devin-abc123",
      "org_id": "org-xyz",
      "status": "running",
      "status_detail": "waiting_for_user",
      "title": "Fix login bug",
      "url": "https://app.devin.ai/sessions/abc123",
      "tags": ["bug", "auth"],
      "pull_requests": [{"pr_url": "https://github.com/acme/api/pull/42", "pr_state": "open"}],
      "acus_consumed": 3.25,
      "created_at": 1756800000,
      "updated_at": 1756803600,
      "is_archived": false,
      "devin_mode": "fast",
      "origin": "api",
      "playbook_id": null,
      "parent_session_id": null,
      "child_session_ids": [],
      "user_id": "user-1",
      "category": "bug_fixing",
      "subcategory": "Authentication",
      "automation_id": "automation-77",
      "structured_output": null
    }
    """

    static let sessionsPage = """
    {
      "items": [
        \(sessionRunningWaiting),
        {
          "session_id": "devin-def456",
          "org_id": "org-xyz",
          "status": "running",
          "status_detail": "working",
          "title": "Add widget",
          "url": "https://app.devin.ai/sessions/def456",
          "tags": [],
          "pull_requests": [],
          "acus_consumed": 0.5,
          "created_at": 1756800100,
          "updated_at": 1756800200,
          "origin": "slack",
          "category": "feature_development",
          "subcategory": "Other",
          "automation_id": null
        },
        {
          "session_id": "devin-ghi789",
          "org_id": "org-xyz",
          "status": "suspended",
          "status_detail": "some_future_detail",
          "title": null,
          "url": "https://app.devin.ai/sessions/ghi789",
          "tags": [],
          "pull_requests": [],
          "acus_consumed": 12,
          "created_at": 1756700000,
          "updated_at": 1756700001,
          "devin_mode": "brand_new_mode",
          "origin": "brand_new_origin",
          "category": "brand_new_category",
          "subcategory": "Whatever"
        }
      ],
      "end_cursor": "cursor-2",
      "has_next_page": true,
      "total": 3
    }
    """

    static let sessionParent = """
    {
      "session_id": "devin-parent",
      "org_id": "org-xyz",
      "status": "running",
      "status_detail": "working",
      "title": "Orchestrate sprint 1",
      "url": "https://app.devin.ai/sessions/parent",
      "tags": [],
      "pull_requests": [],
      "acus_consumed": 8,
      "created_at": 1756800000,
      "updated_at": 1756809000,
      "parent_session_id": null,
      "child_session_ids": ["devin-child1", "devin-child2"]
    }
    """

    static let childSessionsPage = """
    {
      "items": [
        {
          "session_id": "devin-child1",
          "org_id": "org-xyz",
          "status": "exit",
          "status_detail": "finished",
          "title": "A1: filters sheet",
          "url": "https://app.devin.ai/sessions/child1",
          "tags": [],
          "pull_requests": [{"pr_url": "https://github.com/acme/api/pull/43", "pr_state": "merged"}],
          "acus_consumed": 2.5,
          "created_at": 1756800300,
          "updated_at": 1756805000,
          "is_archived": true,
          "origin": "api",
          "parent_session_id": "devin-parent",
          "child_session_ids": []
        },
        {
          "session_id": "devin-child2",
          "org_id": "org-xyz",
          "status": "running",
          "status_detail": "waiting_for_user",
          "title": "A6: child sessions",
          "url": "https://app.devin.ai/sessions/child2",
          "tags": [],
          "pull_requests": [],
          "acus_consumed": 1,
          "created_at": 1756800400,
          "updated_at": 1756808000,
          "is_archived": false,
          "origin": "orchestrator_v9",
          "parent_session_id": "devin-parent",
          "child_session_ids": null
        }
      ],
      "end_cursor": null,
      "has_next_page": false,
      "total": 2
    }
    """

    /// Second page of `sessionsPage` (`after=cursor-2`). Includes an unknown `origin`.
    static let sessionsPage2 = """
    {
      "items": [
        {
          "session_id": "devin-jkl012",
          "org_id": "org-xyz",
          "status": "exit",
          "status_detail": "finished",
          "title": "Bump dependencies",
          "url": "https://app.devin.ai/sessions/jkl012",
          "tags": ["chore"],
          "pull_requests": [{"pr_url": "https://github.com/acme/api/pull/40", "pr_state": "merged"}],
          "acus_consumed": 1.5,
          "created_at": 1756600000,
          "updated_at": 1756600500,
          "origin": "hologram"
        },
        {
          "session_id": "devin-mno345",
          "org_id": "org-xyz",
          "status": "error",
          "status_detail": "error",
          "title": "Migrate DB",
          "url": "https://app.devin.ai/sessions/mno345",
          "tags": [],
          "pull_requests": [],
          "acus_consumed": 0.25,
          "created_at": 1756500000,
          "updated_at": 1756500100
        }
      ],
      "end_cursor": null,
      "has_next_page": false,
      "total": 5
    }
    """

    static let sessionArchived = """
    {
      "session_id": "devin-arch001",
      "org_id": "org-xyz",
      "status": "suspended",
      "status_detail": "user_request",
      "title": "Old spike",
      "url": "https://app.devin.ai/sessions/arch001",
      "tags": ["spike"],
      "pull_requests": [{"pr_url": "https://github.com/acme/api/pull/7", "pr_state": "merged"}],
      "acus_consumed": 1.5,
      "created_at": 1756000000,
      "updated_at": 1756100000,
      "is_archived": true,
      "origin": "teleporter"
    }
    """

    static let archivedSessionsPage = """
    {
      "items": [
        \(sessionArchived),
        {
          "session_id": "devin-arch002",
          "org_id": "org-xyz",
          "status": "exit",
          "status_detail": "finished",
          "title": "Shipped widget",
          "url": "https://app.devin.ai/sessions/arch002",
          "tags": [],
          "pull_requests": [],
          "acus_consumed": 4,
          "created_at": 1755000000,
          "updated_at": 1755100000,
          "is_archived": true
        }
      ],
      "end_cursor": null,
      "has_next_page": false,
      "total": 2
    }
    """

    static let sessionUnarchived = sessionArchived.replacingOccurrences(of: "\"is_archived\": true", with: "\"is_archived\": false")

    static let messagesPage1 = """
    {
      "items": [
        {"event_id": "e1", "source": "user", "message": "Fix the login bug", "created_at": 1756800000},
        {"event_id": "e2", "source": "devin", "message": "On it.", "created_at": 1756800010}
      ],
      "end_cursor": "c1",
      "has_next_page": true
    }
    """

    static let messagesPage2 = """
    {
      "items": [
        {"event_id": "e3", "source": "devin", "message": "Opened PR #42.", "created_at": 1756800500}
      ],
      "end_cursor": null,
      "has_next_page": false
    }
    """

    static let sessionTags = """
    {"tags": ["bug", "auth", "Mobile Sprint 1"], "future_field": "ignored"}
    """

    static let problem422Tags = """
    {"status": 422, "title": "Unprocessable Content", "detail": "Tag 'nope' is not in the organization's allowed tags", "type": "about:blank"}
    """

    static let selfPAT = """
    {"principal_type": "user", "user_id": "user-1", "user_name": "Taj", "org_id": "org-xyz"}
    """

    static let selfEnterprisePAT = """
    {"principal_type": "user", "user_id": "user-1", "user_name": "Taj", "org_id": null}
    """

    static let problem401 = """
    {"status": 401, "title": "Unauthorized", "detail": "Invalid API key", "type": "about:blank"}
    """

    static let membersPage1 = """
    {
      "items": [
        {"user_id": "user-1", "email": "taj@example.com", "name": "Taj Vasudeva",
         "role_assignments": [{"role": {"role_name": "Admin", "role_id": "role-admin", "role_type": "org"}, "org_id": "org-xyz"}]},
        {"user_id": "user-2", "email": "sam@example.com", "name": null,
         "role_assignments": [{"role": {"role_name": "Viewer", "role_id": "role-viewer", "role_type": "galactic"}, "org_id": null}]}
      ],
      "end_cursor": "m1",
      "has_next_page": true,
      "total": 3
    }
    """

    static let membersPage2 = """
    {
      "items": [
        {"user_id": "user-3", "email": null, "name": "  ", "role_assignments": []}
      ],
      "end_cursor": null,
      "has_next_page": false
    }
    """

    static let problem403 = """
    {"status": 403, "title": "Forbidden", "detail": "Missing permission: ViewOrgMembers", "type": "about:blank"}
    """

    static let sessionInsights = """
    {
      "session_id": "devin-abc123",
      "org_id": "org-xyz",
      "url": "https://app.devin.ai/sessions/abc123",
      "status": "exit",
      "status_detail": "finished",
      "title": "Fix login bug",
      "tags": ["bug"],
      "pull_requests": [],
      "acus_consumed": 3.25,
      "created_at": 1756800000,
      "updated_at": 1756803600,
      "num_user_messages": 4,
      "num_devin_messages": 11,
      "session_size": "m",
      "analysis": {
        "issues": [
          {"id": "issue-1", "title": "Flaky test masked the bug", "issue": "The auth test suite was already red, so Devin could not tell its fix worked.",
           "impact": "Two extra iterations (~1.2 ACU).", "label": "environment"},
          {"id": "", "title": "", "issue": "Prompt did not name the target branch.", "impact": "Devin opened the PR against develop.", "label": "prompt"}
        ],
        "timeline": [
          {"title": "Reproduced the bug", "color": "green", "description": "Ran the failing login flow locally.", "issue_id": null},
          {"title": "Blocked on flaky tests", "color": "red", "description": "Spent 20 minutes on unrelated failures.", "issue_id": "issue-1"}
        ],
        "action_items": [
          {"type": "repo_config", "action_item": "Quarantine the flaky auth tests.", "issue_id": "issue-1"},
          {"type": "prompt_improvement", "action_item": "State the base branch in the prompt.", "issue_id": null},
          {"type": "brand_new_type", "action_item": "Something this build has never heard of."}
        ],
        "suggested_prompt": {
          "original_prompt": "Fix the login bug",
          "suggested_prompt": "Fix the login bug in acme/api (base branch: main). The flaky tests in tests/auth are known and can be skipped.",
          "feedback_items": [
            {"summary": "Name the base branch", "excerpt": "Fix the login bug", "details": "Devin guessed develop.", "issue_id": null}
          ]
        },
        "note_usage": {"good_usages": [], "bad_usages": []},
        "classification": {"category": "bug_fixing", "confidence": 0.93, "tools_and_frameworks": ["pytest"], "programming_languages": ["Python"]}
      }
    }
    """

    static let sessionInsightsPending = """
    {
      "session_id": "devin-abc123",
      "org_id": "org-xyz",
      "url": "https://app.devin.ai/sessions/abc123",
      "status": "exit",
      "tags": [],
      "pull_requests": [],
      "acus_consumed": 3.25,
      "created_at": 1756800000,
      "updated_at": 1756803600,
      "num_user_messages": 4,
      "num_devin_messages": 11,
      "session_size": "xxxl",
      "analysis": null
    }
    """

    static let insightsGenerateStarted = """
    {"session_id": "devin-abc123", "status": "started"}
    """

    static let insightsGenerateAlreadyExists = """
    {"session_id": "devin-abc123", "status": "already_exists"}
    """

    static let problem403Insights = """
    {"status": 403, "title": "Forbidden", "detail": "Missing permission: ViewOrgSessions", "type": "about:blank"}
    """

    static let playbooksPage = """
    {
      "items": [
        {"playbook_id": "playbook-1", "title": "Fix CI", "body": "...", "macro": "!fixci", "access_type": "org",
         "created_at": 1, "updated_at": 1, "created_by": "u", "updated_by": "u", "org_id": "org-xyz"}
      ],
      "end_cursor": null,
      "has_next_page": false
    }
    """
}
