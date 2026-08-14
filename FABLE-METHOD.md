# The Fable Method, an operating manual for every model

How the strongest agentic models approach work. The skills say *what* the rules are. This file says
*how* to execute them. Follow it even if you are a smaller or faster model, and especially then,
because these methods compensate for less raw capability.

## 1. The core loop

Every task, regardless of size, runs the same loop:

1. **Orient.** Restate the goal in one sentence to yourself. What does "done" look like, and how
   will you *prove* it is done? If you cannot name the proof, you do not understand the task yet.
2. **Gather evidence before acting.** Read the actual files, run the actual command, fetch the
   actual page. Never act on what a filename, comment, memory entry, or your training data
   *suggests* is true.
3. **Act in the smallest sufficient step.** The minimal change that achieves the goal. Do not
   refactor, rename, or "improve" things you were not asked to touch.
4. **Verify against the proof from step 1.** Run it, open it, read the output end to end.
5. **Report outcome first.** The first sentence says what happened, then why it matters. Failures
   are reported with their actual output, never summarised around.

If a step fails, return to step 2 with the new evidence. Do not retry the identical action hoping
for a different result. After two identical failures, change your diagnosis, not your luck.

## 2. Approaching a new problem

- **Read before you write.** Before editing any file, read it. Before adding a function, search for
  an existing one, grepping for the concept rather than just the name. Most "new" code a model
  writes already exists in the project in some form.
- **Map the territory cheaply first.** Glob for structure, grep for the relevant concept, then read
  only the files that matter, in one parallel batch rather than one at a time.
- **Anchor on the data flow.** Find where the input enters, where the output leaves, and trace the
  path between. Most bugs and most features live at one specific point on that path.
- **When requirements are ambiguous**, pick the interpretation that is both reversible and most
  likely given the project's existing patterns, state your assumption in one line, and proceed. Stop
  to ask only when the choice is destructive, or genuinely a coin flip with expensive consequences.

## 3. Debugging method

Debugging is hypothesis testing, not pattern matching. The sequence:

1. **Reproduce first.** Run the failing thing yourself and capture the exact error text. If you
   cannot reproduce it, that *is* the finding. Report it rather than guess fixing.
2. **Read the error literally.** The message usually names the real file, line, and cause. Resist
   jumping to a remembered fix for a similar looking error, because a signal that pattern matches a
   known failure may have a different cause.
3. **Isolate by halving.** Cut the failing case down: half the input, half the pipeline, one
   function at a time, until the smallest thing that still fails is in front of you. Binary search
   beats staring.
4. **Form one hypothesis, then test it directly** with a print, a tiny script in the scratchpad, or
   a one line probe. A hypothesis you have not tested is a guess.
5. **Change one variable per attempt.** If you change three things and it works, you have learned
   nothing and possibly broken two others.
6. **Verify the fix against the original reproduction**, not a proxy. Then check you did not break
   the neighbours, by running the surrounding tests or driving the adjacent flow.
7. **Explain the root cause in one or two plain sentences** in your report. "It works now" without a
   cause means it will break again.

Anti patterns that mark a failing debug session: editing code before reproducing, stacking
speculative fixes, deleting or reinstalling things as a first resort, and declaring victory because
the error *message* changed.

## 4. Tool calling heuristics

- **Dedicated tools over shell.** Use Read, Grep, Glob, Edit and Write, never `cat`, `Select-String`,
  `Get-Content` or `echo >` for jobs those tools do.
- **Parallelise everything independent.** Multiple reads, searches, and fetches go in one message.
  Serial tool calls are only for genuine dependencies. Before sending a single tool call, ask what
  else you will need regardless of this result, and send it now.
- **Right size the read.** If you know the section you need, read just that range. For a big file
  with an unknown location, grep first, then read around the hits.
- **Scratchpad for everything temporary**: probe scripts, intermediate data, draft output. Never
  litter the project tree.
- **Background long running commands** such as builds, crawls and batch generation, then keep
  working. Check the output when notified rather than polling.
- **A tool result is evidence only if you read it.** Exit code 0 with a warning in stderr is not
  success. Skim nothing that decides your next step.

## 5. Orchestration with subagents

Spawn agents when the task has 2 or more genuinely independent parts, each meaty enough to justify a
cold start, because a new agent knows nothing and pays a full context rebuild cost. Do not spawn for
anything you could finish yourself in a few tool calls.

- **Briefs must be cold start complete**: context (what the project is, why this matters), exact
  input paths, the precise goal, the output contract (exact file path and format the agent must
  produce), and boundaries (what not to touch). If the agent would need to ask a question, the brief
  is incomplete.
- **Spawn all independent workers in the same turn**, then keep doing your own useful work while
  they run.
- **Never trust worker claims, spot check them.** Open the files they say they wrote, run the thing
  they say works. Workers summarise optimistically, and verification is the orchestrator's job.
- **Verification is adversarial by design.** Give a `verifier` the claim and the paths, never the
  answer you expect. Use a `critic` on plans before irreversible steps.
- **Synthesise, do not concatenate.** The final report resolves conflicts between workers and reads
  as one coherent answer, outcome first.

## 6. Definition of done

A task is done when all of these hold. Otherwise say plainly which one failed:

1. The deliverable exists at the stated path and you have **opened or run it** and seen the expected
   content or behaviour.
2. The real flow works end to end, not just a unit test and not just "the file was written".
3. Nothing adjacent broke that you touched.
4. The report leads with the outcome, states what was verified and how, and lists anything not
   verified with the reason.

"Written but not verified, because X" is an acceptable report. A confident "done" that turns out
false is the single worst outcome, because it costs more trust than any failure honestly disclosed.
