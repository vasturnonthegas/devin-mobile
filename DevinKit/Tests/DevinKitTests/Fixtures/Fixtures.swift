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
          "updated_at": 1756800200
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
          "devin_mode": "brand_new_mode"
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

    static let selfPAT = """
    {"principal_type": "user", "user_id": "user-1", "user_name": "Taj", "org_id": "org-xyz"}
    """

    static let selfEnterprisePAT = """
    {"principal_type": "user", "user_id": "user-1", "user_name": "Taj", "org_id": null}
    """

    static let problem401 = """
    {"status": 401, "title": "Unauthorized", "detail": "Invalid API key", "type": "about:blank"}
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
