# MustardOS_RemoteAI – installation, configuration, usage

Author: Patryk Strzelecki <patryk@strzelecki.info>

From a muOS console (developed on an Anbernic RG35XX H with a Bluetooth keyboard) you SSH into a Windows
laptop/PC and attach to AI CLI sessions (Claude Code, agy, or any other CLI you configure) running there
inside [psmux](https://github.com/marlocarlo/psmux). The same session is visible on the PC and on the console.

## Requirements
- **PC:** Windows 10/11, PowerShell 7, the AI CLI tools you want to use, an account that logs in to the desktop.
  The installer adds psmux (winget) and the Windows OpenSSH Server feature. PuTTY (`plink`) is used for the
  upload to the console if installed, otherwise the built-in OpenSSH client.
- **Console:** muOS with SSH enabled (default login `root`/`root`), `muxterm`, an SD card for the files
  (SD2 recommended – it survives muOS reinstalls). Both devices on the same network.

## Installation
1. Clone/copy this folder anywhere on the PC (it stays there – the scripts run from it).
2. Copy `mustardos-remoteai.conf.example` to **`mustardos-remoteai.conf`** and fill it in (IP addresses, Windows user,
   projects folder, AI tools, console login). This file is in `.gitignore` – it never goes to the repository.
3. In PowerShell 7, in this folder: `.\install.ps1`
   - `laptop` – psmux, `~\.psmux.conf`, PowerShell profiles, scheduled task;
   - `console` – uploads the SSH client, scripts and apps to the console, generates the console key there and
     stores its public part in `CONSOLE_PUBKEY`;
   - `sshd` – asks for administrator rights (UAC), configures OpenSSH Server: key-only login, `LAPTOP_USER` only.

   Run single steps with `-Steps laptop|console|sshd`; `-DryRun` shows what would happen.
4. On the console: Applications → **Connect to Claude/Agy**. Leave Applications and enter again if the new apps don't show up.

After changing `mustardos-remoteai.conf`: laptop-side settings apply to new PowerShell windows / connections immediately;
for console-side settings (`LAPTOP_*`, `CONSOLE_*_DIR`) run `.\install.ps1 -Steps console`; for `LAPTOP_USER`,
`LAPTOP_SSH_PORT`, `CONSOLE_HOST`, `CONSOLE_PUBKEY` run `.\install.ps1 -Steps sshd`.

## Configuration – `mustardos-remoteai.conf`
One file for everything, see the comments in [`mustardos-remoteai.conf.example`](../mustardos-remoteai.conf.example).

| Key | Meaning |
|---|---|
| `LAPTOP_HOST`, `LAPTOP_USER`, `LAPTOP_SSH_PORT` | where the console connects and as whom |
| `PROJECTS_ROOT` | starting folder of the directory browser |
| `PWSH_EXE` | PowerShell 7 (sshd shell, scheduled task) |
| `AI_TOOL_<command>='<key>\|<name>\|<exe>'` | AI tools – one line each, add/remove freely |
| `AI_PASSTHRU_ARGS` | arguments that run a tool directly, without psmux |
| `CONSOLE_HOST`, `CONSOLE_USER`, `CONSOLE_PASSWORD`, `CONSOLE_SSH_PORT` | console login, used only by the installer |
| `CONSOLE_PUBKEY` | console public key allowed to log in to the PC (filled in by the installer) |
| `CONSOLE_BASE_DIR`, `CONSOLE_APP_DIR` | where the files go on the console |
| `BROWSER_MIN_NAME_WIDTH`, `SESSION_START_TIMEOUT`, `PSMUX_NO_WARM` | tuning |

The file is read by PowerShell on the PC. The console gets a generated copy with only the keys it needs
(`CONSOLE_BASE_DIR/mustardos-remoteai.conf`, no passwords). Another location: set `$env:MUSTARDOS_REMOTEAI_CONFIG`.

## Usage
**Console → Applications:**
- **Connect to Claude/Agy** – session menu:
  - list shows all sessions tagged with the tool (`[claude]`, `[agy]`, …, `[other]`); `number` = attach;
  - `n` = new session → pick the tool (keys from the config, Enter = the first one) → pick the directory;
  - `s` = PowerShell, `q` = quit, Enter = refresh. The list also refreshes by itself every 3 s while nothing is typed,
    so a session started on the PC appears without restarting the app.
  - Inside a session: **F8** (or **F12**) = detach (the tool keeps running); `Ctrl+b`, then `d` works too on the PC, but the console
    terminal does not pass `Ctrl+b` from a Bluetooth keyboard. The psmux status bar at the bottom shows `[session name]`,
    the detach hint and the time (`laptop\psmux.conf`).
  - **PgUp / PgDn** (on mini keyboards: Fn+↑ / Fn+↓) scroll in the session (e.g. Claude Code's transcript). The muOS
    terminal keeps these keys for itself, so a small keyboard proxy on the console passes them on as F9/F10 and psmux turns
    them back into PgUp/PgDn – nothing to configure. In **Connect to PowerShell** (no psmux) they arrive as F9/F10.
  - While the console is attached, the session is sized to the console screen (`window-size smallest`), so lines wrap
    correctly there; the PC window shows the same smaller area until the console detaches.
- **Directory browser** (starts in `PROJECTS_ROOT`): `number` = open subfolder, **Enter = start here**, `..` = up,
  any text = filter by name (a single match opens automatically), `/` = clear filter,
  `l` = last used directory, `q` = cancel. Folders are listed in columns fitted to the screen width (no paging;
  scroll if they do not fit), long names end with `...`.
- **Connect to PowerShell** – straight into PowerShell 7 on the PC.

**PC:** type `claude`, `agy` (or any configured tool) as usual – it starts inside psmux automatically
(session `<tool>-<dir>`). `ai-ls` = list sessions, `ai-attach [name]` = attach, `--no-mux` = run without psmux.
One-shot calls (`-p`, `--print`, `--version`, subcommands like `update`) run directly. Close all sessions: `psmux kill-server`.

## Troubleshooting
- **"Cannot connect to the laptop"** – PC off / different network / `sshd` stopped (`Get-Service sshd`) /
  wrong `LAPTOP_HOST` (reserve the PC's IP in the router, then `install.ps1 -Steps console`).
- **A tool says "not signed in" in a session started from the console** (agy) – nobody is logged in on the PC
  (e.g. after a reboot), or the scheduled task `MustardOS_RemoteAI Start Session` is missing (`install.ps1 -Steps laptop`).
  See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) → "Why a scheduled task".
- **"(no sessions)" although Claude is open on the PC** – that window runs outside psmux: one-shot calls and subcommands
  (`claude login`, `claude update`, `--no-mux`) are not wrapped. Close it and start plain `claude`; it shows up within 3 s.
- **Console IP changed** – update `CONSOLE_HOST`, run `install.ps1 -Steps sshd` (firewall rule).
- **App names/icons not refreshed on the console** – leave Applications and enter again, or reboot the console.
- **After a muOS reinstall** – files on SD2 survive; if `CONSOLE_APP_DIR` is gone, run `install.ps1 -Steps console`.
- **Test from the console:** `python3 <CONSOLE_BASE_DIR>/test-connect-ai-app.py [dir filter ...]`
  (walks through the menu, leaves 1–2 sessions on the PC).

## Repository contents
| Path | What it is |
|---|---|
| `mustardos-remoteai.conf.example` | configuration template (the real `mustardos-remoteai.conf` is git-ignored) |
| `install.ps1` | installer / updater (steps `laptop`, `console`, `sshd`) |
| `docs\USAGE.md` | this file |
| `docs\HOW-IT-WORKS.md` | architecture, flow, design decisions, gotchas |
| `docs\UNINSTALL.md` | every change made and how to revert it |
| `laptop\common.ps1` | reads the configuration (used by all laptop scripts) |
| `laptop\ai-mux.ps1` | AI tool commands, `ai-ls`, `ai-attach` (loaded from the PowerShell profiles) |
| `laptop\session-picker.ps1` | the session menu + directory browser shown on the console |
| `laptop\start-session.ps1` | creates a session inside the interactive Windows logon (run by the scheduled task) |
| `laptop\register-start-task.ps1` | registers that scheduled task |
| `laptop\setup-sshd.ps1` | configures OpenSSH Server (admin) |
| `laptop\psmux.conf` | installed as `~\.psmux.conf` |
| `console\mustardos_remoteai\` | → `CONSOLE_BASE_DIR`: `ssh-laptop.sh`, `dropbearmulti` (static Dropbear 2025.88 client, aarch64, see `DROPBEAR-LICENSE`), `kbd-proxy.py` (PgUp/PgDn → F9/F10), `test-connect-ai-app.py` |
| `console\application\` | → `CONSOLE_APP_DIR`: the two muOS apps (`mux_launch.sh`, `mux_lang.ini`, wrapper script, icon) |

Runtime files (git-ignored): `laptop\.last_dir`, `laptop\.session_request`, `laptop\*.log`.
