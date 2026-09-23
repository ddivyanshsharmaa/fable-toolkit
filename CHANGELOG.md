# Changelog

## 1.2.0 (2026-09-23)

### Added

- **`/team`, a single entry point.** Ask for work in plain words and it picks the loop, splits the
  task, and assigns each part to the engine that fits it. It never asks who should do what.
- **One-line installers** for macOS, Linux, and Git Bash (`install.sh`) and Windows PowerShell
  (`install.ps1`). They back up anything they replace, leave identical files alone so re-running
  is safe, and respect `CLAUDE_CONFIG_DIR`.
- **Engine setup questions.** The installer asks whether you use Claude Code, Codex, and
  Antigravity, pre-filled with what it detected, offers to sign you in to Codex, and saves the
  answers to `fable-toolkit.conf`. The toolkit never rewrites that file itself: an engine you said
  yes to that is signed out is skipped for that run only, and one you said no to is never used.
- **Setup check (`preflight.sh`).** Detects engines and sign-ins, reads Antigravity's models live,
  reports who will do what, and suggests the Claude Code settings that remove friction
  (permission rules for dispatches, sandbox exclusions on macOS, Linux, and WSL2).
- **Automatic routing** of web research and SEO or content audits to Antigravity, which can search
  and fetch pages in headless mode, and of code and security audits to Codex in a read-only sandbox.
- A project context step in every loop: the project's own `CLAUDE.md`, `AGENTS.md`, and
  `GEMINI.md` feed each brief.

### Changed

- Antigravity models are chosen from the live `agy models` list by tier (fast, heavy, smart)
  instead of hard-coded names. Current defaults: `gemini-3.8-flash-medium`,
  `gemini-3.8-flash-high`, `gemini-3.1-pro-high`.
- `/trio`, `/duo-codex`, and `/duo-gemini` check which engines are available when invoked directly
  and switch to the loop that fits, instead of failing on a missing engine.
- New gotchas from real runs: headless Antigravity cannot run shell commands, it sometimes reports
  a permission error after already writing its output, and on Windows Codex's sandbox can fail with
  error 1344.

## 1.1.0 (2026-08-14)

- Deepened `/trio` into the reference loop: when not to use it, engine assignment by signal,
  checkable acceptance criteria, file ownership, a cold-start brief template, an evidence table,
  structural escalation, a mandatory final gate, and quota economy.
- Aligned `/duo-codex` and `/duo-gemini` with it.
- Removed em dashes across the repository.

## 1.0.0 (2026-08-14)

- Initial release: `/fable`, `/orchestrate`, `/deep-check`, `/trio`, `/duo-codex`,
  `/duo-gemini`, the `verifier`, `researcher`, `worker`, and `critic` agents, and FABLE-METHOD.md.
