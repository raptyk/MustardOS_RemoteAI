# How it works

Names in `CAPS` are keys from `mustardos-remoteai.conf`.

```
CONSOLE (CONSOLE_BASE_DIR, CONSOLE_APP_DIR)           PC (Windows)
CONSOLE_APP_DIR/Connect to Claude-Agy/mux_launch.sh
 └ muxterm (terminal + keyboard)
    └ session-menu.sh → CONSOLE_BASE_DIR/ssh-laptop.sh menu
       └ dbclient (Dropbear) ──SSH, ed25519 key──▶ sshd (Windows service, LAPTOP_SSH_PORT)
                                                   └ pwsh → laptop\session-picker.ps1 (menu)
                                                      ├ attach:  psmux attach → existing session
                                                      └ new:     task "MustardOS_RemoteAI Start Session"
                                                                 → start-session.ps1 (interactive logon)
                                                                 → psmux new-session -d → AI tool
                                                                 then psmux attach
```

## Configuration
- `mustardos-remoteai.conf` (repo root, git-ignored) is the single source of settings. Format `KEY='value'`,
  a subset of sh syntax that PowerShell parses too (`laptop\common.ps1` → `$RemoteAI`).
- The console never reads the PC's file: `install.ps1 -Steps console` writes `CONSOLE_BASE_DIR/mustardos-remoteai.conf`
  with only `LAPTOP_HOST`, `LAPTOP_USER`, `LAPTOP_SSH_PORT`, `LAPTOP_APP_DIR` (path of `laptop\` on the PC),
  `CONSOLE_BASE_DIR`, `CONSOLE_APP_DIR`. Console passwords and keys stay on the PC side.
- The wrapper scripts of the apps get `BASE_DIR` substituted during the upload (apps and the base folder may live
  on different cards).

## Step by step
1. **Windows starts** – the `sshd` service starts automatically (even before login). Nothing else runs in the background.
2. **PowerShell window opened on the PC** – the profile loads `laptop\ai-mux.ps1` (reads the config, defines one
   command per `AI_TOOL_*`, plus `ai-ls`, `ai-attach`).
3. **`claude` / `agy` / … on the PC** – creates psmux session `<tool>-<directory>` running the tool and attaches the window.
   Runs directly (no psmux) for: `AI_PASSTHRU_ARGS`, subcommands, `--no-mux`, or when already inside psmux.
   Exiting the tool = session ends; closing the window = detach only (the tool keeps running).
4. **Console, Connect to Claude/Agy** – SSH with the console key to `LAPTOP_USER@LAPTOP_HOST`; sshd starts `pwsh` with the session menu.
   - The menu redraws itself every 3 s when the psmux session list changes (only while nothing is typed), so a session
     started on the PC appears without restarting the app.
   - Attach: `psmux attach` to the chosen session (the same one the PC sees). `window-size smallest`: while the console
     is attached the window has the console size (91×30), so lines wrap for its screen; the PC window shows the same area.
   - Detach: **F8** or **F12** (`bind-key -n … detach-client`). The console terminal (muxterm) does not pass `Ctrl+b`
     from a Bluetooth keyboard, so the tmux prefix cannot be used there.
   - New: tool + directory chosen in the menu → request written to `laptop\.session_request` → scheduled task started →
     `start-session.ps1` creates the session in the interactive logon → menu waits (`SESSION_START_TIMEOUT`) and attaches.
     If the task is missing or does not respond, the session is started in the SSH logon instead (agy will not be signed in).
5. **Console, Connect to PowerShell** – same connection, no menu.

## Why a scheduled task
An SSH login with a key has **no access to Windows Credential Manager** (no password → no user DPAPI keys; `cmdkey /list` shows `NONE`).
agy keeps its login there (`gemini:antigravity`), so agy started from an SSH logon is "not signed in".
Claude Code keeps its login in a file (`~\.claude`), so it is not affected.
The task `MustardOS_RemoteAI Start Session` (no trigger, "run only when user is logged on") runs in the normal desktop logon,
so sessions it creates have full access; the SSH side only attaches to them.
Limits: works while the PC is locked; does NOT work when nobody is logged in (after a reboot, before login) –
then the session starts in the SSH logon and agy is not signed in. `agy-acc` (account switching) also writes
Credential Manager, so run it on the PC desktop, not over SSH.

Alternatives considered and rejected:
- **agy without Credential Manager** – not possible: per Google's docs agy stores tokens only in the OS keychain.
- **SSH password login** (gives full credentials) – the password would be typed on the console every time or stored on it.
- **"Run whether user is logged on or not" task with stored password** – would also work after a reboot, but stores the
  password (LSA secret, must be updated on password change). Possible upgrade if the post-reboot case matters.
- **Always-running psmux "hub" session** – same logon dependency plus a permanent background process; not simpler.
- **runas /savecred, CredSSP, auto-logon** – store or forward the password; worse security.

## Components
- **Console SSH client:** `CONSOLE_BASE_DIR/dropbearmulti` – Dropbear 2025.88 built statically (aarch64, musl) from the
  official sources (github.com/mkj/dropbear, tag DROPBEAR_2025.88, `zig cc`); license in `DROPBEAR-LICENSE`.
  Key: `id_ed25519` in the same folder (generated on the console by the installer, never leaves it);
  PC host key: `.ssh/known_hosts` there (`ssh-laptop.sh` sets `HOME` to that folder, `-y` = trust on first use).
- **Console apps:** `CONSOLE_APP_DIR/<Folder>/mux_launch.sh`. Displayed name and help come from `mux_lang.ini`
  (`[full]`, `[grid]`, `[help]`, key = UI language, `English` here – other languages fall back to the folder name).
  Folder names cannot contain `/`, hence `Connect to Claude-Agy`. Header comments in `mux_launch.sh`: `# GRID:`,
  `# HELP:`, `# ICON:` icon name → `glyph/<icon>.svg` in the app folder (monochrome SVG, like the theme glyphs).
  Terminal settings per app: `/opt/muos/share/info/config/Terminal/ConnectAI.conf`, `ConnectPowerShell.conf`
  (created by muxterm). muOS bind-mounts `/run/muos/storage/application` from SD2 when `/mnt/sdcard/MUOS/application`
  exists, otherwise from SD1 (`/mnt/mmc/MUOS/application`).
- **Why SD2:** SD1 holds the muOS system (ROOTFS) and the `/mnt/mmc` data partition – both are wiped by a fresh install / migration.
- **Upload:** `install.ps1` packs the files (files only, no directory entries) into a tar and pipes it over SSH
  (`plink`/`ssh` → `tar -xf - -C /`). Works without sftp/scp on the console and with spaces in paths.
- **PC SSH server:** Windows feature OpenSSH Server. `C:\ProgramData\ssh\sshd_config` (block `# MustardOS_RemoteAI`: `Port`,
  keys only, `AllowUsers LAPTOP_USER`). Console key: `C:\ProgramData\ssh\administrators_authorized_keys` if
  `LAPTOP_USER` is an administrator (sshd ignores `~\.ssh\authorized_keys` for admins), otherwise
  `<profile>\.ssh\authorized_keys`. Shell: `HKLM\SOFTWARE\OpenSSH\DefaultShell` = `PWSH_EXE`.
- **AI tools:** `AI_TOOL_<command>` – executable from the config, otherwise the first match in PATH.
- **psmux** (native Windows tmux, winget `marlocarlo.psmux`): one ~10 MB server process per session, nothing runs when
  there are no sessions. Config `~\.psmux.conf`. `PSMUX_NO_WARM=1` disables pre-spawned spare shells (otherwise several × ~165 MB RAM).
- **Firewall:** rule `OpenSSH-Server-In-TCP`, Private profile, only from `CONSOLE_HOST`. Key-only login is the real protection.

## Gotchas (verified)
- **Physical PgUp/PgDn never reach the program** – muxterm uses them to scroll its own scrollback
  (MustardOS/frontend `terminal/input.c`), which is empty inside psmux. `console/mustardos_remoteai/kbd-proxy.py`
  (started by the apps' `mux_launch.sh` before muxterm, stopped with the app) grabs external keyboards exclusively and
  re-emits all keys through a virtual keyboard, PgUp → F9, PgDn → F10; `psmux.conf` maps F9/F10 back to PgUp/PgDn.
  Log: `/tmp/mustardos-remoteai-kbd.log` on the console. A key logger confirmed the Rii mini keyboard sends real
  `KEY_PAGEUP`/`KEY_PAGEDOWN` for Fn+↑/↓.
- **Mouse/touchpad in the terminal** – the keyboard reports the touchpad on the same input device (REL_X/Y, wheel,
  buttons), but muxterm has no mouse support at all, so it is ignored there (it works in DOSBox via RetroArch).
- **`window-size latest` cut lines on the console** – the PC terminal sends focus/mouse events, which made the PC the
  "latest" client again and resized the window back to its width. Hence `smallest`.
- **SSH key logon = no Credential Manager** (see above) – applies to anything storing secrets there.
- **`agy-switch-accounts`** calls `agy --print ...` – passes through `ai-mux.ps1` unchanged (no psmux).
- **Several installs of one CLI** (e.g. Claude Code via npm/nvm and the native `~\.local\bin\claude.exe`) – the one in
  `AI_TOOL_*` wins; leave the executable empty to use PATH.
- **Processes started by the Claude desktop app** get a different PATH and a virtualized `%APPDATA%` for new folders –
  test "like normal Windows" via `explorer.exe`.
- **`Add-WindowsCapability`** can end with "reboot required" – the service only appears after a restart.
- **Windows PowerShell 5.1** reads UTF-8 without BOM as ANSI – laptop scripts are ASCII-only (`ai-mux.ps1` is loaded by 5.1 too).
- **Config edited in Notepad (CRLF)** – fine: the console strips `\r` before reading its copy.

## History
- v1 (removed): reverse tunnel `plink -R` from the PC to the console + a custom Python terminal server (pywinpty).
  Worked, but no authentication on localhost, no window resize, custom code to maintain.
- v2: standard SSH, nothing in the background except the sshd service; console files on SD2.
- v2.1: agy support, directory browser, scheduled task for sessions in the interactive logon.
- v3 (current): one configuration file (`mustardos-remoteai.conf`, template in the repo), installer `install.ps1`
  (laptop, console upload, sshd), no personal data in the code.
