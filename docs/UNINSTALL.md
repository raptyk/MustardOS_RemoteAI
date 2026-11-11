# Uninstall – every change made and how to revert it

Names in `<CAPS>` are values from your `mustardos-remoteai.conf`.

## PC – PowerShell as administrator
```powershell
psmux kill-server                                   # closes AI sessions running in psmux
Stop-Service sshd
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0   # may require a restart
Remove-Item C:\ProgramData\ssh -Recurse -Force      # sshd_config (+ .bak-remoteai), host keys, authorized_keys
Remove-ItemProperty HKLM:\SOFTWARE\OpenSSH -Name DefaultShell
Remove-NetFirewallRule -Name OpenSSH-Server-In-TCP
```
If you keep OpenSSH Server for other uses: restore `C:\ProgramData\ssh\sshd_config.bak-remoteai` and remove the
console key from `administrators_authorized_keys` (or `<profile>\.ssh\authorized_keys` for non-admin users).

## PC – normal PowerShell
```powershell
Unregister-ScheduledTask -TaskName 'MustardOS_RemoteAI Start Session' -Confirm:$false
winget uninstall --id marlocarlo.psmux -e
Remove-Item ~\.psmux -Recurse -Force; Remove-Item ~\.psmux.conf   # a previous one is kept as .psmux.conf.bak-remoteai
[Environment]::SetEnvironmentVariable('PSMUX_NO_WARM', $null, 'User')
# PowerShell profiles (Documents\PowerShell\profile.ps1 and Documents\WindowsPowerShell\profile.ps1):
# remove the line containing "MustardOS_RemoteAI" (originals: profile.ps1.bak-remoteai; a profile that did not exist before
# contains only that line and can be deleted)
Remove-ItemProperty 'HKCU:\Software\SimonTatham\PuTTY\SshHostKeys' -Name 'ssh-ed25519@<CONSOLE_SSH_PORT>:<CONSOLE_HOST>'
ssh-keygen -R <CONSOLE_HOST>
# finally, manually: this folder
```

## Console (over SSH as root)
```sh
rm -rf "<CONSOLE_APP_DIR>/Connect to Claude-Agy" "<CONSOLE_APP_DIR>/Connect to PowerShell"
rmdir <CONSOLE_APP_DIR> /mnt/sdcard/MUOS 2>/dev/null   # only if empty and created for this; muOS then uses SD1 for apps again (after reboot)
rm -rf <CONSOLE_BASE_DIR>
rm -f /opt/muos/share/info/config/Terminal/ConnectAI.conf /opt/muos/share/info/config/Terminal/ConnectPowerShell.conf
```
No system packages or settings are changed on the console.
