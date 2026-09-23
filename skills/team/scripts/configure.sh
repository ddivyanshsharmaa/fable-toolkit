#!/usr/bin/env bash
# Fable Toolkit engine setup.
#
# Records which engines you use, so the team splits work the same way every time. Asks three
# questions (press Enter to accept what was detected), offers to sign in to Codex if needed,
# saves the answers, then shows how work will be split.
#
#   bash configure.sh                          ask interactively
#   bash configure.sh --codex yes --agy no     save without asking
#
# Saved to fable-toolkit.conf in your Claude Code config folder (CLAUDE_CONFIG_DIR, or ~/.claude).
# Nothing changes that file afterwards except running this script again.

set -u

say() { printf '%s\n' "$*"; }
here="$(cd "$(dirname "$0")" && pwd)"
CONF_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF="$CONF_DIR/fable-toolkit.conf"

normalize() {
  case "$1" in
    [Yy] | [Yy][Ee][Ss]) echo yes ;;
    [Nn] | [Nn][Oo]) echo no ;;
    *) echo "" ;;
  esac
}

ARG_CODEX=""
ARG_AGY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --codex) ARG_CODEX="$(normalize "${2:-}")"; shift 2 ;;
    --agy | --antigravity) ARG_AGY="$(normalize "${2:-}")"; shift 2 ;;
    -h | --help) sed -n '2,13p' "$0"; exit 0 ;;
    *) say "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
done
[ -n "$ARG_CODEX" ] || ARG_CODEX="$(normalize "${FABLE_TOOLKIT_CODEX:-}")"
[ -n "$ARG_AGY" ] || ARG_AGY="$(normalize "${FABLE_TOOLKIT_AGY:-}")"

# Questions go to the terminal even when this script arrives through curl | bash. Answers are
# read from fd 3 and prompts written to fd 4. FABLE_TOOLKIT_ANSWERS=<file> feeds answers from a
# file instead, one per line, which is how the questions are tested without a keyboard.
NEED_ASK=no
if [ -z "$ARG_CODEX" ] || [ -z "$ARG_AGY" ]; then NEED_ASK=yes; fi
TTY=""
REAL_TTY=no
if [ "$NEED_ASK" = yes ]; then
  if [ -n "${FABLE_TOOLKIT_ANSWERS:-}" ]; then
    exec 3<"$FABLE_TOOLKIT_ANSWERS" 4>&1
    TTY=answers
  elif (exec </dev/tty) 2>/dev/null; then
    exec 3</dev/tty 4>/dev/tty
    TTY=terminal
    REAL_TTY=yes
  fi
fi

ask() {
  _question=$1
  _default=$2
  if [ -z "$TTY" ]; then
    echo "$_default"
    return
  fi
  _hint="[Y/n]"
  [ "$_default" = no ] && _hint="[y/N]"
  while :; do
    printf '%s %s ' "$_question" "$_hint" >&4
    IFS= read -r _reply <&3 || _reply=""
    _reply="$(printf '%s' "$_reply" | tr -d '\r ')"
    if [ "$TTY" = answers ]; then printf '%s\n' "$_reply" >&4; fi
    if [ -z "$_reply" ]; then
      echo "$_default"
      return
    fi
    _answer="$(normalize "$_reply")"
    if [ -n "$_answer" ]; then
      echo "$_answer"
      return
    fi
    printf 'Please answer y or n.\n' >&4
  done
}

codex_state() {
  if ! command -v codex >/dev/null 2>&1; then
    echo missing
    return
  fi
  # Codex prints its login status on stderr, so both streams are captured.
  _out="$(codex login status </dev/null 2>&1)"
  if printf '%s' "$_out" | grep -qi 'not logged in'; then
    echo not-signed-in
  elif printf '%s' "$_out" | grep -qi 'logged in'; then
    echo ready
  else
    echo not-signed-in
  fi
}

found() { if command -v "$1" >/dev/null 2>&1; then echo yes; else echo no; fi; }

HAVE_CLAUDE="$(found claude)"
CODEX_NOW="$(codex_state)"
AGY_FOUND="$(found agy)"

USE_CLAUDE="$HAVE_CLAUDE"
if [ "$NEED_ASK" = yes ]; then
  say "Fable Toolkit engine setup"
  say "Three quick questions. Press Enter to accept the detected answer."
  say ""
  case "$HAVE_CLAUDE" in
    yes) q="Do you use Claude Code? (detected: installed)" ;;
    *) q="Do you use Claude Code? (detected: not installed)" ;;
  esac
  USE_CLAUDE="$(ask "$q" "$HAVE_CLAUDE")"
fi
if [ "$USE_CLAUDE" = no ] || [ "$HAVE_CLAUDE" = no ]; then
  say "  The team runs inside Claude Code, which needs a Claude subscription or API key."
  say "  Install it from https://code.claude.com/docs/en/setup ; everything here is ready for it."
fi

if [ -n "$ARG_CODEX" ]; then
  USE_CODEX="$ARG_CODEX"
else
  case "$CODEX_NOW" in
    ready) q="Do you use Codex, OpenAI's coding agent? (detected: installed and signed in)"; d=yes ;;
    not-signed-in) q="Do you use Codex, OpenAI's coding agent? (detected: installed, not signed in)"; d=yes ;;
    *) q="Do you use Codex, OpenAI's coding agent? (detected: not installed)"; d=no ;;
  esac
  USE_CODEX="$(ask "$q" "$d")"
fi
if [ "$USE_CODEX" = yes ]; then
  case "$CODEX_NOW" in
    missing)
      say "  Codex is not installed yet: https://developers.openai.com/codex/cli"
      say "  The team starts using it by itself once it is installed and signed in."
      ;;
    not-signed-in)
      if [ -n "$TTY" ] && [ "$(ask "  Sign in to Codex now? It opens a browser." yes)" = yes ]; then
        if [ "$REAL_TTY" = yes ]; then
          codex login <&3 >&4 2>&1 || true
        else
          say "  (answers file in use, so skipping the real sign-in)"
        fi
        CODEX_NOW="$(codex_state)"
      fi
      if [ "$CODEX_NOW" != ready ]; then
        say "  Codex is not signed in yet. Run: codex login"
        say "  Until then the team works without it and picks it up by itself afterwards."
      fi
      ;;
  esac
fi

if [ -n "$ARG_AGY" ]; then
  USE_AGY="$ARG_AGY"
else
  case "$AGY_FOUND" in
    yes) q="Do you use Antigravity, Google's agent CLI? (detected: installed)"; d=yes ;;
    *) q="Do you use Antigravity, Google's agent CLI? (detected: not installed)"; d=no ;;
  esac
  USE_AGY="$(ask "$q" "$d")"
fi
if [ "$USE_AGY" = yes ] && [ "$AGY_FOUND" = no ]; then
  say "  Antigravity is not installed yet: https://antigravity.google"
  say "  The team starts using it by itself once it is installed and signed in."
fi

mkdir -p "$CONF_DIR"
{
  echo "# Fable Toolkit engine setup, saved $(date +%Y-%m-%d) by configure.sh."
  echo "# yes: use this engine whenever it is signed in. If it is not, that run goes without it"
  echo "#      and says so; this file does not change."
  echo "# no:  never use this engine, even if it is installed."
  echo "# To change it, run configure.sh again or ask Claude Code to reconfigure the team."
  echo "FABLE_USE_CODEX=$USE_CODEX"
  echo "FABLE_USE_AGY=$USE_AGY"
} >"$CONF"

say ""
say "Saved to $CONF"
say ""

# Full check with the saved answers, which also prints how the work will be split.
if [ -f "$here/preflight.sh" ]; then
  bash "$here/preflight.sh" </dev/null | grep -v '^FABLE_'
fi
