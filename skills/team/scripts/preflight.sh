#!/usr/bin/env bash
# Fable Toolkit preflight.
#
# Works out which AI engines this run can use, which team loop that allows, which Antigravity
# models to use, and which setup changes would remove friction. Honours the saved engine setup
# (fable-toolkit.conf, written by configure.sh): an engine set to "no" is never used, and one set
# to "yes" that is not signed in right now is skipped for this run only. It only reads; it never
# changes anything, including the saved setup. Runs on macOS (bash 3.2+), Linux, WSL, and Git
# Bash on Windows.
#
# Output: a readable report, then machine readable FABLE_* lines for the /team skill.
# FABLE_IGNORE_CONF=1 reports raw detection and ignores the saved setup.

set -u

say() { printf '%s\n' "$*"; }

TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t fable-preflight 2>/dev/null || echo "${TMPDIR:-/tmp}/fable-preflight-$$")"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# Run a command with stdin closed and a time cap, writing all output to a file.
# macOS has no GNU timeout, so this polls instead. Returns 124 on timeout.
capped() {
  _secs=$1
  _out=$2
  shift 2
  "$@" </dev/null >"$_out" 2>&1 &
  _pid=$!
  _i=0
  while kill -0 "$_pid" 2>/dev/null; do
    if [ "$_i" -ge "$_secs" ]; then
      kill "$_pid" 2>/dev/null
      wait "$_pid" 2>/dev/null
      return 124
    fi
    sleep 1
    _i=$((_i + 1))
  done
  wait "$_pid" 2>/dev/null
}

first_line() { head -n 1 "$1" 2>/dev/null | tr -d '\r'; }

# ---------------------------------------------------------------- saved setup

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF="$CONFIG_DIR/fable-toolkit.conf"
CONFIGURED=no
USE_CODEX=auto
USE_AGY=auto
if [ -z "${FABLE_IGNORE_CONF:-}" ] && [ -f "$CONF" ]; then
  CONFIGURED=yes
  v="$(tr -d '\r' <"$CONF" | sed -n 's/^FABLE_USE_CODEX=//p' | head -n 1)"
  case "$v" in yes | no) USE_CODEX=$v ;; esac
  v="$(tr -d '\r' <"$CONF" | sed -n 's/^FABLE_USE_AGY=//p' | head -n 1)"
  case "$v" in yes | no) USE_AGY=$v ;; esac
fi

# ---------------------------------------------------------------- system

case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*) OS=windows ;;
  Darwin) OS=macos ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then OS=wsl; else OS=linux; fi
    ;;
  *) OS=unknown ;;
esac

CLAUDE_STATE=missing
CLAUDE_VERSION=""
if command -v claude >/dev/null 2>&1; then
  CLAUDE_STATE=found
  capped 20 "$TMP_DIR/claude-version" claude --version
  CLAUDE_VERSION="$(first_line "$TMP_DIR/claude-version")"
fi

# ---------------------------------------------------------------- Codex CLI

CODEX=missing
CODEX_VERSION=""
CODEX_MODEL=""
CODEX_DETAIL=""
if [ "$USE_CODEX" = no ]; then
  CODEX=off
elif command -v codex >/dev/null 2>&1; then
  capped 20 "$TMP_DIR/codex-version" codex --version
  # Codex can print warnings before the version line, so match the version itself.
  CODEX_VERSION="$(tr -d '\r' <"$TMP_DIR/codex-version" | grep -Ei '^codex[a-z-]* v?[0-9]' | head -n 1)"
  capped 30 "$TMP_DIR/codex-login" codex login status
  rc=$?
  if [ "$rc" -eq 124 ]; then
    CODEX=unreachable
    CODEX_DETAIL="codex login status did not answer within 30 seconds"
  elif grep -qi 'not logged in' "$TMP_DIR/codex-login"; then
    CODEX=not-signed-in
  elif grep -qi 'logged in' "$TMP_DIR/codex-login"; then
    CODEX=ready
  else
    CODEX=not-signed-in
    CODEX_DETAIL="$(first_line "$TMP_DIR/codex-login")"
  fi
  codex_config="${CODEX_HOME:-$HOME/.codex}/config.toml"
  if [ -f "$codex_config" ]; then
    CODEX_MODEL="$(grep -E '^[[:space:]]*model[[:space:]]*=' "$codex_config" 2>/dev/null | head -n 1 | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/"//g' -e "s/'//g" | tr -d '\r')"
  fi
fi

# ---------------------------------------------------------------- Antigravity CLI

AGY=missing
AGY_DETAIL=""
AGY_FAST=""
AGY_HEAVY=""
AGY_SMART=""
if [ "$USE_AGY" = no ]; then
  AGY=off
elif command -v agy >/dev/null 2>&1; then
  capped 60 "$TMP_DIR/agy-models" agy models
  rc=$?
  tr -d '\r' <"$TMP_DIR/agy-models" >"$TMP_DIR/agy-models.txt"
  if [ "$rc" -eq 124 ]; then
    AGY=unreachable
    AGY_DETAIL="agy models did not answer within 60 seconds (network, or a sign-in prompt waiting)"
  elif grep -Eq '^gemini-' "$TMP_DIR/agy-models.txt"; then
    AGY=ready
  else
    AGY=not-signed-in
    AGY_DETAIL="$(grep -v -i 'fetching' "$TMP_DIR/agy-models.txt" | head -n 1)"
  fi
  if [ "$AGY" = ready ]; then
    # agy lists newest models first, so the first match per tier is the current one.
    pick() { grep -E "$1" "$TMP_DIR/agy-models.txt" | head -n 1 | cut -f1 | tr -d ' '; }
    AGY_FAST="$(pick '^gemini-[0-9.]+-flash-medium')"
    AGY_HEAVY="$(pick '^gemini-[0-9.]+-flash-high')"
    AGY_SMART="$(pick '^gemini-[0-9.]+-pro-high')"
    [ -n "$AGY_SMART" ] || AGY_SMART="$(pick '^gemini-[0-9.]+-pro')"
    [ -n "$AGY_FAST" ] || AGY_FAST="$(pick '^gemini-.*flash')"
    [ -n "$AGY_HEAVY" ] || AGY_HEAVY="$AGY_FAST"
    [ -n "$AGY_SMART" ] || AGY_SMART="$AGY_HEAVY"
  fi
fi

# ---------------------------------------------------------------- team mode and split

if [ "$CODEX" = ready ] && [ "$AGY" = ready ]; then
  MODE=trio
elif [ "$CODEX" = ready ]; then
  MODE=duo-codex
elif [ "$AGY" = ready ]; then
  MODE=duo-gemini
else
  MODE=solo
fi

case "$MODE" in
  trio)
    CODING="Codex"; AUDITS="Codex (read-only)"; BULK="Antigravity"; RESEARCH="Antigravity" ;;
  duo-codex)
    CODING="Codex"; AUDITS="Codex (read-only)"; BULK="Codex"; RESEARCH="Claude researcher subagents" ;;
  duo-gemini)
    CODING="Antigravity (smart tier)"; AUDITS="Antigravity (smart tier), then Claude"; BULK="Antigravity"; RESEARCH="Antigravity" ;;
  solo)
    CODING="Claude subagents"; AUDITS="Claude critic subagent"; BULK="Claude subagents"; RESEARCH="Claude researcher subagents" ;;
esac

# ---------------------------------------------------------------- setup fixes

FIX_COUNT=0
FIXES=""
add_fix() {
  FIX_COUNT=$((FIX_COUNT + 1))
  FIXES="${FIXES}  ${FIX_COUNT}. $1
"
}

case "$CODEX" in
  not-signed-in) add_fix "Sign in to Codex (opens a browser): codex login" ;;
  unreachable) add_fix "Codex did not respond. Check your network, then run: codex login status" ;;
esac
case "$AGY" in
  not-signed-in) add_fix "Sign in to Antigravity: run agy once in a terminal and complete the browser sign-in" ;;
  unreachable) add_fix "Antigravity did not respond. Run agy once in a terminal; if it asks you to sign in, finish that" ;;
esac

SETTINGS="$CONFIG_DIR/settings.json"
settings_has() { [ -f "$SETTINGS" ] && grep -Fq "$1" "$SETTINGS"; }

rules=""
if [ "$CODEX" = ready ] && ! settings_has 'Bash(codex exec'; then rules="\"Bash(codex exec *)\""; fi
if [ "$AGY" = ready ] && ! settings_has 'Bash(agy -p'; then
  if [ -n "$rules" ]; then rules="$rules, "; fi
  rules="${rules}\"Bash(agy -p *)\""
fi
if [ -n "$rules" ]; then
  add_fix "Let engine dispatches run without a permission prompt each time. In $SETTINGS merge:
       \"permissions\": { \"allow\": [ $rules ] }"
fi

if [ "$OS" != windows ] && settings_has '"sandbox"' && grep -Eq '"enabled"[[:space:]]*:[[:space:]]*true' "$SETTINGS" 2>/dev/null; then
  if { [ "$CODEX" = ready ] || [ "$AGY" = ready ]; } && ! settings_has '"codex *"'; then
    add_fix "Your Claude Code sandbox is on. Codex and Antigravity need the network and run their own
       sandboxes, so exclude them. In $SETTINGS merge:
       \"sandbox\": { \"excludedCommands\": [ \"codex *\", \"agy *\" ] }"
  fi
fi

# ---------------------------------------------------------------- report

describe() {
  case "$1" in
    ready) printf 'ready' ;;
    not-signed-in) printf 'installed, not signed in' ;;
    unreachable) printf 'installed, not responding' ;;
    missing) printf 'not installed' ;;
    off) printf 'off (your saved setup says not to use it)' ;;
  esac
}

say "Fable Toolkit preflight"
say "======================="
case "$OS" in
  windows) say "System:        Windows (Git Bash)" ;;
  macos) say "System:        macOS" ;;
  wsl) say "System:        Linux on WSL" ;;
  linux) say "System:        Linux" ;;
  *) say "System:        unknown" ;;
esac
if [ "$CLAUDE_STATE" = found ]; then
  say "Claude Code:   ${CLAUDE_VERSION:-found}"
else
  say "Claude Code:   not on PATH (install: https://code.claude.com/docs/en/setup)"
fi

line="Codex CLI:     $(describe "$CODEX")"
if [ -n "$CODEX_VERSION" ]; then line="$line, $CODEX_VERSION"; fi
if [ "$CODEX" = ready ] && [ -n "$CODEX_MODEL" ]; then line="$line, model $CODEX_MODEL"; fi
say "$line"
if [ -n "$CODEX_DETAIL" ]; then say "               $CODEX_DETAIL"; fi

say "Antigravity:   $(describe "$AGY")"
if [ "$AGY" = ready ]; then
  say "               fast $AGY_FAST, heavy $AGY_HEAVY, smart $AGY_SMART"
fi
if [ -n "$AGY_DETAIL" ]; then say "               $AGY_DETAIL"; fi

say ""
if [ "$CONFIGURED" = yes ]; then
  say "Saved setup:   Codex $USE_CODEX, Antigravity $USE_AGY (in $CONF)"
  if [ "$USE_CODEX" = yes ] && [ "$CODEX" != ready ]; then
    say "               Codex is not ready right now, so this run goes without it. The saved setup is"
    say "               unchanged, and Codex is used again as soon as it is ready."
  fi
  if [ "$USE_AGY" = yes ] && [ "$AGY" != ready ]; then
    say "               Antigravity is not ready right now, so this run goes without it. The saved"
    say "               setup is unchanged, and Antigravity is used again as soon as it is ready."
  fi
else
  say "Saved setup:   none yet, so this uses what was detected. Save it with configure.sh, or let"
  say "               /team ask its three questions once."
fi
say ""
say "Team mode:     $MODE"
say "Who does what: planning, review, final checks   Claude"
say "               coding and tricky logic          $CODING"
say "               code and security audits         $AUDITS"
say "               bulk edits, long generation      $BULK"
say "               web research, SEO and content    $RESEARCH"
say ""
if [ "$FIX_COUNT" -eq 0 ]; then
  say "Setup:         nothing to change, everything the team needs is in place."
else
  say "Setup fixes (the team still runs without them; each one removes friction):"
  printf '%s' "$FIXES"
fi
say ""
say "Good to know:"
if [ "$AGY" = ready ]; then
  say "  - Antigravity in headless mode cannot run shell commands, and no setting changes that. It can"
  say "    read and write files and search and fetch the web. The loops stage command output as files."
fi
if [ "$OS" = windows ]; then
  say "  - On Windows, engine dispatches go through the Bash tool (Git Bash), not PowerShell 5.1, which"
  say "    cannot close stdin with </dev/null. Without that, both CLIs wait forever."
fi
if [ "$CODEX" = missing ]; then
  say "  - Add Codex for precise coding and security audits: https://developers.openai.com/codex/cli"
fi
if [ "$AGY" = missing ]; then
  say "  - Add the Antigravity CLI for bulk work and web research: https://antigravity.google"
fi
say ""
say "FABLE_MODE=$MODE"
say "FABLE_CODEX=$CODEX"
say "FABLE_AGY=$AGY"
say "FABLE_AGY_FAST=$AGY_FAST"
say "FABLE_AGY_HEAVY=$AGY_HEAVY"
say "FABLE_AGY_SMART=$AGY_SMART"
say "FABLE_CONFIGURED=$CONFIGURED"
say "FABLE_FIXES=$FIX_COUNT"
