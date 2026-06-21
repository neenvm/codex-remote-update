#!/usr/bin/env zsh
set -euo pipefail

APP_PATH="${CODEX_APP_PATH:-/Applications/Codex.app}"
APP_ID="${CODEX_APP_ID:-com.openai.codex}"
LOG_DIR="${CODEX_UPDATE_LOG_DIR:-$HOME/Library/Logs/codex-remote-update}"
MODE="install"
CHECK_TIMEOUT="${CODEX_UPDATE_CHECK_TIMEOUT:-45}"
RELAUNCH_TIMEOUT="${CODEX_UPDATE_RELAUNCH_TIMEOUT:-240}"

usage() {
  cat <<'USAGE'
Usage:
  codex-remote-update [--install] [--status] [--check-only] [--help]

Updates the local macOS Codex.app through the normal Sparkle UI, then verifies
that Codex and its app-server are running again. Designed for use on the Mac
mini from any cwd or over a remote shell.

Options:
  --install     Check for updates and install/relaunch if one is ready. Default.
  --check-only  Open the updater and report the dialog text without installing.
  --status      Print installed versions and current Codex processes only.
  --help        Show this help.

Environment:
  CODEX_APP_PATH                 Defaults to /Applications/Codex.app
  CODEX_UPDATE_CHECK_TIMEOUT     Seconds to wait for the update dialog, default 45
  CODEX_UPDATE_RELAUNCH_TIMEOUT  Seconds to wait for relaunch verification, default 240
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) MODE="install" ;;
    --check-only) MODE="check-only" ;;
    --status) MODE="status" ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/$RUN_ID.log"
LATEST_LOG="$LOG_DIR/latest.log"

log() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*"
  print -r -- "$line"
  print -r -- "$line" >> "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

app_version() {
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    -c 'Print :CFBundleVersion' \
    "$APP_PATH/Contents/Info.plist"
}

cli_version() {
  "$APP_PATH/Contents/Resources/codex" --version
}

codex_processes() {
  /bin/ps -axo pid,etime,command \
    | /usr/bin/grep -E '(/Applications/Codex\.app/Contents/MacOS/Codex|/Applications/Codex\.app/Contents/Resources/codex app-server)' \
    | /usr/bin/grep -v grep || true
}

status() {
  [[ -d "$APP_PATH" ]] || die "Codex app not found at $APP_PATH"
  log "Codex app path: $APP_PATH"
  log "Codex app version/build:"
  app_version | tee -a "$LOG_FILE"
  log "Codex bundled CLI:"
  cli_version | tee -a "$LOG_FILE"
  log "Codex GUI/app-server processes:"
  codex_processes | tee -a "$LOG_FILE"
}

clear_skipped_update() {
  if /usr/bin/defaults read "$APP_ID" SUSkippedVersion >/dev/null 2>&1; then
    local skipped
    skipped="$(/usr/bin/defaults read "$APP_ID" SUSkippedVersion 2>/dev/null || true)"
    log "Clearing skipped Sparkle version: $skipped"
    /usr/bin/defaults delete "$APP_ID" SUSkippedVersion >/dev/null 2>&1 || true
  else
    log "No skipped Sparkle version set."
  fi
}

open_update_dialog() {
  log "Opening Codex updater UI."
  /usr/bin/osascript <<OSA >> "$LOG_FILE" 2>&1
tell application id "$APP_ID" to activate
delay 0.5
tell application "System Events"
  tell process "Codex"
    click menu item "Check for Updates…" of menu "Codex" of menu bar 1
  end tell
end tell
OSA
}

update_ui_dump() {
  /usr/bin/osascript <<'OSA' 2>/dev/null || true
tell application "System Events"
  if not (exists process "Codex") then return "NO_CODEX_PROCESS"
  tell process "Codex"
    set out to ""
    repeat with w in windows
      try
        set out to out & "WINDOW=" & (name of w as text) & linefeed
      end try
      try
        set textValues to value of static texts of w
        repeat with t in textValues
          set out to out & "TEXT=" & (t as text) & linefeed
        end repeat
      end try
      try
        set buttonNames to name of buttons of w
        repeat with b in buttonNames
          set out to out & "BUTTON=" & (b as text) & linefeed
        end repeat
      end try
    end repeat
    return out
  end tell
end tell
OSA
}

wait_for_update_dialog() {
  local dump=""
  local deadline=$((SECONDS + CHECK_TIMEOUT))
  while (( SECONDS < deadline )); do
    dump="$(update_ui_dump)"
    if [[ "$dump" == *"new version"* || "$dump" == *"ready to install"* || "$dump" == *"up to date"* || "$dump" == *"up-to-date"* || "$dump" == *"currently up-to-date"* || "$dump" == *"latest version"* ]]; then
      print -r -- "$dump"
      return 0
    fi
    sleep 1
  done
  print -r -- "$dump"
  return 1
}

start_backup_reopen() {
  local helper_log="$LOG_DIR/$RUN_ID-reopen-helper.log"
  log "Starting finite backup reopen helper: $helper_log"
  /usr/bin/nohup /bin/zsh -lc "
    {
      echo '[codex-remote-update helper] started at ' \$(date)
      sleep 90
      if /usr/bin/pgrep -x Codex >/dev/null 2>&1; then
        echo '[codex-remote-update helper] Codex already running; no backup open needed'
      else
        echo '[codex-remote-update helper] Codex missing; opening $APP_PATH'
        /usr/bin/open -a '$APP_PATH'
      fi
      sleep 20
      echo '[codex-remote-update helper] app version/build:'
      /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' '$APP_PATH/Contents/Info.plist' 2>&1
      echo '[codex-remote-update helper] cli version:'
      '$APP_PATH/Contents/Resources/codex' --version 2>&1
      echo '[codex-remote-update helper] finished at ' \$(date)
    } >> '$helper_log' 2>&1
  " >/dev/null 2>&1 &
  disown || true
}

press_default_install() {
  log "Pressing the updater dialog default action."
  /usr/bin/osascript <<OSA >> "$LOG_FILE" 2>&1
tell application id "$APP_ID" to activate
delay 0.2
tell application "System Events" to key code 36
OSA
}

confirm_quit_if_prompted() {
  local clicked=""
  local deadline=$((SECONDS + 20))
  while (( SECONDS < deadline )); do
    clicked="$(/usr/bin/osascript <<'OSA' 2>/dev/null || true
tell application "System Events"
  if not (exists process "Codex") then return "NO_CODEX_PROCESS"
  tell process "Codex"
    repeat with w in windows
      try
        if (name of buttons of w) contains "Quit" then
          click button "Quit" of w
          return "CLICKED_QUIT"
        end if
      end try
    end repeat
  end tell
end tell
return "NO_QUIT_PROMPT"
OSA
)"
    log "Quit prompt check: $clicked"
    [[ "$clicked" == "CLICKED_QUIT" || "$clicked" == "NO_CODEX_PROCESS" ]] && return 0
    sleep 1
  done
  log "No quit prompt clicked; continuing to relaunch verification."
}

wait_for_relaunch() {
  local old_version="$1"
  local deadline=$((SECONDS + RELAUNCH_TIMEOUT))
  local current_version=""
  log "Waiting for Codex relaunch/app-server verification."
  while (( SECONDS < deadline )); do
    current_version="$(app_version | tr '\n' ' ' 2>/dev/null || true)"
    if /usr/bin/pgrep -x Codex >/dev/null 2>&1 \
      && /usr/bin/pgrep -f "$APP_PATH/Contents/Resources/codex app-server" >/dev/null 2>&1; then
      log "Codex is running. Version/build: $current_version"
      if [[ -n "$old_version" && "$current_version" == "$old_version" ]]; then
        log "Version unchanged from before; this can be normal if no update was pending."
      fi
      return 0
    fi
    sleep 2
  done
  die "Timed out waiting for Codex/app-server to relaunch."
}

main() {
  : > "$LOG_FILE"
  ln -sf "$LOG_FILE" "$LATEST_LOG"
  log "Log file: $LOG_FILE"

  if [[ "$MODE" == "status" ]]; then
    status
    return
  fi

  [[ -d "$APP_PATH" ]] || die "Codex app not found at $APP_PATH"
  local before
  before="$(app_version | tr '\n' ' ')"
  status
  clear_skipped_update
  open_update_dialog

  local dialog
  if ! dialog="$(wait_for_update_dialog)"; then
    print -r -- "$dialog" >> "$LOG_FILE"
    die "Could not identify the Sparkle update dialog within ${CHECK_TIMEOUT}s. See $LOG_FILE"
  fi

  log "Updater dialog:"
  print -r -- "$dialog" | tee -a "$LOG_FILE"

  if [[ "$dialog" == *"up to date"* || "$dialog" == *"up-to-date"* || "$dialog" == *"currently up-to-date"* || "$dialog" == *"latest version"* ]]; then
    log "No update appears to be pending."
    return
  fi

  if [[ "$MODE" == "check-only" ]]; then
    log "Check-only mode; not installing."
    return
  fi

  start_backup_reopen
  press_default_install
  confirm_quit_if_prompted
  wait_for_relaunch "$before"
  status
  log "Codex remote update flow complete."
}

main "$@"
