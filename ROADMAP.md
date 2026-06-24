# Codex-Only Cross-Platform Roadmap

This project is for Codex update and health workflows only. It should not become
a generic desktop app updater.

The macOS desktop updater is intentionally macOS-only because it automates the
local Codex.app Sparkle updater UI and verifies that Codex GUI plus
`codex app-server` come back afterward. Cross-platform support is implemented as
doctor/status scripts that report Codex app, CLI, and app-server health.

Reference docs:

- Codex app: https://developers.openai.com/codex/app
- Codex app for Windows: https://developers.openai.com/codex/app/windows
- Codex CLI: https://developers.openai.com/codex/cli
- Codex CLI reference: https://developers.openai.com/codex/cli/reference

## Design Goal

Build toward a cross-platform Codex update doctor that can safely answer:

- Which Codex surfaces are installed here?
- What versions are installed?
- Is the app-server or remote-control path healthy?
- Is there an official update path for this platform?
- Can an update be applied safely without interrupting active work?

Only apply updates through official Codex, operating-system, package-manager, or
app-store mechanisms. Do not download opaque binaries, patch app bundles, call
private endpoints, or install persistent privileged helpers.

## Platform Scope

### macOS

Current support:

- Codex desktop app status.
- Bundled Codex CLI version.
- `codex app-server` process verification.
- Normal Codex.app Sparkle updater UI.
- Finite reopen watchdog.
- Cross-platform doctor via `scripts/codex-update-doctor.sh`.

Possible future support:

- Prefer `codex update` for standalone CLI installs when available.
- Separate app update and CLI update checks when the installed CLI is not the
  app-bundled CLI.

### Windows

Current support:

- Detect Codex desktop app installation from Appx package metadata.
- Detect Codex CLI on `PATH`.
- Report Codex app, CLI, and app-server status.
- Report whether `winget` can see a Codex package from the Microsoft Store
  source.
- Run `codex update` only when available and explicitly allowed with
  `CODEX_UPDATE_ALLOW_APPLY=1`.

Planned support:

- Prefer official Windows update paths such as Microsoft Store or `winget` only
  after exact package identity is verified on a real Windows host.

Safety constraints:

- No UI automation unless an official command-line or package-manager path is
  unavailable and the behavior is explicitly documented.
- No registry writes except read-only detection unless a future official Codex
  Windows workflow requires it and the user opts in.
- No PowerShell execution policy changes.
- No background services or scheduled tasks installed by this project.

Open questions to verify on a real Windows host:

- Exact package id and `winget` upgrade behavior for Codex.
- Where the Codex app stores its app-server executable and process name.
- Whether `codex update` is available and reliable for the installed CLI.
- How to distinguish Windows-native Codex from WSL Codex safely.

### Linux

Current support:

- Codex CLI status and version detection.
- `codex update` support when available and explicitly allowed with
  `CODEX_UPDATE_ALLOW_APPLY=1`.
- WSL-aware reporting that points Windows app checks to the PowerShell doctor.

Planned support:

- Official installer guidance when self-update is unavailable.

Non-goal for now:

- Native Codex desktop app update support. The public Codex app docs currently
  advertise macOS and Windows app downloads, not a Linux desktop app.

Safety constraints:

- Do not pipe remote install scripts directly into `sh` by default.
- If official reinstall is needed, print reviewable commands or download the
  installer to a file for inspection before execution.
- Do not use `sudo` automatically.
- Do not modify shell profiles, system package sources, or service managers.

## Proposed Command Shape

Keep the current macOS commands working:

```bash
codex-remote-update --status
codex-remote-update --quiet-check
codex-remote-update --check-only
codex-remote-update --install
```

For cross-platform work, add safer neutral commands before adding installers:

```bash
scripts/codex-update-doctor.sh --doctor
scripts/codex-update-doctor.sh --app-status
scripts/codex-update-doctor.sh --cli-status
scripts/codex-update-doctor.sh --app-server-status
scripts/codex-update-doctor.sh --check
```

`--install` should remain platform-gated and refuse when the safe official path
for the detected platform/install type is unknown.

## Implementation Phases

1. Refactor the current script into small platform/status functions without
   changing macOS behavior. Partial: added separate doctor scripts.
2. Add read-only OS detection and Codex CLI detection for macOS, Windows, Linux,
   and WSL. Done.
3. Add `--doctor` as a read-only report. Done.
4. Add `--check` for update availability where an official check path exists.
5. Add Windows update support only after testing on a real Windows machine.
6. Add Linux CLI update support only through official CLI mechanisms.

## Verification Requirements

Every platform backend needs:

- Read-only status command.
- Negative tests for malformed paths/config.
- Proof it does not require elevated permissions for status/check.
- Proof it refuses unknown install types.
- Proof it does not install persistence.
- Clear logs showing what was checked and what was changed.
