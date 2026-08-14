---
name: duo-codex
description: >-
  Run a task through the two engine loop where Claude orchestrates, writes the spec, and reviews,
  while Codex (`codex exec`) does all the implementation. Loops review and fix rounds until the
  result passes every acceptance criterion, then proves the assembled result works end to end. Use
  when the user says "duo codex", "claude and codex", "use codex for this", or "codex team". Pick
  this over /trio when no Antigravity or Gemini subscription is available.
---

# /duo-codex, the Claude and Codex loop

You (Claude, in this session) are the **orchestrator and reviewer**. Codex writes the code. You
write the spec, dispatch briefs, review output against primary evidence, loop fixes until the
criteria pass, and then prove the assembled result actually works.

Codex runs on a ChatGPT subscription, so there is no per-call API key. But every dispatch spends
real quota, and a vague brief burns a whole round. Brief quality is the single biggest lever you
control.

Have Antigravity too? Use **/trio** and hand the bulk work to Gemini, which is faster and cheaper
for boilerplate. Have only Antigravity? Use **/duo-gemini**.

## Use this when, and only when

Worth the overhead:

- The task splits into 2 or more units that can be worked on without seeing each other's output, or
  is one substantial coding job worth a dedicated session.
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
| **Codex** | `codex exec` | precision coding | every implementation unit: features, refactors, bug fixes, tricky logic, tests, boilerplate |

Codex is your only worker, so bulk and precision work both land on it. Split bulk into several
units rather than one giant brief: parallel sessions finish sooner, and a failed unit then costs
one narrow re-round instead of redoing everything.

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

### 1. Spec (you)

Write `spec.md` in the run dir with four sections.

**Goal.** One sentence, outcome shaped.

**Numbered acceptance criteria.** This is the entire quality gate. Each criterion must be settled
by a command you can run or an observation you can make. If you cannot name the command, the
criterion is not ready.

| Too vague to use | Checkable |
|---|---|
| "the CSV export works" | "`node export.js fixtures/sample.json` writes `out/report.csv` with 1 header row and 42 data rows" |
| "clean up the styles" | "no file under `src/` contains an inline `style=` attribute, and `npm run lint` exits 0" |
| "add tests" | "`npm test` passes, with at least one test per exported function in `src/parser.js`, and every test asserts on a return value" |
| "make it faster" | "`time node bench.js` reports under 400ms on the 10k row fixture, down from 2.1s" |

Note what the third example does: it blocks the stub test failure mode in advance. Write criteria
that forbid the shortcut you expect the engine to take.

**Units and ownership.** Split the work so no unit needs another unit's output. For each unit record
its id, goal, the criteria it owns, and its file list.

The collision rule: **every file has exactly one owning unit per round.** Two Codex sessions editing
the same file in parallel is the most expensive failure in this loop, because the review cannot tell
you which write survived, only that the result is wrong. If two units both need a file, merge them
into one unit or run them in separate rounds.

**Boundaries.** What must not be created, edited, or deleted by anyone.

### 2. Dispatch (parallel, background, through the Bash tool)

Each unit gets a cold start complete brief file in the run dir. Codex cannot see this conversation,
cannot ask a question, and will invent anything you leave out. Use this template:

```markdown
# Unit <id>: <one line goal>

## Project context
<two or three sentences: what this project is, what already works, why this unit exists>

## Stack and conventions
<language, framework, test runner, how to run things, style conventions to match>

## Files you own
<absolute paths this unit may create or edit>

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
<exact paths and formats to deliver, and what to put in your final message>

## Report honestly
If anything failed or you skipped it, say so explicitly and include the actual error text.
Do not summarise around a failure. A disclosed failure is cheap to fix; a hidden one is not.
```

```bash
codex exec -C "<project>" --sandbox workspace-write \
  -o "<rundir>/codex-u1-round1.md" \
  "$(cat "<rundir>/brief-u1.md")" </dev/null
```

- Capture the `session id` line Codex prints and record it in the run dir. Fix rounds resume that
  session, which preserves its context and is far better than starting cold.
- Dispatch all independent units **in the same message** as parallel background calls. While they
  run, build the review checklist and write the commands you will use for each criterion.
- For a read only unit, such as an audit or "find where X happens", use `--sandbox read-only` so it
  cannot touch the tree at all.

### 3. Review (you, and this is the point of the whole skill)

Never accept an engine's claim. For every criterion, gather primary evidence yourself and record it
in `review-roundN.md` as a table:

```
| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | <criterion text> | PASS | `npm test` exit 0, 14 passed, 0 skipped |
| 2 | <criterion text> | FAIL | `node export.js fixtures/sample.json` -> "TypeError: rows is not iterable" at export.js:31 |
```

Evidence means the command you ran and its decisive output, or the file and line you read. "Codex
said it works" is testimony, not evidence, and never fills that column.

Read the actual diff too, not just the test result. Look specifically for:

- A test that runs but asserts nothing, or asserts on a hardcoded value.
- A function that exists and is correct but was never wired into its caller.
- An edited file that was not in that unit's ownership list.
- A criterion quietly skipped while the report talks about the others.
- An exception swallowed so a run exits 0.

### 4. Fix rounds

Any FAIL gets a fix brief that quotes the failed criterion and pastes **the evidence**, the real
error text or the wrong output. An engine cannot fix what it cannot see.

```bash
codex exec resume <session-id> "$(cat "<rundir>/fixbrief-u1.md")" </dev/null
```

Escalate structurally, not by repetition:

| Round | If it still fails |
|---|---|
| 1 | Fix brief with evidence, resumed into the same session. |
| 2 | Change something real. Split the unit into two narrower briefs, or add the context the engine clearly lacked, or start a fresh session when the old one has gone down a bad path. |
| 3 | Take it yourself and fix the residual. |
| after 3 | Report the criterion as failing. |

Never loosen a criterion to make it pass. If the criterion was wrong, say that explicitly in the
report and give the corrected one, rather than quietly editing the goalposts.

If the same unit fails twice for the same reason, the brief is the problem, not the engine. Rewrite
the brief with the missing context instead of resending it.

### 5. Final gate, you prove the whole thing works

**Mandatory, and it cannot be delegated to Codex.** Per unit reviews confirm each piece passed in
isolation. They say nothing about whether the assembled result works, and integration is exactly
where parallel sessions break: two units that each passed can still disagree about a function
signature, a schema, or a path.

Run all six checks before you tell the user anything is done:

1. **Exercise the real flow end to end, from a clean state.** Start the app, run the script on real
   input, open the page in a browser, execute the CLI the way a user would. Not a unit test, not
   "the file was written".
2. **Re-run every acceptance criterion against the assembled deliverable**, not against the per unit
   output you already reviewed.
3. **Open every file the spec promised, at the exact path it named.** Existence is not correctness.
4. **Check the neighbours.** Run the surrounding tests or drive the adjacent flow to confirm nothing
   that already worked is now broken.
5. **Confirm the boundaries held.** `git status` and `git diff --stat`, or the manual snapshot diff,
   must show changes only in files the spec allowed. A session editing an out of scope file is a
   finding even when every criterion passes.
6. **Re-read the outputs for silent shortfalls**, using the list in step 3 above.

If a check genuinely cannot be run, because of missing credentials, a missing environment, or a
browser you do not have, write **"written but not verified, because X"** in the report. Never round
an unrun check up to a pass, and never let Codex's own "I could not verify this" stand in for your
verification.

For high stakes or irreversible work, additionally spawn a `verifier` agent with the claim and the
paths but **not** your expected answer, then reconcile its verdict with yours before reporting.

### 6. Report

Outcome first, in prose. Cover what was built and where, every criterion with its final verdict and
the evidence that settled it, rounds used per unit, anything NOT verified with the reason, and
anything you had to fix yourself after round 3, since that is a signal about the spec. The "not
verified" section is mandatory and never empty by default.

## Quota economy

Each dispatch is real spend on a subscription, so:

- One dispatch per unit per round. No "just checking in" follow ups.
- Batch small related work into one unit rather than five tiny dispatches.
- Re-read a brief before sending it. Most wasted rounds trace to a missing path or an unstated
  convention, not to engine weakness.
- Resume beats respawn. A resumed session already knows the codebase it just read.
- Never dispatch work you have not written a criterion for. You will not be able to tell whether it
  came back correct, which makes the spend worthless.

## Gotchas, all verified live

- **`codex exec` hangs forever unless stdin is closed.** Always append `</dev/null` and run it
  through the **Bash tool**. On Windows, PowerShell 5.1 has no `<` redirect, so the Bash tool is
  mandatory rather than a preference. This is the number one failure mode.
- It needs network. If a dispatch produces no output for about two minutes, it is probably running
  inside a sandboxed shell. Rerun it unsandboxed.
- Flags worth knowing: `-C <dir>` sets the working dir, `--sandbox read-only|workspace-write`,
  `-o <file>` captures just the final message, `--skip-git-repo-check` for non repo dirs, and
  `resume <id>` or `--last` to continue a session.
- Codex's own sandbox often cannot run Python or your test suite, and it will honestly report that
  it could not verify. That is expected. Running the tests is your job as reviewer, not grounds for
  a fix round.
- Never put secrets or credentials in a brief. Briefs go to an external service.
- Engines can silently do less than asked, skipping a file or stubbing a test. The review step
  exists because of this. Check every criterion, never a sample.
