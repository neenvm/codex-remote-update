# Codex Remote Update

Safely update the macOS Codex desktop app from a remote shell while preserving a
way back into the app after it quits for the updater.

This is a small, macOS-only Codex skill and script. It uses the normal logged-in
Codex.app Sparkle updater UI, starts a finite backup reopen watchdog, and then
verifies that both the Codex GUI and `codex app-server` are running again.

## What It Is For

- Updating Codex on a Mac you are controlling remotely.
- Recovering from Codex desktop / Connections / app-server version mismatches.
- Checking the installed Codex GUI version, bundled CLI version, and app-server
  process from a terminal.
- Avoiding fragile persistent `launchd` reopen loops.

## What It Is Not

- Not a Linux, Windows, browser-only, or headless updater.
- Not a private updater client.
- Not an updater bypass, app-bundle patcher, or credential helper.
- Not a guarantee that private Codex internal thread state is idle.

The script only works on the Mac GUI host that owns the running Codex.app
session. If you are viewing that Mac through remote desktop, run this on the
remote Mac, not on the laptop or phone you are viewing from.

## Should I Trust This?

Read the script before you run it. The install path is `git clone`, not
`curl | sh`, so you can inspect exactly what will execute.

Safety-relevant facts:

- It does not use `sudo`.
- It does not install daemons, login items, or persistent `launchd` jobs.
- It does not store or read credentials.
- It does not call private update endpoints.
- It does not patch or replace the app bundle manually.
- It writes logs and a finite reopen helper script under
  `~/Library/Logs/codex-remote-update/` by default.
- It may clear Codex.app's skipped Sparkle update preference so the normal
  updater can check again.
- It uses macOS Accessibility / System Events only to drive Codex.app's normal
  updater UI.
- Only `--install` can quit/relaunch Codex.

Start with read-only checks:

```bash
scripts/codex-remote-update.sh --status
scripts/codex-remote-update.sh --quiet-check
```

See [SECURITY.md](SECURITY.md) for the full trust boundary.

## Install

Install as a Codex skill:

```bash
mkdir -p "$HOME/.codex/skills"
git clone https://github.com/neenvm/codex-remote-update.git "$HOME/.codex/skills/codex-remote-update"
```

Optional: make the script callable from any directory on the same Mac.

```bash
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.codex/skills/codex-remote-update/scripts/codex-remote-update.sh" \
  "$HOME/.local/bin/codex-remote-update"
```

Make sure `~/.local/bin` is on your `PATH` if you use the short command.

## Usage

From the skill directory:

```bash
scripts/codex-remote-update.sh --status
scripts/codex-remote-update.sh --quiet-check
scripts/codex-remote-update.sh --check-only
scripts/codex-remote-update.sh --install
```

If you installed the optional symlink:

```bash
codex-remote-update --status
codex-remote-update --quiet-check
codex-remote-update --check-only
codex-remote-update --install
```

Over SSH:

```bash
ssh <mac-host> 'zsh -lc "codex-remote-update --status"'
ssh <mac-host> 'zsh -lc "codex-remote-update --quiet-check"'
ssh <mac-host> 'zsh -lc "codex-remote-update --install"'
```

## Recommended Flow

1. Confirm you are on the Mac that owns the Codex GUI session.
2. Run `codex-remote-update --status`.
3. Run `codex-remote-update --quiet-check`.
4. Run `codex-remote-update --check-only` if you only want to inspect whether
   Sparkle reports an update.
5. Run `codex-remote-update --install` only when it is acceptable for Codex to
   quit and relaunch.
6. Reconnect if needed, then run `codex-remote-update --status` or inspect
   `~/Library/Logs/codex-remote-update/latest.log`.

`--install` refuses by default if it sees shell-visible Codex worker activity.
Use `--force-active` only when you explicitly accept interrupting active work.

## Options

```text
--install              Check for updates and install/relaunch if one is ready. Default.
--check-only           Open the updater and report the dialog text without installing.
--status               Print installed versions and current Codex processes only.
--quiet-check          Report whether shell-visible Codex worker activity looks quiet.
--test-reopen-helper   Start only the finite backup reopen watchdog.
--force-active         Allow install even if the quiet check sees active workers.
--help                 Show script help.
```

## Environment

```text
CODEX_APP_PATH=/Applications/Codex.app
CODEX_APP_ID=com.openai.codex
CODEX_UPDATE_LOG_DIR=~/Library/Logs/codex-remote-update
CODEX_UPDATE_CHECK_TIMEOUT=45
CODEX_UPDATE_RELAUNCH_TIMEOUT=240
CODEX_UPDATE_HELPER_TIMEOUT=600
CODEX_UPDATE_HELPER_INTERVAL=10
CODEX_UPDATE_ACTIVE_CPU_THRESHOLD=5.0
CODEX_UPDATE_ALLOW_ACTIVE_THREADS=1
```

## Logs

Every run writes a timestamped log under:

```text
~/Library/Logs/codex-remote-update/
```

The latest run is also linked at:

```text
~/Library/Logs/codex-remote-update/latest.log
```

If an install causes a disconnect, the backup watchdog writes its own
`*-reopen-helper.log` in the same directory. The watchdog exits after Codex GUI
and `codex app-server` are both detected, or after its timeout.

## Safety Notes

- The script uses Codex.app's normal `Check for Updates...` menu item.
- It clears a skipped Sparkle version when one is set, then asks Sparkle to
  check again.
- It does not call private update endpoints.
- It does not store credentials.
- It does not install persistent `launchd` jobs.
- It cannot see private Codex internal thread state, so `--quiet-check` is a
  conservative shell-process check rather than a perfect idle detector.

## Troubleshooting

If the updater UI cannot be found, verify that you are in a logged-in macOS GUI
session and that Accessibility permissions allow terminal automation of Codex.

If Codex updates but remote control still looks broken, verify all three pieces:

```bash
codex-remote-update --status
pgrep -x Codex
pgrep -f "/Applications/Codex.app/Contents/Resources/codex app-server"
```

If an older failed experiment left a persistent reopen job behind, inspect
`launchctl print gui/$(id -u)` for names such as `codex-force-restart-*` or
`codex-reopen-after-*`, then unload only the stale job after confirming Codex is
running normally.

## Repository Layout

```text
LICENSE                         MIT license
SECURITY.md                     Security model and review guidance
SKILL.md                         Codex skill instructions
agents/openai.yaml               Skill display metadata
scripts/codex-remote-update.sh   Update/check/watchdog script
```

## License

MIT. See [LICENSE](LICENSE).
