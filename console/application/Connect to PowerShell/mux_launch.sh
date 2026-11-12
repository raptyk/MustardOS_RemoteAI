#!/bin/sh
# HELP: PowerShell 7 on the laptop over SSH
# ICON: connect_powershell
# GRID: Connect to PowerShell

. /opt/muos/script/var/stage.sh
. /opt/muos/script/var/display.sh
. /opt/muos/script/var/launch.sh

SETUP_STAGE_OVERLAY
SETUP_SDL_ENVIRONMENT

SET_VAR "system" "foreground_process" "muxterm"

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
TERM_CFG_DIR="/opt/muos/share/info/config/Terminal"
mkdir -p "$TERM_CFG_DIR"

BASE_DIR='/mnt/sdcard/mustardos_remoteai'   # set by install.ps1 from CONSOLE_BASE_DIR
# Keyboard proxy: physical PgUp/PgDn -> F9/F10 (muxterm keeps PgUp/PgDn for its own scrollback).
# Started before muxterm so muxterm sees its virtual keyboard; stopped when the app exits.
KBD_PROXY=
if command -v python3 >/dev/null && [ -f "$BASE_DIR/kbd-proxy.py" ]; then
    python3 "$BASE_DIR/kbd-proxy.py" >/tmp/mustardos-remoteai-kbd.log 2>&1 &
    KBD_PROXY=$!
    sleep 0.5
fi

# Italic text (e.g. Claude Code "recap" lines) in a real italic font: the synthetic slant is barely readable here.
[ -f "$BASE_DIR/muxterm-italic.sh" ] && sh "$BASE_DIR/muxterm-italic.sh" "$TERM_CFG_DIR/ConnectPowerShell.conf"

/opt/muos/frontend/muxterm --gl -c "$TERM_CFG_DIR/ConnectPowerShell.conf" -- "$APP_DIR/powershell.sh"

[ -n "$KBD_PROXY" ] && kill "$KBD_PROXY" 2>/dev/null
