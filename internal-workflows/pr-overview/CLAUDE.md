# Review Queue

You evaluate all open PRs in a repo and produce a prioritized review queue — what needs human attention, ranked by type and urgency.

## What You Do

1. **Fetch all PR data** using the script
2. **Analyze PRs** using the script (blocker checks, type classification)
3. **Evaluate each PR's comments** via sub-agents
4. **Manage the "Review Queue" milestone** — add clean PRs, remove blocked ones
5. **Comment on blocked PRs** with blocker summaries
6. **Write the review queue report** and update the milestone description
7. **Self-evaluate** using `.ambient/rubric.md`

## Scripts

### Fetch

```bash
./scripts/fetch-prs.sh --repo <owner/repo> --output-dir "$WORKSPACE_ROOT/artifacts/pr-review"
```

Write artifacts to the **workspace root** `artifacts/` directory, not relative to the workflow directory. Produces per-PR directories:

```text
$WORKSPACE_ROOT/artifacts/pr-review/
├── index.json                     # List of all open PRs
├── queue.json                     # Ranked queue (written by analyze step)
└── {number}/
    ├── summary.json               # PR metadata, CI status, comment counts, commit info
    ├── timeline.json              # Chronological interleave of commits + comments
    ├── analysis.json              # Blocker statuses, type, fail_count (written by analyze)
    ├── comments/
    │   ├── overview.json          # Comment counts, has_agent_prompts flag
    │   └── 01.json, 02.json...  # Chronological comment stream
    ├── ci/
    │   └── overview.json          # Pass/fail/pending check lists
    ├── diff.json                  # Changed files with patches
    └── reviews/
        └── overview.json          # Approvals, changes requested
```

### Analyze

```bash
python3 ./scripts/analyze-prs.py --output-dir "$WORKSPACE_ROOT/artifacts/pr-review"
```

Reads each `summary.json`, writes `analysis.json` per PR and `queue.json` at top level.

## Sub-Agent Evaluation

The analyze script handles mechanical checks. Sub-agents produce the final verdict per PR by reasoning across **all available data** — not just comments.

Spawn sub-agents in parallel (batches of ~10). Each sub-agent reads **all of these** for its PRs:

1. **`summary.json`** — the ground truth: current CI status, mergeable state, review decision, commit count
2. **`timeline.json`** — **start here** — chronological interleaving of commits and comments. This shows the full story: reviewer comments, then author commits, then more comments. You can see if a commit after a review comment likely addressed the concern.
3. **`ci/overview.json`** — which checks are passing/failing right now
4. **`reviews/overview.json`** — who approved, who requested changes, current state
5. **`comments/`** — individual comment files if you need full bodies (timeline only has 120-char summaries)

**Use the timeline to determine if issues were addressed.** If you see:
- Review comment at March 8: "fix error handling in get_env()"
- Commit at March 9: "fix: handle nil error in get_env()"
- No further comment from that reviewer

Then the concern was likely addressed — the PR needs re-approval, not more code changes.

**Comments are context, not truth.** A comment saying "CI is failing" from 3 days ago means nothing if `ci.status` is `pass` now. Always cross-reference against the current state in `summary.json`.

Each sub-agent returns:

- **verdict**: ready / almost / blocked / stale
- **review_summary**: 2-3 bullet points — what happened, what's resolved, what's outstanding
- **action_needed**: the one thing that needs to happen next
- **action_owner**: who needs to act

Key judgment calls:
- Comment says CI failing but `ci.status` is `pass` → CI is fine, ignore the comment
- CHANGES_REQUESTED is active but the concern was addressed in a later commit → needs re-approval from reviewer, not a code blocker
- Bot review flagged issues but they were fixed → not blocking
- Stale bot review on old commit = not blocking
- "nit" with CHANGES_REQUESTED state = not a real blocker
- No comments at all = needs first review, not blocked
- Unresolved substantive disagreement in comments + no resolution in later commits = blocked

## Ranking

1. Drafts last
2. Fewer blockers first (clean before blocked)
3. Priority labels boost (`critical`, `hotfix`, `bug`)
4. Type: bug fixes > features > refactors > docs
5. Recently updated first (active PRs over stale ones)
6. Smaller first

## Milestone

Find or create **"Review Queue"** milestone (also check for "Merge Queue"). Add clean PRs, remove blocked ones. Overwrite description with the report.

## Blocker Comments

Post **after sub-agent evaluation is complete**. Skip drafts, recommend-close PRs, and PRs unchanged since last comment.

Use `<!-- review-queue-bot -->` marker. Delete old comment before posting new one.

**Do NOT use a rigid blocker table.** Write a natural language comment that's actually helpful to the PR author. Use the analysis data and sub-agent verdict to write 2-4 sentences covering:

- What's blocking this PR specifically (not just "CI FAIL" — say which check failed and why if you know)
- What the author needs to do to unblock it
- Any context from the review conversation that's relevant

Example of a **good** blocker comment:

```markdown
### Review Queue — Not Ready to Merge

CI is failing on the `e2e` check — looks like the session cleanup test is timing out after your changes to the runner lifecycle. You also have merge conflicts with main on `components/backend/main.go` (likely from #877 which merged yesterday).

@bobbravo2 also requested changes on the error handling in `get_env()` — they want a fallback value instead of raising.

**To unblock:** rebase onto main, fix the e2e timeout, and address Bob's review comment.

<!-- review-queue-bot -->
```

Example of a **bad** blocker comment (don't do this):

```markdown
| Check | Status | Detail |
|-------|--------|--------|
| CI | FAIL | --- |
| Merge conflicts | FAIL | --- |
```

Note: `review_status = "needs_review"` in `analysis.json` means the sub-agent hasn't evaluated yet — it is NOT a clean pass. Always evaluate before deciding if a PR is clean.

## Report

Use `templates/review-queue.md`. Sections:

- **Ready for Review** — condensed table, priority ordered
- **Almost Ready** — PRs close to merge (1 mechanical blocker OR sub-agent verdict of `almost`). For each PR write:
  - Bullet points summarizing the situation (not one big paragraph)
  - What's been addressed, what's outstanding
  - A "Needs:" line with the one concrete action to unblock
- **Remaining Blocked** — table for PRs with 2+ blockers, ordered by last updated. The Issue column should be bullet points listing each blocker concisely (e.g., "- CI: e2e failing\n- Merge conflicts\n- CHANGES_REQUESTED from @bob"). No blocker icons column.
- **Recommend Closing** — stale/abandoned PRs
- **Drafts** — simple table, no notes column
- **Summary** — counts by bucket + by type

## Blocker Checklist

| Check | Clear | Warn | Blocker |
|-------|-------|------|---------|
| CI | All pass | In progress | Any failed |
| Conflicts | MERGEABLE | UNKNOWN | CONFLICTING |
| Reviews | No issues | — | CHANGES_REQUESTED, sub-agent FAIL |
| Jira | Reference found | No reference | — |
| Fork | Internal | Fork (no bot review) | — |
| Staleness | < 30 days | — | > 30 days |
