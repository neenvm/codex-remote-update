---
name: codex-remote-update
description: Codex-only update and health workflow. Use the macOS Sparkle updater/watchdog for Codex.app, and the doctor scripts to inspect Codex app, CLI, and app-server health on macOS, Windows, Linux, or WSL.
---

# Codex Remote Update

## Overview

Use the bundled scripts for Codex-only update and health workflows. The macOS
remote updater updates Codex on the active macOS GUI host without leaving a
persistent reopen loop. It depends on Codex.app, Sparkle, `osascript`, `open`,
and the logged-in GUI session.

The cross-platform doctor scripts provide read-only Codex app/CLI/app-server
status on macOS, Windows, Linux, and WSL. They refuse unknown update paths.

## Quick Start

Install as a Codex skill from GitHub:

```bash
mkdir -p "$HOME/.codex/skills"
git clone https://github.com/neenvm/codex-remote-update.git "$HOME/.codex/skills/codex-remote-update"
```

From the skill directory:

```bash
scripts/codex-update-doctor.sh --doctor
scripts/codex-remote-update.sh --status
scripts/codex-remote-update.sh --quiet-check
scripts/codex-remote-update.sh --check-only
scripts/codex-remote-update.sh --install
```

On Windows PowerShell:

```powershell
.\scripts\codex-update-doctor.ps1 -Doctor
.\scripts\codex-update-doctor.ps1 -Check
```

To make it callable from any directory on the same Mac:

```bash
mkdir -p "$HOME/.local/bin"
ln -sf "$PWD/scripts/codex-remote-update.sh" "$HOME/.local/bin/codex-remote-update"
ln -sf "$PWD/scripts/codex-update-doctor.sh" "$HOME/.local/bin/codex-update-doctor"
codex-update-doctor --doctor
codex-remote-update --status
```

To trigger it over SSH from another machine:

```bash
ssh <mac-host> 'zsh -lc "codex-remote-update --install"'
```

## Workflow

1. Run the read-only doctor first. On macOS/Linux/WSL use `scripts/codex-update-doctor.sh --doctor`; on Windows use `.\scripts\codex-update-doctor.ps1 -Doctor`.
2. Verify the target machine is the Mac that owns the Codex GUI/session before using the macOS app updater. For remote-control issues, update the host shown in Connections, not the laptop viewing it.
3. Run `scripts/codex-remote-update.sh --status` to capture the current GUI version, bundled CLI version, and app-server process.
4. Run `scripts/codex-remote-update.sh --quiet-check` to make sure no shell-visible active Codex worker processes are running. This is conservative but cannot read private Codex internal thread state.
5. Run `scripts/codex-remote-update.sh --check-only` when you want to confirm whether Sparkle has an update ready without restarting Codex.
6. Run `scripts/codex-remote-update.sh --install` when a restart is acceptable. By default install refuses if the quiet check sees active Codex worker activity. Expect a brief disconnect if the current conversation is inside Codex.
7. After reconnecting, run `scripts/codex-remote-update.sh --status` or inspect `~/Library/Logs/codex-remote-update/latest.log`.

## Guardrails

- Use the normal logged-in macOS app and Sparkle updater UI only.
- Use doctor scripts for Windows, Linux, WSL, web-only, or non-GUI hosts.
- Default install must pass the quiet check first. Use `--force-active` only when the user explicitly accepts interrupting active Codex work.
- Do not use private updater endpoints or manual app-bundle surgery.
- Do not create persistent `launchctl` or `KeepAlive` reopen jobs. The bundled script uses a finite detached watchdog that repeatedly reopens Codex until GUI plus app-server are back, then exits.
- Do not claim Linux Codex desktop app update support unless OpenAI publishes a Linux desktop app.
- If a previous failed update left jobs such as `codex-force-restart-*` or `codex-reopen-after-*`, unload them after verifying Codex is running.
- Preserve user work: warn that the update will quit/relaunch Codex when running from an active Codex chat.

## Script

The macOS updater implementation is `scripts/codex-remote-update.sh`. The
cross-platform doctor implementations are `scripts/codex-update-doctor.sh` and
`scripts/codex-update-doctor.ps1`. Read or patch scripts only when behavior
needs to change; otherwise execute them directly.
