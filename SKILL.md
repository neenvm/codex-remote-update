---
name: codex-remote-update
description: macOS-only workflow to safely update and relaunch the macOS Codex desktop app from a remote shell using the normal Sparkle updater UI. Use when the user asks to update Codex on a Mac, fix a remote Connections/app-server version mismatch, ensure Codex reopens after updating, check the installed Codex GUI/CLI/app-server version, or avoid persistent launchd reopen loops on a Mac host.
---

# Codex Remote Update

## Overview

Use the bundled script to update Codex on the active macOS GUI host without leaving a persistent reopen loop. This skill is macOS-only because it depends on Codex.app, Sparkle, `osascript`, `open`, and the logged-in GUI session. The script checks versions, clears a skipped Sparkle version if present, opens Codex's normal `Check for Updates...` flow, starts a finite backup reopen watchdog, installs the update if one is ready, and verifies that both the GUI and `codex app-server` are running again.

## Quick Start

Install as a Codex skill from GitHub:

```bash
mkdir -p "$HOME/.codex/skills"
git clone https://github.com/neenvm/codex-remote-update.git "$HOME/.codex/skills/codex-remote-update"
```

From the skill directory:

```bash
scripts/codex-remote-update.sh --status
scripts/codex-remote-update.sh --quiet-check
scripts/codex-remote-update.sh --check-only
scripts/codex-remote-update.sh --install
```

To make it callable from any directory on the same Mac:

```bash
mkdir -p "$HOME/.local/bin"
ln -sf "$PWD/scripts/codex-remote-update.sh" "$HOME/.local/bin/codex-remote-update"
codex-remote-update --status
```

To trigger it over SSH from another machine:

```bash
ssh <mac-host> 'zsh -lc "codex-remote-update --install"'
```

## Workflow

1. Verify the target machine is the Mac that owns the Codex GUI/session. For remote-control issues, update the host shown in Connections, not the laptop viewing it.
2. Run `scripts/codex-remote-update.sh --status` to capture the current GUI version, bundled CLI version, and app-server process.
3. Run `scripts/codex-remote-update.sh --quiet-check` to make sure no shell-visible active Codex worker processes are running. This is conservative but cannot read private Codex internal thread state.
4. Run `scripts/codex-remote-update.sh --check-only` when you want to confirm whether Sparkle has an update ready without restarting Codex.
5. Run `scripts/codex-remote-update.sh --install` when a restart is acceptable. By default install refuses if the quiet check sees active Codex worker activity. Expect a brief disconnect if the current conversation is inside Codex.
6. After reconnecting, run `scripts/codex-remote-update.sh --status` or inspect `~/Library/Logs/codex-remote-update/latest.log`.

## Guardrails

- Use the normal logged-in macOS app and Sparkle updater UI only.
- Do not use this skill for Linux, Windows, web-only Codex, or non-GUI hosts.
- Default install must pass the quiet check first. Use `--force-active` only when the user explicitly accepts interrupting active Codex work.
- Do not use private updater endpoints or manual app-bundle surgery.
- Do not create persistent `launchctl` or `KeepAlive` reopen jobs. The bundled script uses a finite detached watchdog that repeatedly reopens Codex until GUI plus app-server are back, then exits.
- If a previous failed update left jobs such as `codex-force-restart-*` or `codex-reopen-after-*`, unload them after verifying Codex is running.
- Preserve user work: warn that the update will quit/relaunch Codex when running from an active Codex chat.

## Script

The deterministic implementation is `scripts/codex-remote-update.sh`. Read or patch the script only when behavior needs to change; otherwise execute it directly.
