---
name: orchestrate
description: >-
  Decompose a large task into parallel subagent work, run it, and synthesize verified results, the
  way a strong orchestrator model runs multi agent work. Use this whenever a task has multiple
  independent parts, spans many files or sites, needs research from several angles at once, or the
  user says "orchestrate", "use agents", "parallelize", "fan out", "do all of these", "run these in
  parallel", or asks for something big enough that one linear pass would be slow or sloppy. Also
  use when coordinating long running background work (builds, crawls, batch content generation).
---

# Orchestrate

Run multi part work through subagents the way an experienced orchestrator does: decompose by
independence, give each worker a complete cold start briefing, run everything in parallel, then
synthesise and *verify* before reporting.

## When not to orchestrate

Spawning is the expensive path. Each subagent starts with zero context and has to re-derive
everything you already know. If the task fits in a few of your own tool calls, do it inline.
Orchestrate only when:

- There are 2 or more genuinely independent workstreams (different files, different sites, different
  questions), or
- A workstream is long running and you can usefully do other work while it runs, or
- You need an *independent* opinion, such as verification or review, that your own context would
  bias.

A task with "multiple angles" is not automatically a multi agent task. Independence is the test, not
size.

## Step 1, decompose by independence

Split the task so that no subagent needs another subagent's output. Where B depends on A, either
keep both in one agent's prompt, or run A synchronously first and inline its result into B's prompt.
Never spawn A and B together hoping B can "check in later", because agents cannot see each other.

For each unit, write down before spawning:

- **Goal.** One sentence, outcome shaped ("produce X at path Y"), not activity shaped ("look into
  X").
- **Output contract.** The exact file path or report structure it must deliver. Ambiguous contracts
  are the number one cause of unusable agent output.
- **Boundaries.** What it must not touch or decide, for example "do not edit files outside
  src/posts/" or "report the problem, do not fix it".

## Step 2, write cold start prompts

The subagent knows nothing about this conversation. A good prompt includes:

1. Context in two or three sentences: what project, what is already true, why this task exists.
2. Exact absolute paths to every file or URL it needs. Never say "the config file", say
   `/home/you/projects/my-app/config.json`.
3. The goal and output contract from Step 1.
4. Constraints and non goals.
5. "Report honestly: if something failed or was skipped, say so explicitly with the error output."

Line 5 matters because agents drift optimistic. A worker that hit an error will often summarise
around it, so demanding failure disclosure in the prompt is cheap insurance.

## Step 3, spawn

- Launch all independent agents **in the same turn** so they run concurrently.
- Background them (the default) when you have other work or more spawns to do. Go synchronous
  (`run_in_background: false`) only when the very next step needs the result.
- Pick the most specific agent type available. Check the agent list in context for custom agents
  like `verifier`, `researcher`, `worker` and `critic`, and fall back to general-purpose.
- Use `isolation: "worktree"` when two agents will edit code in the same repo, so they cannot stomp
  each other.
- Do not poll. You are re-invoked when background agents finish. If you must wait on something
  external such as CI or a deploy, schedule the wait deliberately rather than spinning.

## Step 4, synthesise and verify

When results come back:

1. Read every result fully. The agent's final message is for *you*, and the user never saw it, so
   anything important has to be restated in your own report.
2. Reconcile conflicts between agents explicitly rather than averaging them away. If two workers
   disagree on a fact, that is a finding, not noise.
3. **Spot check claims before repeating them.** For each load bearing claim ("the file was created",
   "all 40 pages return 200", "tests pass"), verify the cheapest one or two yourself: read the file,
   run the command, fetch the URL. If a spot check fails, distrust that agent's whole report and
   re-verify or re-run it.
4. **Then verify the assembled result, not just the parts.** Every worker passing is not the same as
   the job working. Run the real flow end to end once, from a clean state, over the combined output:
   start the app, run the script, open the page, execute the CLI the way a user would. Integration is
   where parallel work breaks, because two workers that each succeeded can still disagree about a
   path, a schema, or a function signature. Also confirm the boundaries held (`git status` and
   `git diff --stat` should show changes only where the briefs allowed) and that nothing adjacent
   broke.
5. To continue a worker with a follow up, fix, or clarification, use SendMessage to the same agent,
   which keeps its context. Spawning a fresh agent for a follow up throws that context away.

Anything you could not exercise yourself gets reported as "written but not verified, because X". An
unrun check is never rounded up to a pass, and a worker's assurance never substitutes for your own
observation.

## Step 5, report

Lead with the outcome: what got produced and where, what is verified against what was merely
reported by workers, and what failed. One readable summary in complete sentences. The user should
not need to know how many agents ran or what they were named.

## Failure handling

- An agent that errored or returned garbage: fix the *prompt*, which usually means missing context
  or an ambiguous contract, rather than re-sending it verbatim.
- An agent that timed out mid work: check whether partial output landed at the contract path before
  re-running, because the work may be mostly done.
- If the same subtask fails twice with refined prompts, do it inline yourself. Orchestration has
  negative value there.
