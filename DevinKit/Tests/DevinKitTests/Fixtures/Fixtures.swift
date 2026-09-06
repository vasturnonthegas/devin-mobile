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

    static let attachmentsArray = """
    [
      {"attachment_id": "att-1", "name": "screenshot.png", "source": "user",
       "url": "https://api.devin.ai/v3/organizations/org-xyz/attachments/0f3c-uuid/screenshot.png", "content_type": "image/png"},
      {"attachment_id": "att-2", "name": "crash.log", "source": "devin",
       "url": "https://api.devin.ai/v3/organizations/org-xyz/attachments/8a1b-uuid/crash.log", "content_type": null},
      {"attachment_id": "att-3", "name": "photo.HEIC", "source": "user",
       "url": "/v3/organizations/org-xyz/attachments/77e2-uuid/photo.HEIC", "content_type": "application/octet-stream"},
      {"attachment_id": "att-4", "name": "design", "source": "user",
       "url": "https://cdn.example.com/design.bin", "content_type": "application/x-future-type; charset=binary"}
    ]
    """

    static let attachmentsPage = """
    {"items": \(attachmentsArray), "end_cursor": null, "has_next_page": false}
    """

    static let sessionTags = """
    {"tags": ["bug", "auth", "Mobile Sprint 1"], "future_field": "ignored"}
    """

    static let attachmentUploaded = """
    {
      "attachment_id": "att-7f3a9c",
      "name": "bug.png",
      "url": "https://api.devin.ai/v3/organizations/org-xyz/attachments/7f3a9c1e-2b4d-4f6a-9c8e-1d2e3f4a5b6c/bug.png",
      "content_type": "image/png",
      "scan_status": "pending_future_value"
    }
    """

    static let problem413Attachment = """
    {"status": 413, "title": "Payload Too Large", "detail": "Attachments must be 25 MB or smaller", "type": "about:blank"}
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
