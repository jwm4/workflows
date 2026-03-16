# Review Queue — Agent Instructions

You evaluate open pull requests and produce a prioritized review queue. You work directly with the `gh` CLI — no scripts, no intermediate files.

## Input

The user provides the repo (e.g. `ambient-code/platform`). If not provided, ask for it. Use it as `REPO` in all commands below.

## Workflow

### Step 1: Fetch all open PRs active in the last 2 weeks

Single `gh pr list` call. Filter to PRs with `updatedAt` within the last 14 days using inline Python.

```bash
gh pr list --repo $REPO --state open --limit 100 \
  --json number,title,author,updatedAt,createdAt,headRefName,mergeable,statusCheckRollup,reviewDecision,labels,isDraft,additions,deletions,changedFiles,url,isCrossRepository,headRepositoryOwner
```

From the JSON, extract per-PR:
- **CI status**: scan `statusCheckRollup` for any check with conclusion `FAILURE`, `TIMED_OUT`, `CANCELLED`, or `ACTION_REQUIRED`
- **Mergeable**: `MERGEABLE`, `CONFLICTING`, or `UNKNOWN`
- **Review decision**: `APPROVED`, `CHANGES_REQUESTED`, or `REVIEW_REQUIRED`
- **Type**: classify from title prefix and branch name (see classification table below)

### Step 2: Get reviews and comments for actionable PRs

**Prioritize which PRs to deep-dive on.** Skip drafts and obviously stale/conflicting PRs unless they have `CHANGES_REQUESTED`. Focus on PRs that could realistically be merged or unblocked.

For each actionable PR, batch these into a single loop:

```bash
for pr in $PR_NUMBERS; do
  echo "=== PR #$pr ==="
  # Last commit date
  gh pr view $pr --repo $REPO --json commits --jq '.commits[-1].committedDate'
  # Formal reviews (approvals, changes requested)
  gh api repos/$REPO/pulls/$pr/reviews --jq '.[] | select(.state != "COMMENTED" and .state != "DISMISSED") | "\(.user.login): \(.state) @ \(.submitted_at)"'
  # Recent inline comments — last 5, newest first
  gh api "repos/$REPO/pulls/$pr/comments?per_page=5&sort=created&direction=desc" --jq '.[] | "\(.user.login) @ \(.created_at): \(.body[0:200])"'
  # Recent issue comments — last 3, newest first
  gh api "repos/$REPO/issues/$pr/comments?per_page=3&sort=created&direction=desc" --jq '.[] | "\(.user.login) @ \(.created_at): \(.body[0:200])"'
done
```

### Step 3: Classify and triage

**Type classification** (from title prefix, branch name, or labels):

| Type | Signals | Priority |
|------|---------|----------|
| `bug-fix` | `fix:`, `fix(`, `fix/`, `bug/`, `hotfix/` | Highest |
| `feature` | `feat:`, `feat(`, `feat/`, `feature/` | High |
| `refactor` | `refactor:`, `refactor/` | Medium |
| `chore` | `chore:`, `ci:`, `build:`, dependabot, `[Amber]`, bot authors | Medium |
| `docs` | `docs:`, `docs/`, markdown-only | Lower |

**Blocker evaluation** — for each PR, mark each check as `pass`, `FAIL`, or `warn`:

| Check | FAIL when | warn when |
|-------|-----------|-----------|
| CI | Any check with `FAILURE`/`TIMED_OUT`/`CANCELLED` | Checks still in progress |
| Conflicts | `mergeable == CONFLICTING` | `mergeable == UNKNOWN` |
| Reviews | `CHANGES_REQUESTED` without subsequent `APPROVED`/`DISMISSED` | — |
| Jira | — | No `RHOAIENG-\d+` in title, body, or branch (informational only) |

**Staleness check**: Compare last commit date against review/comment dates:
- Review raised **BEFORE** latest commit → flag as "may be addressed — investigate"
- Review raised **AFTER** latest commit → flag as "likely still unaddressed"

### Step 4: Investigate potentially stale reviews

Only for **substantive** issues — Major/Critical from CodeRabbit, or `CHANGES_REQUESTED` from humans. Skip trivial nitpicks.

For each flagged review:
1. Read the review comment body to understand the specific concern
2. Identify which file(s) the concern is about
3. Fetch the relevant file diff:
   ```bash
   gh api repos/$REPO/pulls/{number}/files --jq '.[] | select(.filename == "the/file.go") | .patch'
   ```
4. Read the patch to determine if the concern was addressed
5. Record verdict: "resolved by commit on {date}" or "still unaddressed despite {date} commit"

### Step 5: Produce the report

The report is optimized for a developer asking "what should I look at next?" Group PRs by the action the reader should take, not by PR status. Use the tiered format below exactly.

Within each tier, sort by: bug-fix > feature > chore > docs, then smallest first.

---

#### Output format

Every tier uses the same core columns so the report is scannable at a glance:

| Column | Contents |
|--------|----------|
| **#** | PR number |
| **Title** | PR title (truncated to ~50 chars if needed) |
| **Author** | GitHub login |
| **Last Active** | Date of most recent update (e.g. `Mar 16`) |
| **Mergeable** | `✅` or `❌ Conflicts` |
| **CI** | `✅ All pass` or `❌ {failing check names}` |
| **Review Issues** | Human and CodeRabbit findings — severity, whether addressed or stale, reviewer names. `✅ Approved (name)` if approved. `Awaiting review` if no reviews yet. |

The **Review Issues** column is the most important — it tells the reader whether they need to act. Include:
- Approval status and who approved
- CodeRabbit findings with severity (Critical/Major/Minor) and whether addressed by a later commit or still unaddressed
- Human review status (CHANGES_REQUESTED from whom, whether subsequently addressed)
- "Awaiting review" if no reviews exist yet

```
## Active PRs (Last 2 Weeks) — {REPO}

### Review & Merge Now

These PRs are approved, CI green, no conflicts — just need someone to click merge.

| # | Title | Author | Last Active | Mergeable | CI | Review Issues |
|---|-------|--------|-------------|-----------|-----|---------------|
| ... |

### Review Next

These PRs are CI green, no conflicts, no blocking issues — they need your review.
Sorted by priority: bug fixes first, smallest PRs first.

| # | Title | Author | Last Active | Mergeable | CI | Review Issues |
|---|-------|--------|-------------|-----------|-----|---------------|
| ... |

### Needs Author Work

These PRs have blockers the author needs to fix. Don't review until resolved.

| # | Title | Author | Last Active | Mergeable | CI | Review Issues | Action Needed |
|---|-------|--------|-------------|-----------|-----|---------------|---------------|
| ... |

Action Needed column: specific next step for the author.

### Stale / Conflicting

PRs with merge conflicts, no recent activity, or multiple blockers.

| # | Title | Author | Last Active | Mergeable | CI | Review Issues |
|---|-------|--------|-------------|-----------|-----|---------------|
| ... |

### Dependabot / Automated

| # | Title | Mergeable | CI | Review Issues |
|---|-------|-----------|-----|---------------|
| ... |

---

## Critical Issues

Numbered list of the most important findings across all PRs.
Focus on: production-risk items, security concerns, and patterns (e.g. "N PRs have conflicts").
```

---

Use this exact tier structure. Do NOT split into sub-tiers like "Tier 1 / Tier 2" by recency — group by **action type** instead. Recency is shown in the Last Active column.

The same report format is used for both the terminal output (shown to the user) and the milestone description (Step 6).

### Step 6: Update the GitHub milestone

Manage a **"Review Queue"** milestone as a living bucket of ready PRs.

```bash
# Find or create milestone
MILESTONE_NUM=$(gh api "repos/$REPO/milestones" --jq '.[] | select(.title=="Review Queue") | .number')
if [ -z "$MILESTONE_NUM" ]; then
  MILESTONE_NUM=$(gh api "repos/$REPO/milestones" -f title="Review Queue" -f state=open \
    -f description="Auto-managed by Review Queue workflow" --jq '.number')
fi
```

**Sync PRs:**
- First, list PRs currently in the milestone: `gh api "repos/$REPO/issues?milestone=$MILESTONE_NUM&state=all&per_page=100"`
- **Remove** closed/merged PRs, PRs with conflicts, PRs with CI failures, PRs with `CHANGES_REQUESTED`: `gh api -X PATCH "repos/$REPO/issues/{number}" -F milestone=null`
- **Add** open PRs with 0 blockers (CI green, no conflicts, no unresolved reviews, not draft): `gh api -X PATCH "repos/$REPO/issues/{number}" -F milestone=$MILESTONE_NUM`

**Update milestone description** with the full report from Step 5. Include a `Last updated` timestamp at the top.

If any API call fails, log the error and continue — milestone sync is best-effort.

### Step 7: Comment on blocked PRs

Post or update a blocker summary on each PR with `FAIL` blockers. Use `<!-- review-queue-bot -->` as a hidden marker to find/replace previous comments.

**Rules:**
- Find existing comment containing the marker
- If the PR was NOT updated since the last bot comment, skip
- If the PR WAS updated, delete the old comment and post a new one
- Never comment on draft PRs or clean PRs
- On any API error, skip and move on

**Comment format:**
```markdown
## Review Queue Status

| Check | Status | Detail |
|-------|--------|--------|
| CI | FAIL | `build` failed |
| Conflicts | pass | --- |
| Reviews | FAIL | Changes requested by @reviewer |

**Action needed:** {specific action from triage}

> Auto-generated by Review Queue workflow. Updated when PR changes.

<!-- review-queue-bot -->
```

### Step 8: Notify on resolved review feedback

For PRs where Step 4 confirmed that a **human** reviewer's `CHANGES_REQUESTED` feedback was addressed by a subsequent commit:

```markdown
@{reviewer} — the review queue analysis indicates your feedback from {date} may have been addressed in the {date} commit. Could you re-review?

<!-- review-queue-bot -->
```

For CodeRabbit issues confirmed resolved, note it in the Step 7 blocker comment (e.g. "CodeRabbit X issue resolved by Mar 15 commit") — no separate comment needed.

**Never** dismiss reviews or approve PRs. Only leave informational comments.

## Important constraints

- **Read-only for approvals/merges** — never approve, merge, or dismiss reviews
- **2-week window** — only evaluate PRs updated in the last 14 days
- **No scripts or intermediate files** — work directly with `gh` CLI and inline processing
- **Prioritize depth over breadth** — deep-dive on PRs that are close to mergeable; skip conflicting/draft PRs for review investigation
- **Parallel where possible** — batch independent `gh` calls
- **Best-effort side effects** — if milestone or comment API calls fail, log and continue; the report is the primary output
- **Stop early** — once you have enough context for a PR verdict, move on
