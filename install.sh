#!/usr/bin/env bash
# Fable Toolkit installer for macOS, Linux, WSL, and Git Bash on Windows.
#
#   curl -fsSL https://raw.githubusercontent.com/ddivyanshsharmaa/fable-toolkit/main/install.sh | bash
#
# On macOS and Linux it installs through Claude Code's plugin system, so later updates are one
# command, and falls back to copying files if that does not finish. On Windows it copies files,
# because Claude Code's plugin install from GitHub can fail there with a file lock (EBUSY/EPERM).
# Copying backs up anything it replaces. Then it checks which AI engines this machine can use.
#
# Optional environment variables:
#   FABLE_TOOLKIT_MODE=plugin|copy   force one install method
#   FABLE_TOOLKIT_REF=<branch>       install another branch (default: main)
#   FABLE_TOOLKIT_SRC=<folder>       install from a local checkout instead of GitHub
#   FABLE_TOOLKIT_CODEX=yes|no       answer the Codex question in advance (unattended installs)
#   FABLE_TOOLKIT_AGY=yes|no         answer the Antigravity question in advance
#   CLAUDE_CONFIG_DIR                respected, same as Claude Code itself
#
# At the end it asks three questions (Claude Code, Codex, Antigravity), saves the answers, and
# shows who will do what. Change them any time by running the installer again.

# Everything lives in main(), called on the last line, so a partial download never runs.
main() {
  set -euo pipefail

  REPO="ddivyanshsharmaa/fable-toolkit"
  REF="${FABLE_TOOLKIT_REF:-main}"
  MODE="${FABLE_TOOLKIT_MODE:-auto}"
  SRC="${FABLE_TOOLKIT_SRC:-}"
  CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  WORK_DIR=""
  trap cleanup EXIT

  say "Fable Toolkit installer"
  say ""

  HAS_CLAUDE=no
  if command -v claude >/dev/null 2>&1; then HAS_CLAUDE=yes; fi
  HAS_PLUGIN_CLI=no
  if [ "$HAS_CLAUDE" = yes ] && claude plugin marketplace --help </dev/null >/dev/null 2>&1; then
    HAS_PLUGIN_CLI=yes
  fi
  case "$(uname -s 2>/dev/null)" in
    MINGW* | MSYS* | CYGWIN*) IS_WINDOWS=yes ;;
    *) IS_WINDOWS=no ;;
  esac

  AUTO=no
  case "$MODE" in
    auto)
      AUTO=yes
      if [ "$HAS_PLUGIN_CLI" = yes ] && [ "$IS_WINDOWS" = no ]; then MODE=plugin; else MODE=copy; fi
      ;;
    plugin)
      [ "$HAS_PLUGIN_CLI" = yes ] || fail "plugin mode needs Claude Code's 'claude plugin' command. Update Claude Code, or rerun with FABLE_TOOLKIT_MODE=copy."
      ;;
    copy) ;;
    *) fail "FABLE_TOOLKIT_MODE must be plugin or copy, not '$MODE'" ;;
  esac

  if [ "$HAS_CLAUDE" = no ]; then
    say "Claude Code is not on your PATH yet. The toolkit will be ready the moment you install it:"
    say "  https://code.claude.com/docs/en/setup"
    say ""
  fi

  if [ "$MODE" = plugin ]; then
    if plugin_install; then
      warn_manual_copies
    elif [ "$AUTO" = yes ]; then
      say ""
      say "Claude Code's plugin installer did not finish, so installing by copying files instead."
      MODE=copy
      copy_install
    else
      fail "Claude Code's plugin installer did not finish. Rerun with FABLE_TOOLKIT_MODE=copy."
    fi
  else
    copy_install
  fi

  run_setup

  say ""
  say "Done. Start a new Claude Code session in any project and just ask, for example:"
  say "  use the team to add CSV export to the reports page, with tests"
  say "It works out which engines you have and runs the right loop on its own."
  if [ "$MODE" = plugin ]; then
    say ""
    say "Update later:  claude plugin marketplace update fable-toolkit"
    say "               claude plugin update fable-toolkit@fable-toolkit"
    say "Uninstall:     claude plugin uninstall fable-toolkit@fable-toolkit"
  else
    say ""
    say "Update later by running the same install command again."
  fi
  say "Change which engines the team uses: run the installer again, or ask Claude Code to"
  say "reconfigure the team."
}

say() { printf '%s\n' "$*"; }

fail() {
  printf '\nInstall failed: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
}

plugin_install() {
  if [ -n "$SRC" ]; then
    market_src="$SRC"
  elif [ "$REF" = main ]; then
    market_src="$REPO"
  else
    market_src="$REPO@$REF"
  fi

  if claude plugin marketplace list </dev/null 2>/dev/null | grep -q 'fable-toolkit'; then
    say "Refreshing the fable-toolkit marketplace..."
    claude plugin marketplace update fable-toolkit </dev/null || return 1
  else
    say "Adding the fable-toolkit marketplace from $market_src..."
    claude plugin marketplace add "$market_src" </dev/null || return 1
  fi

  if claude plugin list </dev/null 2>/dev/null | grep -q 'fable-toolkit@fable-toolkit'; then
    say "Updating the plugin..."
    claude plugin update fable-toolkit@fable-toolkit </dev/null || return 1
  else
    say "Installing the plugin..."
    claude plugin install fable-toolkit@fable-toolkit </dev/null || return 1
  fi
}

# A plugin install next to an older manual copy lists every skill twice. Say so, never delete.
warn_manual_copies() {
  dupes=""
  for name in team trio duo-codex duo-gemini fable orchestrate deep-check; do
    if [ -f "$CONFIG_DIR/skills/$name/SKILL.md" ]; then dupes="$dupes $name"; fi
  done
  if [ -n "$dupes" ]; then
    say ""
    say "Heads up: $CONFIG_DIR/skills also has folders named:$dupes"
    say "Claude Code will list those skills twice. If they came from an older manual install of this"
    say "toolkit, delete those folders. If you customised them, keep them; the plugin copies are"
    say "prefixed fable-toolkit: so both can live side by side."
  fi
}

fetch_source() {
  if [ -n "$SRC" ]; then
    [ -d "$SRC/skills" ] || fail "FABLE_TOOLKIT_SRC=$SRC has no skills folder"
    return
  fi
  command -v curl >/dev/null 2>&1 || fail "curl is needed to download the toolkit"
  command -v tar >/dev/null 2>&1 || fail "tar is needed to unpack the toolkit"
  WORK_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t fable-toolkit)"
  say "Downloading $REPO ($REF)..."
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$REF.tar.gz" | tar -xzf - -C "$WORK_DIR" \
    || fail "could not download https://github.com/$REPO (branch $REF)"
  SRC=""
  for dir in "$WORK_DIR"/*/; do
    SRC="${dir%/}"
    break
  done
  [ -n "$SRC" ] && [ -d "$SRC/skills" ] || fail "the download did not contain a skills folder"
}

# Put one skill folder or agent file in place. Identical copies are left alone; anything
# different is moved to a backup folder outside skills/ (so Claude Code does not load it twice).
place() {
  kind=$1
  name=$2
  from=$3
  to="$CONFIG_DIR/$kind/$name"
  if [ -e "$to" ]; then
    if diff -rq "$from" "$to" >/dev/null 2>&1; then
      SAME=$((SAME + 1))
      return
    fi
    mkdir -p "$BACKUP/$kind"
    mv "$to" "$BACKUP/$kind/$name"
    MOVED=$((MOVED + 1))
  fi
  cp -R "$from" "$to"
  PLACED=$((PLACED + 1))
}

copy_install() {
  fetch_source
  BACKUP="$CONFIG_DIR/fable-toolkit-backup-$(date +%Y%m%d-%H%M%S)"
  PLACED=0
  SAME=0
  MOVED=0
  mkdir -p "$CONFIG_DIR/skills" "$CONFIG_DIR/agents"

  for dir in "$SRC"/skills/*/; do
    name="$(basename "$dir")"
    place skills "$name" "$SRC/skills/$name"
  done
  for file in "$SRC"/agents/*.md; do
    place agents "$(basename "$file")" "$file"
  done
  if [ -f "$SRC/FABLE-METHOD.md" ]; then
    to="$CONFIG_DIR/FABLE-METHOD.md"
    if [ -e "$to" ] && ! cmp -s "$SRC/FABLE-METHOD.md" "$to"; then
      mkdir -p "$BACKUP"
      mv "$to" "$BACKUP/FABLE-METHOD.md"
      MOVED=$((MOVED + 1))
    fi
    cp "$SRC/FABLE-METHOD.md" "$to"
  fi
  chmod +x "$CONFIG_DIR/skills/team/scripts/"*.sh 2>/dev/null || true

  say "Installed into $CONFIG_DIR: $PLACED updated, $SAME already up to date."
  if [ "$MOVED" -gt 0 ]; then
    say "Your previous versions of $MOVED item(s) are saved in $BACKUP"
  fi
  say "Optional: to load the Fable operating manual in every session, add this line to"
  say "  $CONFIG_DIR/CLAUDE.md :   @FABLE-METHOD.md"
}

# Ask which engines this person uses, save it, and show how work will be split.
run_setup() {
  script=""
  if [ "$MODE" = copy ]; then
    script="$CONFIG_DIR/skills/team/scripts/configure.sh"
  else
    script="$( { find "$CONFIG_DIR/plugins/cache" -path '*fable-toolkit*' -name configure.sh 2>/dev/null || true; } | sort | tail -n 1)"
  fi
  if [ -z "$script" ] || [ ! -f "$script" ]; then
    if [ -n "$SRC" ] && [ -f "$SRC/skills/team/scripts/configure.sh" ]; then
      script="$SRC/skills/team/scripts/configure.sh"
    fi
  fi
  say ""
  if [ -n "$script" ] && [ -f "$script" ]; then
    bash "$script" || true
  else
    say "Claude Code asks which engines you use the first time you ask it to use the team."
  fi
}

main "$@"
