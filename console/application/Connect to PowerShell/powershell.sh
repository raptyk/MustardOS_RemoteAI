#!/bin/sh
# Plain PowerShell 7 on the laptop over SSH
BASE_DIR='/mnt/sdcard/mustardos_remoteai'   # set by install.ps1 from CONSOLE_BASE_DIR
exec "$BASE_DIR/ssh-laptop.sh"
