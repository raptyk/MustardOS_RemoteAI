# Registers the on-demand scheduled task "MustardOS_RemoteAI Start Session" (no trigger - it only runs when
# session-picker.ps1 starts it). It runs start-session.ps1 in the user's interactive logon session.
# No admin needed. Safe to re-run (also after moving the folder).
# Remove: Unregister-ScheduledTask -TaskName 'MustardOS_RemoteAI Start Session' -Confirm:$false
# Author: Patryk Strzelecki <patryk@strzelecki.info>
. (Join-Path $PSScriptRoot 'common.ps1')
$name   = $RemoteAI.TaskName
$script = Join-Path $PSScriptRoot 'start-session.ps1'
$pwsh   = $RemoteAI.Config.PWSH_EXE
if (-not (Test-Path -LiteralPath $pwsh)) { throw "PowerShell 7 not found at '$pwsh' (PWSH_EXE in mustardos-remoteai.conf)." }
$action = New-ScheduledTaskAction -Execute $pwsh `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`"" `
    -WorkingDirectory $PSScriptRoot
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances Queue
Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings `
    -Description 'MustardOS_RemoteAI: creates psmux sessions (AI tools) requested from the console' -Force | Out-Null
"OK: task '$name' registered"
