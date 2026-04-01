---
name: sprint-report
description: Generate a comprehensive sprint health report from Jira data (CSV or MCP). Analyzes 8 metric dimensions, detects anti-patterns, and produces styled HTML/Markdown reports.
---

# Sprint Health Report

You are generating a sprint health report. Follow the full pipeline below.

**Reference files** (read when needed, not upfront):

- `references/jira-fields.md` — custom field IDs and discovery
- `references/jira-query-patterns.md` — JQL patterns and data volume guidance

## Step 0: Discovery & Proposal

Before asking the user any questions, discover what you can automatically.

### 0a. Interpret the User Request

The user may provide any combination of: project key, component name, board
name, team name, sprint name/number, or just a vague reference like "my
sprint." Extract whatever identifiers are present.

**Search directly for what the user gave you.** If they said "AgentOps",
call `jira_get_agile_boards(board_name="AgentOps")`. Do NOT call
`jira_get_all_projects` or enumerate projects — go straight to the
identifier the user provided.

### 0b. Discover the Sprint (Jira MCP)

If Jira MCP is available:

1. **Find the board:**
   - `jira_get_agile_boards(project_key=X)` or
     `jira_get_agile_boards(board_name=X)`
   - If the user provided a component name, search boards by the project
     containing that component
2. **Find the active sprint:**
   - `jira_get_sprints_from_board(board_id=BOARD_ID, state="active")`
   - If multiple active sprints: include all in proposal and ask which one
   - If none: offer the most recently closed sprint
3. **Get a rough item count** (for the proposal only):
   - `jira_get_sprint_issues(sprint_id=SPRINT_ID, fields="summary,status,assignee")`
   - Count total items and unique assignees from the response
   - Do NOT fetch story points or custom fields yet — that happens in Step 1

This is a lightweight preview. Full field discovery and data ingestion happen
in Step 1 after the user approves the plan.

### 0c. Propose a Plan

Present a short proposal:

```
I found [Sprint Name] ([state], [start] – [end]).

Proposed plan:
- Analyze [N] items across [M] team members
- [Include/Skip] historical comparison ([K] closed sprints available)
- Generate HTML report for all audiences
- Output to artifacts/sprint-report/

Approve to proceed, or tell me what to change.
```

Set these defaults (user can override any of them):

| Setting | Default | Override Example |
| --- | --- | --- |
| Output format | HTML (template exists) | "Make it Markdown" |
| Audience | All | "Just for scrum master" |
| Historical trends | Include if 3+ closed sprints available | "Skip trends" |
| Sprint | Current active sprint | "Use Sprint 2 instead" |

**Wait for user approval, then immediately continue to Step 1.** Any
affirmative response ("yes", "approve", "looks good", "proceed", "continue")
means go. If the user requests changes, adjust the plan and re-propose. Do
not stall or ask for further confirmation after receiving approval.

### 0d. CSV or Other Source

If Jira MCP is not available, or the user provides a CSV:

- Ask only what you cannot derive: data source path, team name, sprint dates
- Still propose defaults for everything else

## Step 1: Ingest Data

The user has approved the plan. Now fetch the full data set.

### 1a. Discover Custom Fields

Read `references/jira-fields.md` for known field IDs. If the Jira instance
is `redhat.atlassian.net`, use the confirmed IDs in the "Known Fields"
section — no discovery needed.

For other instances, confirm the correct IDs:

- Use `jira_search_fields` to search for "story point" and "sprint"
- Or fetch a single issue with all fields and inspect the keys:
  `jira_search("project = X ORDER BY created DESC", maxResults=1, fields="*all")`
- Record the story points field ID and sprint field ID for subsequent queries

### 1b. Query Sprint Issues (Full Fetch)

Now re-fetch the sprint data with the **complete field list**. The lightweight
query from Step 0b was just for the proposal — this is the real data pull.

See `references/jira-query-patterns.md` for details.

```
jira_get_sprint_issues(
    sprint_id=SPRINT_ID,
    fields="summary,status,issuetype,priority,assignee,created,updated,resolutiondate,components,description,customfield_XXXXX,customfield_YYYYY"
)
```

Replace `customfield_XXXXX` and `customfield_YYYYY` with the IDs from 1a.

**DO NOT use `fields=*all`** — this returns 100+ custom fields per issue and
can produce 500k+ characters, exceeding tool output limits.

### 1c. Handle Mixed Sprints

If the query returns items from multiple sprints (carryover):

- Filter to current sprint ID in post-processing
- Record carryover items separately (count them as a metric)
- Include carryover items in the appendix, clearly marked

### 1d. CSV Ingestion

Parse rows and map columns to the standard fields: key, type, status,
priority, assignee, story points, created date, resolved date, sprint, AC.

### 1e. Assess Data Quality

After ingesting data, compute coverage:

| Check | How to Measure |
| --- | --- |
| Story points | % of items with a non-null, non-zero points field |
| Resolution dates | % of items with `resolutiondate` set |
| Acceptance criteria | % of items with AC patterns in `description` |
| Priority | % of items with priority set |
| Assignee | % of items with an assignee |

**Minimum requirements:**

- Sprint has >0 items (if 0: stop and tell the user)
- Sprint has valid start/end dates (if missing: warn but continue)

**Set fallback metrics when data is sparse:**

| Metric | Ideal | Fallback | Caveat to Display |
| --- | --- | --- | --- |
| Delivery Rate | Points completed / committed | Items completed / committed | "Item-based (no story points)" |
| Velocity | Avg points per sprint | Avg items per sprint | "Item-based velocity" |
| Cycle Time | Created → resolved (days) | Days in current status | "Estimated from status duration" |
| Story Sizing | Point distribution | Item type distribution | "Cannot analyze sizing without estimates" |

If 2+ critical gaps exist (no points + no priorities + no AC + <3 days
elapsed), warn the user:

> Data quality is low — the report will have limited insights. Proceed
> anyway, or wait until items are estimated?

If proceeding, add a prominent data quality callout at the top of the
Executive Summary.

### 1f. Historical Data (If Approved in Step 0)

Query the last 3–5 closed sprints from the same board. For each, retrieve
issues the same way as the active sprint and calculate: velocity, completion
rate, carryover count. See `references/jira-query-patterns.md` for queries.

If fewer than 3 closed sprints exist, skip trends and note it in the report.

### 1g. Identify Team

1. Extract unique assignees from sprint items
2. Sort alphabetically by last name
3. Format: "F. LastName" (e.g., "C. Zaccaria")
4. If >10 members: show first 8 + "and N more"

## Step 2: Compute Metrics (All 8 Dimensions)

Calculate every dimension — do not skip any even if data is sparse. Note when
data is insufficient rather than omitting the dimension.

| Dimension | Key Metrics |
| --- | --- |
| Commitment Reliability | delivery rate (points or items completed / committed), item completion rate |
| Scope Stability | items added/removed mid-sprint, scope change %, sprint goal alignment |
| Flow Efficiency | cycle time, WIP count, status distribution (see cycle time tools below) |
| Story Sizing | point distribution, oversized items (>8 pts), unestimated items |
| Work Distribution | load per assignee, concentration risk (>30% = flag), unassigned items |
| Blocker Analysis | flagged items, blocking/blocked relationships, impediment duration |
| Backlog Health | acceptance criteria coverage, priority distribution, definition of ready |
| Delivery Predictability | carryover count, zombie items (>60 days old), aging analysis |

### Cycle Time Calculation

Prefer specialized tools over manual date arithmetic:

1. **Best:** `jira_get_issue_sla` — returns pre-computed cycle time, lead
   time, and time-in-status breakdowns. Call for resolved items.
2. **Good:** `jira_get_issue_dates` — returns status transition history.
   Calculate cycle time as the span from first "In Progress" transition to
   resolution.
3. **Fallback:** `created` → `resolutiondate` from sprint issue data (less
   accurate — includes backlog time).

For items still in progress, use `jira_get_issue_dates` to get time-in-status
for the current status. This is useful for WIP aging analysis.

Batch these calls for the top 10–15 items to avoid excessive API calls.

### Sprint Goal Alignment

If the sprint goal is defined (non-empty):

1. Classify each item as aligned/not-aligned based on whether its summary
   relates to a keyword or theme in the goal
2. Calculate alignment percentage
3. If <50%: add observation — "Only X% of items align with stated sprint goal"
4. If >80%: add positive signal

### Positive Signal Detection

Actively look for what is going well. Find at least 3 positive signals from:

- High AC coverage (>70%)
- Low never-started rate (<15%)
- Even work distribution (no one >30% load)
- No critical blockers
- Sprint goal clearly defined
- Items completed on time
- Low carryover rate (<30%)
- Good priority coverage (>70%)
- WIP within limits (<team size)
- Fast cycle time (<7 days avg)
- No zombie items (all items <60 days old)
- Good sprint goal alignment (>80%)

If <3 found, list whatever exists and note "Limited positive signals this
sprint — opportunity for improvement."

## Step 3: Detect Anti-Patterns

Check for each pattern. Only report patterns with supporting data — do not
speculate.

| Anti-Pattern | Trigger |
| --- | --- |
| Overcommitment | committed > 2× historical velocity |
| Perpetual carryover | items spanning 3+ sprints |
| Missing Definition of Ready | 0% acceptance criteria coverage |
| Work concentration | one person assigned >30% of items |
| Mid-sprint scope injection | items added after sprint start without descoping |
| Zombie items | any open item >60 days old |
| Item repurposing | summary/description changed mid-sprint (requires changelog) |
| Hidden work | items with no status transitions since added (requires changelog) |

### Systematic Zombie Detection

Do not just find the oldest item. Check **every** open item:

1. Calculate `age = today − created_date` for all open items
2. Filter where `age > 60 days`
3. If count > 0: list ALL zombie items with key and age
4. If count == 0: record as positive signal

### Review Bottleneck Check

If >40% of items are in a "Review"-like status:

- Flag as flow bottleneck
- Note that "Review" can mean code review, QA, or stakeholder approval
- Recommend the team investigate which type dominates and consider splitting
  the status for visibility

## Step 4: Generate Health Rating

Compute a risk score on a 0–10 scale:

| Factor | +3 | +2 | +1 | 0 |
| --- | --- | --- | --- | --- |
| Delivery rate | <50% | 50–69% | 70–84% | 85%+ |
| AC coverage | — | <30% | 30–69% | 70%+ |
| Zombie items | — | 3+ | 1–2 | none |
| Never started | — | >30% | 15–30% | <15% |
| Priority gaps | — | — | <30% prioritized | 30%+ |

**Rating bands:** 0–3 = HEALTHY, 4–6 = MODERATE RISK, 7–10 = HIGH RISK

If using fallback metrics (item-based instead of points-based), note the
reduced confidence in the rating.

## Step 5: Produce the Report

Generate artifacts in `artifacts/sprint-report/`:

- `{SprintName}_Health_Report.md` — full Markdown report
- `{SprintName}_Health_Report.html` — styled HTML with KPI cards, progress bars, coaching notes

Use whichever format(s) the user approved in Step 0. If they said "both,"
produce both.

### Report Structure

Every report follows this structure regardless of format:

1. **Executive Summary** — health rating, top 5 numbers, positive signals (minimum 3), data quality note (if applicable)
2. **KPI Dashboard** — delivery rate, WIP count, AC coverage, never-started items, cycle time, carryover
3. **Dimension Analysis** — 8 cards with observations, risks, root causes
4. **Anti-Pattern Detection** — evidence-based pattern cards
5. **Top 5 Actions for Next Sprint** — numbered, actionable
6. **Coaching Notes** — retrospective facilitation, sprint planning, backlog refinement
7. **Appendix** — per-item detail table with status, points, assignee, sprint history

### HTML Template

Before generating the HTML report, **Read** the template at `templates/report.html`.

- Use the exact CSS, HTML structure, and JavaScript from the template
- Replace all `{{PLACEHOLDER}}` markers with computed values
- HTML-escape all Jira-sourced text (issue summaries, descriptions, assignee
  names, comments) before interpolation — escape `&`, `<`, `>`, `"`, `'`
- For repeating components (dimension cards, KPI cards, anti-pattern cards,
  action cards, coaching cards, observation blocks, appendix rows), replicate
  the example pattern for each data item
- The template includes inline HTML comments describing how to repeat patterns
  and which CSS classes to use
- Do NOT modify the CSS or JavaScript sections
- Do NOT add features not present in the template (charts, trend graphs, etc.)
- Preserve the sidebar table of contents and all section IDs for scroll-spy

### Placeholder Derivation

Key placeholders and how to derive them:

- `{{NEXT_SPRINT_NAME}}` — increment the sprint number if numeric (Sprint 3 → Sprint 4), else "Next Sprint"
- `{{TEAM_MEMBERS}}` — "F. Last" format, comma-separated, truncate with "..." if >100 chars
- `{{POSITIVE_SIGNAL}}` — repeat `<li>` for each signal (minimum 3)
- `{{DELIVERY_RATE_VALUE}}` — "X.X%" (item-based if no story points; label accordingly)
- `{{DELIVERY_RATE_SUB}}` — "X of Y items completed" or "X of Y points completed"
- Progress bar widths — use point totals if available, otherwise item counts;
  show label only if segment width >10%

## Step 6: Changelog Analysis (Conditional)

Changelogs add significant payload. Do NOT include `expand=changelog` on the
main sprint query in Step 1b — fetch changelogs separately for targeted items.

**Preferred tool:** `jira_batch_get_changelogs` — fetches changelogs for
multiple issue keys in one call. Use this for the top 10–15 highest-risk
items (oldest, blocked, carryover, reassigned).

```
jira_batch_get_changelogs(issue_keys=["KEY-1", "KEY-2", "KEY-3", ...])
```

**Fallback** (if batch tool is unavailable): `jira_search` with
`key in (KEY-1, KEY-2, ...)` and `expand=changelog`.

**If skipping entirely:** note in the report that some anti-patterns (item
repurposing, hidden work, reassignment churn) could not be assessed.

### What to Extract from Changelogs

| Pattern | What to Look For |
| --- | --- |
| Item repurposing | `summary` or `description` field changed mid-sprint |
| Reassignment | `assignee` changed (signals unclear ownership) |
| Status churn | item moved backward (e.g., Review → In Progress) |
| Sprint hopping | `Sprint` field changed (added/removed mid-sprint) |
| Hidden work | no status transitions since item was added |

Integrate findings into the report on the first write — do not produce the
report and then rewrite it.

## Critical Constraints

- Do NOT build Python scripts, CLI tools, or reusable analyzers
- Do NOT implement features the user didn't ask for (dark mode, PDF export, trend charts, etc.)
- Batch tool calls wherever possible (parallel `jira_search` calls, not serial)
- Stick to the requested output format(s) — don't produce both unless asked
- After Step 0 approval, execute the full pipeline without stopping between steps

## Output

- Report artifacts in `artifacts/sprint-report/`
- Present a brief summary of the health rating and top findings inline after
  generating the report files
