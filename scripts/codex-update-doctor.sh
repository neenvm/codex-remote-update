#!/bin/sh
set -eu

MODE="doctor"
MAC_APP_PATH="${CODEX_APP_PATH:-/Applications/Codex.app}"
MAC_UPDATER="${CODEX_MAC_UPDATER:-$(dirname "$0")/codex-remote-update.sh}"
ALLOW_UPDATE="${CODEX_UPDATE_ALLOW_APPLY:-0}"

usage() {
  cat <<'USAGE'
Usage:
  codex-update-doctor.sh [--doctor] [--status] [--app-status] [--cli-status]
                         [--app-server-status] [--check] [--install] [--help]

Codex-only cross-platform doctor for macOS, Linux, and WSL.

Modes:
  --doctor             Read-only OS, Codex app, CLI, and app-server report. Default.
  --status             Alias for --doctor.
  --app-status         Report Codex desktop app status where supported.
  --cli-status         Report Codex CLI status.
  --app-server-status  Report Codex app-server process status.
  --check              Read-only update path check.
  --install            Apply only known safe Codex update paths.
  --help               Show this help.

Environment:
  CODEX_APP_PATH=/Applications/Codex.app
  CODEX_MAC_UPDATER=path/to/codex-remote-update.sh
  CODEX_UPDATE_ALLOW_APPLY=1   Required for non-macOS CLI self-update.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --doctor|--status) MODE="doctor" ;;
    --app-status) MODE="app-status" ;;
    --cli-status) MODE="cli-status" ;;
    --app-server-status) MODE="app-server-status" ;;
    --check) MODE="check" ;;
    --install) MODE="install" ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

os_name() {
  uname -s 2>/dev/null || echo unknown
}

is_macos() {
  [ "$(os_name)" = "Darwin" ]
}

is_linux() {
  [ "$(os_name)" = "Linux" ]
}

is_wsl() {
  is_linux || return 1
  if [ -r /proc/version ] && grep -Eqi 'microsoft|wsl' /proc/version; then
    return 0
  fi
  return 1
}

section() {
  printf '\n== %s ==\n' "$1"
}

run_and_prefix() {
  label="$1"
  shift
  if output="$("$@" 2>&1)"; then
    printf '%s: %s\n' "$label" "$output"
    return 0
  fi
  status=$?
  printf '%s: unavailable (%s)\n' "$label" "$output"
  return "$status"
}

codex_cli_path() {
  command -v codex 2>/dev/null || true
}

codex_cli_status() {
  section "Codex CLI"
  cli="$(codex_cli_path)"
  if [ -z "$cli" ]; then
    echo "status: not found on PATH"
    echo "update: unavailable until Codex CLI is installed"
    return 1
  fi

  echo "path: $cli"
  run_and_prefix "version" "$cli" --version || true
  if "$cli" update --help >/dev/null 2>&1; then
    echo "self-update: codex update is available"
  else
    echo "self-update: codex update is not available for this install"
  fi
}

mac_app_status() {
  section "Codex macOS App"
  if ! is_macos; then
    echo "status: not supported on $(os_name)"
    echo "reason: Codex desktop app status in this script is macOS-only"
    return 1
  fi
  if [ ! -d "$MAC_APP_PATH" ]; then
    echo "status: not found at $MAC_APP_PATH"
    return 1
  fi
  if [ ! -f "$MAC_APP_PATH/Contents/Info.plist" ]; then
    echo "status: invalid app bundle, missing Info.plist"
    return 1
  fi

  echo "path: $MAC_APP_PATH"
  if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy \
      -c 'Print :CFBundleShortVersionString' \
      -c 'Print :CFBundleVersion' \
      -c 'Print :CFBundleIdentifier' \
      "$MAC_APP_PATH/Contents/Info.plist" \
      | awk 'NR==1{print "version: "$0} NR==2{print "build: "$0} NR==3{print "bundle-id: "$0}'
  fi
  if [ -x "$MAC_APP_PATH/Contents/Resources/codex" ]; then
    run_and_prefix "bundled-cli" "$MAC_APP_PATH/Contents/Resources/codex" --version || true
  fi
}

desktop_app_status() {
  case "$(os_name)" in
    Darwin)
      mac_app_status
      ;;
    Linux)
      section "Codex Desktop App"
      if is_wsl; then
        echo "status: not managed from WSL"
        echo "reason: use the Windows PowerShell doctor for the Windows Codex app"
      else
        echo "status: not supported"
        echo "reason: public Codex app docs advertise macOS and Windows app downloads, not a Linux desktop app"
      fi
      ;;
    *)
      section "Codex Desktop App"
      echo "status: unsupported OS for this shell script: $(os_name)"
      echo "hint: use scripts/codex-update-doctor.ps1 on Windows"
      ;;
  esac
}

app_server_status() {
  section "Codex app-server"
  if ps -axo pid=,command= 2>/dev/null | awk '/codex app-server/ && !/awk/ { found=1; print "process: pid=" $1 " " substr($0, index($0,$2)) } END { exit found ? 0 : 1 }'; then
    return 0
  fi
  echo "status: no codex app-server process found"
  return 1
}

update_check() {
  section "Update Check"
  case "$(os_name)" in
    Darwin)
      if [ -x "$MAC_UPDATER" ]; then
        echo "macOS app: use $MAC_UPDATER --check-only for Sparkle UI check"
      else
        echo "macOS app: updater script not executable at $MAC_UPDATER"
      fi
      ;;
    Linux)
      if is_wsl; then
        echo "Windows app: use scripts/codex-update-doctor.ps1 from PowerShell"
      else
        echo "Linux app: no native desktop app update path is advertised"
      fi
      ;;
  esac

  cli="$(codex_cli_path)"
  if [ -n "$cli" ] && "$cli" update --help >/dev/null 2>&1; then
    echo "CLI: codex update command is available"
  elif [ -n "$cli" ]; then
    echo "CLI: codex update command is not available for this install"
  else
    echo "CLI: codex not found on PATH"
  fi
}

install_update() {
  case "$(os_name)" in
    Darwin)
      if [ ! -x "$MAC_UPDATER" ]; then
        echo "ERROR: macOS updater script not executable at $MAC_UPDATER" >&2
        exit 1
      fi
      exec "$MAC_UPDATER" --install
      ;;
    Linux)
      cli="$(codex_cli_path)"
      if [ -z "$cli" ]; then
        echo "ERROR: codex CLI not found on PATH; refusing to install anything automatically." >&2
        exit 1
      fi
      if ! "$cli" update --help >/dev/null 2>&1; then
        echo "ERROR: codex update is not available for this CLI install; refusing unknown update path." >&2
        exit 1
      fi
      if [ "$ALLOW_UPDATE" != "1" ]; then
        echo "ERROR: set CODEX_UPDATE_ALLOW_APPLY=1 to run codex update on this platform." >&2
        exit 1
      fi
      exec "$cli" update
      ;;
    *)
      echo "ERROR: unsupported OS for install mode: $(os_name)" >&2
      exit 1
      ;;
  esac
}

doctor() {
  section "System"
  echo "os: $(os_name)"
  if is_wsl; then
    echo "environment: WSL"
  fi
  desktop_app_status || true
  codex_cli_status || true
  app_server_status || true
  update_check
}

case "$MODE" in
  doctor) doctor ;;
  app-status) desktop_app_status ;;
  cli-status) codex_cli_status ;;
  app-server-status) app_server_status ;;
  check) update_check ;;
  install) install_update ;;
esac
