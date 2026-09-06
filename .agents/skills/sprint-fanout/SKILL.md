---
name: sprint-fanout
description: Turn every open story in one or more GitHub milestones of devin-mobile into merged PRs with a team of agents — one implementer per story, one integrator per sprint that rebases, waits for CI and merges in issue order. Use when asked to "do Sprint N", "fan out on the backlog", or land many issues at once.
---

# Sprint fan-out (stories → PRs → merged `main`)

Proven on Sprints 1–5 (issues #15–#48 → PRs #56–#90, all merged, `main` green).

## When to use
- Several open issues in a milestone, each independently implementable.
- The user wants PRs opened *and* landed (auto-merge once CI is green).
- One-off issues are NOT this skill: the `devin-mobile: new issue → PR` automation already
  starts a session per newly opened non-epic issue.

## Prerequisites (this macOS machine)
- `xcodegen` at `/Users/devin/tools/xcodegen/xcodegen/bin/xcodegen`, Xcode with an iOS Simulator runtime.
- `python3` ≥ 3.10 on PATH (the workflow runtime needs `X | None` annotations).
- `GITHUB_DEVIN_PROJECTS_TOKEN` in the environment (read by `gh` as `GH_TOKEN`; never print it).
- Main clone at `/Users/devin/repos/devin-mobile` on `main`, clean.

## Procedure
1. Invoke the built-in `dynamic-workflows` skill (required before `run_workflow`).
2. Build the inventory and review it with the user:
   ```sh
   cd /Users/devin/repos/devin-mobile/.agents/skills/sprint-fanout
   export GH_TOKEN="$GITHUB_DEVIN_PROJECTS_TOKEN"
   python3 build_stories.py "Sprint 6" "Sprint 7"
   ```
   It picks every open issue in each milestone minus `epic`/`chore` labels and writes
   `stories.json`. Drop stories that need owner-only inputs (PATs, App Store account,
   product decisions) — they only produce `blocked` results.
3. Copy `workflow.py` somewhere outside the repo (e.g. `~/workflows/<run>/`), set the CONFIG
   block: `SPRINT_ORDER`, `STORIES_PATH`, `GATES` (stories that must land before their sprint
   continues, e.g. shared plumbing), `MODE`.
   - `MODE = "shared"` (default): subagents on this box, each in its own git worktree under
     `/Users/devin/worktrees/issue-<n>`. Required when the org's sessions API has no macOS
     platform (child sessions could only run `swift test`).
   - `MODE = "sessions"`: separate-VM child sessions with `repos=[REPO]`; only if macOS is
     available to `devin_session_create`.
4. `run_workflow` with the file path. Keep the `run_id`; on interruption (quota, kill) resume
   with the same `run_id` — completed calls replay from the journal.
5. Verify authoritatively when it finishes (the tool output is truncated):
   ```sh
   gh pr list -R vasturnonthegas/devin-mobile --state all --limit 60 --json number,state,title
   gh run list -R vasturnonthegas/devin-mobile --branch main --limit 3
   gh issue list -R vasturnonthegas/devin-mobile --state open
   ```
   Exactly one merged PR per story, no unexpected open PRs, latest `main` CI green.
6. Report per-sprint merged/open/blocked counts with links; list `blocked` stories with
   their reasons instead of opening follow-up issues.

## Lessons baked into the prompts (don't remove)
- **Concurrency 3** in shared mode. 8 parallel `xcodebuild`s + a booted simulator each hit
  `kern.maxprocperuid` → "Resource temporarily unavailable (os error 35)", dead shells.
- Build with `-destination 'generic/platform=iOS Simulator'`; never boot extra simulators.
- Subagent shells block `gh pr create`; PRs are opened with `gh api -X POST repos/…/pulls`.
- Integrators work `--detach` on `origin/<branch>` (the branch is checked out in the author's
  worktree), push with `--force-with-lease`, merge with a merge commit, wait for `main` CI
  after every merge, and skip PRs an earlier (interrupted) integrator already merged.
- Story agents never merge and never open issues (the issue automation would fan out again).
- CI fails on any `warning:` line — prompts require a zero-warning build before the PR.

## Resuming after a crash
- Worktrees survive; a re-run agent is told to `cd` into an existing worktree and continue.
- A story that got a PR but whose call was lost re-runs cheaply: the prompt tells it to look
  for an open PR with `Closes #N` first and just report it.
- If you must change a prompt for a retry, only the changed calls re-run; leave the rest
  byte-identical so they replay.
