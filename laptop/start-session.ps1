# Run by the scheduled task "MustardOS_RemoteAI Start Session" inside the user's normal (interactive)
# Windows logon session. Reads .session_request (written by session-picker.ps1 over SSH) and
# creates a detached psmux session there.
# Why: an SSH key logon has no access to Windows Credential Manager, so tools that keep their
# login there (agy) would start "not signed in". Sessions created here have full access.
# Author: Patryk Strzelecki <patryk@strzelecki.info>
$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'start-session.log'
try {
    . (Join-Path $PSScriptRoot 'ai-mux.ps1')
    $req = $RemoteAI.RequestFile
    $r = Get-Content $req -Raw | ConvertFrom-Json
    Remove-Item $req -Force
    # validate the request: known tool, safe session name, existing directory
    if (-not $RemoteAI.Tools.Contains([string]$r.Tool)) { throw "unknown tool '$($r.Tool)'" }
    if ([string]$r.Name -notmatch '^[\w-]+$') { throw "invalid session name '$($r.Name)'" }
    if (-not (Test-Path -LiteralPath $r.Dir -PathType Container)) { throw "no such directory '$($r.Dir)'" }
    Start-AiSession -Tool $r.Tool -Dir $r.Dir -Name $r.Name -Detached
    Add-Content $log "$(Get-Date -Format s) OK $($r.Name) $($r.Dir)"
} catch {
    Add-Content $log "$(Get-Date -Format s) ERROR $_"
}
