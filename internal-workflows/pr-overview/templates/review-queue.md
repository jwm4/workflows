# Review Queue — {{REPO}}

**Date:** {{DATE}}
**Open PRs:** {{TOTAL_PRS}} | **Ready for Review:** {{READY_COUNT}} | **In Queue:** {{MILESTONE_COUNT}}

### At a Glance

{{AT_A_GLANCE}}

---

## Ready for Review ({{READY_COUNT}})

| # | PR | Type | Author | Size | Updated | Action Needed |
|---|---|---|---|---|---|---|
{{#each READY_PR_ROWS}}
| {{RANK}} | [#{{NUMBER}}]({{URL}}) — {{TITLE}} | {{TYPE}} | {{AUTHOR}} | {{SIZE}} | {{UPDATED}} | {{ACTION_NEEDED}} |
{{/each}}

---

{{#if ALMOST_READY_ENTRIES}}
## Almost Ready ({{NEAR_COUNT}})

{{#each ALMOST_READY_ENTRIES}}
**[#{{NUMBER}}]({{URL}}) — {{TITLE}}**
{{TYPE}} · {{AUTHOR}} · {{SIZE}} · {{UPDATED}}

{{CONTEXT_BULLETS}}

**Needs:** {{WHAT_NEEDED}}

---

{{/each}}
{{/if}}

## Remaining Blocked ({{BLOCKED_COUNT}})

| # | PR | Type | Author | Updated | Issue |
|---|---|---|---|---|---|
{{#each BLOCKED_PR_ROWS}}
| {{RANK}} | [#{{NUMBER}}]({{URL}}) — {{TITLE}} | {{TYPE}} | {{AUTHOR}} | {{UPDATED}} | {{ISSUE_BULLETS}} |
{{/each}}

---

{{#if RECOMMEND_CLOSE_ENTRIES}}
## Recommend Closing ({{CLOSE_COUNT}})

| PR | Author | Reason | Last Updated |
|---|---|---|---|
{{#each RECOMMEND_CLOSE_ENTRIES}}
| [#{{NUMBER}}]({{URL}}) — {{TITLE}} | {{AUTHOR}} | {{REASON}} | {{UPDATED}} |
{{/each}}

---

{{/if}}

{{#if DRAFT_ROWS}}
## Drafts ({{DRAFT_COUNT}})

| PR | Type | Author | Updated |
|---|---|---|---|
{{#each DRAFT_ROWS}}
| [#{{NUMBER}}]({{URL}}) — {{TITLE}} | {{TYPE}} | {{AUTHOR}} | {{UPDATED}} |
{{/each}}

---

{{/if}}

## Summary

| Bucket | Count |
|--------|-------|
| Ready for review | {{READY_COUNT}} |
| In queue (milestone) | {{MILESTONE_COUNT}} |
| Almost ready | {{NEAR_COUNT}} |
| Blocked | {{BLOCKED_COUNT}} |
| Drafts | {{DRAFT_COUNT}} |
{{#if FORK_COUNT}}| Fork PRs (need manual review) | {{FORK_COUNT}} |{{/if}}
| **Total open** | **{{TOTAL_PRS}}** |

### By Type

| Type | Count |
|------|-------|
{{#each TYPE_COUNTS}}
| {{TYPE}} | {{COUNT}} |
{{/each}}
