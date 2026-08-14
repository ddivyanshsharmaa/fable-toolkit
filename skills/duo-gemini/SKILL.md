---
name: duo-gemini
description: >-
  Run a task through the two-engine loop where Claude orchestrates, writes the spec, and reviews,
  while Antigravity (`agy -p`, Gemini models) does all the implementation and bulk generation —
  looping review→fix rounds until the result passes every acceptance criterion. Use when the user
  says "duo gemini", "claude and antigravity", "claude and agy", "use gemini for this", or wants
  Gemini doing the work with Claude reviewing. Pick this over /trio when there is no Codex
  subscription available.
---

# /duo-gemini — Claude + Antigravity loop

You (Claude, in this session) are the **orchestrator and reviewer**. Antigravity (Gemini)
does the implementation. You write specs, dispatch briefs, review output against evidence,
and loop fixes until the acceptance criteria pass.

Antigravity runs on a Google subscription — **no per-call API key**, and rounds are comparatively
cheap, so a fix round costs little. Briefs still need to be complete: Gemini fills gaps with
plausible invention rather than stopping to ask.

Have Codex too? Use **/trio** and send the tricky logic to Codex while Gemini takes bulk work.
Have only Codex? Use **/duo-codex**.

## Roles — fixed, don't blur them

| Engine | Command | Best at | Use for |
|---|---|---|---|
| **Claude (you)** | this session | judgment, verification | spec, decomposition, review, running tests, final residual fixes only |
| **Antigravity** (Gemini) | `agy -p` | fast bulk work, long generation | boilerplate, docs, data transforms, repetitive multi-file edits, long generated content |

**Model tiering matters more here than in /trio**, because Gemini is your only worker:

- `"Gemini 3.5 Flash (Medium)"` — default. Boilerplate, docs, mechanical edits, content generation.
- `"Gemini 3.1 Pro (High)"` — slower and smarter. Use up front for tricky logic, algorithms, and anything with subtle correctness requirements; and as the escalation when a Flash unit fails review twice.

Run `agy models` to confirm the exact names available to you; they go verbatim into `--model`.

## Pipeline

### 0. Setup
- Run dir: `<project>/.duo/<yyyyMMdd-HHmmss>/` — every brief, output, and review verdict lands here so the loop is auditable.
- If the project is a git repo, record `git rev-parse HEAD` and require a clean-ish tree so review can use `git diff`. If not a repo, list the files that will change and snapshot them (copy to run dir) so you can diff manually. Never run `git init` at your home-directory level.

### 1. SPEC (you)
Write `spec.md` in the run dir:
- Goal in one sentence.
- **Numbered acceptance criteria** — each one objectively checkable by a command or observation. This is the quality gate; vague criteria make the loop spin forever.
- File boundaries: what may be created/edited, what must NOT be touched.
- Split into units, tagging each with its model tier (Flash for bulk, Pro for logic). Keep units disjoint by file so parallel dispatches cannot collide.
- A unit that needs judgment or has fuzzy requirements stays with you.

### 2. DISPATCH (parallel, background, via the Bash tool)
Each unit gets a **cold-start-complete brief file** in the run dir: project context, **absolute** paths, the goal, its acceptance criteria verbatim, output contract, boundaries.

```bash
agy -p "$(cat "<rundir>/brief-u1.md")" \
  --model "Gemini 3.5 Flash (Medium)" --mode accept-edits \
  --add-dir "<project-abs-path>" \
  --print-timeout 15m </dev/null > "<rundir>/agy-u1-round1.md" 2>&1
```

**The single most common failure: files landing in the wrong place.** `agy` ignores the shell's
working directory. Without `--add-dir <project>` *and* absolute paths written inside the brief,
it writes into its own scratch directory and reports success. Always confirm the files exist at
the spec's paths before reviewing content.

Independent units dispatch **in the same message** as parallel background calls. While they run, prepare the review checklist.

### 3. REVIEW (you — this is the whole point)
Never trust engine claims. For every acceptance criterion gather primary evidence:
- Confirm the files exist at the paths the spec named (not in a scratch dir).
- `git diff` (or manual diff) — read the actual changes, whole files if short.
- Run the tests / build / script; drive the real flow end to end.
- Verdict per criterion: **PASS / FAIL + evidence** (command output, line refs).
Write `review-roundN.md` in the run dir.

Watch specifically for Gemini's characteristic misses: invented file paths, a plausible-looking function that was never wired into the caller, generated content that drifts off the requested format after the first few items, and truncation on long outputs.

### 4. LOOP
- Any FAIL → write a fix brief quoting each failed criterion **with the evidence** (error text, wrong output), then dispatch a **fresh** `agy -p` call. There is no session resume, so the fix brief must include the original brief's content plus the failures.
- Escalate to `--model "Gemini 3.1 Pro (High)"` for a unit that failed twice, before spending a third Flash round.
- Re-review. **Max 3 rounds per unit.** After round 3, fix small residuals yourself; if a criterion still can't pass, report it honestly as failing — never loosen the criterion to force a pass.

### 5. FINAL GATE — you prove the whole thing works

**This step is mandatory and cannot be delegated.** Per-unit reviews confirm that each piece
passed in isolation; they say nothing about whether the assembled result works. Gemini's report
is testimony, and it is the most optimistic of the engines. Your own observation is the only
evidence. Before you tell the user anything is done, run all six checks:

1. **Exercise the real flow end to end, from a clean state.** Start the app, run the script with
   real input, open the page in the browser, execute the CLI the way a user would. Not a unit
   test, not "the file was written".
2. **Re-run every acceptance criterion against the assembled deliverable**, not against the
   per-unit output you already reviewed. Integration is where parallel dispatches break: two
   units that each passed can still disagree about a function signature, a schema, or a path.
3. **Open every file the spec promised, at the exact absolute path the spec named.** With `agy`
   this is the highest-yield check in the whole loop: work that landed in the scratch directory
   reads as a complete success in the transcript.
4. **Check the neighbours.** Run the surrounding tests or drive the adjacent flow to confirm
   nothing that already worked is now broken.
5. **Confirm the boundaries held.** `git status` / `git diff --stat` (or the manual snapshot
   diff) must show changes only in files the spec allowed. Files created outside the boundary
   are a finding even when the criteria pass.
6. **Read the outputs for silent shortfalls** — a plausible function never wired into its caller,
   an invented path, generated content that drifts off format after the first few items, a file
   truncated mid-way, a stubbed test that asserts nothing.

If a check genuinely cannot be run (no credentials, no environment, needs a browser you don't
have), say **"written but not verified, because X"** in the report. Never round an unrun check
up to a pass.

For high-stakes or irreversible work, additionally spawn a `verifier` agent with the claim and
the paths but **not** your expected answer, and reconcile its verdict with yours before
reporting.

Report outcome-first: what was built, rounds used, which model tier each unit ended on, every
criterion's final verdict with the evidence that settled it, and an explicit list of anything NOT
verified and why.

## Gotchas

- **`agy` hangs forever without stdin closed.** Always append `</dev/null` and use the **Bash tool**. On Windows PowerShell 5.1 there is no `<` redirect, so the Bash tool is mandatory, not a preference. This is the #1 failure mode.
- Print mode times out at 5m by default — set `--print-timeout 15m` for real work, longer for big generation jobs.
- Needs network — if a dispatch produces no output for ~2 min, it is likely running in a sandboxed shell; rerun without sandbox.
- `--mode accept-edits` lets it write files. Without it you get a plan, not a change.
- Redirect both streams (`> file 2>&1`): `agy` puts useful diagnostics on stderr, and a silent failure looks identical to an empty success otherwise.
- Never put secrets/credentials in briefs — they go to an external service.
- Engines can silently do LESS than asked (skip a file, stub a test). The review step exists because of this; check every criterion, not a sample.
