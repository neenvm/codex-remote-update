# Security

`codex-remote-update` is intentionally small and auditable. The macOS updater is
a zsh script that automates the local macOS Codex.app updater UI and verifies
that Codex comes back after an update. The cross-platform doctor scripts are
read-only by default and report Codex app/CLI/app-server health.

The project scope is Codex-only. It should not be used or extended as a generic
updater for unrelated apps.

## Trust Boundary

The script runs with the permissions of the user who starts it. It does not ask
for `sudo`, install privileged helpers, store credentials, or call private
updater endpoints.

Expected sensitive capabilities:

- macOS Accessibility / System Events automation, so the script can click
  Codex.app's `Check for Updates...` menu item and press the updater dialog's
  default action.
- Normal Codex.app Sparkle update networking, performed by Codex.app/Sparkle
  after the user runs `--check-only` or `--install`.
- Local process inspection with `ps` and `pgrep`, used to report Codex GUI,
  app-server, and shell-visible worker activity.
- Windows process/Appx/winget inspection in the PowerShell doctor. Windows
  update application is intentionally refused until a safe package identity is
  verified on a real Windows host, unless `codex update` is available and the
  user opts in with `CODEX_UPDATE_ALLOW_APPLY=1`.
- Local log writes and a finite reopen helper script under
  `~/Library/Logs/codex-remote-update/` by default.
- A Codex.app preference write that clears `SUSkippedVersion` when Sparkle has a
  skipped update recorded.

## What It Does Not Do

- No `sudo`.
- No `curl | sh` installer.
- No credential reads or writes.
- No shelling out to package managers.
- No private API calls.
- No persistent `launchd`, `KeepAlive`, login item, or daemon installation.
- No app-bundle patching or manual replacement.
- No exchange/trading/payment behavior.
- No generic non-Codex app updates.

## How To Review Before Running

Clone the repository, inspect the script, then run read-only checks first:

```bash
git clone https://github.com/neenvm/codex-remote-update.git
cd codex-remote-update
less scripts/codex-remote-update.sh
zsh -n scripts/codex-remote-update.sh
scripts/codex-remote-update.sh --status
scripts/codex-remote-update.sh --quiet-check
scripts/codex-update-doctor.sh --doctor
```

`--status` only prints installed Codex versions and matching processes.
`--quiet-check` adds a conservative process check for active Codex workers.
`codex-update-doctor.sh --doctor` is read-only and adds Codex CLI/app-server
health reporting.

The actions that open the updater UI are:

```bash
scripts/codex-remote-update.sh --check-only
scripts/codex-remote-update.sh --install
```

Only `--install` can quit/relaunch Codex.

## Reporting Issues

Please open a GitHub issue with:

- macOS version.
- Codex app version/build from `--status`.
- The command you ran.
- Relevant lines from `~/Library/Logs/codex-remote-update/latest.log`.

Do not include credentials, private keys, tokens, or sensitive personal data in
issue reports.
