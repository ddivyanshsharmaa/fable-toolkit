#!/usr/bin/env bash
# Fable Toolkit account sign-in loop.
#
# Asks which service you want to sign in to, signs you in, saves the account (with the email or ID
# you give, so you can tell accounts apart), then asks again, until you type done. Add as many
# accounts as you like, including several of the same service.
#
# This signs you in and keeps a tidy list in ~/.fable-accounts. The team does not read that list
# yet, so for now it is a safe place for your sign-ins, not an automatic account switcher.
#
#   bash accounts.sh                     sign in to accounts (loops until you type done)
#   bash accounts.sh --ask-first         same, but first asks whether you want to (installer)
#   bash accounts.sh --list              show the saved accounts
#   bash accounts.sh --remove <service> <name>   forget one account (deletes its saved key file)
#
# Three kinds of service:
#   sign-in link   Claude Code, Codex, Grok: the tool prints a web address; each account gets its own
#                  folder so several can be signed in at once.
#   first run      agy, Gemini CLI, Qwen Code, Kimi, Copilot CLI, Cursor: you sign in the first time
#                  you run the tool. Fable Toolkit does not check these sign-ins.
#   API key        DeepSeek, OpenRouter, Groq, Mistral, Z.ai, Together and any other: you create a key
#                  on the provider's website and paste it; it is saved in a file only you can read
#                  (owner-only on macOS and Linux). Providers bill API use to your account.
#
# Use separate accounts for separate purposes (work and personal). Do not rotate several personal
# subscriptions to get past a usage limit: the providers' terms may forbid it. Nothing here is sent
# anywhere by this script.

set -u
umask 077

say() { printf '%s\n' "$*"; }

ACC_DIR="${FABLE_ACCOUNTS_DIR:-$HOME/.fable-accounts}"
REG="$ACC_DIR/accounts.conf"

case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*) IS_WIN=yes ;;
  *) IS_WIN=no ;;
esac

# Run a command with the credential variables removed, so a stray API key in the environment can
# never stand in for the sign-in being set up or checked.
cenv() {
  env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_BASE_URL \
    -u OPENAI_API_KEY -u CODEX_API_KEY "$@"
}

winpath() { if [ "$IS_WIN" = yes ] && command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

# Sets P_LABEL, P_KIND (login|firstrun|apikey), P_BIN, P_ENV, P_URL for a service key.
set_provider() {
  P_LABEL=""; P_KIND=""; P_BIN=""; P_ENV=""; P_URL=""
  case "$1" in
    claude) P_LABEL="Claude Code"; P_KIND=login; P_BIN=claude; P_ENV=CLAUDE_CONFIG_DIR ;;
    codex) P_LABEL="Codex (OpenAI)"; P_KIND=login; P_BIN=codex; P_ENV=CODEX_HOME ;;
    grok) P_LABEL="Grok (xAI)"; P_KIND=login; P_BIN=grok; P_ENV=GROK_HOME ;;
    agy) P_LABEL="Antigravity (agy)"; P_KIND=firstrun; P_BIN=agy ;;
    gemini) P_LABEL="Gemini CLI"; P_KIND=firstrun; P_BIN=gemini ;;
    qwen) P_LABEL="Qwen Code"; P_KIND=firstrun; P_BIN=qwen ;;
    kimi) P_LABEL="Kimi (Moonshot)"; P_KIND=firstrun; P_BIN=kimi ;;
    copilot) P_LABEL="GitHub Copilot CLI"; P_KIND=firstrun; P_BIN=copilot ;;
    cursor) P_LABEL="Cursor Agent"; P_KIND=firstrun; P_BIN=agent ;;
    deepseek) P_LABEL="DeepSeek"; P_KIND=apikey; P_ENV=DEEPSEEK_API_KEY; P_URL=https://platform.deepseek.com/api_keys ;;
    openrouter) P_LABEL="OpenRouter"; P_KIND=apikey; P_ENV=OPENROUTER_API_KEY; P_URL=https://openrouter.ai/settings/keys ;;
    groq) P_LABEL="Groq"; P_KIND=apikey; P_ENV=GROQ_API_KEY; P_URL=https://console.groq.com/keys ;;
    mistral) P_LABEL="Mistral"; P_KIND=apikey; P_ENV=MISTRAL_API_KEY; P_URL=https://console.mistral.ai/api-keys/ ;;
    zai) P_LABEL="Z.ai (GLM)"; P_KIND=apikey; P_ENV=ZAI_API_KEY; P_URL=https://z.ai ;;
    together) P_LABEL="Together AI"; P_KIND=apikey; P_ENV=TOGETHER_API_KEY; P_URL=https://api.together.ai/settings/api-keys ;;
    custom) P_LABEL="Another service (API key)"; P_KIND=apikey ;;
    *) return 1 ;;
  esac
  return 0
}

# One line per saved account: provider|name|location|id|envvar   (older lists with 3 fields still read)
each_account() {
  [ -f "$REG" ] || return 0
  grep -v '^#' "$REG" | tr -d '\r' | while IFS='|' read -r _p _n _loc _id _env; do
    [ -n "$_p" ] && printf '%s|%s|%s|%s|%s\n' "$_p" "$_n" "$_loc" "${_id:-}" "${_env:-}"
  done
}

use_hint() { # provider name location envvar
  _prov=$1; _nm=$2; _loc=$3; _ev=$4
  set_provider "$_prov" 2>/dev/null || { P_KIND=apikey; }
  case "$P_KIND" in
    login)
      if [ "$IS_WIN" = yes ]; then
        printf '$env:%s="%s"; %s' "$_ev" "$(winpath "$_loc")" "$P_BIN"
      else
        printf '%s="%s" %s' "$_ev" "$_loc" "$P_BIN"
      fi ;;
    firstrun) printf '%s  (one sign-in per computer user)' "$P_BIN" ;;
    apikey)
      if [ "$IS_WIN" = yes ]; then
        printf '$env:%s=(Get-Content "%s")' "$_ev" "$(winpath "$_loc")"
      else
        printf 'export %s="$(cat "%s")"' "$_ev" "$_loc"
      fi ;;
  esac
}

list_accounts() {
  _any=no
  while IFS='|' read -r _p _n _loc _id _env; do
    [ -n "$_p" ] || continue
    _any=yes
    set_provider "$_p" 2>/dev/null || P_LABEL="$_p"
    _who=""; [ -n "$_id" ] && _who="  ($_id)"
    say "  $P_LABEL  $_n$_who"
    say "      use it:  $(use_hint "$_p" "$_n" "$_loc" "$_env")"
  done <<EOF
$(each_account)
EOF
  [ "$_any" = yes ] || say "  (none saved yet)"
}

warn_env() {
  for _v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN OPENAI_API_KEY CODEX_API_KEY; do
    if [ -n "$(eval "printf '%s' \"\${$_v:-}\"")" ]; then
      say "Warning: $_v is set in your environment. Claude Code and Codex may use it instead of a signed-in account."
    fi
  done
}

show_help() {
  cat <<'EOF'
Fable Toolkit account sign-in loop.

  accounts.sh                     sign in to accounts (loops until you type done)
  accounts.sh --ask-first         same, but first asks whether you want to
  accounts.sh --list              show the saved accounts
  accounts.sh --remove <service> <name>   forget one account and delete its saved key file

Services: claude codex grok agy gemini qwen kimi copilot cursor deepseek openrouter groq mistral zai together
The list lives in ~/.fable-accounts/accounts.conf. Nothing here is sent anywhere.
EOF
}

ASK_FIRST=no
MODE=run
RM_P=""; RM_N=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ask-first) ASK_FIRST=yes; shift ;;
    --list) MODE=list; shift ;;
    --remove) MODE=remove; RM_P="${2:-}"; RM_N="${3:-}"; shift; [ $# -gt 0 ] && shift; [ $# -gt 0 ] && shift ;;
    -h | --help) show_help; exit 0 ;;
    *) say "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
done

if [ "$MODE" = list ]; then
  say "Saved accounts:"
  list_accounts
  warn_env
  exit 0
fi

if [ "$MODE" = remove ]; then
  if [ -z "$RM_P" ] || [ -z "$RM_N" ]; then say "Usage: accounts.sh --remove <service> <name>"; exit 2; fi
  if [ ! -f "$REG" ] || ! grep -q "^$RM_P|$RM_N|" "$REG"; then say "No saved account '$RM_N' for $RM_P."; exit 1; fi
  _line="$(grep "^$RM_P|$RM_N|" "$REG" | head -n 1 | tr -d '\r')"
  _loc="$(printf '%s' "$_line" | cut -d'|' -f3)"
  grep -v "^$RM_P|$RM_N|" "$REG" >"$REG.tmp" && mv "$REG.tmp" "$REG"
  set_provider "$RM_P" 2>/dev/null || true
  say "Removed '$RM_N' from the list."
  if [ "$P_KIND" = apikey ] && [ -f "$_loc" ]; then rm -f "$_loc" && say "Deleted its saved key file."; fi
  if [ "$P_KIND" = login ] && [ -d "$_loc" ]; then say "Its sign-in folder is still on disk; delete it yourself if you want it gone: $_loc"; fi
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
  say "Signing in needs a terminal. Run it yourself later:  bash $ACC_DIR/accounts.sh"
  exit 0
fi

EOF_HIT=no
# Reads one line into $REPLY_TXT. End of input sets EOF_HIT and reads as "done".
prompt() {
  printf '%s ' "$1" >&4
  if ! IFS= read -r REPLY_TXT <&3; then REPLY_TXT="done"; EOF_HIT=yes; fi
  REPLY_TXT="$(printf '%s' "$REPLY_TXT" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [ "$TTY" = answers ]; then printf '%s\n' "$REPLY_TXT" >&4; fi
}

# Same, but nothing is echoed while typing, for API keys.
prompt_secret() {
  printf '%s ' "$1" >&4
  if [ "$TTY" = answers ]; then
    if ! IFS= read -r REPLY_TXT <&3; then REPLY_TXT=""; EOF_HIT=yes; fi
    printf '(hidden)\n' >&4
  else
    if ! IFS= read -rs REPLY_TXT <&3; then REPLY_TXT=""; EOF_HIT=yes; fi
    printf '\n' >&4
  fi
  REPLY_TXT="$(printf '%s' "$REPLY_TXT" | tr -d '\r\n\t ')"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_done() {
  case "$(lower "$1")" in
    done | d | finish | finished | quit | exit | q | stop | no | n) return 0 ;;
  esac
  return 1
}

is_cancel() {
  case "$(lower "$1")" in
    cancel | back | done | quit | exit | q) return 0 ;;
  esac
  return 1
}

count_of() { if [ -f "$REG" ]; then grep -c "^$1|" "$REG" 2>/dev/null || true; else echo 0; fi; }

# Ask for a short name (work, personal, ...). Sets $NAME. Returns 1 if cancelled or input ended.
ask_name() {
  _provider=$1
  _default="$_provider-$(( $(count_of "$_provider") + 1 ))"
  while :; do
    prompt "  Name for this account, for example work or personal [$_default] (cancel to go back):"
    [ "$EOF_HIT" = yes ] && return 1
    is_cancel "$REPLY_TXT" && return 1
    NAME="$REPLY_TXT"
    [ -n "$NAME" ] || NAME="$_default"
    NAME="$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9_\n-' '-')"
    if [ -f "$REG" ] && grep -q "^$_provider|$NAME|" "$REG"; then
      say "  You already have a $_provider account named $NAME. Pick a different name."
      continue
    fi
    return 0
  done
}

ask_id() { # optional email or ID to tell accounts apart. Sets $ACC_ID
  prompt "  Email or ID of this account, so you can tell your accounts apart (optional):"
  ACC_ID="$(printf '%s' "$REPLY_TXT" | tr -d '|')"
  [ "$EOF_HIT" = yes ] && ACC_ID=""
}

record() { # provider name location id envvar
  mkdir -p "$ACC_DIR"
  chmod 700 "$ACC_DIR" 2>/dev/null || true
  [ -f "$REG" ] || printf '# Fable Toolkit accounts. provider|name|location|id|envvar. Written by accounts.sh.\n' >"$REG"
  printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >>"$REG"
}

not_installed() {
  say "  $P_LABEL is not on your PATH (command '$P_BIN'). Install it, then pick it again."
}

add_login() { # claude | codex | grok
  command -v "$P_BIN" >/dev/null 2>&1 || { not_installed; return; }
  ask_name "$PROV" || { say "  Cancelled."; return; }
  _dir="$ACC_DIR/$PROV/$NAME"
  _fresh=no; [ -d "$_dir" ] || _fresh=yes
  mkdir -p "$_dir"
  ask_id
  _flags=""
  if [ "$PROV" = codex ] || [ "$PROV" = grok ]; then
    prompt "  Is this a remote or headless machine with no browser? [y/N]"
    case "$(lower "$REPLY_TXT")" in y | yes) _flags="--device-auth" ;; esac
  fi
  if [ "$PROV" = claude ] && [ -n "$ACC_ID" ]; then
    case "$ACC_ID" in *@*) _flags="--email $ACC_ID" ;; esac
  fi
  say "  Signing in '$NAME'. Open the web address it prints (a browser may open by itself),"
  say "  sign in with the account you want for '$NAME', then come back here."
  if [ "$REAL_TTY" = yes ]; then
    # $_flags is deliberately unquoted: it is empty, one word, or "--email address".
    # shellcheck disable=SC2086
    case "$PROV" in
      claude) cenv CLAUDE_CONFIG_DIR="$_dir" claude auth login $_flags <&3 >&4 2>&1 || true ;;
      codex) cenv CODEX_HOME="$_dir" codex login $_flags <&3 >&4 2>&1 || true ;;
      grok) GROK_HOME="$_dir" grok login $_flags <&3 >&4 2>&1 || true ;;
    esac
  else
    say "  (answers file in use, so skipping the real sign-in: $P_ENV=$_dir $P_BIN login $_flags)"
  fi
  _ok=no
  case "$PROV" in
    claude) cenv CLAUDE_CONFIG_DIR="$_dir" claude auth status </dev/null >/dev/null 2>&1 && _ok=yes ;;
    codex)
      _out="$(cenv CODEX_HOME="$_dir" codex login status </dev/null 2>&1)"
      if ! printf '%s' "$_out" | grep -qi 'not logged in' && printf '%s' "$_out" | grep -qi 'logged in'; then _ok=yes; fi ;;
    grok) [ -s "$_dir/auth.json" ] && _ok=yes ;;
  esac
  if [ "$_ok" = yes ]; then
    say "  Signed in: $P_LABEL account '$NAME'."
    record "$PROV" "$NAME" "$_dir" "$ACC_ID" "$P_ENV"
    say "  Note: this folder starts empty, so it has none of your Claude/Codex settings or the toolkit's skills."
  else
    say "  '$NAME' is not signed in, so it was not saved. Pick $P_LABEL again to retry."
    [ "$_fresh" = yes ] && rm -rf "$_dir"
  fi
}

add_firstrun() { # agy, gemini, qwen, kimi, copilot, cursor
  command -v "$P_BIN" >/dev/null 2>&1 || { not_installed; return; }
  ask_name "$PROV" || { say "  Cancelled."; return; }
  say "  $P_LABEL signs you in the first time you start it. Fable Toolkit does not run or check that step."
  say "  Open another terminal, run:  $P_BIN"
  say "  and sign in using what it shows, then close it and come back here."
  say "  It keeps one signed-in account per computer user, so only the account signed in right now works."
  ask_id
  prompt "  Press Enter once you have signed in, or type skip:"
  if [ "$EOF_HIT" = yes ]; then say "  Skipped $P_LABEL."; return; fi
  case "$(lower "$REPLY_TXT")" in
    "" | y | yes | signed) ;;
    *) say "  Skipped $P_LABEL."; return ;;
  esac
  record "$PROV" "$NAME" "this computer user" "$ACC_ID" ""
  say "  Noted: $P_LABEL account '$NAME' (not verified by Fable Toolkit)."
}

add_apikey() {
  if [ "$PROV" = custom ]; then
    prompt "  What is the service called (for example Perplexity)?"
    [ "$EOF_HIT" = yes ] && return
    _svc="$(printf '%s' "$REPLY_TXT" | tr -c 'A-Za-z0-9_\n-' '-')"
    [ -n "$_svc" ] || { say "  Skipped."; return; }
    prompt "  Name of the environment variable it expects (for example PERPLEXITY_API_KEY):"
    [ "$EOF_HIT" = yes ] && return
    _env="$(printf '%s' "$REPLY_TXT" | tr -c 'A-Za-z0-9_\n' '_')"
    [ -n "$_env" ] || { say "  Skipped."; return; }
    _prov="$_svc"
  else
    _env="$P_ENV"
    _prov="$PROV"
    say "  $P_LABEL uses an API key (the provider bills API use to your account)."
    say "  Create one on the provider's website, as its own docs describe: $P_URL"
  fi
  ask_name "$_prov" || { say "  Cancelled."; return; }
  ask_id
  prompt_secret "  Paste the API key (nothing shows while you type), or press Enter to skip:"
  if [ -z "$REPLY_TXT" ]; then
    say "  Skipped."
    return
  fi
  mkdir -p "$ACC_DIR/keys"
  chmod 700 "$ACC_DIR" "$ACC_DIR/keys" 2>/dev/null || true
  _file="$ACC_DIR/keys/$_prov-$NAME.key"
  ( umask 077; printf '%s\n' "$REPLY_TXT" >"$_file" )
  chmod 600 "$_file" 2>/dev/null || true
  REPLY_TXT=""
  say "  Saved the key for '$NAME' to $_file. Keep that file private."
  record "$_prov" "$NAME" "$_file" "$ACC_ID" "$_env"
}

if [ "$ASK_FIRST" = yes ]; then
  prompt "Sign in to your AI accounts now (Claude, Codex, Grok, DeepSeek and more)? [Y/n]"
  case "$(lower "$REPLY_TXT")" in
    n | no | skip | later | q | cancel) say "Skipped. Run it any time:  bash $ACC_DIR/accounts.sh"; exit 0 ;;
  esac
  [ "$EOF_HIT" = yes ] && exit 0
fi

say ""
say "Account sign-in. I will keep asking until you type done."
say "You can add as many accounts as you like, including several of the same service."
say "This saves your sign-ins and a list of them. The team does not use the list yet."
warn_env
while :; do
  say ""
  say "Saved so far:"
  list_accounts
  say ""
  say "Which service do you want to sign in to?"
  say "   1) Claude Code        2) Codex              3) Grok"
  say "   4) Antigravity (agy)  5) Gemini CLI         6) Qwen Code"
  say "   7) Kimi               8) GitHub Copilot     9) Cursor Agent"
  say "  10) DeepSeek          11) OpenRouter        12) Groq"
  say "  13) Mistral           14) Z.ai (GLM)        15) Together AI"
  say "  16) Another service (API key)"
  prompt "Type a number or the name, or type done when you have finished:"
  [ "$EOF_HIT" = yes ] && break
  choice="$(lower "$REPLY_TXT")"
  if is_done "$choice"; then break; fi
  PROV=""
  case "$choice" in
    1 | claude*) PROV=claude ;;
    2 | codex* | openai | chatgpt) PROV=codex ;;
    3 | grok | xai) PROV=grok ;;
    4 | agy | antigravity) PROV=agy ;;
    5 | gemini*) PROV=gemini ;;
    6 | qwen* | alibaba) PROV=qwen ;;
    7 | kimi | moonshot) PROV=kimi ;;
    8 | copilot | github*) PROV=copilot ;;
    9 | cursor*) PROV=cursor ;;
    10 | deepseek) PROV=deepseek ;;
    11 | openrouter) PROV=openrouter ;;
    12 | groq) PROV=groq ;;
    13 | mistral | vibe) PROV=mistral ;;
    14 | zai | z.ai | glm | zhipu) PROV=zai ;;
    15 | together*) PROV=together ;;
    16 | other | custom | perplexity | cerebras) PROV=custom ;;
    "") say "Type a number from 1 to 16, or done when you have finished."; continue ;;
    *) say "I did not understand '$REPLY_TXT'. Type a number from 1 to 16, or done."; continue ;;
  esac
  set_provider "$PROV"
  case "$P_KIND" in
    login) add_login ;;
    firstrun) add_firstrun ;;
    apikey) add_apikey ;;
  esac
done

say ""
say "All done. Your accounts:"
list_accounts
say ""
# Keep a stable copy next to the list, so the command below survives plugin updates.
if [ -f "$0" ] && [ "$(cd "$(dirname "$0")" && pwd)" != "$ACC_DIR" ]; then
  mkdir -p "$ACC_DIR" && cp "$0" "$ACC_DIR/accounts.sh" 2>/dev/null || true
fi
say "Add or review later (in Git Bash on Windows):  bash ~/.fable-accounts/accounts.sh"
say "Other options: --list   --remove <service> <name>   --help"
say "Reminder: this only signs you in and saves the list. Keep your keys private, and use separate"
say "accounts for separate purposes; rotating personal subscriptions past usage limits may break a provider's terms."
