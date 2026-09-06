"""Dynamic workflow: fan out one agent per story, then an integrator per sprint.

Run with the `run_workflow` tool (pass this file's path). Resume a crashed/killed run by
passing its run_id — every agent call is journaled by prompt hash, so finished stories are
replayed, not re-done. Edit only the CONFIG block; keep prompt text stable between resumes
(changing a prompt re-runs that call).
"""
import asyncio
import json

# ----------------------------------------------------------------------------- CONFIG
REPO = "vasturnonthegas/devin-mobile"
STORIES_PATH = "/Users/devin/repos/devin-mobile/.agents/skills/sprint-fanout/stories.json"
# Execution order. Must match the "sprint" values in stories.json.
SPRINT_ORDER = ["Sprint 6"]
# Stories that must be merged before the rest of their sprint starts (shared plumbing).
GATES = {}
# "shared": subagents on this macOS machine, one git worktree each (Xcode available).
# "sessions": separate-VM child sessions (only if the org exposes a macOS platform to the
#             sessions API; otherwise agents can only run `swift test`).
MODE = "shared"
MAIN_CLONE = "/Users/devin/repos/devin-mobile"
WORKTREES = "/Users/devin/worktrees"
XCODEGEN_DIR = "/Users/devin/tools/xcodegen/xcodegen/bin"
# 8 parallel xcodebuilds + a simulator each exhausted the per-user process table on a
# 12-core / 16 GB host; 3 is the safe ceiling there.
SHARED_CONCURRENCY = 3
SESSIONS_CONCURRENCY = 8
# ------------------------------------------------------------------------------------

REPO_URL = f"https://github.com/{REPO}"
with open(STORIES_PATH) as f:
    STORIES = json.load(f)

_slots = asyncio.Semaphore(SHARED_CONCURRENCY if MODE == "shared" else SESSIONS_CONCURRENCY)


def agent_kwargs():
    return {"vm_mode": "shared"} if MODE == "shared" else {"repos": [REPO]}


async def run_agent(*args, **kwargs):
    async with _slots:
        return await agent(*args, **kwargs)


def stories_for(sprint):
    return sorted((s for s in STORIES if s["sprint"] == sprint), key=lambda s: s["number"])


def sid(s):
    return s["title"].split(" · ")[0].split(":")[0].strip()


META = {
    "name": f"{REPO.split('/')[1]}-{'-'.join(sp.lower().replace(' ', '') for sp in SPRINT_ORDER)}",
    "description": f"Implement every story in {', '.join(SPRINT_ORDER)} of {REPO} as a PR, then an integrator rebases + merges each sprint's green PRs in issue order.",
    "product": "Devin Mobile (native iOS client, DevinKit + SwiftUI)",
    "soft_time_limit_minutes": 45,
    "phases": [
        {
            "title": f"implement {sp}",
            "detail": "one agent per story: branch, implement, swift test + xcodebuild, open PR",
            "labels": [f"{sid(s)} #{s['number']}" for s in stories_for(sp)],
        }
        for sp in SPRINT_ORDER
    ] + [
        {
            "title": f"integrate {sp}",
            "detail": "rebase onto main in issue order, wait for CI, merge, verify main is green",
            "count": 2 if sp in GATES else 1,
            "soft_time_limit_minutes": 60,
        }
        for sp in SPRINT_ORDER
    ],
}

IMPL_SCHEMA = {
    "type": "object",
    "properties": {
        "issue": {"type": "integer"},
        "status": {"type": "string", "enum": ["pr_opened", "blocked", "failed"]},
        "branch": {"type": "string"},
        "pr_url": {"type": "string"},
        "pr_number": {"type": "integer"},
        "summary": {"type": "string"},
        "blocker": {"type": "string", "description": "why no PR was opened (status blocked/failed); empty otherwise"},
        "touched_shared_files": {"type": "array", "items": {"type": "string"},
                                 "description": "files under DevinMobile/App or DevinKit/Sources you modified (not created)"},
    },
    "required": ["issue", "status", "branch", "pr_url", "summary", "blocker"],
}

INTEGRATE_SCHEMA = {
    "type": "object",
    "properties": {
        "merged": {"type": "array", "items": {"type": "string"}, "description": "PR URLs merged, in merge order"},
        "not_merged": {"type": "array", "items": {"type": "string"}, "description": "'<pr_url>: <reason>' for each PR left open"},
        "main_ci_green": {"type": "boolean"},
        "main_sha": {"type": "string"},
        "notes": {"type": "string"},
    },
    "required": ["merged", "not_merged", "main_ci_green", "main_sha", "notes"],
}

RULES = """\
Repo conventions (HANDOFF.md is authoritative; read it fully first):
- Layout: `DevinKit/` = platform-agnostic Swift package (API client, models, Keychain store, unit tests with MockTransport); `DevinMobile/` = SwiftUI app (iOS 17+, @Observable + @MainActor, NO third-party packages); `project.yml` = XcodeGen spec (the .xcodeproj is generated and gitignored).
- All API knowledge lives in DevinKit. Views never see JSON keys or raw status strings. Every new API call = client method + realistic fixture (with an unknown enum value) + `DevinClientTests` case asserting URL/query/headers/body. If the story touches the API, fetch https://docs.devin.ai/v3-openapi.json — the spec wins over HANDOFF.md.
- Swift 5 language mode with SWIFT_STRICT_CONCURRENCY=complete: keep types Sendable.
- Polling, not push. Credentials only in Keychain. Never log tokens; `DevinClient` builds the Authorization header in one place.
- New Swift files under `DevinMobile/` are picked up automatically by XcodeGen. Edit `project.yml` only if the story needs a new target/entitlement.
- Comments are sparse; document invariants, never the diff.
- Keep the diff scoped to the story. Prefer NEW files (new views/models/extensions) over rewriting shared ones (`SessionStore.swift`, `AppModel.swift`, `InboxView`, `SessionDetailModel`, `DevinClient.swift`); when you must touch a shared file, make the smallest additive change possible — other agents are editing sibling stories concurrently and an integrator will rebase your PR.
"""

VERIFY = """\
Verification (all required before opening the PR):
1. `cd DevinKit && swift test` must pass.
2. If you are on macOS: `xcodegen generate`, then
   `xcodebuild build -project DevinMobile.xcodeproj -scheme DevinMobile -destination 'generic/platform=iOS Simulator' -configuration Debug -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'`
   must print BUILD SUCCEEDED with ZERO `warning:` lines (CI greps for warnings).
   If the story changes UI and a simulator is available, run the app (mock/preview data — there is no PAT for the live API) and take `xcrun simctl io booted screenshot shot.png` for the PR.
   If you are NOT on macOS, say so in the PR and rely on the macOS CI job.
3. Open the PR against `main` following `.github/pull_request_template.md`: Summary with pseudo-diffs (not prose), `Closes #<issue>`, manual Simulator test steps, screenshot if any, checklist ticked honestly. Title: `<story id>: <short title>`.
4. Watch CI (`DevinKit tests (Linux)` + `iOS build (Simulator)`). Fix failures and push again. Never disable or skip tests. Do NOT merge the PR — an integrator merges it. Do not open new GitHub issues (an automation turns every new issue into a session); put follow-ups in the PR description instead.
"""


def shared_env(worktree_name, branch_expr):
    return f"""## Environment — you are a subagent sharing ONE macOS machine with a few other agents working on sibling stories
- The main clone is `{MAIN_CLONE}`. NEVER check out a branch, edit files, or run builds there. Create your own git worktree and work ONLY inside it:
  `mkdir -p {WORKTREES} && cd {MAIN_CLONE} && git fetch origin && git worktree add {WORKTREES}/{worktree_name} -b {branch_expr} origin/main && cd {WORKTREES}/{worktree_name}`
  (if `{WORKTREES}/{worktree_name}` already exists from an earlier attempt, `cd` into it, `git fetch origin`, read `git status`/`git diff`, and continue on its existing branch instead.)
- Never touch other agents' worktrees (`{WORKTREES}/*`), never run `git worktree remove/prune`, never kill processes you did not start, never run destructive git commands (`reset --hard`, `clean -fd`, `checkout -- <file>`), never `git add .` (stage files explicitly; never commit `DevinMobile.xcodeproj`, `.derived/`, `*.log`, or generated `DevinMobile/Info.plist`).
- GitHub: `gh` is installed but `gh pr create` is BLOCKED in this shell. Run `export GH_TOKEN="$GITHUB_DEVIN_PROJECTS_TOKEN"` in the same shell, then open PRs with the API:
  `gh api -X POST repos/{REPO}/pulls -f base=main -f head=<branch> -f title='<title>' -F body=@<body-file.md>` (returns `html_url`/`number`). `gh pr view/checks/close/merge`, `gh pr comment`, `gh issue comment`, `gh api` all work. `git push -u origin <branch>` works through the pre-configured remote. Never print or log the token. Screenshots cannot be uploaded from this shell; describe them in the PR body instead of attaching (say so honestly).
- Xcode and `xcodegen` (`{XCODEGEN_DIR}/xcodegen` — add that dir to PATH; do NOT `brew install`) are installed. Run `xcodegen generate` inside YOUR worktree only. Build with `-destination 'generic/platform=iOS Simulator'` (no booted device needed).
- Simulators: do NOT create, clone, or boot new simulators — each booted device costs ~300 processes and the host's process table is finite. For a manual smoke test use the already-booted `iPhone 17 Pro` (`xcrun simctl list devices | grep Booted`); if none is booted, boot `iPhone 17 Pro` once and shut it down (`xcrun simctl shutdown <udid>`) when you finish. Skip screenshots if the device is busy; the zero-warning build is what matters.
- Keep the host healthy: at most one `xcodebuild` at a time from you; wait for `swift test` to finish before starting xcodebuild. When done, leave the worktree in place (do not delete it).

"""


def impl_prompt(story):
    shared = MODE == "shared"
    slug = f"{sid(story).lower()}-<slug>"
    branch = f"devin/$(date +%s)-{slug}"
    env = shared_env(f"issue-{story['number']}", branch) if shared else ""
    branch_step = (
        f"- Follow the Environment section above to create your worktree on branch `{branch}` cut from the CURRENT origin/main."
        if shared else
        f"- `git fetch origin && git checkout -b {branch} origin/main` — always branch from the CURRENT origin/main."
    )
    return f"""You are implementing ONE user story in {REPO_URL} (a native iOS client for Devin) and opening a pull request for it. Work only on this story.

## Story
Issue #{story['number']} — {story['title']}
Labels: {', '.join(story['labels'])} · Milestone: {story['sprint']}

{story['body']}

{env}## Before you start
{branch_step}
- Check open PRs first: if one already has `Closes #{story['number']}` in its body, do not duplicate it — report status `pr_opened` with that PR's URL and stop.
- If the story cannot be completed without something only the repo owner can provide (Apple Developer credentials, App Store Connect, a live Devin PAT, a product decision the issue explicitly defers to the owner), do NOT open a PR. Leave a short comment on the issue stating exactly what is needed, and report status `blocked` with that reason. If the story has a decision part and an implementable part, implement what you can and note the open decision in the PR.

{RULES}
{VERIFY}
## Report
Structured output: issue={story['number']}, status (pr_opened | blocked | failed), branch, pr_url, pr_number, a two-line summary, blocker (empty unless blocked/failed), and touched_shared_files (existing files you modified under DevinMobile/App, DevinMobile/Features or DevinKit/Sources).
"""


def integrate_prompt(sprint, results, gate_note=""):
    prs = sorted((r for r in results if r["status"] == "pr_opened" and r.get("pr_url")), key=lambda r: r["issue"])
    table = json.dumps(
        [{"issue": r["issue"], "pr_url": r["pr_url"], "branch": r["branch"],
          "touched_shared_files": sorted(r.get("touched_shared_files") or [])} for r in prs],
        indent=1, sort_keys=True)
    skipped = [f"#{r['issue']}: {r['status']} — {r['blocker']}" for r in results if r["status"] != "pr_opened"]
    env = ""
    if MODE == "shared":
        wt = f"integrate-{sprint.lower().replace(' ', '-')}"
        env = shared_env(wt, f"integrate/{wt}-$(date +%s)") + (
            "Integrator specifics: each PR branch is still checked out in its author's worktree, so git will refuse `git checkout <pr-branch>` in yours. "
            "Work detached instead: `git fetch origin && git checkout --detach origin/<pr-branch>`, rebase/fix there, verify, then "
            "`git push --force-with-lease origin HEAD:<pr-branch>`. Never operate inside another agent's worktree. "
            "Some PRs in the table may ALREADY be merged (by an earlier integrator run): `gh pr view <n> --json state,mergedAt` first; if merged, skip it and list it in `merged`. "
            "If a story's PR was closed as superseded, land the surviving PR for that issue instead.\n\n")
    return f"""You are the integrator for {sprint} of {REPO_URL}. Several agents each opened one PR against `main` from a branch cut off main at roughly the same time; your job is to land them all cleanly, in issue order, and leave `main` green.{gate_note}

{env}## PRs to land (merge in this order)
{table}

Stories with no PR (nothing to do for these, just mention them in notes):
{json.dumps(skipped, indent=1) if skipped else "none"}

## Procedure — repeat for each PR in order
1. `git fetch origin`. Check the PR's mergeability against the current `main` (`gh pr view <n> --json mergeable,mergeStateStatus` if gh works, otherwise `git merge-base --is-ancestor origin/main <branch>` / a trial `git merge --no-commit`).
2. If it is behind main or conflicting: rebase it onto origin/main. Resolve conflicts so BOTH stories' behaviour survives (read both diffs; never drop the other story's code). Re-run `cd DevinKit && swift test`, then on macOS `xcodegen generate` and the xcodebuild command from CI (`.github/workflows/ci.yml`) — zero `warning:`/`error:` lines. Push with `git push --force-with-lease`.
3. Wait for the PR's CI (`DevinKit tests (Linux)` and `iOS build (Simulator)`) to be green on the CURRENT head. If it fails, fix it on the branch (do not skip or delete tests), push, and wait again. Give up on a PR only after 3 fix attempts — leave it open with a comment explaining why and continue with the next one.
4. Merge with a merge commit (the repo's existing convention — `gh pr merge <n> --merge` or the GitHub API `PUT /repos/{REPO}/pulls/<n>/merge` with `merge_method=merge`, authenticated with the `GITHUB_DEVIN_PROJECTS_TOKEN` env var if the CLI is not signed in). Never force-push `main`.
5. After the merge, wait for the CI run on `main` for the new merge commit. If it is red, fix `main` via a small follow-up PR (branch `devin/<ts>-fix-main-<issue>`), wait for green, merge it, and only then continue.

## Finish
- Confirm the final `main` CI run is green and record its SHA.
- Every merged PR should have auto-closed its issue via `Closes #N`; if one did not, close the issue with a comment linking the PR.
- Structured output: merged (PR URLs in merge order), not_merged ('<pr_url>: <reason>'), main_ci_green, main_sha, notes (conflicts you resolved, anything the owner should double-check on a device).
"""


async def implement(story):
    label = f"{sid(story)} #{story['number']}"
    try:
        r = await run_agent(impl_prompt(story), phase=f"implement {story['sprint']}", schema=IMPL_SCHEMA,
                            label=label, **agent_kwargs())
    except WorkflowAgentError as e:
        log(f"{label}: agent failed — {e}")
        r = {"issue": story["number"], "status": "failed", "branch": "", "pr_url": "",
             "summary": "", "blocker": f"agent error: {e}", "touched_shared_files": []}
    log(f"{label}: {r['status']} {r.get('pr_url') or r.get('blocker')}")
    return r


async def integrate(sprint, results, label_suffix="", gate_note=""):
    prs = [r for r in results if r["status"] == "pr_opened" and r.get("pr_url")]
    if not prs:
        log(f"integrate {sprint}{label_suffix}: no PRs to merge")
        return {"merged": [], "not_merged": [], "main_ci_green": True, "main_sha": "", "notes": "no PRs"}
    try:
        r = await run_agent(integrate_prompt(sprint, results, gate_note), phase=f"integrate {sprint}",
                            schema=INTEGRATE_SCHEMA, label=f"integrate {sprint}{label_suffix}", **agent_kwargs())
    except WorkflowAgentError as e:
        log(f"integrate {sprint}{label_suffix}: agent failed — {e}")
        r = {"merged": [], "not_merged": [f"{p['pr_url']}: integrator failed ({e})" for p in prs],
             "main_ci_green": False, "main_sha": "", "notes": f"integrator agent error: {e}"}
    log(f"integrate {sprint}{label_suffix}: merged {len(r['merged'])}, left open {len(r['not_merged'])}, main green={r['main_ci_green']}")
    return r


async def run_sprint(sprint):
    stories = stories_for(sprint)
    gate_nums = GATES.get(sprint, [])
    gate = [s for s in stories if s["number"] in gate_nums]
    rest = [s for s in stories if s["number"] not in gate_nums]
    impl_results, integ_results = [], []

    if gate:
        log(f"{sprint}: gate stories {[s['number'] for s in gate]} first")
        gate_res = await pipeline(gate, implement)
        impl_results += gate_res
        integ_results.append(await integrate(sprint, gate_res, label_suffix=" (gate)",
                                             gate_note=" These are prerequisite stories; the rest of the sprint starts only after they are on main."))

    log(f"{sprint}: implementing {len(rest)} stories in parallel")
    res = await pipeline(rest, implement)
    impl_results += res
    integ_results.append(await integrate(sprint, res))
    return {"sprint": sprint, "implement": impl_results, "integrate": integ_results}


async def main():
    await register_workflow(META)
    report = []
    for sprint in SPRINT_ORDER:
        log(f"===== {sprint} =====")
        report.append(await run_sprint(sprint))

    log("===== SUMMARY =====")
    for r in report:
        merged = sum(len(i["merged"]) for i in r["integrate"])
        open_ = [x for i in r["integrate"] for x in i["not_merged"]]
        blocked = [f"#{x['issue']} ({x['status']}): {x['blocker']}" for x in r["implement"] if x["status"] != "pr_opened"]
        log(f"{r['sprint']}: {merged} merged; {len(open_)} PRs left open; {len(blocked)} stories without PR")
        for x in open_:
            log(f"  open: {x}")
        for x in blocked:
            log(f"  no PR: {x}")
    print(json.dumps(report, indent=1, sort_keys=True))


asyncio.run(main())
