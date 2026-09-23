---
name: team
description: >-
  Hand a task to the AI team with one request. Uses the engines the user said they have (Claude
  Code, the Codex CLI, the Antigravity CLI), checks they are signed in, then runs the right loop
  and assigns every part automatically: Claude plans and verifies, Codex takes precise coding and
  code or security audits, Antigravity takes bulk generation, web research, and content or SEO
  audits. Never asks who should do what. Use when the user says "use the team", "ai team", "the
  team", "delegate this", "get Codex or Antigravity on this", "full team", "reconfigure the team",
  or hands over a big job with several parts.
---

# /team, one request, the right engines, automatically

The user should never need to know which engine does what. In this skill you find out what is
available, fix or flag anything in the way, pick the loop, assign every unit to the engine that
fits it, and prove the assembled result works.

Small job? If you could finish it in a handful of your own tool calls, just do it and skip the
team. The team pays off when work splits into parts, runs long, or needs a second model's
precision.

## Step 1. Preflight, once per session

Run the bundled check through the Bash tool:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh"
```

It only reads, never changes anything, and takes a few seconds (up to a minute when Antigravity
is slow to list its models). The report ends with machine readable lines:

| Line | Values |
|---|---|
| `FABLE_MODE` | `trio`, `duo-codex`, `duo-gemini`, or `solo` |
| `FABLE_CODEX`, `FABLE_AGY` | `ready`, `not-signed-in`, `unreachable`, `missing`, or `off` (the user's saved setup says not to use it) |
| `FABLE_AGY_FAST` | Antigravity model id for bulk and mechanical work |
| `FABLE_AGY_HEAVY` | model id for long generation, where drift and truncation are the risk |
| `FABLE_AGY_SMART` | model id for hard logic, security review, and escalation |
| `FABLE_CONFIGURED` | `yes` when the user has saved which engines they use, `no` otherwise |
| `FABLE_FIXES` | how many setup fixes the report recommends |

If there is no Bash tool (native Windows without Git for Windows, where Claude Code runs PowerShell
instead), the Codex and Antigravity loops cannot run: both CLIs wait forever unless stdin is closed
with `</dev/null`, which PowerShell 5.1 cannot do. Run the job in `solo` mode with `orchestrate`,
and tell the user once: install Git for Windows (https://git-scm.com/downloads/win) and restart
Claude Code, and their saved engines take over from then on. Do not change the saved setup.

**The saved setup is the user's decision, and you never change it on your own.** It lives in
`fable-toolkit.conf` in the Claude Code config folder, written by the installer or by
`configure.sh`. An engine set to `no` is never used, even when installed. An engine set to `yes`
that is not ready this time (signed out, offline) is skipped for this run only; say so in one line
with the fix, and leave the file alone so the engine comes back by itself once it is ready.

If `FABLE_CONFIGURED` is `no` (the user installed through `/plugin` and never ran the installer),
ask once, with the detected state as the suggested answer: "Do you use Codex?" and "Do you use
Antigravity?". Use AskUserQuestion when it is available. Save the answers and rerun the preflight:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/configure.sh" --codex <yes|no> --agy <yes|no>
bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh"
```

After that, never ask again. The one exception is the user asking to change it ("reconfigure the
team", "I have Codex now", "stop using Antigravity"): ask the two questions again, or take the
answer straight from their message, and run `configure.sh` with it.

Then tell the user the mode in one line, for example: "Running as trio: Codex and Antigravity are
both signed in." Do not ask which engines they have beyond the one time above.

## Step 2. Apply the setup fixes the user will want

The report lists two kinds of fix.

- **Sign-ins** (`codex login`, or running `agy` once). These open a browser, so only the user can
  finish them. Give the exact command, say which mode you are running in meanwhile, and carry on
  in that mode rather than waiting.
- **Claude Code settings** (a permission rule so dispatches stop prompting; on macOS, Linux, and
  WSL2 with the sandbox on, excluding the two CLIs from it). Show the exact JSON change and ask
  once. On yes, apply it yourself: copy `settings.json` to a timestamped backup next to it, merge
  the keys without removing anything already there, confirm the file still parses as JSON, and
  tell the user `/status` shows whether it loaded.

Never block the task on an optional fix. The loops work without them; the fixes only remove
friction.

## Step 3. Route to the loop

| `FABLE_MODE` | Follow this skill | Workers |
|---|---|---|
| `trio` | `trio` | Codex and Antigravity |
| `duo-codex` | `duo-codex` | Codex |
| `duo-gemini` | `duo-gemini` | Antigravity |
| `solo` | `orchestrate` | Claude subagents |

Invoke that skill (in a plugin install its name carries a `fable-toolkit:` prefix), or read its
instructions directly at `${CLAUDE_SKILL_DIR}/../<skill>/SKILL.md`. Follow it from its Setup step,
skip its own preflight since you already ran it, and use the model ids from this preflight
wherever it names an Antigravity model.

## Step 4. Assign every unit automatically

Decide per unit from the signal in the work. Never ask the user who should do it; say who did what
in the final report.

| Signal in the unit | trio | duo-codex | duo-gemini | solo |
|---|---|---|---|---|
| Subtle logic, edge cases decide correctness | Codex | Codex | Antigravity smart | Claude worker |
| Must read existing code and match its patterns | Codex | Codex | Antigravity smart | Claude worker |
| Code review or security audit of a repository | Codex, `--sandbox read-only` | Codex, `--sandbox read-only` | Antigravity smart, then your own pass | Claude critic |
| Same mechanical change across many files | Antigravity fast | Codex, split into parallel units | Antigravity fast | Claude workers |
| Long generated docs, data, config, or content | Antigravity heavy | Codex | Antigravity heavy | Claude worker |
| Web research, competitor or market scan, SEO or content audit of public pages | Antigravity | Claude researcher | Antigravity | Claude researcher |
| Reading or summarising many local files | Antigravity, files named in the brief | Codex, read-only | Antigravity | Claude worker |
| A product decision, a taste call, or anything without a checkable criterion | you | you | you | you |

"Claude worker", "Claude researcher", and "Claude critic" are this toolkit's `worker`,
`researcher`, and `critic` agents, spawned with the Agent tool.

Antigravity can search the web and fetch pages in headless mode, so research and public-page audits
go to it without any setup. It cannot run shell commands there, so anything that needs a command
(a crawl, a test run, a `git log`) you run first and hand over as files.

For research and audit units, the brief must demand a source (URL, or file and line) for every
finding, and your review checks at least three of those sources yourself. A finding without a
source does not count.

Keep for yourself anything that touches credentials, production data, or an irreversible action.
Briefs go to external services.

## Step 5. Finish the way the loop says

The chosen loop's review, fix rounds, final gate, and report all apply unchanged. Add one line to
the report naming which engine handled which units, so the user sees the split without asking.
