# Fable Toolkit

Six skills and four agents for [Claude Code](https://claude.com/claude-code) that push it toward
one behaviour: **finish the job, then prove it works.**

Most agent failures are not intelligence failures. They are process failures. The model stops
half way to ask a question nobody is there to answer, or it writes a file and calls that "done",
or it fans work out to subagents and repeats their optimistic summaries without checking any of
them. This toolkit is the process that closes those gaps, written as skills so Claude Code loads
it automatically when the situation calls for it.

It also lets you hand implementation to **Codex** and **Antigravity (Gemini)** while Claude stays
the orchestrator and reviewer, if you happen to pay for those too.

## Install

As a plugin (recommended, keeps everything updatable):

```
/plugin marketplace add ddivyanshsharmaa/fable-toolkit
/plugin install fable-toolkit@fable-toolkit
```

Or manually, if you would rather own the files:

```bash
git clone https://github.com/ddivyanshsharmaa/fable-toolkit
cp -r fable-toolkit/skills/* ~/.claude/skills/
cp -r fable-toolkit/agents/* ~/.claude/agents/
```

On Windows PowerShell:

```powershell
git clone https://github.com/ddivyanshsharmaa/fable-toolkit
Copy-Item fable-toolkit\skills\* $HOME\.claude\skills\ -Recurse
Copy-Item fable-toolkit\agents\* $HOME\.claude\agents\ -Recurse
```

Nothing here needs an API key, a server, or a paid service. The engine loops need the relevant
CLI installed, and that is the only external dependency.

## What is inside

### Skills

| Skill | What it does |
|---|---|
| `/fable` | Operating mode for any substantial task: run to completion, act on reversible steps without asking, report outcome first, never claim done without evidence. Invoke it at the start of a big open ended job. |
| `/orchestrate` | Decompose work by independence, write cold start complete briefs, spawn subagents in parallel, then spot check their claims and verify the assembled result before reporting. |
| `/deep-check` | Evidence first verification. Restates a claim as something observable, picks the cheapest discriminating test, and returns CONFIRMED, PLAUSIBLE, UNVERIFIED or REFUTED with proof plus a mandatory "not checked" list. |
| `/trio` | Three engine loop: Claude specs and reviews, Codex does precision coding, Antigravity does bulk work. Loops review and fix rounds until every acceptance criterion passes. |
| `/duo-codex` | Two engine loop for a Codex subscription only. Claude specs and reviews, Codex implements. |
| `/duo-gemini` | Two engine loop for an Antigravity subscription only. Claude specs and reviews, Gemini implements, with model tiering between Flash and Pro. |

### Agents

Spawn these with the Agent tool, or let `/orchestrate` pick them.

| Agent | What it is for |
|---|---|
| `verifier` | Independent evidence based checking. Give it the claim and the paths, never the answer you expect. |
| `researcher` | Multi source investigation. Returns cited findings, separates fact from inference, states confidence. |
| `worker` | One scoped implementation unit inside an orchestrated job. Needs a full brief. |
| `critic` | Adversarial attack on a plan, diff or conclusion before you commit to it. |

### FABLE-METHOD.md

An operating manual covering the core loop, debugging method, tool calling heuristics,
orchestration rules and a definition of done. It exists because smaller and faster models benefit
from it most, and they will not read a skill they were never told to invoke.

To load it into every session, import it from your global `~/.claude/CLAUDE.md`:

```markdown
@FABLE-METHOD.md
```

Copy `FABLE-METHOD.md` next to that `CLAUDE.md` first. Keep it compact if you edit it, since it
enters the context of every single session.

## Which engine loop should I use

| You pay for | Use | Who writes the code |
|---|---|---|
| Claude + ChatGPT + Google | `/trio` | Codex for logic, Gemini for bulk |
| Claude + ChatGPT | `/duo-codex` | Codex |
| Claude + Google | `/duo-gemini` | Gemini, Flash for bulk and Pro for logic |
| Claude only | `/orchestrate` | Claude subagents |

All three loops share the same six step shape:

1. **Spec.** Claude writes numbered acceptance criteria, each one settled by a command it can run.
   The skill ships a table of vague versus checkable criteria, because a criterion like "add tests"
   invites a stub while "at least one test per exported function, each asserting on a return value"
   forbids it in advance. It also assigns file ownership, since two engines writing the same file in
   parallel is the most expensive failure in the loop.
2. **Dispatch.** Every unit gets a cold start complete brief, built from the template in the skill:
   project context, stack and conventions, files you own, files you must not touch, criteria copied
   verbatim, how to check your own work, and an explicit demand to report failures with their real
   error text. If the engine would need to ask a question, the brief is incomplete and the round is
   wasted.
3. **Review.** Claude gathers primary evidence per criterion and fills an evidence table with the
   command it ran and the output that settled it. "The engine said it works" never fills that column.
4. **Fix rounds.** Failures go back with the evidence attached. Escalation is structural rather than
   repetitive: round two changes the model tier or splits the brief, round three Claude takes over,
   and after that the criterion is reported as failing rather than quietly loosened.
5. **Final gate.** Six mandatory checks over the assembled result: run the real flow end to end from
   a clean state, re-run every criterion against the whole thing rather than the per unit output,
   open every promised file at its exact path, run the neighbouring tests, confirm the boundaries
   held, and re-read for silent shortfalls.
6. **Report.** Outcome first, with every criterion's verdict and a mandatory list of what was not
   verified and why.

Step 5 is the one that matters most, and it is the one agent workflows usually skip. Every unit
passing in isolation is not the same as the job working, and integration is exactly where multi
engine work breaks.

### Engine CLI requirements

- `/trio` and `/duo-codex` need the Codex CLI (`codex exec`) installed and signed in.
- `/trio` and `/duo-gemini` need the Antigravity CLI (`agy`) installed and signed in.
- Both CLIs hang forever unless stdin is closed. The skills always append `</dev/null` and run
  through a POSIX shell for that reason. On Windows this means the Bash tool, not PowerShell 5.1,
  which has no `<` redirect.

## Design notes

A few decisions that are load bearing, in case you fork this:

- **Acceptance criteria are the whole quality gate.** Vague criteria make the fix loop spin
  forever, so the spec step refuses anything that cannot be settled by a command or an
  observation.
- **Three rounds, then honesty.** After the third failed round the orchestrator fixes small
  residuals itself and reports whatever still fails. Loosening a criterion to force a green
  result is the failure mode this is guarding against.
- **Briefs never carry secrets.** The engine loops send briefs to external services, so
  credentials stay out of them.
- **"Not checked" sections are mandatory.** Verifying the easy 80 percent and letting the reader
  assume 100 percent is the most common way verification lies.

## Contributing

Issues and pull requests are welcome, particularly new engine loops (a Cursor or Aider variant
would slot in cleanly) and sharper acceptance criteria patterns.

## Disclaimer

Not affiliated with, endorsed by, or produced by Anthropic, OpenAI or Google. "Claude Code",
"Codex" and "Antigravity" are the products of their respective owners, and this repository is
just a set of markdown instructions that drive them.

## License

MIT. See [LICENSE](LICENSE).
