---
name: duo-gemini
description: >-
  Two engine loop where Claude orchestrates, writes the spec, and reviews, while Antigravity
  (`agy -p`, Gemini models) does the implementation, bulk generation, web research, and content or
  SEO audits. Loops review and fix rounds until the result passes every acceptance criterion, then
  proves the assembled result works end to end. Usually reached through /team, which picks this
  loop on its own when Antigravity is signed in and Codex is not. Invoke directly when the user
  says "duo gemini", "claude and antigravity", "claude and agy", or "use gemini for this".
---

# /duo-gemini, the Claude and Antigravity loop

You (Claude, in this session) are the **orchestrator and reviewer**. Antigravity (Gemini) does the
implementation. You write the spec, dispatch briefs, review output against primary evidence, loop
fixes until the criteria pass, and then prove the assembled result actually works.

Antigravity runs on a Google subscription, so there is no per-call API key, and rounds are
comparatively cheap. Briefs still have to be complete: Gemini fills gaps with plausible invention
rather than stopping to ask, and a confident wrong answer costs more to detect than a refusal.

Invoked directly rather than through **/team**? Run the preflight first:

```bash
bash "${CLAUDE_SKILL_DIR}/../team/scripts/preflight.sh"
```

If `FABLE_MODE` comes back as anything other than `duo-gemini`, switch to that loop (`trio` when
Codex is also available for the tricky logic, `duo-codex`, or `orchestrate` for `solo`) and tell
the user why in one line. Never ask the user which engines they have. Keep the `FABLE_AGY_*` model
ids; the tiers below use them.

## Use this when, and only when

Worth the overhead:

- The task is bulky: many files, long generation, a wide mechanical refactor, a pile of docs.
- It splits into 2 or more units that can be worked on without seeing each other's output.
- You can write acceptance criteria a command can settle.

Not worth it, do it yourself instead:

- You could finish it in a handful of your own tool calls.
- Requirements are still fuzzy. Dispatching an unclear spec produces confident wrong work, and you
  pay for it twice.
- The task is one continuous judgment call, such as choosing an approach or reviewing a design.
- It touches credentials, production data, or anything irreversible. Briefs go to an external
  service.

## Roles, fixed, do not blur them

| Engine | Command | Strength | Give it |
|---|---|---|---|
| **Claude (you)** | this session | judgment, verification | spec, decomposition, review, running the tests, final residual fixes only |
| **Antigravity** (Gemini) | `agy -p` | fast bulk work, long generation | boilerplate, docs, data transforms, repetitive multi file edits, long generated content, web research, content and SEO audits |

**Model tiering matters more here than in /trio**, because Gemini is your only worker. The
preflight reads the tiers live from `agy models`, so newer models are picked up on their own:

| Tier | Preflight line | In September 2026 | Use for |
|---|---|---|---|
| Fast | `FABLE_AGY_FAST` | `gemini-3.8-flash-medium` | Default. Boilerplate, docs, mechanical edits, web research. |
| Heavy | `FABLE_AGY_HEAVY` | `gemini-3.8-flash-high` | Long generation, where drift and truncation are the risk. |
| Smart | `FABLE_AGY_SMART` | `gemini-3.1-pro-high` | Tricky logic, algorithms, subtle correctness, code or security review, and the escalation when a Flash unit fails twice. |

The short id goes straight into `--model`. Antigravity also offers Claude and GPT-OSS models; stay
on the Gemini tiers here, because Claude already orchestrates and reviews, and the point of the
team is a second model family's work.

Assign units yourself; never ask the user which tier or engine should take one. A code review or
security audit goes to the smart tier, and your own review pass then checks every finding against
the code.

Keep for yourself anything that needs a product decision, a taste call, or that you cannot write a
checkable criterion for.

## The loop

Spec, dispatch, review, fix, final gate, report. Steps 3 and 5 are where the value is. Everything
before them is setup for them.

### 0. Setup

- Create the run dir `<project>/.duo/<yyyyMMdd-HHmmss>/`. Every brief, engine output, and review
  verdict lands here, so the loop is auditable after the fact.
- If the project is a git repo, record `git rev-parse HEAD` and require a reasonably clean tree so
  review can lean on `git diff`. If it is not a repo, list the files that will change and copy them
  into the run dir as a snapshot so you can diff manually.
- Never run `git init` at your home directory level.
- Read the project's own agent instructions if they exist: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`,
  and the setup and deploy sections of the README. Anything a worker must respect (conventions,
  deploy steps, files that are off limits) goes into every brief's Project context. Antigravity
  only reads an `AGENTS.md` at the root of a folder it was launched in or given with `--add-dir`,
  so do not count on it finding the rest.
- If a unit needs the output of a shell command (a crawl, a test run, a `git log`, an API call),
  run it yourself now and save the output as files for the brief. Headless Antigravity cannot run
  shell commands.

### 1. Spec (you)

Write `spec.md` in the run dir with four sections.

**Goal.** One sentence, outcome shaped.

**Numbered acceptance criteria.** This is the entire quality gate. Each criterion must be settled
by a command you can run or an observation you can make. If you cannot name the command, the
criterion is not ready.

| Too vague to use | Checkable |
|---|---|
| "the CSV export works" | "`node export.js fixtures/sample.json` writes `out/report.csv` with 1 header row and 42 data rows" |
| "write the docs" | "every exported function in `src/api.js` has a matching `##` section in `docs/api.md`, and no section is under 40 words" |
| "add tests" | "`npm test` passes, with at least one test per exported function in `src/parser.js`, and every test asserts on a return value" |
| "convert the templates" | "all 38 files under `templates/` use the new `{{ }}` syntax, `grep -rc '<% ' templates/` returns 0, and `npm run build` exits 0" |

Notice what these do beyond stating the goal: they pin a count, forbid the shortcut, and name the
command. Gemini's characteristic failure is drifting off the pattern partway through a long job, so
criteria that pin a **count** are worth more here than anywhere else.

**Units and ownership.** Split the work so no unit needs another unit's output. For each unit record
its id, model tier, goal, the criteria it owns, and its file list.

The collision rule: **every file has exactly one owning unit per round.** Two parallel dispatches
writing the same file is the most expensive failure in this loop, because the review cannot tell you
which write survived, only that the result is wrong.

**Boundaries.** What must not be created, edited, or deleted by anyone.

### 2. Dispatch (parallel, background, through the Bash tool)

Each unit gets a cold start complete brief file in the run dir, with **absolute** paths throughout.
Gemini cannot see this conversation, cannot ask a question, and will invent anything you leave out.
Use this template:

```markdown
# Unit <id>: <one line goal>

## Project context
<two or three sentences: what this project is, what already works, why this unit exists, plus any
rule from the project's own CLAUDE.md or AGENTS.md that this unit must respect>

## Stack and conventions
<language, framework, test runner, how to run things, style conventions to match>

## Files you own
<ABSOLUTE paths this unit may create or edit>

## Files you must NOT touch
<absolute paths owned by other units, plus anything off limits>

## Goal
<outcome shaped: produce X at path Y with property Z>

## Acceptance criteria (copied verbatim from spec.md)
1. <criterion>
2. <criterion>

## How to check your own work
<the exact commands to run, and what output means pass>

## Output contract
<exact ABSOLUTE paths and formats to deliver, and what to put in your final message>

## Report honestly
If anything failed or you skipped it, say so explicitly and include the actual error text.
Do not summarise around a failure. A disclosed failure is cheap to fix; a hidden one is not.
```

```bash
agy -p "$(cat "<rundir>/brief-u1.md")" \
  --model "<FABLE_AGY_FAST, or the tier the unit needs>" --mode accept-edits \
  --add-dir "<project-abs-path>" \
  --print-timeout 15m </dev/null > "<rundir>/agy-u1-round1.md" 2>&1
```

A research or audit unit that only reports findings does not need `--mode accept-edits`; its answer
lands in the output file. Antigravity searches the web and fetches pages on its own in this mode.
Demand a source URL for every finding, and check at least three of them yourself in review.

**The single most common failure is files landing in the wrong place.** `agy` ignores the shell's
working directory. Without `--add-dir <project>` **and** absolute paths written inside the brief, it
writes into its own scratch directory and reports success anyway. Confirm the files exist at the
spec's paths before you review a single line of content.

Dispatch all independent units **in the same message** as parallel background calls. While they run,
build the review checklist and write the commands you will use for each criterion.

### 3. Review (you, and this is the point of the whole skill)

Never accept an engine's claim. For every criterion, gather primary evidence yourself and record it
in `review-roundN.md` as a table:

```
| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | <criterion text> | PASS | `grep -rc '<% ' templates/` returned 0 across 38 files |
| 2 | <criterion text> | FAIL | docs/api.md has 12 of 19 sections; parseQuery, formatRow and 5 others missing |
```

Evidence means the command you ran and its decisive output, or the file and line you read. "Gemini
said it works" is testimony, not evidence, and never fills that column.

Read the actual diff too, not just the summary. Gemini's characteristic misses, in order of how
often they bite:

- Files written to the scratch directory instead of the project.
- Output that holds the requested format for the first few items and then drifts.
- A file truncated part way through a long generation.
- An invented path, filename, or API that does not exist in the project.
- A plausible, correct looking function that was never wired into its caller.
- A test that runs but asserts nothing.

### 4. Fix rounds

Any FAIL gets a fix brief that quotes the failed criterion and pastes **the evidence**, the real
error text or the wrong output. There is no session resume, so the fix brief must carry the original
brief's full content plus the failures, then go out as a fresh `agy -p` call.

Escalate structurally, not by repetition:

| Round | If it still fails |
|---|---|
| 1 | Fix brief with evidence, fresh dispatch on the same tier. |
| 2 | Move the unit to the smart tier (`FABLE_AGY_SMART`), or split it into smaller units when the failure is drift or truncation rather than logic. |
| 3 | Take it yourself and fix the residual. |
| after 3 | Report the criterion as failing. |

Never loosen a criterion to make it pass. If the criterion was wrong, say that explicitly in the
report and give the corrected one, rather than quietly editing the goalposts.

If the same unit fails twice for the same reason, the brief is the problem, not the engine. Rewrite
the brief with the missing context instead of resending it.

### 5. Final gate, you prove the whole thing works

**Mandatory, and it cannot be delegated to Gemini.** Per unit reviews confirm each piece passed in
isolation. They say nothing about whether the assembled result works, and integration is exactly
where parallel dispatches break: two units that each passed can still disagree about a function
signature, a schema, or a path.

Run all six checks before you tell the user anything is done:

1. **Exercise the real flow end to end, from a clean state.** Start the app, run the script on real
   input, open the page in a browser, execute the CLI the way a user would. Not a unit test, not
   "the file was written".
2. **Re-run every acceptance criterion against the assembled deliverable**, not against the per unit
   output you already reviewed.
3. **Open every file the spec promised, at the exact absolute path it named.** With `agy` this is
   the highest yield check in the entire loop, because work that landed in the scratch directory
   reads as a complete success in the transcript.
4. **Check the neighbours.** Run the surrounding tests or drive the adjacent flow to confirm nothing
   that already worked is now broken.
5. **Confirm the boundaries held.** `git status` and `git diff --stat`, or the manual snapshot diff,
   must show changes only in files the spec allowed. Files created outside the boundary are a
   finding even when every criterion passes.
6. **Re-read the outputs for silent shortfalls**, using the list in step 3 above. On a long job,
   check the last item as carefully as the first, since drift shows up at the end.

If a check genuinely cannot be run, because of missing credentials, a missing environment, or a
browser you do not have, write **"written but not verified, because X"** in the report. Never round
an unrun check up to a pass.

For high stakes or irreversible work, additionally spawn a `verifier` agent with the claim and the
paths but **not** your expected answer, then reconcile its verdict with yours before reporting.

### 6. Report

Outcome first, in prose. Cover what was built and where, every criterion with its final verdict and
the evidence that settled it, rounds used and which model tier each unit ended on, anything NOT
verified with the reason, and anything you had to fix yourself after round 3, since that is a signal
about the spec. The "not verified" section is mandatory and never empty by default. Add one line
naming which units Antigravity handled and on which tier.

## Quota economy

Rounds are cheap here, but attention is not:

- One dispatch per unit per round. No "just checking in" follow ups.
- For a logic heavy unit, one smart tier dispatch usually beats three Flash retries.
- Split long generation jobs by count rather than pushing one huge brief. Drift and truncation both
  scale with output length.
- Never dispatch work you have not written a criterion for. You will not be able to tell whether it
  came back correct, which makes the round worthless.

## Gotchas from real runs

- **`agy` hangs forever unless stdin is closed.** Always append `</dev/null` and run it through the
  **Bash tool**. On Windows, PowerShell 5.1 has no `<` redirect, so the Bash tool is mandatory
  rather than a preference. This is the number one failure mode.
- It ignores the shell's working directory. `--add-dir <project>` plus absolute paths in the brief
  are both required, or output lands in the CLI's own scratch directory.
- Print mode times out at 5m by default. Set `--print-timeout 15m` for real work, and longer for big
  generation jobs.
- It needs network. If a dispatch produces no output for about two minutes, it is probably running
  inside a sandboxed shell. Rerun it unsandboxed.
- `--mode accept-edits` is what lets it write files. Without it you get a plan, not a change.
- **`agy -p` cannot run shell commands.** Headless mode auto denies anything that needs its
  `command` permission, and editing Antigravity's settings does not change that. It can still read
  and write files, search the web, and fetch pages. Stage command output as files, name them in the
  brief, and tell it not to run shell or terminal commands.
- It sometimes writes its deliverable and then trips that permission error on a trailing self check.
  A log ending in the error is not proof of failure; check the output path first.
- Redirect both streams with `> file 2>&1`. Useful diagnostics go to stderr, and without it a silent
  failure looks identical to an empty success.
- `agy models` lists the models your account can use. The first column, the short id, works in
  `--model`.
- Never put secrets or credentials in a brief. Briefs go to an external service.
- Engines can silently do less than asked, skipping a file or stubbing a test. The review step
  exists because of this. Check every criterion, never a sample.
