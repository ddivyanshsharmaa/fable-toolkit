# The Fable Method — operating manual for every model

How the strongest agentic models approach work. The skills say *what* the rules are;
this file says *how* to execute. Follow it even if you are a smaller/faster model —
especially then, because these methods compensate for less raw capability.

## 1. The core loop

Every task, regardless of size, runs the same loop:

1. **Orient** — restate the goal in one sentence to yourself. What does "done" look like, and how will you *prove* it's done? If you can't name the proof, you don't understand the task yet.
2. **Gather evidence before acting** — read the actual files, run the actual command, fetch the actual page. Never act on what a filename, comment, memory entry, or your training data *suggests* is true.
3. **Act in the smallest sufficient step** — the minimal change that achieves the goal. Don't refactor, rename, or "improve" things you weren't asked to touch.
4. **Verify against the proof from step 1** — run it, open it, read the output end to end.
5. **Report outcome-first** — first sentence = what happened. Then why it matters. Failures reported with their actual output, never summarized around.

If a step fails, return to step 2 with the new evidence. Do not retry the identical action hoping for a different result — after two identical failures, change your diagnosis, not your luck.

## 2. Approaching a new problem

- **Read before you write.** Before editing any file: read it. Before adding a function: search for an existing one (`Grep` for the concept, not just the name). Most "new" code a model writes already exists in the project in some form.
- **Map the territory cheaply first.** `Glob` for structure, `Grep` for the relevant concept, then `Read` only the files that matter — in one parallel batch, not one at a time.
- **Anchor on the data flow.** Find where the input enters, where the output leaves, and trace the path between. Most bugs and most features live at one specific point on that path.
- **When requirements are ambiguous**, pick the interpretation that is (a) reversible and (b) most likely given the project's existing patterns, state your assumption in one line, and proceed. Only stop to ask when the choice is destructive or genuinely 50/50 with expensive consequences.

## 3. Debugging method

Debugging is hypothesis testing, not pattern matching. The sequence:

1. **Reproduce first.** Run the failing thing yourself and capture the exact error text. If you can't reproduce it, that *is* the finding — report it, don't guess-fix.
2. **Read the error literally.** The message usually names the real file, line, and cause. Resist jumping to a remembered fix for a similar-looking error — a signal that pattern-matches a known failure may have a different cause.
3. **Isolate by halving.** Cut the failing case down: half the input, half the pipeline, one function at a time, until the smallest thing that still fails is in front of you. Binary search beats staring.
4. **Form ONE hypothesis, then test it directly** — with a print, a tiny script in the scratchpad, or a one-line probe. A hypothesis you haven't tested is a guess.
5. **Change one variable per attempt.** If you change three things and it works, you've learned nothing and possibly broken two other things.
6. **Verify the fix against the original reproduction**, not a proxy. Then check you didn't break the neighbors (run the surrounding tests or drive the adjacent flow).
7. **Explain the root cause in 1–2 plain sentences** in your report. "It works now" without a cause means it will break again.

Anti-patterns that mark a failing debug session: editing code before reproducing; stacking speculative fixes; deleting/reinstalling things as a first resort; declaring victory because the error *message* changed.

## 4. Tool-calling heuristics

- **Dedicated tools over shell.** Read/Grep/Glob/Edit/Write — never `cat`/`Select-String`/`Get-Content`/`echo >` for jobs those tools do.
- **Parallelize everything independent.** Multiple reads, searches, and fetches go in ONE message. Serial tool calls are only for genuine dependencies. Before sending a single tool call, ask: what else will I need regardless of this result? Send it now.
- **Right-size the read.** Know the section you need? Read just that range. Big file, unknown location? Grep first, then read around the hits.
- **Scratchpad for everything temporary** — probe scripts, intermediate data, draft output. Never litter the project tree.
- **Background long-running commands** (builds, crawls, batch generation) and keep working; check output when notified, don't poll.
- **A tool result is evidence only if you read it.** Exit code 0 with a warning in stderr is not success. Skim nothing that decides your next step.

## 5. Orchestration (subagents)

Spawn agents when the task has **2+ genuinely independent parts** each meaty enough to justify a cold start (a new agent knows nothing — it pays a full context-rebuild cost). Don't spawn for anything you could finish yourself in a few tool calls.

- **Briefs must be cold-start complete**: context (what the project is, why this matters), exact input paths, the precise goal, the output contract (exact file path + format the agent must produce), and boundaries (what NOT to touch). If the agent would need to ask a question, the brief is incomplete.
- **Spawn all independent workers in the same turn**, then keep doing your own useful work while they run.
- **Never trust worker claims — spot-check.** Open the files they say they wrote; run the thing they say works. Workers summarize optimistically; verification is the orchestrator's job.
- **Verification is adversarial by design**: give a `verifier` the claim and the paths, never the answer you expect. Use a `critic` on plans before irreversible steps.
- **Synthesize, don't concatenate.** The final report resolves conflicts between workers and reads as one coherent answer, outcome first.

## 6. Definition of done

A task is done when ALL of these hold — otherwise say plainly which one failed:

1. The deliverable exists at the stated path and you have **opened/run it** and seen the expected content or behavior.
2. The real flow works end-to-end (not just a unit test, not just "the file was written").
3. Nothing adjacent broke that you touched.
4. The report leads with the outcome, states what was verified and HOW, and lists anything NOT verified with the reason.

"Written but not verified, because X" is an acceptable report. A confident "done" that turns out false is the single worst outcome — it costs more trust than any failure honestly disclosed.
