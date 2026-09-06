"""Build the deterministic story inventory (stories.json) for workflow.py.

Usage:
    export GH_TOKEN="$GITHUB_DEVIN_PROJECTS_TOKEN"   # never print it
    python3 build_stories.py "Sprint 6" "Sprint 7"    # milestones, in execution order

Every OPEN issue in each milestone becomes a story unless it carries an EXCLUDE label.
Stories are ordered by issue number inside a sprint; sprints keep the order given on
the command line. Review the printed table before running the workflow.
"""
import json
import os
import subprocess
import sys

REPO = "vasturnonthegas/devin-mobile"
EXCLUDE_LABELS = {"epic", "chore"}
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stories.json")


def gh_json(path):
    return json.loads(subprocess.check_output(["gh", "api", "--paginate", path], text=True))


def main(milestones):
    if not milestones:
        sys.exit("usage: build_stories.py <milestone> [<milestone> ...]")
    all_issues = gh_json(f"repos/{REPO}/issues?state=open&per_page=100")
    out = []
    for sprint in milestones:
        picked = [
            i for i in all_issues
            if "pull_request" not in i
            and i.get("milestone") and i["milestone"]["title"] == sprint
            and not ({l["name"] for l in i["labels"]} & EXCLUDE_LABELS)
        ]
        if not picked:
            sys.exit(f"no open non-epic issues in milestone {sprint!r}")
        for i in sorted(picked, key=lambda i: i["number"]):
            out.append({
                "number": i["number"],
                "sprint": sprint,
                "title": i["title"],
                "labels": sorted(l["name"] for l in i["labels"]),
                "body": (i["body"] or "").strip(),
            })
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    for s in out:
        print(f"{s['sprint']:<10} #{s['number']:<4} {s['title']}")
    print(f"{len(out)} stories -> {OUT}")


if __name__ == "__main__":
    main(sys.argv[1:])
