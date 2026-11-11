#!/bin/sh
# AI session menu (psmux sessions on the laptop) over SSH
BASE_DIR='/mnt/sdcard/mustardos_remoteai'   # set by install.ps1 from CONSOLE_BASE_DIR
exec "$BASE_DIR/ssh-laptop.sh" menu
