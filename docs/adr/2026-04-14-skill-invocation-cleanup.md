# Proposal: Remove Manual Skill-Loading Boilerplate from Bugfix Workflow

**Date:** 2026-04-14
**Status:** Implemented
**Scope:** `workflows/bugfix/` (lessons may apply to other workflows later)

## Context

The bugfix workflow has 11 skills that coordinate through a controller (or
speedrun) orchestrator. During development, we discovered that the Ambient Code
Platform had a bug where the built-in skill invocation tool was not functioning.
Skills still *appeared* to work because the `systemPrompt` told the model where
skill files lived, and the model could load them with its file-reading tool and
follow the instructions manually. We engineered the workflow around this
workaround, adding explicit file-path references, dispatch blocks, and
return-and-re-read instructions throughout every skill.

The platform bug has since been fixed. The skill tool now works correctly. But
the workaround scaffolding remains embedded in every skill file, adding
complexity, brittleness, and — critically — encouraging the agent to use the
file tool to load skills instead of the platform's native skill invocation
mechanism.

### What the workaround looks like today

Every phase skill (assess, reproduce, diagnose, fix, test, review, document)
contains two boilerplate blocks:

**Dispatch block** (top of file):

```markdown
## Dispatch

If you were dispatched by the controller or by speedrun, continue below.
Otherwise, read `.claude/skills/controller/SKILL.md` first — it will send
you back here with the proper workflow context.
```

**Return block** (bottom of file):

```markdown
## When This Phase Is Done

...

Then announce which file you are returning to (e.g., "Returning to
`.claude/skills/controller/SKILL.md`." or "Returning to
`.claude/skills/speedrun/SKILL.md` for next phase.") and **re-read that
file** for next-step guidance.
```

The controller and speedrun skills contain complementary instructions:

**Controller** — "How to Execute a Phase":

```markdown
2. **Read** the skill file from the list above. You MUST call the Read tool on
   the skill's `SKILL.md` file before executing.
```

**Speedrun** — "Execute a Phase":

```markdown
2. **Read** the phase skill from the table above
...
4. The skill will tell you to announce which file you are returning to and
   re-read it. Return to **this file** (`.claude/skills/speedrun/SKILL.md`).
```

Both orchestrators also list every phase with its full file path (e.g.,
`.claude/skills/assess/SKILL.md`), which the agent uses as an argument to the
Read tool.

### Why this is problematic

1. **It bypasses the skill tool.** The instructions explicitly tell the agent to
   use the Read tool on `SKILL.md` files. This was necessary when the skill tool
   was broken, but now it means the agent is not using the platform's native
   skill invocation, which may handle context management, scoping, and lifecycle
   differently (and better) than raw file reading.

2. **It's not portable.** Different runners (Claude Code, Gemini CLI, Cursor,
   etc.) may expose skills through different mechanisms. Hardcoding "read
   `.claude/skills/foo/SKILL.md`" assumes a specific file layout and a specific
   tool for loading it. A portable workflow should say *which* skill to run, not
   *how* to load it.

3. **The return-and-re-read pattern is fragile.** Telling the agent to "re-read
   this file for next-step guidance" after every phase is a workaround for the
   fact that the controller wasn't being invoked as a skill. When the skill tool
   works correctly, the orchestrator (controller or speedrun) should naturally
   retain context after a sub-skill completes — there's no need to re-read
   anything.

4. **It adds ~20 lines of boilerplate per skill.** Across 11 skills, that's
   ~200 lines of dispatch/return scaffolding that obscures the actual workflow
   logic.

5. **It confuses the agent.** The instructions create an unusual execution model
   where the agent must track which file "dispatched" it and manually navigate
   back. This is error-prone and was one of the main sources of reliability
   issues during testing.

## Proposal

### Principle: say *what* to run, not *how* to run it

The orchestrator skills (controller and speedrun) should tell the agent which
skill to run next by name. They should not tell the agent how to load or invoke
that skill. The agent (or its runner) knows how to run skills — that's a
platform capability, not a workflow concern.

### Changes to orchestrator skills (controller, speedrun)

**Current pattern:**

```markdown
1. **Assess** (`/assess`) — `.claude/skills/assess/SKILL.md`
...
2. **Read** the skill file from the list above. You MUST call the Read tool on
   the skill's `SKILL.md` file before executing.
...
4. When the skill is done, it will report its findings and re-read this
   controller. Then use "Recommending Next Steps" below to offer options.
```

**Proposed pattern:**

```markdown
1. **Assess** (`/assess`) — `assess` skill
...
2. **Run** the skill for the current phase.
...
4. When the skill completes, use "Recommending Next Steps" below to offer
   options.
```

Specifically:

- Replace file paths (`.claude/skills/assess/SKILL.md`) with skill names
  (`assess` skill) in phase listings
- Remove instructions about using the Read tool to load skills
- Remove instructions about the agent returning to or re-reading the
  orchestrator file
- Keep phase descriptions, gating rules, and recommendation logic unchanged

### Changes to phase skills (assess, reproduce, diagnose, fix, test, review, document, pr, summary)

**Remove the dispatch block entirely.** When a skill is invoked through the
skill tool, it doesn't need to know who invoked it or redirect to another skill
if invoked "incorrectly." The skill should just do its job.

**Remove the return block's re-read instruction.** When a skill completes, it
should report its results. It doesn't need to tell the agent to go back and
re-read the controller. The orchestrator will naturally resume after the
sub-skill completes.

**Keep the results reporting.** The "When This Phase Is Done" section should
still list what findings to report — that's genuinely useful guidance. Just
remove the "announce which file you are returning to and re-read that file"
part.

### Changes to ambient.json systemPrompt

**Current:**

```json
"systemPrompt": "You are Amber, an expert colleague for systematic bug resolution.\n\nAt the start of the session, read .claude/skills/controller/SKILL.md — it defines the workflow phases, how to execute them, and how to recommend next steps."
```

**Proposed:**

```json
"systemPrompt": "You are Amber, an expert colleague for systematic bug resolution.\n\nAt the start of the session, run the controller skill — it defines the workflow phases, how to execute them, and how to recommend next steps."
```

Change "read `.claude/skills/controller/SKILL.md`" to "run the controller
skill."

### Changes to CLAUDE.md

**Current:**

```markdown
All phases are implemented as skills at `.claude/skills/{name}/SKILL.md`.
The workflow controller at `.claude/skills/controller/SKILL.md` manages phase
transitions and recommendations. The `/speedrun` skill at
`.claude/skills/speedrun/SKILL.md` runs all remaining phases without stopping.
```

**Proposed:**

```markdown
All phases are implemented as skills. The controller skill manages phase
transitions and recommendations. The speedrun skill runs all remaining phases
without stopping.
```

Remove file paths; refer to skills by name.

## Files affected

| File | Change |
|------|--------|
| `.ambient/ambient.json` | Replace file path with skill name in `systemPrompt` |
| `CLAUDE.md` | Replace file paths with skill names |
| `.claude/skills/controller/SKILL.md` | Replace file paths with skill names in phase list; remove Read tool instructions; remove re-read-on-return instructions |
| `.claude/skills/speedrun/SKILL.md` | Same as controller |
| `.claude/skills/assess/SKILL.md` | Remove dispatch block; simplify "When This Phase Is Done" |
| `.claude/skills/reproduce/SKILL.md` | Same |
| `.claude/skills/diagnose/SKILL.md` | Same |
| `.claude/skills/fix/SKILL.md` | Same |
| `.claude/skills/test/SKILL.md` | Same |
| `.claude/skills/review/SKILL.md` | Same |
| `.claude/skills/document/SKILL.md` | Same |
| `.claude/skills/pr/SKILL.md` | Remove "return to coordinating skill and re-read" |
| `.claude/skills/summary/SKILL.md` | Remove conditional return-and-re-read |

Total: 13 files, all within `workflows/bugfix/`.

## What this does NOT change

- **Phase logic.** The actual steps within each skill (how to diagnose, how to
  write tests, etc.) are untouched. Only dispatch/return boilerplate is removed.
- **Gating rules.** The controller's `AskUserQuestion` gates between phases
  remain. Speedrun's hard gates (e.g., assess PR gate) remain.
- **Artifact paths.** All `artifacts/bugfix/` references stay as-is.
- **Recommendation logic.** The controller's next-step recommendations are
  unchanged.
- **Escalation rules.** `CLAUDE.md` escalation triggers are unchanged.
- **The orchestration model itself.** Controller and speedrun still orchestrate
  phase skills. This proposal only changes how they *invoke* those skills (by
  name instead of by file path + Read tool).

## Risks

### The agent might not find skills by name alone

If the runner doesn't properly index skills, the agent might not know how to
invoke a skill called "assess." Mitigation: test in ACP before merging. If the
skill tool doesn't resolve names reliably, we can add a mapping hint (e.g.,
"the `assess` skill at `assess/SKILL.md`") without prescribing the invocation
mechanism.

### The skill tool might handle context differently

When a skill is invoked via the skill tool (vs. read with the file tool), the
context management may differ — the skill's content might be scoped differently,
or the agent might not retain the orchestrator's context after the skill
completes. Mitigation: test the full controller flow end-to-end. If context
loss is an issue, we may need to keep a lighter version of the return guidance.

### Behavioral regression from removing dispatch blocks

The dispatch block served a secondary purpose: if a user invoked a phase skill
directly (e.g., by saying "/diagnose" without going through the controller), the
dispatch block redirected them to the controller first. Without it, a directly-
invoked skill will just execute without workflow context. This may actually be
fine — the skill still works standalone, and the controller is still available
if the user wants guided flow.

## Testing plan

1. **Validate JSON** — `ambient.json` parses correctly after edit
2. **Skill resolution** — Verify the agent can find and invoke each skill by
   name in ACP
3. **Full controller flow** — Run a bug fix from assess through PR using the
   controller, confirming phase transitions work without re-read instructions
4. **Speedrun flow** — Run a full speedrun and confirm it progresses through
   all phases
5. **Direct skill invocation** — Invoke a phase skill directly (e.g.,
   "/diagnose") and confirm it works standalone
6. **Edge cases** — Test the review → fix → test → review loop in speedrun
   mode; test `/summary` mid-workflow

## Decisions on open questions

1. **Skill names vs. slash-command names:** Use skill names — "the `assess`
   skill." Slash-command syntax might bias the agent toward looking for a
   command file instead of using the skill tool.

2. **Speedrun's phase table:** Remove file paths entirely; use only skill names.
   The agent shouldn't know where the files are — knowing paths encourages it
   to load files directly instead of using the skill tool. Keep the completion
   signals (artifact existence checks) in the table.

3. **README.md:** Leave as-is. The README is documentation for humans and agents
   that need to *modify* the workflow, which is a legitimate reason to know
   file paths and load files directly.

4. **Controller's "Always read skill files" rule:** Drop entirely. The
   controller already tells the agent when to run each skill as part of the
   phase execution flow. A separate general rule restating this is redundant
   and was really just reinforcing the Read-tool workaround.
