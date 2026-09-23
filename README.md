# Fable Toolkit

Seven skills and four agents for [Claude Code](https://claude.com/claude-code) that push it toward
one behaviour: **finish the job, then prove it works.**

Most agent failures are not intelligence failures. They are process failures. The model stops
half way to ask a question nobody is there to answer, or it writes a file and calls that "done",
or it fans work out to subagents and repeats their optimistic summaries without checking any of
them. This toolkit is the process that closes those gaps, written as skills so Claude Code loads
it automatically when the situation calls for it.

It also turns Claude Code into the lead of an AI team. If you have **Codex** (OpenAI) or
**Antigravity** (Google) too, Claude hands them the parts they are best at, checks their work
against real evidence, and proves the assembled result works. You never have to say who does
what.

## Install in one line

**macOS, Linux, WSL, or Git Bash on Windows**

```bash
curl -fsSL https://raw.githubusercontent.com/ddivyanshsharmaa/fable-toolkit/main/install.sh | bash
```

**Windows PowerShell**

```powershell
irm https://raw.githubusercontent.com/ddivyanshsharmaa/fable-toolkit/main/install.ps1 | iex
```

The installer then:

1. Installs the skills and agents. On macOS and Linux it uses Claude Code's plugin system, so
   updates are one command, and falls back to copying files if that does not finish. On Windows it
   copies files, because Claude Code's plugin install from GitHub can fail there with a file lock.
2. Backs up anything it would replace, outside the skills folder, and leaves identical files alone,
   so running it again is always safe.
3. Asks three questions: do you use Claude Code, Codex, and Antigravity? Each one comes pre-filled
   with what it detected, so pressing Enter three times is enough. If you say yes to Codex and it is
   signed out, it offers to sign you in right there.
4. Saves your answers and shows exactly who will do what.

Already inside Claude Code on macOS or Linux? This works too:

```
/plugin marketplace add ddivyanshsharmaa/fable-toolkit
/plugin install fable-toolkit@fable-toolkit
```

The first time you use the team, it asks once whether you use Codex and Antigravity.

## Use it

Open Claude Code in any project and just ask:

```
use the team to add CSV export to the reports page, with tests
```

The `/team` skill takes it from there. It checks which of your engines are signed in, picks the
right loop, splits the work, dispatches each part to the engine that fits it, reviews every part
against evidence it gathers itself, fixes what fails, and runs the finished result end to end
before telling you it is done. It never asks who should do what.

## Who does what

Decided per task, automatically, from the engines you said you use:

| Work | Claude + Codex + Antigravity | Claude + Codex | Claude + Antigravity | Claude only |
|---|---|---|---|---|
| Planning, review, final checks | Claude | Claude | Claude | Claude |
| Coding and tricky logic | Codex | Codex | Antigravity, smart tier | Claude subagents |
| Code and security audits | Codex, read-only | Codex, read-only | Antigravity, smart tier, then Claude | Claude critic |
| Bulk edits, long generation | Antigravity | Codex | Antigravity | Claude subagents |
| Web research, SEO and content audits | Antigravity | Claude researcher | Antigravity | Claude researcher |

The loop behind each column is a skill of its own: `/trio`, `/duo-codex`, `/duo-gemini`, and
`/orchestrate`. `/team` picks the column for you.

## Your engine setup

Your answers are saved in `fable-toolkit.conf` inside your Claude Code config folder, and the
toolkit never changes that file on its own.

- **yes** means use that engine whenever it is signed in. If it is signed out or offline one day,
  that run goes without it and tells you so, and the engine is back the moment it is ready again.
- **no** means never use it, even if it is installed.

To change it, run the installer again, or tell Claude Code "reconfigure the team". After a
one-line install you can also run the script directly:

```bash
bash ~/.claude/skills/team/scripts/configure.sh                        # asks again
bash ~/.claude/skills/team/scripts/configure.sh --codex yes --agy no   # no questions
```

For unattended installs, answer in advance with `FABLE_TOOLKIT_CODEX=yes|no` and
`FABLE_TOOLKIT_AGY=yes|no` in front of the install command.

## Setup check

Every team run starts with a quick read-only check. It reports what it found and what would remove
friction, for example:

```
Codex CLI:     ready, codex-cli 0.155.1, model gpt-5.6-sol
Antigravity:   ready
               fast gemini-3.8-flash-medium, heavy gemini-3.8-flash-high, smart gemini-3.1-pro-high
Saved setup:   Codex yes, Antigravity yes
Team mode:     trio
Setup fixes:
  1. Let engine dispatches run without a permission prompt each time. In settings.json merge:
       "permissions": { "allow": [ "Bash(codex exec *)", "Bash(agy -p *)" ] }
```

Claude offers to apply settings fixes for you: it shows the exact change, backs up your
`settings.json`, merges without removing anything, and confirms the file still parses. On macOS,
Linux, and WSL2 with the Claude Code sandbox turned on, it also suggests
`"sandbox": { "excludedCommands": [ "codex *", "agy *" ] }`, since both CLIs need the network and
run sandboxes of their own. Sign-ins open a browser, so those stay yours to finish.

## Models

The check reads Antigravity's models live from `agy models`, so new releases are picked up without
an update to this toolkit. In September 2026 that gives:

| Engine | Model | Used for |
|---|---|---|
| Antigravity fast | `gemini-3.8-flash-medium` | bulk edits, docs, web research |
| Antigravity heavy | `gemini-3.8-flash-high` | long generation, where drift is the risk |
| Antigravity smart | `gemini-3.1-pro-high` | hard logic, security review, escalation after two failed rounds |
| Codex | whatever your Codex config names, for example `gpt-5.6-sol` | coding, audits |
| Claude | whatever you run Claude Code on | planning and review, where model quality pays off most |

## What is inside

### Skills

| Skill | What it does |
|---|---|
| `/team` | The one request entry point. Uses your saved engine setup, checks sign-ins, picks the loop, and assigns every part automatically. |
| `/trio` | Three engine loop: Claude specs and reviews, Codex codes and audits, Antigravity does bulk work and web research. |
| `/duo-codex` | Two engine loop when you have Codex but not Antigravity. |
| `/duo-gemini` | Two engine loop when you have Antigravity but not Codex, with model tiering between Flash and Pro. |
| `/orchestrate` | Claude only: decompose by independence, brief subagents, spot check their claims, verify the assembled result. |
| `/fable` | Operating mode for any substantial task: run to completion, act on reversible steps without asking, report outcome first, never claim done without evidence. |
| `/deep-check` | Evidence first verification with CONFIRMED, PLAUSIBLE, UNVERIFIED or REFUTED verdicts and a mandatory "not checked" list. |

With the plugin install the names carry a prefix, such as `/fable-toolkit:team`. Asking in plain
words works either way.

### Agents

Spawn these with the Agent tool, or let the loops pick them.

| Agent | What it is for |
|---|---|
| `verifier` | Independent evidence based checking. Give it the claim and the paths, never the answer you expect. |
| `researcher` | Multi source investigation. Returns cited findings, separates fact from inference, states confidence. |
| `worker` | One scoped implementation unit inside an orchestrated job. Needs a full brief. |
| `critic` | Adversarial attack on a plan, diff or conclusion before you commit to it. |

### FABLE-METHOD.md

An operating manual covering the core loop, debugging method, tool calling heuristics,
orchestration rules and a definition of done. It exists because smaller and faster models benefit
from it most, and they will not read a skill they were never told to invoke. The installer copies
it into your Claude Code folder; to load it into every session, add this line to your global
`CLAUDE.md`:

```markdown
@FABLE-METHOD.md
```

Keep it compact if you edit it, since it enters the context of every single session.

## How every loop runs

All the team loops share the same six step shape:

1. **Spec.** Claude writes numbered acceptance criteria, each one settled by a command it can run.
   A criterion like "add tests" invites a stub, while "at least one test per exported function,
   each asserting on a return value" forbids it in advance. It also reads the project's own
   `CLAUDE.md` or `AGENTS.md` and assigns file ownership, since two engines writing the same file in
   parallel is the most expensive failure in the loop.
2. **Dispatch.** Every unit gets a cold start complete brief: project context, conventions, files
   it owns, files it must not touch, criteria copied verbatim, how to check its own work, and a
   demand to report failures with their real error text.
3. **Review.** Claude gathers primary evidence per criterion and fills an evidence table with the
   command it ran and the output that settled it. "The engine said it works" never fills that column.
4. **Fix rounds.** Failures go back with the evidence attached. Round two changes something real (a
   stronger model tier, a split brief), round three Claude takes over, and after that the criterion
   is reported as failing rather than quietly loosened.
5. **Final gate.** Six mandatory checks over the assembled result: run the real flow end to end
   from a clean state, re-run every criterion against the whole thing, open every promised file at
   its exact path, run the neighbouring tests, confirm the boundaries held, and re-read for silent
   shortfalls.
6. **Report.** Outcome first, every criterion's verdict, which engine did which part, and a
   mandatory list of what was not verified and why.

Step 5 is the one that matters most, and it is the one agent workflows usually skip. Every unit
passing in isolation is not the same as the job working.

## Requirements

- Claude Code, signed in with whatever account you use (subscription, API key, or a cloud
  provider). Optional: the [Codex CLI](https://developers.openai.com/codex/cli) and the
  [Antigravity CLI](https://antigravity.google), signed in with your own accounts. Nothing here
  needs an API key, a server, or a paid service of its own, and nothing is tied to any one person's
  accounts: each machine uses whatever its own tools are signed into.
- On native Windows, [Git for Windows](https://git-scm.com/downloads/win) if you want Codex or
  Antigravity on the team. Claude Code treats it as optional, but engine dispatches must run
  through Git Bash because both CLIs wait forever unless stdin is closed, and PowerShell 5.1 cannot
  do that with `</dev/null`. Without it, the team runs with Claude alone and says so. WSL needs
  nothing extra.
- Tested in September 2026 on Windows 11 with Claude Code 2.1.257, Codex CLI 0.155.1, and the
  Antigravity CLI. The scripts are written for macOS (bash 3.2) and Linux too, but were not run on
  those systems for this release.

## Troubleshooting

- **`/plugin marketplace add` fails on Windows with "Failed to finalize marketplace cache" and
  EBUSY or EPERM.** Claude Code downloaded the repository but Windows would not let it rename the
  folder, which retries do not fix. Use the PowerShell one-liner above, which installs by copying
  files instead.
- **On Windows the team only ever uses Claude, even though you have Codex or Antigravity.** Git for
  Windows is probably missing, so Claude Code has no Bash tool to dispatch through. Install it from
  https://git-scm.com/downloads/win and restart Claude Code; your saved answers take over from there.
- **Codex suddenly reports you are signed out.** Run `codex login`. One cause seen in practice: an
  IDE extension signing in with the same OpenAI account can end the CLI's session. Signing the
  extension out, or using a separate account for it, avoids the tug of war.
- **A dispatch produces no output for minutes.** Either stdin was not closed (the loops always add
  `</dev/null`), or the CLI is running inside a sandbox without network. The setup check suggests
  the sandbox exclusion.
- **An engine you said yes to is not being used.** The setup check says why, usually a sign-in.
  Your saved setup stays as you left it, and the engine comes back once it is ready.

## Design notes

A few decisions that are load bearing, in case you fork this:

- **The user never assigns work.** `/team` decides per unit from the signal in the task and reports
  the split afterwards. The only question it asks is which engines you use, once.
- **Your engine setup is yours.** The toolkit reads it and never rewrites it. A missing engine is
  handled per run, out loud, not by quietly changing your choice.
- **Settings change only with consent,** with a backup first, and only by merging.
- **No skill pre-authorizes anything.** A skill that grants itself tools needs approval before it
  can even start, which silently blocks it in `claude -p` pipelines. Dispatches stop prompting
  through one permanent permission rule instead, which the setup check offers and you approve once.
- **Acceptance criteria are the whole quality gate.** Vague criteria make the fix loop spin
  forever, so the spec step refuses anything that cannot be settled by a command or an observation.
- **Three rounds, then honesty.** Loosening a criterion to force a green result is the failure mode
  this is guarding against.
- **Briefs never carry secrets.** The loops send briefs to external services, so credentials stay
  out of them. Anything that touches credentials, production data, or an irreversible action stays
  with Claude.
- **"Not checked" sections are mandatory.** Verifying the easy 80 percent and letting the reader
  assume 100 percent is the most common way verification lies.

## Contributing

Issues and pull requests are welcome, particularly new engine loops (a Cursor or Aider variant
would slot in cleanly), reports from macOS and Linux installs, and sharper acceptance criteria
patterns. See [CHANGELOG.md](CHANGELOG.md) for what changed in each release.

## Disclaimer

Not affiliated with, endorsed by, or produced by Anthropic, OpenAI or Google. "Claude Code",
"Codex" and "Antigravity" are the products of their respective owners, and this repository is
a set of markdown instructions and small scripts that drive them.

## License

MIT. See [LICENSE](LICENSE).
