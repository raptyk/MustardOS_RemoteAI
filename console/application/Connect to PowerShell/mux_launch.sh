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

/opt/muos/frontend/muxterm --gl -c "$TERM_CFG_DIR/ConnectPowerShell.conf" -- "$APP_DIR/powershell.sh"
