# Loaded from the PowerShell profiles (5.1 and 7) - added by install.ps1.
# For every AI tool in mustardos-remoteai.conf (AI_TOOL_<command>) defines a command with the same name that
# starts the tool inside a psmux session, so it can be attached from another terminal
# (e.g. the console app "Connect to Claude/Agy").
# Author: Patryk Strzelecki <patryk@strzelecki.info>
#   <tool> [args]         start in psmux (session <tool>-<directory>)
#   ... --no-mux          run directly, without psmux (also: $env:AI_NO_MUX=1)
#   ai-ls                 list sessions
#   ai-attach [name]      attach to a session (default: the first one)

. (Join-Path $PSScriptRoot 'common.ps1')
if ($RemoteAI.Config.PSMUX_NO_WARM -eq '1') { $env:PSMUX_NO_WARM = '1' }   # no pre-spawned spare shells

function global:Get-AiToolExe([string]$Tool) {
    $exe = $RemoteAI.Tools[$Tool].Exe
    if ($exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    $c = Get-Command $Tool -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}

function global:Get-AiSessionList {
    @(psmux ls -F '#{session_name}' 2>$null | Where-Object { $_ })
}

function global:Get-AiSessionName([string]$Tool, [string]$Dir) {
    $base = "$Tool-" + ((Split-Path -Leaf $Dir) -replace '[^A-Za-z0-9_-]', '-')
    $existing = Get-AiSessionList
    $name = $base; $i = 2
    while ($existing -contains $name) { $name = "$base-$i"; $i++ }
    return $name
}

# -Detached: create the session without attaching (used by start-session.ps1)
function global:Start-AiSession([string]$Tool, [string]$Dir = $PWD.ProviderPath, [string[]]$ToolArgs = @(),
                                [string]$Name, [switch]$Detached) {
    $exe = Get-AiToolExe $Tool
    if (-not $exe) { Write-Error "$Tool not found (mustardos-remoteai.conf: AI_TOOL_$Tool, or PATH)."; return }
    if (-not $Name) { $Name = Get-AiSessionName $Tool $Dir }
    $q = { param($s) "'" + ("$s" -replace "'", "''") + "'" }
    $cmd = '& ' + (& $q $exe)
    foreach ($a in $ToolArgs) { $cmd += ' ' + (& $q $a) }
    if ($Detached) { psmux new-session -d -s $Name -c $Dir $cmd }
    else { psmux new-session -s $Name -c $Dir $cmd }
}

function global:Invoke-AiTool([string]$Tool, [object[]]$ToolArgs) {
    $exe = Get-AiToolExe $Tool
    if (-not $exe) { Write-Error "$Tool not found."; return }
    $argv = @($ToolArgs | Where-Object { "$_" -ne '--no-mux' })
    $passthru = ($ToolArgs.Count -ne $argv.Count) -or $env:TMUX -or $env:AI_NO_MUX `
        -or -not (Get-Command psmux -CommandType Application -ErrorAction SilentlyContinue) `
        -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected
    if (-not $passthru -and $argv.Count -gt 0) {
        if ("$($argv[0])" -notlike '-*') { $passthru = $true }   # subcommands: update, mcp, ...
        foreach ($x in $argv) { if ("$x" -in $RemoteAI.PassthruArgs) { $passthru = $true } }
    }
    if ($passthru) { & $exe @argv; return }
    Start-AiSession -Tool $Tool -Dir $PWD.ProviderPath -ToolArgs $argv
}

foreach ($t in $RemoteAI.Tools.Keys) {
    Set-Item "function:global:$t" ([scriptblock]::Create("Invoke-AiTool '$t' `$args"))
}

function global:ai-ls {
    psmux ls -F '#{session_name}  [#{?session_attached,attached,detached}]  #{pane_current_path}' 2>$null
}

function global:ai-attach([string]$Name) {
    if (-not $Name) { $Name = @(Get-AiSessionList)[0] }
    if ($Name) { psmux attach -t $Name } else { Write-Host 'No sessions.' }
}
