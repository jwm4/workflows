#!/usr/bin/env python3
"""
Structure raw PR API data into a clean directory layout.

Takes raw JSON files from GitHub API and produces:
  {output-dir}/summary.json
  {output-dir}/comments/overview.json + 01.json, 02.json, ...
  {output-dir}/ci/overview.json
  {output-dir}/diff.json
  {output-dir}/reviews/overview.json

Usage:
    python3 structure-pr-data.py \
        --pr-json raw/pr.json \
        --reviews-json raw/reviews.json \
        --review-comments-json raw/review_comments.json \
        --check-runs-json raw/check_runs.json \
        --diff-json raw/diff_files.json \
        --output-dir artifacts/123
"""

import argparse
import json
import os
import sys


def build_comments(pr_comments, reviews, review_comments):
    """Merge all comment sources chronologically, filter empty bodies."""
    all_comments = []

    for c in pr_comments:
        all_comments.append({
            "source": "pr_comment",
            "id": c.get("id", ""),
            "author": c.get("author", {}).get("login", ""),
            "timestamp": c.get("createdAt", ""),
            "body": c.get("body", ""),
        })

    for r in reviews:
        body = r.get("body", "")
        if not body or not body.strip():
            continue
        all_comments.append({
            "source": "review",
            "id": r.get("id", ""),
            "author": r.get("user", {}).get("login", ""),
            "state": r.get("state", ""),
            "timestamp": r.get("submitted_at", ""),
            "body": body,
        })

    for rc in review_comments:
        body = rc.get("body", "")
        if not body or not body.strip():
            continue
        all_comments.append({
            "source": "inline_comment",
            "id": rc.get("id", ""),
            "author": rc.get("user", {}).get("login", ""),
            "path": rc.get("path", ""),
            "line": rc.get("line"),
            "timestamp": rc.get("created_at", ""),
            "body": body,
        })

    all_comments.sort(key=lambda c: c.get("timestamp", ""))
    return all_comments


def build_ci(check_runs):
    """Categorize check runs into passing/failing/pending."""
    passing, failing, pending = [], [], []
    for cr in check_runs:
        name = cr.get("name", "unknown")
        status = cr.get("status", "")
        conclusion = cr.get("conclusion", "")
        if status != "completed":
            pending.append({"name": name, "status": status})
        elif conclusion in ("failure", "timed_out", "cancelled", "action_required"):
            failing.append({
                "name": name,
                "conclusion": conclusion,
                "run_id": cr.get("id", ""),
                "html_url": cr.get("html_url", ""),
            })
        else:
            passing.append(name)
    return passing, failing, pending


def build_reviews(reviews, review_decision):
    """Extract review state per user."""
    user_states = {}
    for r in reviews:
        login = r.get("user", {}).get("login", "")
        state = r.get("state", "")
        if login:
            user_states[login] = state

    approvals = [{"user": u, "state": s} for u, s in user_states.items() if s == "APPROVED"]
    changes_requested = [{"user": u, "state": s} for u, s in user_states.items() if s == "CHANGES_REQUESTED"]

    return {
        "decision": review_decision,
        "approvals": approvals,
        "changes_requested": changes_requested,
        "total_reviews": len(reviews),
    }


def main():
    parser = argparse.ArgumentParser(description="Structure raw PR data")
    parser.add_argument("--pr-json", required=True)
    parser.add_argument("--reviews-json", required=True)
    parser.add_argument("--review-comments-json", required=True)
    parser.add_argument("--check-runs-json", required=True)
    parser.add_argument("--diff-json", required=True)
    parser.add_argument("--commits-json", default=None)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    out = args.output_dir
    os.makedirs(f"{out}/comments", exist_ok=True)
    os.makedirs(f"{out}/ci", exist_ok=True)
    os.makedirs(f"{out}/reviews", exist_ok=True)

    with open(args.pr_json) as f:
        pr = json.load(f)
    with open(args.reviews_json) as f:
        reviews = json.load(f)
    with open(args.review_comments_json) as f:
        review_comments = json.load(f)
    with open(args.check_runs_json) as f:
        check_runs = json.load(f)
    with open(args.diff_json) as f:
        diff_files = json.load(f)

    # -- Comments --
    all_comments = build_comments(pr.get("comments", []), reviews, review_comments)
    inline_threads = [c for c in all_comments if c["source"] == "inline_comment"]
    has_agent_prompts = any("Prompt for AI Agents" in c.get("body", "") for c in all_comments)

    comments_overview = {
        "total": len(all_comments),
        "by_source": {
            "review": sum(1 for c in all_comments if c["source"] == "review"),
            "inline_comment": len(inline_threads),
            "pr_comment": sum(1 for c in all_comments if c["source"] == "pr_comment"),
        },
        "has_agent_prompts": has_agent_prompts,
        "latest_activity": all_comments[-1]["timestamp"] if all_comments else "",
        "authors": sorted(set(c["author"] for c in all_comments if c["author"])),
    }
    with open(f"{out}/comments/overview.json", "w") as f:
        json.dump(comments_overview, f, indent=2, ensure_ascii=False)
    for i, c in enumerate(all_comments, 1):
        with open(f"{out}/comments/{i:02d}.json", "w") as f:
            json.dump(c, f, indent=2, ensure_ascii=False)

    # -- CI --
    passing, failing, pending = build_ci(check_runs)
    ci_overview = {"total": len(check_runs), "passing": passing, "failing": failing, "pending": pending}
    with open(f"{out}/ci/overview.json", "w") as f:
        json.dump(ci_overview, f, indent=2, ensure_ascii=False)

    ci_status = "pass"
    if failing:
        ci_status = "failing"
    elif pending:
        ci_status = "pending"

    # -- Diff --
    diff_data = {
        "total_files": len(diff_files),
        "additions": sum(df.get("additions", 0) for df in diff_files),
        "deletions": sum(df.get("deletions", 0) for df in diff_files),
        "files": diff_files,
    }
    with open(f"{out}/diff.json", "w") as f:
        json.dump(diff_data, f, indent=2, ensure_ascii=False)

    # -- Reviews --
    reviews_overview = build_reviews(reviews, pr.get("reviewDecision", ""))
    with open(f"{out}/reviews/overview.json", "w") as f:
        json.dump(reviews_overview, f, indent=2, ensure_ascii=False)

    # -- Commits + Timeline --
    commits_list = []
    if args.commits_json:
        try:
            with open(args.commits_json) as f:
                raw_commits = json.load(f)
            for c in raw_commits:
                commit = c.get("commit", {})
                commits_list.append({
                    "sha": c.get("sha", "")[:7],
                    "message": commit.get("message", "").split("\n")[0],
                    "author": commit.get("author", {}).get("name", ""),
                    "timestamp": commit.get("author", {}).get("date", ""),
                })
        except (FileNotFoundError, json.JSONDecodeError):
            pass

    # Build timeline: interleave commits and comments chronologically
    timeline = []
    for c in all_comments:
        timeline.append({
            "type": "comment",
            "timestamp": c.get("timestamp", ""),
            "author": c.get("author", ""),
            "summary": c.get("body", "")[:120],
            "source": c.get("source", ""),
        })
    for c in commits_list:
        timeline.append({
            "type": "commit",
            "timestamp": c["timestamp"],
            "author": c["author"],
            "summary": c["message"][:120],
            "sha": c["sha"],
        })
    timeline.sort(key=lambda x: x.get("timestamp", ""))

    with open(f"{out}/timeline.json", "w") as f:
        json.dump(timeline, f, indent=2, ensure_ascii=False)

    # -- Summary (written last, includes rollups) --
    author = (pr.get("author") or {}).get("login", "unknown")
    summary = {
        "number": pr.get("number"),
        "title": pr.get("title", ""),
        "author": author,
        "url": pr.get("url", ""),
        "branch": pr.get("headRefName", ""),
        "base": pr.get("baseRefName", "main"),
        "isDraft": pr.get("isDraft", False),
        "isFork": pr.get("isCrossRepository", False),
        "forkOwner": (pr.get("headRepositoryOwner") or {}).get("login", ""),
        "mergeable": pr.get("mergeable", "UNKNOWN"),
        "headSha": pr.get("headRefOid", ""),
        "createdAt": pr.get("createdAt", ""),
        "updatedAt": pr.get("updatedAt", ""),
        "labels": [lb.get("name", "") for lb in (pr.get("labels") or [])],
        "size": {
            "files": pr.get("changedFiles", 0) or 0,
            "additions": pr.get("additions", 0) or 0,
            "deletions": pr.get("deletions", 0) or 0,
        },
        "body": pr.get("body", ""),
        "comments": {
            "total": comments_overview["total"],
            "inline_threads": len(inline_threads),
            "has_agent_prompts": has_agent_prompts,
        },
        "ci": {
            "status": ci_status,
            "failing": [f["name"] for f in failing],
            "passing_count": len(passing),
            "pending_count": len(pending),
        },
        "reviews": {
            "decision": reviews_overview["decision"],
            "approvals": len(reviews_overview["approvals"]),
            "changes_requested_by": [cr["user"] for cr in reviews_overview["changes_requested"]],
        },
        "commits": {
            "total": len(commits_list),
            "latest": commits_list[-1]["message"] if commits_list else "",
            "latest_sha": commits_list[-1]["sha"] if commits_list else "",
            "latest_timestamp": commits_list[-1]["timestamp"] if commits_list else "",
        },
    }
    with open(f"{out}/summary.json", "w") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)

    print(f"Structured PR #{summary['number']} -> {out}/", file=sys.stderr)
    print(f"  Comments: {comments_overview['total']} ({len(inline_threads)} inline)", file=sys.stderr)
    print(f"  CI: {len(passing)} pass, {len(failing)} fail, {len(pending)} pending", file=sys.stderr)
    print(f"  Diff: {diff_data['total_files']} files (+{diff_data['additions']}/-{diff_data['deletions']})", file=sys.stderr)


if __name__ == "__main__":
    main()
