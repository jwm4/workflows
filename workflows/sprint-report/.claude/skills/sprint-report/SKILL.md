---
name: sprint-report
description: Generate a comprehensive sprint health report from Jira data (CSV or MCP). Analyzes 8 metric dimensions, detects anti-patterns, and produces styled HTML/Markdown reports.
---

# Sprint Health Report

You are generating a sprint health report. The user has already answered the
intake questions from the startup prompt. Execute the full pipeline below in a
**single pass** — do not stop between steps.

## User Input

```text
$ARGUMENTS
```

Consider the user input before proceeding. It contains answers to the startup
questions (data source, team, audience, format, assumptions).

## Step 1: Ingest Data

Parse the sprint data from whichever source the user provided:

- **CSV export:** Read the uploaded file and parse rows
- **Jira MCP:** Use `jira_search` with the sprint ID or board ID + sprint filter
- **Other format:** Adapt to whatever the user described

Extract these fields per issue: key, type, status, priority, assignee, story
points, created date, resolved date, sprint field, acceptance criteria, flagged
status, blockers.

## Step 2: Compute Metrics (All 8 Dimensions)

Calculate every dimension — do not skip any even if data is sparse. Note when
data is insufficient rather than omitting the dimension.

| Dimension | Key Metrics |
| --- | --- |
| Commitment Reliability | delivery rate (points completed / committed), item completion rate |
| Scope Stability | items added/removed mid-sprint, scope change percentage |
| Flow Efficiency | cycle time (created → resolved), WIP count, status distribution |
| Story Sizing | point distribution, oversized items (>8 pts), unestimated items |
| Work Distribution | load per assignee, concentration risk, unassigned items |
| Blocker Analysis | flagged items, blocking/blocked relationships, impediment duration |
| Backlog Health | acceptance criteria coverage, priority distribution, definition of ready |
| Delivery Predictability | carryover count, zombie items (>2 sprints), aging analysis |

## Step 3: Detect Anti-Patterns

Check for each of these evidence-based patterns. Only report patterns with
supporting data — do not speculate.

| Anti-Pattern | Trigger |
| --- | --- |
| Overcommitment | committed > 2× historical velocity |
| Perpetual carryover | items spanning 3+ sprints |
| Missing Definition of Ready | 0% acceptance criteria coverage |
| Work concentration | one person assigned >30% of items |
| Mid-sprint scope injection | items added without descoping |
| Zombie items | >60 days old, still open |
| Item repurposing | summary/description changed mid-sprint |
| Hidden work | items with no status transitions |

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

## Step 5: Produce the Report

Generate artifacts in `artifacts/sprint-report/`:

- `{SprintName}_Health_Report.md` — full Markdown report
- `{SprintName}_Health_Report.html` — styled HTML with KPI cards, progress bars, coaching notes

Use whichever format(s) the user requested. If they said "both," produce both.

### Report Structure

Every report follows this structure regardless of format:

1. **Executive Summary** — health rating, top 5 numbers, positive signals
2. **KPI Dashboard** — delivery rate, WIP count, AC coverage, never-started items, cycle time, carryover
3. **Dimension Analysis** — 8 cards with observations, risks, root causes
4. **Anti-Pattern Detection** — evidence-based pattern cards
5. **Top 5 Actions for Next Sprint** — numbered, actionable
6. **Coaching Notes** — retrospective facilitation, sprint planning, backlog refinement
7. **Appendix** — per-item detail table with status, points, assignee, sprint history

### HTML Template

Before generating the HTML report, **Read** the template at `templates/report.html`.

- Use the exact CSS, HTML structure, and JavaScript from the template
- Replace all `{{PLACEHOLDER}}` markers with values computed from the sprint data
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
  navigation

## Step 6: Jira Enrichment (Optional)

If Jira MCP is available and the user wants deeper analysis, batch-fetch the
top 10–15 highest-risk issues via `jira_get_issue` to get changelogs and
comments. Use a single `jira_search` with JQL `key in (...)` rather than
individual fetches.

**Important:** Integrate enrichment data on the first write. Do not produce the
report and then rewrite it — weave the findings in as you go.

## Critical Constraints

- Do NOT build Python scripts, CLI tools, or reusable analyzers
- Do NOT implement features the user didn't ask for (dark mode, PDF export, trend charts, etc.)
- Batch tool calls wherever possible (parallel `jira_get_issue` calls, not serial)
- If the user's answers are complete, produce the report without asking follow-up questions
- Stick to the requested output format(s) — don't produce both unless asked

## Output

- Report artifacts in `artifacts/sprint-report/`
- Present a brief summary of the health rating and top findings inline after
  generating the report files
