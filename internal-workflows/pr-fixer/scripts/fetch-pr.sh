#!/usr/bin/env bash
#
# fetch-pr.sh — Fetch all data for a single PR and structure it.
#
# Usage:
#   ./scripts/fetch-pr.sh --repo owner/repo --pr 123 [--output-dir artifacts/123] [--with-logs]
#

set -euo pipefail

REPO=""
PR_NUM=""
OUTPUT_DIR=""
WITH_LOGS=false
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)     REPO="$2"; shift 2 ;;
        --pr)       PR_NUM="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --with-logs) WITH_LOGS=true; shift ;;
        -h|--help)  echo "Usage: $0 --repo owner/repo --pr 123 [--output-dir artifacts/123] [--with-logs]"; exit 0 ;;
        *)          echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -z "$REPO" || -z "$PR_NUM" ]] && { echo "Error: --repo and --pr required" >&2; exit 1; }
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="artifacts/${PR_NUM}"

for cmd in gh jq python3; do
    command -v "$cmd" &>/dev/null || { echo "Error: ${cmd} not installed" >&2; exit 1; }
done
gh auth status &>/dev/null || { echo "Error: gh not authenticated" >&2; exit 1; }

OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

DETAIL_FIELDS="number,title,author,createdAt,updatedAt,labels,isDraft,baseRefName,headRefName,headRefOid,url,state,additions,deletions,changedFiles,mergeable,body,reviewDecision,statusCheckRollup,comments,assignees,milestone,files,isCrossRepository,headRepositoryOwner"

echo "Fetching PR #${PR_NUM} from ${REPO}..." >&2

# -- Parallel API calls --
gh pr view "$PR_NUM" --repo "$REPO" --json "$DETAIL_FIELDS" \
    > "${TMPDIR}/pr.json" 2>"${TMPDIR}/pr.err" &
PID_PR=$!

gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUM}/reviews" \
    --paginate > "${TMPDIR}/reviews.json" 2>"${TMPDIR}/reviews.err" &
PID_REVIEWS=$!

gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUM}/comments" \
    --paginate > "${TMPDIR}/review_comments.json" 2>"${TMPDIR}/rc.err" &
PID_RC=$!

gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUM}/commits" \
    --paginate > "${TMPDIR}/commits.json" 2>"${TMPDIR}/commits.err" &
PID_COMMITS=$!

gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUM}/files" \
    --paginate 2>"${TMPDIR}/diff.err" \
    | jq '[.[] | {filename, status, additions, deletions, patch}]' \
    > "${TMPDIR}/diff_files.json" &
PID_DIFF=$!

wait "$PID_PR" 2>/dev/null || { cat "${TMPDIR}/pr.err" >&2; echo '{}' > "${TMPDIR}/pr.json"; }
wait "$PID_REVIEWS" 2>/dev/null || { cat "${TMPDIR}/reviews.err" >&2; echo '[]' > "${TMPDIR}/reviews.json"; }
wait "$PID_RC" 2>/dev/null || { cat "${TMPDIR}/rc.err" >&2; echo '[]' > "${TMPDIR}/review_comments.json"; }
wait "$PID_COMMITS" 2>/dev/null || { cat "${TMPDIR}/commits.err" >&2; echo '[]' > "${TMPDIR}/commits.json"; }
wait "$PID_DIFF" 2>/dev/null || { cat "${TMPDIR}/diff.err" >&2; echo '[]' > "${TMPDIR}/diff_files.json"; }

# -- Check runs (needs HEAD_SHA from pr.json) --
HEAD_SHA=$(jq -r '.headRefOid // empty' "${TMPDIR}/pr.json" 2>/dev/null || true)
echo '[]' > "${TMPDIR}/check_runs.json"
if [[ -n "$HEAD_SHA" ]]; then
    gh api "repos/${OWNER}/${REPO_NAME}/commits/${HEAD_SHA}/check-runs" \
        --paginate 2>/dev/null \
        | jq '.check_runs // []' > "${TMPDIR}/check_runs.json" 2>/dev/null || echo '[]' > "${TMPDIR}/check_runs.json"
fi

# -- Structure the data --
python3 "${SCRIPT_DIR}/structure-pr-data.py" \
    --pr-json "${TMPDIR}/pr.json" \
    --reviews-json "${TMPDIR}/reviews.json" \
    --review-comments-json "${TMPDIR}/review_comments.json" \
    --check-runs-json "${TMPDIR}/check_runs.json" \
    --diff-json "${TMPDIR}/diff_files.json" \
    --commits-json "${TMPDIR}/commits.json" \
    --output-dir "${OUTPUT_DIR}"

# -- Fetch CI failure logs (optional) --
if [[ "$WITH_LOGS" == "true" && -n "$HEAD_SHA" ]]; then
    mkdir -p "${OUTPUT_DIR}/ci/logs"
    FAILING=$(jq -r '.failing[]?.name // empty' "${OUTPUT_DIR}/ci/overview.json" 2>/dev/null)
    if [[ -n "$FAILING" ]]; then
        echo "  Fetching CI failure logs..." >&2
        RUN_ID=$(gh api "repos/${OWNER}/${REPO_NAME}/actions/runs?head_sha=${HEAD_SHA}&status=failure" \
            --jq '.workflow_runs[0].id' 2>/dev/null || true)
        if [[ -n "$RUN_ID" && "$RUN_ID" != "null" ]]; then
            gh run view "$RUN_ID" --repo "$REPO" --log-failed 2>/dev/null \
                | tail -200 > "${OUTPUT_DIR}/ci/logs/failure.txt" 2>/dev/null || true
            echo "  Wrote failure logs (last 200 lines)" >&2
        fi
    fi
fi

echo "" >&2
echo "Fetch complete for PR #${PR_NUM}: ${OUTPUT_DIR}/" >&2
