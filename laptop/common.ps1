# MustardOS_RemoteAI - shared settings loader (laptop side). Dot-sourced by every other laptop script.
# Author: Patryk Strzelecki <patryk@strzelecki.info>
#
# Reads <repo>\mustardos-remoteai.conf (or the file named in $env:MUSTARDOS_REMOTEAI_CONFIG) and publishes
# $global:RemoteAI with everything the scripts need:
#   .Root .LaptopDir .ConfigFile .Config (all keys, defaults applied)
#   .Tools (ordered: command -> @{ Key; Name; Exe }) .PassthruArgs .ProjectsRoot .TaskName
# Must stay compatible with Windows PowerShell 5.1 (it is loaded from the 5.1 profile too) and ASCII-only.

function global:Read-RemoteAIConfigFile([string]$Path) {
    # Parses KEY='value' / KEY="value" / KEY=value lines (the subset of sh syntax used by the console).
    $cfg = [ordered]@{}
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
        $k = $Matches[1]; $v = $Matches[2]
        if ($v -match "^'([^']*)'") { $v = $Matches[1] }
        elseif ($v -match '^"((?:[^"\\]|\\.)*)"') { $v = $Matches[1] -replace '\\(["\\$`])', '$1' }
        else { $v = ($v -replace '\s+#.*$', '').Trim() }
        $cfg[$k] = $v
    }
    return $cfg
}

function global:Import-RemoteAIConfig([string]$LaptopDir) {
    $laptopDir = $LaptopDir
    $root = Split-Path $laptopDir -Parent
    $file = if ($env:MUSTARDOS_REMOTEAI_CONFIG) { $env:MUSTARDOS_REMOTEAI_CONFIG } else { Join-Path $root 'mustardos-remoteai.conf' }

    $defaults = [ordered]@{
        LAPTOP_HOST = ''; LAPTOP_USER = $env:USERNAME; LAPTOP_SSH_PORT = '22'
        PROJECTS_ROOT = $env:USERPROFILE
        PWSH_EXE = 'C:\Program Files\PowerShell\7\pwsh.exe'
        AI_PASSTHRU_ARGS = '-p --print --prompt -v --version -h --help'
        CONSOLE_HOST = ''; CONSOLE_USER = 'root'; CONSOLE_PASSWORD = ''; CONSOLE_SSH_PORT = '22'; CONSOLE_PUBKEY = ''
        CONSOLE_BASE_DIR = '/mnt/sdcard/mustardos_remoteai'; CONSOLE_APP_DIR = '/mnt/sdcard/MUOS/application'
        BROWSER_PAGE_SIZE = '12'; SESSION_START_TIMEOUT = '20'; PSMUX_NO_WARM = '1'
    }
    $cfg = [ordered]@{}
    foreach ($k in $defaults.Keys) { $cfg[$k] = $defaults[$k] }
    $found = Test-Path -LiteralPath $file
    if ($found) {
        $user = Read-RemoteAIConfigFile $file
        foreach ($k in $user.Keys) { $cfg[$k] = $user[$k] }
    } else {
        Write-Warning "MustardOS_RemoteAI: $file not found - using defaults. Copy mustardos-remoteai.conf.example to mustardos-remoteai.conf."
    }

    # AI tools in file order; none configured -> Claude Code only
    $tools = [ordered]@{}
    foreach ($k in @($cfg.Keys)) {
        if ($k -notmatch '^AI_TOOL_(\w+)$') { continue }
        $cmd = $Matches[1]
        $p = @("$($cfg[$k])" -split '\|', 3) + @('', '', '')
        $exe = if ($p[2].Trim()) { [Environment]::ExpandEnvironmentVariables($p[2].Trim()) } else { '' }
        $name = if ($p[1].Trim()) { $p[1].Trim() } else { $cmd }
        $key = if ($p[0].Trim()) { $p[0].Trim() } else { $cmd }
        $tools[$cmd] = @{ Key = $key; Name = $name; Exe = $exe }
    }
    if ($tools.Count -eq 0) {
        $tools['claude'] = @{ Key = 'c'; Name = 'Claude Code'; Exe = "$env:USERPROFILE\.local\bin\claude.exe" }
    }

    $global:RemoteAI = [pscustomobject]@{
        Root         = $root
        LaptopDir    = $laptopDir
        ConfigFile   = $file
        ConfigFound  = $found
        Config       = $cfg
        Tools        = $tools
        PassthruArgs = @("$($cfg.AI_PASSTHRU_ARGS)" -split '\s+' | Where-Object { $_ })
        ProjectsRoot = [Environment]::ExpandEnvironmentVariables($cfg.PROJECTS_ROOT)
        PageSize     = [Math]::Max(3, [int]$cfg.BROWSER_PAGE_SIZE)
        StartTimeout = [Math]::Max(5, [int]$cfg.SESSION_START_TIMEOUT)
        TaskName     = 'MustardOS_RemoteAI Start Session'
        LastDirFile  = Join-Path $laptopDir '.last_dir'
        RequestFile  = Join-Path $laptopDir '.session_request'
        StartLog     = Join-Path $laptopDir 'start-session.log'
    }
}

Import-RemoteAIConfig -LaptopDir $PSScriptRoot
