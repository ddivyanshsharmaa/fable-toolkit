---
name: trio
description: >-
  Run a task through the three-engine AI team — Claude orchestrates, writes specs, and reviews;
  Codex does the precision coding; Antigravity (Gemini) does heavy/bulk grunt work — looping
  review→fix rounds until the result passes all acceptance criteria. Use when the user says
  "trio", "ai team", "the team", "use codex and antigravity", "full team on this", or wants
  multiple AI engines collaborating on one job.
---

# /trio — the three-engine team loop

You (Claude, in this session) are the **orchestrator and reviewer**. You do not write
the bulk implementation. You write specs, dispatch work to the other two engines,
review their output against evidence, and loop fixes until quality passes.

All three engines run on subscriptions / free tiers — **no per-call API keys**. But each
dispatch costs real quota on those subscriptions, so briefs must be complete on the first
try (a vague brief = a wasted round).

Only have two of the three engines? Use **/duo-codex** (Claude + Codex) or **/duo-gemini**
(Claude + Antigravity) instead.

## Roles — fixed, don't blur them

| Engine | Command | Best at | Use for |
|---|---|---|---|
| **Claude (you)** | this session | judgment, verification | spec, decomposition, review, tests, final fixes only |
| **Codex** | `codex exec` | precision coding | features, refactors, bug fixes, tricky logic, tests |
| **Antigravity** (Gemini) | `agy -p` | fast bulk work | boilerplate, docs, data transforms, long generated content, repetitive multi-file edits |

Escalation: if an Antigravity unit fails review twice, redispatch it with
`--model "Gemini 3.1 Pro (High)"` (slower, smarter) or reassign it to Codex.

## Pipeline

### 0. Setup
- Run dir: `<project>/.trio/<yyyyMMdd-HHmmss>/` — every brief, output, and review verdict lands here so the loop is auditable.
- If the project is a git repo, record `git rev-parse HEAD` and require a clean-ish tree so review can use `git diff`. If not a repo, list the files that will change and snapshot them (copy to run dir) so you can diff manually. Never run `git init` at your home-directory level.

### 1. SPEC (you)
Write `spec.md` in the run dir:
- Goal in one sentence.
- **Numbered acceptance criteria** — each one objectively checkable by a command or observation. This is the quality gate; vague criteria make the loop spin forever.
- File boundaries: what may be created/edited, what must NOT be touched.
- Split into units: CODE units → Codex, GRUNT units → Antigravity. A unit that needs judgment or has fuzzy requirements stays with you.

### 2. DISPATCH (parallel, background, via the Bash tool)
Each unit gets a **cold-start-complete brief file** in the run dir: project context, exact paths, the goal, its acceptance criteria verbatim, output contract, boundaries. If the engine would need to ask a question, the brief is incomplete.

Codex (coding, may write inside the project):
```bash
codex exec -C "<project>" --sandbox workspace-write \
  -o "<rundir>/codex-u1-round1.md" \
  "$(cat "<rundir>/brief-u1.md")" </dev/null
```
Capture the `session id` line codex prints — fix rounds resume it.

Antigravity (grunt; **ignores the shell's cwd** — you MUST pass `--add-dir` AND put absolute target paths in the brief, or it writes to its own scratch dir):
```bash
agy -p "$(cat "<rundir>/brief-u2.md")" \
  --model "Gemini 3.5 Flash (Medium)" --mode accept-edits \
  --add-dir "<project-abs-path>" \
  --print-timeout 15m </dev/null > "<rundir>/agy-u2-round1.md" 2>&1
```

Independent units dispatch **in the same message** as parallel background calls. While they run, prepare the review checklist.

### 3. REVIEW (you — this is the whole point)
Never trust engine claims. For every acceptance criterion gather primary evidence:
- `git diff` (or manual diff) — read the actual changes, whole files if short.
- Run the tests / build / script; drive the real flow end to end.
- Verdict per criterion: **PASS / FAIL + evidence** (command output, line refs).
Write `review-roundN.md` in the run dir.

### 4. LOOP
- Any FAIL → write a fix brief quoting each failed criterion **with the evidence** (error text, wrong output), and send it back to the engine that owns the unit:
  - Codex: `codex exec resume <session-id> "$(cat fixbrief.md)" </dev/null` (keeps its context — much better than a fresh start).
  - Antigravity: fresh `agy -p` call with the fix brief (include the original brief content; agy rounds are cheap).
- Re-review. **Max 3 rounds per unit.** After round 3, fix small residuals yourself; if a criterion still can't pass, report it honestly as failing — never loosen the criterion to force a pass.

### 5. FINAL GATE — you prove the whole thing works

**This step is mandatory and cannot be delegated.** Per-unit reviews confirm that each piece
passed in isolation; they say nothing about whether the assembled result works. The engines'
reports are testimony. Your own observation is the only evidence. Before you tell the user
anything is done, run all six checks:

1. **Exercise the real flow end to end, from a clean state.** Start the app, run the script with
   real input, open the page in the browser, execute the CLI the way a user would. Not a unit
   test, not "the file was written".
2. **Re-run every acceptance criterion against the assembled deliverable**, not against the
   per-unit output you already reviewed. Integration is where multi-engine work breaks: two
   units that each passed can still disagree about a function signature, a schema, or a path.
3. **Open every file the spec promised** and confirm its content, at the exact path the spec
   named. Existence is not correctness.
4. **Check the neighbours.** Run the surrounding tests or drive the adjacent flow to confirm
   nothing that already worked is now broken.
5. **Confirm the boundaries held.** `git status` / `git diff --stat` (or the manual snapshot
   diff) must show changes only in files the spec allowed. An engine editing an out-of-scope
   file is a finding even when the criteria pass.
6. **Read the outputs for silent shortfalls** — a stubbed test that asserts nothing, a
   hardcoded return that satisfies the check, a generated list that drifts off format after the
   first few items, a truncated file.

If a check genuinely cannot be run (no credentials, no environment, needs a browser you don't
have), say **"written but not verified, because X"** in the report. Never round an unrun check
up to a pass, and never let "Codex said it couldn't verify" stand in for your own verification.

For high-stakes or irreversible work, additionally spawn a `verifier` agent with the claim and
the paths but **not** your expected answer, and reconcile its verdict with yours before
reporting.

Report outcome-first: what was built, rounds used, what each engine did, every criterion's final
verdict with the evidence that settled it, and an explicit list of anything NOT verified and why.

## Gotchas

- **Both CLIs hang forever without stdin closed.** Always append `</dev/null` and use the **Bash tool**. On Windows PowerShell 5.1 there is no `<` redirect, so the Bash tool is mandatory, not a preference. This is the #1 failure mode.
- Both need network — if a dispatch produces no output for ~2 min, it is likely running in a sandboxed shell; rerun without sandbox.
- `agy` print mode times out at 5m by default — set `--print-timeout 15m` for real work.
- `agy models` lists available models; names go verbatim in `--model` (e.g. `"Gemini 3.5 Flash (Medium)"`, `"Gemini 3.1 Pro (High)"`).
- `codex exec` flags: `-C <dir>` working dir, `--sandbox read-only|workspace-write`, `-o <file>` writes just the final message, `--skip-git-repo-check` for non-repo dirs, `resume <id>|--last` continues a session.
- `agy` ignores the shell's working directory: without `--add-dir <project>` + absolute paths in the brief, files land in the CLI's own scratch directory. Always check output landed where the spec says.
- Codex's own sandbox often can't run Python/tests — it will (honestly) report "couldn't verify". That's fine: running tests is YOUR job as reviewer, not grounds for a fix round.
- Never put secrets/credentials in briefs — they go to external services.
- Engines can silently do LESS than asked (skip a file, stub a test). The review step exists because of this; check every criterion, not a sample.
