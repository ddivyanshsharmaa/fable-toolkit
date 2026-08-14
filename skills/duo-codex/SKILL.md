---
name: duo-codex
description: >-
  Run a task through the two-engine loop where Claude orchestrates, writes the spec, and reviews,
  while Codex (`codex exec`) does all the implementation — looping review→fix rounds until the
  result passes every acceptance criterion. Use when the user says "duo codex", "claude and
  codex", "use codex for this", "codex team", or wants Codex to do the coding with Claude
  reviewing. Pick this over /trio when there is no Antigravity/Gemini subscription available.
---

# /duo-codex — Claude + Codex loop

You (Claude, in this session) are the **orchestrator and reviewer**. Codex writes the code.
You write specs, dispatch briefs, review output against evidence, and loop fixes until the
acceptance criteria pass.

Codex runs on a ChatGPT subscription — **no per-call API key**, but each dispatch costs real
quota, so briefs must be complete on the first try. A vague brief is a wasted round.

Have Antigravity too? Use **/trio** instead and give the bulk work to Gemini, which is cheaper
and faster for boilerplate. Have only Antigravity? Use **/duo-gemini**.

## Roles — fixed, don't blur them

| Engine | Command | Best at | Use for |
|---|---|---|---|
| **Claude (you)** | this session | judgment, verification | spec, decomposition, review, running tests, final residual fixes only |
| **Codex** | `codex exec` | precision coding | every implementation unit: features, refactors, bug fixes, tricky logic, tests, boilerplate |

Because Codex is your only worker, bulk and precision work both land on it. Split bulk units
into separate dispatches rather than one giant brief: parallel sessions finish faster and a
failed unit only costs one re-round.

## Pipeline

### 0. Setup
- Run dir: `<project>/.duo/<yyyyMMdd-HHmmss>/` — every brief, output, and review verdict lands here so the loop is auditable.
- If the project is a git repo, record `git rev-parse HEAD` and require a clean-ish tree so review can use `git diff`. If not a repo, list the files that will change and snapshot them (copy to run dir) so you can diff manually. Never run `git init` at your home-directory level.

### 1. SPEC (you)
Write `spec.md` in the run dir:
- Goal in one sentence.
- **Numbered acceptance criteria** — each one objectively checkable by a command or observation. This is the quality gate; vague criteria make the loop spin forever.
- File boundaries: what may be created/edited, what must NOT be touched.
- Split into units that can run **without seeing each other's output**. Two Codex sessions editing the same file will collide — either give them disjoint files, or run them sequentially, or use one session for both.
- A unit that needs judgment or has fuzzy requirements stays with you.

### 2. DISPATCH (parallel, background, via the Bash tool)
Each unit gets a **cold-start-complete brief file** in the run dir: project context, exact paths, the goal, its acceptance criteria verbatim, output contract, boundaries. If Codex would need to ask a question, the brief is incomplete.

```bash
codex exec -C "<project>" --sandbox workspace-write \
  -o "<rundir>/codex-u1-round1.md" \
  "$(cat "<rundir>/brief-u1.md")" </dev/null
```

- Capture the `session id` line codex prints — fix rounds resume it, which preserves its context and is far better than a fresh start.
- Independent units dispatch **in the same message** as parallel background calls. While they run, prepare the review checklist.
- For a read-only investigation unit (audit, "find where X happens"), use `--sandbox read-only` so it cannot touch the tree.

### 3. REVIEW (you — this is the whole point)
Never trust engine claims. For every acceptance criterion gather primary evidence:
- `git diff` (or manual diff) — read the actual changes, whole files if short.
- Run the tests / build / script; drive the real flow end to end.
- Verdict per criterion: **PASS / FAIL + evidence** (command output, line refs).
Write `review-roundN.md` in the run dir.

Watch specifically for: a stubbed test that asserts nothing, an edited file that was not in the brief, a criterion silently skipped, and "I could not verify" being read as "it works".

### 4. LOOP
- Any FAIL → write a fix brief quoting each failed criterion **with the evidence** (error text, wrong output), then resume the owning session:
```bash
codex exec resume <session-id> "$(cat "<rundir>/fixbrief-u1.md")" </dev/null
```
- Re-review. **Max 3 rounds per unit.** After round 3, fix small residuals yourself; if a criterion still can't pass, report it honestly as failing — never loosen the criterion to force a pass.
- If the same unit fails twice for the same reason, the brief is the problem, not the engine. Rewrite the brief with the missing context instead of repeating it.

### 5. FINAL GATE — you prove the whole thing works

**This step is mandatory and cannot be delegated.** Per-unit reviews confirm that each piece
passed in isolation; they say nothing about whether the assembled result works. Codex's report
is testimony. Your own observation is the only evidence. Before you tell the user anything is
done, run all six checks:

1. **Exercise the real flow end to end, from a clean state.** Start the app, run the script with
   real input, open the page in the browser, execute the CLI the way a user would. Not a unit
   test, not "the file was written".
2. **Re-run every acceptance criterion against the assembled deliverable**, not against the
   per-unit output you already reviewed. Integration is where parallel sessions break: two units
   that each passed can still disagree about a function signature, a schema, or a path.
3. **Open every file the spec promised** and confirm its content, at the exact path the spec
   named. Existence is not correctness.
4. **Check the neighbours.** Run the surrounding tests or drive the adjacent flow to confirm
   nothing that already worked is now broken.
5. **Confirm the boundaries held.** `git status` / `git diff --stat` (or the manual snapshot
   diff) must show changes only in files the spec allowed. A session editing an out-of-scope
   file is a finding even when the criteria pass.
6. **Read the outputs for silent shortfalls** — a stubbed test that asserts nothing, a hardcoded
   return that satisfies the check, an exception swallowed to make a run go green.

If a check genuinely cannot be run (no credentials, no environment, needs a browser you don't
have), say **"written but not verified, because X"** in the report. Never round an unrun check
up to a pass, and never let Codex's own "I couldn't verify this" stand in for your verification.

For high-stakes or irreversible work, additionally spawn a `verifier` agent with the claim and
the paths but **not** your expected answer, and reconcile its verdict with yours before
reporting.

Report outcome-first: what was built, rounds used, every criterion's final verdict with the
evidence that settled it, and an explicit list of anything NOT verified and why.

## Gotchas

- **`codex exec` hangs forever without stdin closed.** Always append `</dev/null` and use the **Bash tool**. On Windows PowerShell 5.1 there is no `<` redirect, so the Bash tool is mandatory, not a preference. This is the #1 failure mode.
- Needs network — if a dispatch produces no output for ~2 min, it is likely running in a sandboxed shell; rerun without sandbox.
- Flags worth knowing: `-C <dir>` working dir, `--sandbox read-only|workspace-write`, `-o <file>` writes just the final message, `--skip-git-repo-check` for non-repo dirs, `resume <id>|--last` continues a session.
- Codex's own sandbox often can't run Python/tests — it will (honestly) report "couldn't verify". That's fine: running tests is YOUR job as reviewer, not grounds for a fix round.
- Never put secrets/credentials in briefs — they go to an external service.
- Engines can silently do LESS than asked (skip a file, stub a test). The review step exists because of this; check every criterion, not a sample.
