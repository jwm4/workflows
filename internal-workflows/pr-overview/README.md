# Review Queue Workflow

Evaluates all open PRs (last 2 weeks) in a GitHub repository and generates a prioritized review queue — an ordered list of what needs human attention, ranked by type and urgency.

Also syncs a GitHub milestone, posts blocker comments on PRs, and investigates whether flagged review issues have been addressed by subsequent commits.

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated

## How it works

The agent works directly with `gh` CLI calls — no scripts, no intermediate files, no `jq` dependency.

1. **Fetch** — single `gh pr list` call + per-PR review/comment fetches
2. **Classify** — type (bug-fix > feature > chore > docs), blockers (CI, conflicts, reviews)
3. **Investigate stale reviews** — for reviews raised before the latest commit, check the diff to see if the issue was actually fixed
4. **Report** — tiered output: Ready to Merge > Ready for Review > Needs Work > Stale/Conflicting
5. **Milestone sync** — add clean PRs to "Review Queue" milestone, remove blocked ones
6. **PR comments** — post/update blocker summaries on blocked PRs
7. **Nudge reviewers** — for addressed feedback, tag the original reviewer to re-review

## Directory Structure

```text
pr-overview/
├── .ambient/
│   └── ambient.json    # Workflow config
├── CLAUDE.md           # Agent behavioral instructions
└── README.md
```
