---
name: speedrun
description: Speed-run the remaining bugfix phases without stopping between them.
---

# /speedrun — Run the Remaining Workflow

You are in **speedrun mode**. Run the next incomplete phase, then continue to
the next one. Do not use the controller skill.

## User Input

```text
$ARGUMENTS
```

Consider the user input before proceeding. It may contain a bug report, issue
URL, context about where they are in the workflow, or instructions about which
phases to include or skip.

## How Speedrun Works

The speedrun loop:

1. Determine which phase to run next (see "Determine Next Phase" below)
2. If all phases are done (including `/summary`), stop
3. Otherwise, run the skill for that phase (see "Execute a Phase" below)
4. When the skill completes, continue to the next phase

This loop continues until all phases are complete or an escalation stops you.

## Determine Next Phase

Check which phases are already done by looking for artifacts and conversation
context, then pick the first phase that is NOT done.

### Phase Order and Completion Signals

| Phase | Skill | "Done" signal |
| ------- | ------- | --------------- |
| assess | `assess` | `artifacts/bugfix/reports/assessment.md` exists |
| reproduce | `reproduce` | `artifacts/bugfix/reports/reproduction.md` exists |
| diagnose | `diagnose` | `artifacts/bugfix/analysis/root-cause.md` exists |
| fix | `fix` | `artifacts/bugfix/fixes/implementation-notes.md` exists |
| test | `test` | `artifacts/bugfix/tests/verification.md` exists |
| review | `review` | `artifacts/bugfix/review/verdict.md` exists |
| document | `document` | `artifacts/bugfix/docs/pr-description.md` exists |
| pr | `pr` | A PR URL has been shared in conversation |
| summary | `summary` | `artifacts/bugfix/summary.md` exists |

### Rules

- Check artifacts in order. The first phase whose signal is NOT satisfied is next.
- If no artifacts exist, start at **assess**.
- If the user specifies a starting point in `$ARGUMENTS`, respect that.
- If conversation context clearly establishes a phase was completed (even
  without an artifact), skip it.

## Execute a Phase

1. **Announce** the phase to the user (e.g., "Starting the /fix phase — speedrun mode.")
2. **Run** the skill for the current phase
3. When the skill completes, continue to the next phase

## Speedrun Rules

- **Do not stop and wait between phases.** After each phase completes,
  continue to the next one.
- **Do not use the controller skill.** This skill replaces the controller for
  this run.
- **DO still follow CLAUDE.md escalation rules.** If a phase hits an
  escalation condition (confidence below 80%, unclear root cause after
  investigation, multiple valid solutions with unclear trade-offs, security or
  compliance concern, architectural decision needed), stop and ask the user.
  After the user responds, continue with the next phase.

## Phase-Specific Notes

### assess

- If no bug report or issue URL exists in `$ARGUMENTS` or conversation, ask
  the user once, then proceed.
- Present the assessment inline but do not wait for confirmation.

### reproduce

- If reproduction fails, note the failure and continue to diagnose anyway
  (diagnosis may reveal why reproduction is difficult).

### diagnose

- If multiple root causes are plausible and you cannot determine which is
  correct with high confidence, this is an escalation point — stop and ask.

### fix

- Create a feature branch if one doesn't exist yet.
- If the diagnosis identified multiple fix approaches with unclear trade-offs,
  this is an escalation point — stop and ask.

### test

- Run the full test suite. If tests fail due to your fix, attempt to resolve
  them before continuing.
- If failures persist after a reasonable attempt, note them and continue —
  review will catch outstanding issues.

### review

- Always run this phase between test and document.
- **Verdict: "fix and tests are solid"** — continue to document.
- **Verdict: "fix is adequate, tests incomplete"** — attempt to add the
  missing tests, then continue to document.
- **Verdict: "fix is inadequate"** — perform **one** revision cycle: go back
  to fix → test → review. If the second review still says "inadequate," stop
  and report the issues to the user instead of looping further.

### document

- Generate all documentation artifacts per the skill.

### pr

- Follow the PR skill's full process including its fallback ladder.
- If PR creation fails after exhausting fallbacks, report and stop.

### summary

- Always run this as the final phase. It replaces the Completion Report below.
- The summary skill scans all artifacts and presents a synthesized overview.
  This is the last thing the user sees — it surfaces findings that might
  otherwise get buried in earlier artifacts.
- Speedrun still MUST honor any `AskUserQuestion` hard gates from earlier
  phases (e.g., the existing-PR decision in assess). Those gates block until
  the user responds — do not skip or work around them.

## Completion Report (Early Stop Only)

If you stop early due to escalation (before `/summary` runs), present:

```markdown
## Speedrun Complete

### Phases Run
- [each phase that ran and its key outcome]

### Artifacts Created
- [all artifacts with paths]

### Result
- [PR URL, or reason for stopping early]

### Notes
- [any escalations, skipped phases, or items needing follow-up]
```

## Usage Examples

**From the beginning (no prior work):**

```text
/speedrun Fix bug https://github.com/org/repo/issues/425 - session status updates failing
```

**Mid-workflow (some phases already done):**

```text
/speedrun
```

The skill detects existing artifacts and picks up from the next incomplete phase.

**With an explicit starting point:**

```text
/speedrun Start from /fix — I already know the root cause
```
