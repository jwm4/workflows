#!/usr/bin/env bash
#
# fetch-prs.sh — Fetch all open PR data and structure it.
#
# Usage:
#   ./scripts/fetch-prs.sh --repo owner/repo [--output-dir artifacts/pr-review]
#

set -euo pipefail

REPO=""
OUTPUT_DIR="artifacts/pr-review"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STRUCTURE_SCRIPT="${SCRIPT_DIR}/structure-pr-data.py"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)       REPO="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)    echo "Usage: $0 --repo owner/repo [--output-dir artifacts/pr-review]"; exit 0 ;;
        *)            echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$REPO" ]] && { echo "Error: --repo required" >&2; exit 1; }

for cmd in gh jq python3; do
    command -v "$cmd" &>/dev/null || { echo "Error: ${cmd} not installed" >&2; exit 1; }
done
gh auth status &>/dev/null || { echo "Error: gh not authenticated" >&2; exit 1; }

if [[ ! -f "$STRUCTURE_SCRIPT" ]]; then
    echo "Error: structure-pr-data.py not found at ${STRUCTURE_SCRIPT}" >&2
    exit 1
fi

OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Fetching open PRs for ${REPO}..." >&2

INDEX_FIELDS="number,title,author,createdAt,updatedAt,labels,isDraft,baseRefName,headRefName,url,state,additions,deletions,changedFiles,mergeable,body,isCrossRepository,headRepositoryOwner"

mkdir -p "${OUTPUT_DIR}"
gh pr list --repo "$REPO" --state open --limit 200 --json "$INDEX_FIELDS" \
    | jq '.' > "${OUTPUT_DIR}/index.json"

PR_COUNT=$(jq 'length' "${OUTPUT_DIR}/index.json")
echo "Found ${PR_COUNT} open PRs." >&2

[[ "$PR_COUNT" -eq 0 ]] && { echo "No open PRs found."; exit 0; }

DETAIL_FIELDS="number,title,author,createdAt,updatedAt,labels,isDraft,baseRefName,headRefName,headRefOid,url,state,additions,deletions,changedFiles,mergeable,body,reviewDecision,statusCheckRollup,comments,assignees,milestone,files,isCrossRepository,headRepositoryOwner"
PR_NUMBERS=$(jq -r '.[].number' "${OUTPUT_DIR}/index.json")
FETCHED=0

for PR_NUM in $PR_NUMBERS; do
    FETCHED=$((FETCHED + 1))
    echo -ne "  Fetching PR #${PR_NUM}... (${FETCHED}/${PR_COUNT})\r" >&2

    PR_TMP="${TMPDIR}/${PR_NUM}"
    mkdir -p "$PR_TMP"

    gh pr view "$PR_NUM" --repo "$REPO" --json "$DETAIL_FIELDS" \
        2>/dev/null > "${PR_TMP}/pr.json" || echo '{}' > "${PR_TMP}/pr.json"

    gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUM}/reviews" \
        --paginate 2>/dev/null > "${PR_TMP}/reviews.json" || echo '[]' > "${PR_TMP}/reviews.json"

    gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUM}/comments" \
        --paginate 2>/dev/null > "${PR_TMP}/review_comments.json" || echo '[]' > "${PR_TMP}/review_comments.json"

    gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUM}/commits" \
        --paginate 2>/dev/null > "${PR_TMP}/commits.json" || echo '[]' > "${PR_TMP}/commits.json"

    HEAD_SHA=$(jq -r '.headRefOid // empty' "${PR_TMP}/pr.json" 2>/dev/null || true)
    echo '[]' > "${PR_TMP}/check_runs.json"
    if [[ -n "$HEAD_SHA" ]]; then
        gh api "repos/${OWNER}/${REPO_NAME}/commits/${HEAD_SHA}/check-runs" \
            --paginate 2>/dev/null \
            | jq '.check_runs // []' > "${PR_TMP}/check_runs.json" 2>/dev/null || echo '[]' > "${PR_TMP}/check_runs.json"
    fi

    echo '[]' > "${PR_TMP}/diff_files.json"
    MERGEABLE=$(jq -r '.mergeable // "UNKNOWN"' "${PR_TMP}/pr.json" 2>/dev/null || echo "UNKNOWN")
    IS_DRAFT=$(jq -r '.isDraft // false' "${PR_TMP}/pr.json" 2>/dev/null || echo "false")
    if [[ "$MERGEABLE" == "MERGEABLE" && "$IS_DRAFT" != "true" ]]; then
        gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUM}/files" \
            --paginate 2>/dev/null \
            | jq '[.[] | {filename, status, additions, deletions, patch}]' \
            > "${PR_TMP}/diff_files.json" 2>/dev/null || echo '[]' > "${PR_TMP}/diff_files.json"
    fi

    python3 "$STRUCTURE_SCRIPT" \
        --pr-json "${PR_TMP}/pr.json" \
        --reviews-json "${PR_TMP}/reviews.json" \
        --review-comments-json "${PR_TMP}/review_comments.json" \
        --check-runs-json "${PR_TMP}/check_runs.json" \
        --diff-json "${PR_TMP}/diff_files.json" \
        --commits-json "${PR_TMP}/commits.json" \
        --output-dir "${OUTPUT_DIR}/${PR_NUM}" 2>/dev/null

    sleep 0.3
done

echo "" >&2
echo "Fetch complete: ${PR_COUNT} PRs -> ${OUTPUT_DIR}/" >&2
