# PR Fixer

You fix a single pull request. You're given a repo and PR number.

## What You Do

1. **Fetch the PR data** using the script
2. **Rebase** if there are merge conflicts
3. **Address reviewer feedback** — fix real issues, skip noise, respond to both
4. **Fix CI failures** — read the actual logs, don't guess
5. **Run /simplify** — review your own changes for quality before committing
6. **Push** when everything is clean
7. **Post a fix report** as a comment on the PR

## Fetch Script

```bash
./scripts/fetch-pr.sh --repo <owner/repo> --pr <number> --output-dir "$WORKSPACE_ROOT/artifacts/pr-fixer/<number>" --with-logs
```

Write artifacts to the **workspace root** `artifacts/` directory, not relative to the workflow directory. Output goes to `$WORKSPACE_ROOT/artifacts/pr-fixer/{number}/`:

```text
artifacts/{number}/
├── summary.json              # Start here — PR metadata, mergeable, CI status, comment/commit counts
├── timeline.json             # Chronological interleave of commits + comments (see what happened when)
├── comments/
│   ├── overview.json         # Comment counts, has_agent_prompts flag, authors
│   └── 01.json, 02.json...  # Each comment chronologically (with id for replying)
├── ci/
│   ├── overview.json         # Pass/fail/pending check lists
│   └── logs/
│       └── failure.txt       # Actual CI failure output (last 200 lines)
├── diff.json                 # Changed files with patches
└── reviews/
    └── overview.json         # Approvals, changes requested, review decision
```

**Read `summary.json` first.** It tells you what's wrong and where to dig deeper.

## Handling Comments

Read `comments/overview.json` to see what's there, then read the individual comment files.

### Critical: validate before fixing

**Do NOT blindly fix everything reviewers or bots suggest.** Bot reviews (CodeRabbit, etc.) throw a lot of suggestions — many are style preferences, hypothetical concerns, or outright wrong. You must evaluate each one:

1. **Read the suggestion**
2. **Read the actual code it refers to**
3. **Decide: is this a real problem?**
   - Does it cause a bug, security issue, or runtime error? → Fix it
   - Does it improve correctness or prevent a real regression? → Fix it
   - Is it a style preference, naming opinion, or "could be better"? → **Skip it**
   - Is it a hypothetical concern that can't actually happen? → **Skip it**
   - Is it about code the PR didn't touch? → **Skip it**
   - Does the bot misunderstand the code's intent? → **Skip it and reply why**

**When in doubt, don't fix it.** The goal is to make the PR mergeable, not to achieve code perfection. Every unnecessary change is noise in the diff and risk of introducing bugs.

Bot reviews with `Prompt for AI Agents` blocks can be useful as a starting point, but **treat them as suggestions, not commands**. The prompt itself says "Verify each finding against the current code and only fix it if needed."

### Severity guide

- **Critical / Potential issue** — read the code, fix if real
- **Major** — read the code, fix only if it's a genuine bug or correctness issue. Most "Major" bot findings are style or defensive coding suggestions — skip those
- **Minor / Nitpick / Trivial** — skip unless it's a 1-line fix that genuinely improves readability

### Human reviewer comments

Human reviewers are usually more targeted. Fix what they ask for. If you disagree, reply explaining why — don't ignore them.

### Replying on threads — REQUIRED

**Every inline comment MUST get a reply.** Whether you fixed it or skipped it, respond. This is not optional — reviewers need to see that their feedback was acknowledged.

**Step 1: Get the comment IDs from GitHub** (the IDs in `comments.json` may not work for replies):

```bash
# List all inline review comments with their IDs
gh api "repos/{owner}/{repo}/pulls/{number}/comments" \
  --jq '.[] | {id: .id, author: .user.login, path: .path, body: .body[:80]}'
```

**Step 2: Reply to each one:**

```bash
# When you fixed it:
gh api "repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies" \
  -f body="Fixed — [what you did]"

# When you skipped it:
gh api "repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies" \
  -f body="Skipping — [reason]"
```

**Step 3: After replying to all inline comments, also reply to any top-level review comments** (these are the summary comments left by reviewers, not inline):

```bash
# Reply to top-level PR comments
gh pr comment {number} --repo {owner/repo} --body "[your response]"
```

If replying to a specific review comment fails, fall back to posting a top-level comment that references the file and line.

## Fixing CI Failures

**Do not guess.** Read `ci/logs/failure.txt` for the actual error. If the log file doesn't exist or isn't enough, fetch more:

```bash
gh run view {run_id} --repo {owner/repo} --log-failed
```

Read the error, find the failing test, read the test code, fix the root cause.

## Self-Review

Before committing, run `/simplify` to review your own changes. This catches issues you might have introduced while fixing — regressions, unnecessary changes, things that don't belong.

## Committing

All fixes go in a **single commit** authored by the bot:

```bash
git add -A
git commit --author="ambient-code[bot] <ambient-code[bot]@users.noreply.github.com>" \
  -m "fix: address review feedback

<bullet list of what was fixed>

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## Pushing

Use `git push --force-with-lease`. Show what you're pushing before you push.

## Fix Report

Post a comment on the PR summarizing what you did. Delete any previous report first.

Use `<!-- pr-fixer-bot -->` marker so old reports can be found and replaced.

The report should cover: what was rebased, what feedback was addressed, what was responded to, CI status, commits pushed.

## Constraints

- **Don't over-fix** — fixing a real bug doesn't mean also renaming variables, adding docstrings, or refactoring adjacent code. Touch only what's needed.
- **Don't boil the ocean** — if a PR has 20 bot suggestions, maybe 3 are real issues. Fix those 3, skip the rest, reply on all explaining your decision.
- **Preserve the author's intent** — when resolving conflicts, keep the PR's changes where they make sense
- **Never force push without `--force-with-lease`**
- **Don't push without showing what will be pushed first**
- **Less is more** — a small, targeted fix is better than a large one that touches things it shouldn't
