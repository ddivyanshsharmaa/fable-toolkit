---
name: trio
description: >-
  Three engine loop. Claude orchestrates, writes the spec, and reviews; Codex does precision coding
  and code or security audits; Antigravity (Gemini) does bulk work, long generation, and web
  research. Loops review and fix rounds until every acceptance criterion passes, then proves the
  assembled result works end to end. Usually reached through /team, which picks this loop on its
  own when both engines are signed in. Invoke directly when the user says "trio", "use codex and
  antigravity", or "full team on this".
---

# /trio, the three engine team loop

You (Claude, in this session) are the **orchestrator and reviewer**. You do not write the bulk
implementation. You write the spec, dispatch briefs to the other two engines, review their output
against primary evidence, loop fixes until the criteria pass, and then prove the assembled result
actually works.

All three engines run on subscriptions, so there is no per-call API key. But every dispatch spends
real quota, and a vague brief burns a whole round. Brief quality is the single biggest lever you
control.

Invoked directly rather than through **/team**? Run the preflight first:

```bash
bash "${CLAUDE_SKILL_DIR}/../team/scripts/preflight.sh"
```

If `FABLE_MODE` comes back as anything other than `trio`, switch to that loop (`duo-codex`,
`duo-gemini`, or `orchestrate` for `solo`) and tell the user why in one line. Never ask the user
which engines they have. Keep the `FABLE_AGY_*` model ids for the dispatches below.

## Use this when, and only when

Worth the overhead:

- The task splits into 2 or more units that can be worked on without seeing each other's output.
- The work is bulky (many files, long generation, a wide refactor) or needs sustained coding focus.
- You can write acceptance criteria a command can settle.

Not worth it, do it yourself instead:

- You could finish it in a handful of your own tool calls.
- Requirements are still fuzzy. Dispatching an unclear spec produces confident wrong work, and you
  pay for it twice.
- The task is one continuous judgment call, such as choosing an approach or reviewing a design.
- It touches credentials, production data, or anything irreversible. Briefs go to external services.

## Roles, fixed, do not blur them

| Engine | Command | Strength | Give it |
|---|---|---|---|
| **Claude (you)** | this session | judgment, verification | spec, decomposition, review, running the tests, final residual fixes only |
| **Codex** | `codex exec` | precision coding | features, refactors, bug fixes, tricky logic, real tests, code and security audits |
| **Antigravity** (Gemini) | `agy -p` | fast bulk work | boilerplate, docs, data transforms, long generated content, repetitive multi file edits, web research, content and SEO audits |

Assigning a unit is a judgment call, so use the signal, not the file count. Decide it yourself;
never ask the user which engine should take a unit.

| Signal in the unit | Send it to |
|---|---|
| Correctness is subtle, edge cases decide it | Codex |
| Must read existing code and match its patterns | Codex |
| Code review or security audit of a repository | Codex, with `--sandbox read-only` |
| Same mechanical change across many files | Antigravity, fast tier |
| Long generated prose, data, or config | Antigravity, heavy tier |
| Web research, competitor scan, SEO or content audit of public pages | Antigravity, fast tier |
| Reading or summarising many local files you name in the brief | Antigravity, fast tier |
| Needs a product decision or a taste call | Keep it yourself |
| You cannot write a checkable criterion for it | Keep it yourself |

## The loop

Spec, dispatch, review, fix, final gate, report. Steps 3 and 5 are where the value is. Everything
before them is setup for them.

### 0. Setup

- Create the run dir `<project>/.trio/<yyyyMMdd-HHmmss>/`. Every brief, engine output, and review
  verdict lands here, so the loop is auditable after the fact.
- If the project is a git repo, record `git rev-parse HEAD` and require a reasonably clean tree so
  review can lean on `git diff`. If it is not a repo, list the files that will change and copy them
  into the run dir as a snapshot so you can diff manually.
- Never run `git init` at your home directory level.
- Read the project's own agent instructions if they exist: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`,
  and the setup and deploy sections of the README. Anything a worker must respect (conventions,
  deploy steps, files that are off limits) goes into every brief's Project context. The engines
  start cold and do not reliably find these files themselves; Antigravity, for one, only reads an
  `AGENTS.md` at the root of a folder it was launched in or given with `--add-dir`.

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
that forbid the shortcut you expect an engine to take.

**Units and ownership.** Split the work so no unit needs another unit's output. For each unit
record its id, engine, goal, the criteria it owns, and its file list.

The collision rule: **every file has exactly one owning unit per round.** If two units both need a
file, merge them into one unit or run them in separate rounds. Two engines writing the same file in
parallel is the most expensive failure in this loop, because the review cannot tell you which write
survived, only that the result is wrong.

**Boundaries.** What must not be created, edited, or deleted by anyone.

### 2. Dispatch (parallel, background, through the Bash tool)

Each unit gets a cold start complete brief file in the run dir. The engine cannot see this
conversation, cannot ask a question, and will invent anything you leave out. Use this template:

```markdown
# Unit <id>: <one line goal>

## Project context
<two or three sentences: what this project is, what already works, why this unit exists, plus any
rule from the project's own CLAUDE.md or AGENTS.md that this unit must respect>

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

Codex (coding, may write inside the project):

```bash
codex exec -C "<project>" --sandbox workspace-write \
  -o "<rundir>/codex-u1-round1.md" \
  "$(cat "<rundir>/brief-u1.md")" </dev/null
```

Capture the `session id` line Codex prints and record it in the run dir. Fix rounds resume that
session, which preserves its context and is far better than starting cold.

For a code review or security audit, use `--sandbox read-only` so Codex cannot touch the tree, and
ask for every finding with its file and line.

Antigravity (bulk work; it ignores the shell's working directory, so `--add-dir` **and** absolute
paths inside the brief are both mandatory):

```bash
agy -p "$(cat "<rundir>/brief-u2.md")" \
  --model "<FABLE_AGY_FAST from the preflight>" --mode accept-edits \
  --add-dir "<project-abs-path>" \
  --print-timeout 15m </dev/null > "<rundir>/agy-u2-round1.md" 2>&1
```

Pick the model id from the preflight by what the unit needs: `FABLE_AGY_FAST` for bulk and
mechanical work (in September 2026 that is `gemini-3.8-flash-medium`), `FABLE_AGY_HEAVY` for long
generation (`gemini-3.8-flash-high`), and `FABLE_AGY_SMART` for logic and escalation
(`gemini-3.1-pro-high`). The preflight reads them live from `agy models`, so newer models are
picked up without editing this skill. The short id works in `--model` and avoids quoting trouble.

A research or audit unit that only reports findings does not need `--mode accept-edits`; its answer
lands in the output file. Antigravity searches the web and fetches pages on its own in this mode.

Dispatch all independent units **in the same message** as parallel background calls. While they
run, do not idle: build the review checklist, write the commands you will use for each criterion,
and check that any fixture or test data the review needs actually exists.

### 3. Review (you, and this is the point of the whole skill)

Never accept an engine's claim. For every criterion, gather primary evidence yourself and record it
in `review-roundN.md` as a table:

```
| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | <criterion text> | PASS | `npm test` exit 0, 14 passed, 0 skipped |
| 2 | <criterion text> | FAIL | `node export.js fixtures/sample.json` -> "TypeError: rows is not iterable" at export.js:31 |
```

Evidence means the command you ran and its decisive output, or the file and line you read. "The
engine said it works" is testimony, not evidence, and never fills that column.

Read the actual diff too, not just the test result. Look specifically for:

- A test that runs but asserts nothing, or asserts on a hardcoded value.
- A function that exists and is correct but was never wired into its caller.
- An edited file that was not in that unit's ownership list.
- A criterion quietly skipped while the report talks about the others.
- Generated content that holds format for the first few items and then drifts.
- An exception swallowed so a run exits 0.

### 4. Fix rounds

Any FAIL gets a fix brief that quotes the failed criterion and pastes **the evidence**, the real
error text or the wrong output. An engine cannot fix what it cannot see.

- Codex: `codex exec resume <session-id> "$(cat "<rundir>/fixbrief-u1.md")" </dev/null`
- Antigravity: a fresh `agy -p` call. There is no session resume, so the fix brief must carry the
  original brief's content plus the failures.

Escalate structurally, not by repetition:

| Round | If it still fails |
|---|---|
| 1 | Fix brief with evidence to the same engine and session. |
| 2 | Change something real. Move the Antigravity unit to the smart tier (`FABLE_AGY_SMART`), or split the Codex unit into two narrower briefs, or add the context the engine clearly lacked. Reassigning an Antigravity unit to Codex is fair game here. |
| 3 | Take it yourself and fix the residual. |
| after 3 | Report the criterion as failing. |

Never loosen a criterion to make it pass. If the criterion was wrong, say that explicitly in the
report and give the corrected one, rather than quietly editing the goalposts.

If the same unit fails twice for the same reason, the brief is the problem, not the engine. Rewrite
the brief with the missing context instead of resending it.

### 5. Final gate, you prove the whole thing works

**Mandatory, and it cannot be delegated to any engine.** Per unit reviews confirm each piece passed
in isolation. They say nothing about whether the assembled result works, and integration is exactly
where multi engine work breaks: two units that each passed can still disagree about a function
signature, a schema, or a path.

Run all six checks before you tell the user anything is done:

1. **Exercise the real flow end to end, from a clean state.** Start the app, run the script on real
   input, open the page in a browser, execute the CLI the way a user would. Not a unit test, not
   "the file was written".
2. **Re-run every acceptance criterion against the assembled deliverable**, not against the per unit
   output you already reviewed.
3. **Open every file the spec promised, at the exact path it named.** Existence is not correctness,
   and with Antigravity a file in its scratch directory reads as success in the transcript.
4. **Check the neighbours.** Run the surrounding tests or drive the adjacent flow to confirm nothing
   that already worked is now broken.
5. **Confirm the boundaries held.** `git status` and `git diff --stat`, or the manual snapshot diff,
   must show changes only in files the spec allowed. An engine editing an out of scope file is a
   finding even when every criterion passes.
6. **Re-read the outputs for silent shortfalls**, using the list in step 3 above.

If a check genuinely cannot be run, because of missing credentials, a missing environment, or a
browser you do not have, write **"written but not verified, because X"** in the report. Never round
an unrun check up to a pass, and never let "Codex reported it could not verify" stand in for your
own verification.

For high stakes or irreversible work, additionally spawn a `verifier` agent with the claim and the
paths but **not** your expected answer, then reconcile its verdict with yours before reporting.

### 6. Report

Outcome first, in prose. Cover:

- What was built and where it lives.
- Every criterion with its final verdict and the evidence that settled it.
- Rounds used per unit, and what each engine actually did.
- Anything NOT verified, with the reason. This section is mandatory and never empty by default.
- Anything you had to fix yourself after round 3, since that is a signal about the spec.
- One line naming which engine handled which units.

The user should not need to know how many dispatches ran or what the units were called.

## Quota economy

Each dispatch is real spend on a subscription, so:

- One dispatch per unit per round. No "just checking in" follow ups.
- Batch small related work into one unit rather than five tiny dispatches.
- Re-read a brief before sending it. Most wasted rounds trace to a missing path or an unstated
  convention, not to engine weakness.
- For a logic heavy unit, one smart tier dispatch usually beats three Flash retries.
- Never dispatch work you have not written a criterion for. You will not be able to tell whether it
  came back correct, which makes the spend worthless.

## Gotchas from real runs

- **Both CLIs hang forever unless stdin is closed.** Always append `</dev/null` and run them through
  the **Bash tool**. On Windows, PowerShell 5.1 has no `<` redirect, so the Bash tool is mandatory
  rather than a preference. This is the number one failure mode.
- Both need network. If a dispatch produces no output for about two minutes, it is probably running
  inside a sandboxed shell. Rerun it unsandboxed.
- `agy` print mode times out at 5m by default. Set `--print-timeout 15m` for real work, and longer
  for big generation jobs.
- `agy models` lists the models your account can use. The first column, the short id such as
  `gemini-3.8-flash-medium`, works in `--model`.
- **`agy -p` cannot run shell commands.** Headless mode auto denies anything that needs its
  `command` permission, and editing Antigravity's settings does not change that. It can still read
  and write files, search the web, and fetch pages. So run any command yourself first, save the
  output to files, name those files in the brief, and tell it not to run shell or terminal
  commands.
- `agy` sometimes writes its deliverable and then trips that permission error on a trailing self
  check. A log ending in the error is not proof of failure; check the output path first.
- `agy` needs `--mode accept-edits` to write files at all. Without it you get a plan, not a change.
- Redirect both streams from `agy` with `> file 2>&1`. Useful diagnostics go to stderr, and without
  it a silent failure looks identical to an empty success.
- `codex exec` flags worth knowing: `-C <dir>` sets the working dir, `--sandbox
  read-only|workspace-write`, `-o <file>` captures just the final message,
  `--skip-git-repo-check` for non repo dirs, and `resume <id>` or `--last` to continue a session.
- Codex's own sandbox often cannot run Python or your test suite, and it will honestly report that
  it could not verify. That is expected. Running the tests is your job as reviewer, not grounds for
  a fix round.
- On Windows, Codex can fail every command with `SetTokenInformation(TokenDefaultDacl) failed:
  1344` when its sandbox cannot start inside the calling shell. `--sandbox read-only` units still
  work. For a write unit that hits it, an untested but low risk fallback: run it read-only, ask for
  the change as a unified diff in the final message, and apply that diff yourself with `git apply`.
- Never put secrets or credentials in a brief. Briefs go to external services.
- Engines can silently do less than asked, skipping a file or stubbing a test. The review step
  exists because of this. Check every criterion, never a sample.
