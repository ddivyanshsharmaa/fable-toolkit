#!/usr/bin/env bash
# Fable Toolkit account sign-in loop.
#
# Asks which service you want to sign in to, signs you in, then asks again, until you type done.
# Use it for as many accounts as you like, for example five Claude accounts and two Codex ones.
#
#   bash accounts.sh               sign in to accounts (loops until you type done)
#   bash accounts.sh --ask-first   same, but first asks whether you want to (used by the installer)
#   bash accounts.sh --list        show the accounts saved so far
#
# What each service uses:
#   Claude Code    its own sign-in link (claude auth login). Every account gets its own folder.
#   Codex          its own sign-in link (codex login). Every account gets its own folder.
#   Antigravity    agy has no login command; it asks you to sign in the first time you run it.
#   DeepSeek       no sign-in link exists; it uses an API key you create on its website.
#
# Accounts are listed in ~/.fable-accounts/accounts.conf. Folders and keys live next to it, and
# keys are plain files, set to owner-only on macOS and Linux. Keep that folder private.
# Nothing here is sent anywhere by this script.

set -u

say() { printf '%s\n' "$*"; }

ACC_DIR="${FABLE_ACCOUNTS_DIR:-$HOME/.fable-accounts}"
REG="$ACC_DIR/accounts.conf"

ASK_FIRST=no
LIST_ONLY=no
while [ $# -gt 0 ]; do
  case "$1" in
    --ask-first) ASK_FIRST=yes; shift ;;
    --list) LIST_ONLY=yes; shift ;;
    -h | --help) sed -n '2,18p' "$0"; exit 0 ;;
    *) say "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
done

list_accounts() {
  if [ ! -s "$REG" ] || ! grep -qv '^#' "$REG"; then
    say "  (none saved yet)"
    return
  fi
  grep -v '^#' "$REG" | while IFS='|' read -r _p _n _loc; do
    case "$_p" in
      claude) say "  Claude Code   $_n    use it:  CLAUDE_CONFIG_DIR=\"$_loc\" claude" ;;
      codex) say "  Codex         $_n    use it:  CODEX_HOME=\"$_loc\" codex" ;;
      agy) say "  Antigravity   $_n    use it:  agy" ;;
      deepseek) say "  DeepSeek      $_n    key file: $_loc" ;;
    esac
  done
}

if [ "$LIST_ONLY" = yes ]; then
  say "Saved accounts:"
  list_accounts
  exit 0
fi

# Questions go to the terminal even when this script arrives through curl | bash. Answers are
# read from fd 3 and prompts written to fd 4. FABLE_TOOLKIT_ANSWERS=<file> feeds answers from a
# file instead, one per line, and skips every real sign-in; that is how this is tested.
TTY=""
REAL_TTY=no
if [ -n "${FABLE_TOOLKIT_ANSWERS:-}" ]; then
  exec 3<"$FABLE_TOOLKIT_ANSWERS" 4>&1
  TTY=answers
elif (exec </dev/tty) 2>/dev/null; then
  exec 3</dev/tty 4>/dev/tty
  TTY=terminal
  REAL_TTY=yes
else
  say "Signing in needs a terminal. Run this yourself later:  bash $0"
  exit 0
fi

# Reads one line into $REPLY_TXT. End of input counts as "done", so the loop can never spin.
prompt() {
  printf '%s ' "$1" >&4
  if ! IFS= read -r REPLY_TXT <&3; then REPLY_TXT="done"; fi
  REPLY_TXT="$(printf '%s' "$REPLY_TXT" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [ "$TTY" = answers ]; then printf '%s\n' "$REPLY_TXT" >&4; fi
}

# Same, but nothing is echoed while typing, for API keys.
prompt_secret() {
  printf '%s ' "$1" >&4
  if [ "$TTY" = answers ]; then
    if ! IFS= read -r REPLY_TXT <&3; then REPLY_TXT=""; fi
    printf '(hidden)\n' >&4
  else
    if ! IFS= read -rs REPLY_TXT <&3; then REPLY_TXT=""; fi
    printf '\n' >&4
  fi
  REPLY_TXT="$(printf '%s' "$REPLY_TXT" | tr -d '\r\n ')"
}

is_done() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    done | d | finish | finished | quit | exit | q | stop | no | n) return 0 ;;
  esac
  return 1
}

count_of() { if [ -f "$REG" ]; then grep -c "^$1|" "$REG" 2>/dev/null || true; else echo 0; fi; }

# Ask for a short name (work, personal, ...). Letters, digits, - and _ only. Sets $NAME.
ask_name() {
  _provider=$1
  _default="$_provider-$(( $(count_of "$_provider") + 1 ))"
  while :; do
    prompt "  Name for this account, for example work or personal [$_default]:"
    NAME="$REPLY_TXT"
    [ -n "$NAME" ] || NAME="$_default"
    NAME="$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9_\n-' '-')"
    if [ -f "$REG" ] && grep -q "^$_provider|$NAME|" "$REG"; then
      say "  You already have a $_provider account named $NAME. Pick a different name."
      continue
    fi
    return
  done
}

record() { # provider name location
  mkdir -p "$ACC_DIR"
  [ -f "$REG" ] || printf '# Fable Toolkit accounts. provider|name|location. Written by accounts.sh.\n' >"$REG"
  printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$REG"
}

add_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    say "  Claude Code is not installed yet: https://code.claude.com/docs/en/setup"
    say "  Install it, then run this again."
    return
  fi
  ask_name claude
  _dir="$ACC_DIR/claude/$NAME"
  mkdir -p "$_dir"
  prompt "  Email to pre-fill on the login page (optional, press Enter to skip):"
  _email="$REPLY_TXT"
  say "  Signing in '$NAME'. Open the web address it prints (a browser may open by itself),"
  say "  sign in with the account you want for '$NAME', then come back here."
  if [ "$REAL_TTY" = yes ]; then
    if [ -n "$_email" ]; then
      CLAUDE_CONFIG_DIR="$_dir" claude auth login --email "$_email" <&3 >&4 2>&1 || true
    else
      CLAUDE_CONFIG_DIR="$_dir" claude auth login <&3 >&4 2>&1 || true
    fi
  else
    say "  (answers file in use, so skipping the real sign-in: CLAUDE_CONFIG_DIR=$_dir claude auth login)"
  fi
  if CLAUDE_CONFIG_DIR="$_dir" claude auth status </dev/null >/dev/null 2>&1; then
    say "  Signed in: Claude Code account '$NAME'."
    record claude "$NAME" "$_dir"
  else
    say "  '$NAME' is not signed in. It was not saved. Pick Claude Code again to retry."
  fi
}

add_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    say "  Codex is not installed yet: https://developers.openai.com/codex/cli"
    say "  Install it, then run this again."
    return
  fi
  ask_name codex
  _dir="$ACC_DIR/codex/$NAME"
  mkdir -p "$_dir"
  say "  Signing in '$NAME'. Open the web address it prints (a browser may open by itself),"
  say "  sign in with the account you want for '$NAME', then come back here."
  if [ "$REAL_TTY" = yes ]; then
    CODEX_HOME="$_dir" codex login <&3 >&4 2>&1 || true
  else
    say "  (answers file in use, so skipping the real sign-in: CODEX_HOME=$_dir codex login)"
  fi
  _out="$(CODEX_HOME="$_dir" codex login status </dev/null 2>&1)"
  if printf '%s' "$_out" | grep -qi 'not logged in'; then
    say "  '$NAME' is not signed in. It was not saved. Pick Codex again to retry."
  elif printf '%s' "$_out" | grep -qi 'logged in'; then
    say "  Signed in: Codex account '$NAME'."
    record codex "$NAME" "$_dir"
  else
    say "  Could not confirm the sign-in for '$NAME'. It was not saved. Pick Codex again to retry."
  fi
}

add_agy() {
  if ! command -v agy >/dev/null 2>&1; then
    say "  Antigravity is not installed yet: https://antigravity.google"
    say "  Install it, then run this again."
    return
  fi
  say "  Antigravity has no login command. It asks you to sign in the first time you start it."
  say "  Open another terminal, run:  agy"
  say "  sign in with the web address it shows, then close it and come back here."
  say "  agy keeps one signed-in Google account per computer user, so this script cannot"
  say "  switch between several; use a separate computer user for a second one."
  prompt "  Press Enter when you have signed in (or type skip):"
  if is_done "$REPLY_TXT" || [ "$REPLY_TXT" = skip ]; then
    say "  Skipped Antigravity."
    return
  fi
  record agy default "this computer user"
  say "  Noted: Antigravity."
}

add_deepseek() {
  say "  DeepSeek has no sign-in link; it uses an API key (DeepSeek bills API use to your account)."
  say "  Create one here:  https://platform.deepseek.com/api_keys"
  ask_name deepseek
  prompt_secret "  Paste the API key (nothing shows while you type), or press Enter to skip:"
  if [ -z "$REPLY_TXT" ]; then
    say "  Skipped DeepSeek."
    return
  fi
  mkdir -p "$ACC_DIR/deepseek"
  chmod 700 "$ACC_DIR" "$ACC_DIR/deepseek" 2>/dev/null || true
  _file="$ACC_DIR/deepseek/$NAME.key"
  ( umask 077; printf '%s\n' "$REPLY_TXT" >"$_file" )
  chmod 600 "$_file" 2>/dev/null || true
  REPLY_TXT=""
  say "  Saved the key for '$NAME' to $_file. Keep that file private."
  record deepseek "$NAME" "$_file"
}

if [ "$ASK_FIRST" = yes ]; then
  prompt "Sign in to your AI accounts now (Claude, Codex, Antigravity, DeepSeek)? [Y/n]"
  case "$(printf '%s' "$REPLY_TXT" | tr '[:upper:]' '[:lower:]')" in
    n | no) say "Skipped. Run it any time:  bash $0"; exit 0 ;;
  esac
fi

say ""
say "Account sign-in. I will keep asking until you type done."
say "You can add as many accounts as you like, including several of the same service."
while :; do
  say ""
  say "Saved so far:"
  list_accounts
  say ""
  say "Which service do you want to sign in to?"
  say "  1) Claude Code    2) Codex    3) Antigravity (agy)    4) DeepSeek"
  prompt "Type 1-4 or the name, or type done when you have finished:"
  choice="$(printf '%s' "$REPLY_TXT" | tr '[:upper:]' '[:lower:]')"
  if is_done "$choice"; then break; fi
  case "$choice" in
    1 | claude*) add_claude ;;
    2 | codex* | openai | chatgpt) add_codex ;;
    3 | agy | antigravity | gemini | google) add_agy ;;
    4 | deepseek) add_deepseek ;;
    "") say "Type a number from 1 to 4, or done when you have finished." ;;
    *) say "I did not understand '$REPLY_TXT'. Type 1, 2, 3 or 4, or done." ;;
  esac
done

say ""
say "All done. Your accounts:"
list_accounts
say ""
say "Add more or review later:  bash $0     List them:  bash $0 --list"
say "Note: this signs you in and remembers the accounts. The team still uses your normal"
say "Claude Code, Codex and Antigravity sign-ins unless you start a tool with one of the commands above."
