#Requires -Version 7
# MustardOS_RemoteAI installer - run on the laptop in PowerShell 7, from this folder:
#   .\install.ps1                         all steps: laptop, sshd, console
#   .\install.ps1 -Steps console          only (re)deploy the console files + settings
#   .\install.ps1 -Steps console -DryRun  build the console package and show what would be sent
# All settings come from mustardos-remoteai.conf (copy mustardos-remoteai.conf.example first).
# Every step is safe to re-run. Author: Patryk Strzelecki <patryk@strzelecki.info>
#
# Steps:
#   laptop  - psmux (winget), ~\.psmux.conf, PSMUX_NO_WARM, PowerShell profiles (5.1 + 7) load laptop\ai-mux.ps1,
#             scheduled task "MustardOS_RemoteAI Start Session"                                   (no admin)
#   sshd    - OpenSSH Server, key-only login for LAPTOP_USER, firewall              (asks for admin / UAC)
#   console - uploads the SSH client, scripts, apps and a console copy of the settings (no passwords) to the
#             console; generates the console key there if missing and stores it in CONSOLE_PUBKEY
param(
    [ValidateSet('laptop', 'sshd', 'console')] [string[]]$Steps = @('laptop', 'console', 'sshd'),
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'laptop\common.ps1')
$R = $RemoteAI
$cfg = $R.Config
if (-not $R.ConfigFound) { throw "Create $($R.ConfigFile) first (copy mustardos-remoteai.conf.example and edit it)." }

function Write-Step([string]$s) { Write-Host "`n=== $s ===" -ForegroundColor Yellow }

# Rewrites one KEY='value' line in mustardos-remoteai.conf (keeps the rest of the file untouched).
function Set-ConfigValue([string]$Key, [string]$Value) {
    $text = [IO.File]::ReadAllText($R.ConfigFile)
    $line = "$Key='$($Value -replace "'", '')'"
    $rx = [regex]"(?m)^$Key=('[^']*'|`"[^`"]*`"|\S*)"
    $text = if ($rx.IsMatch($text)) { $rx.Replace($text, $line.Replace('$', '$$'), 1) } else { $text.TrimEnd() + "`n$line`n" }
    [IO.File]::WriteAllText($R.ConfigFile, $text)
    $cfg[$Key] = $Value
}

# Text file with BOM detection preserved (profiles may be read by Windows PowerShell 5.1).
function Edit-TextFile([string]$Path, [scriptblock]$Change) {
    $bom = $false; $text = ''
    if (Test-Path -LiteralPath $Path) {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $text = [IO.File]::ReadAllText($Path)
    } else { New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null }
    $new = & $Change $text
    if ($new -ne $text) {
        if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath "$Path.bak-remoteai")) { Copy-Item -LiteralPath $Path "$Path.bak-remoteai" }
        [IO.File]::WriteAllText($Path, $new, [Text.UTF8Encoding]::new($bom))
        return $true
    }
    return $false
}

# ------------------------------------------------------------------------------------------------
function Install-Laptop {
    Write-Step 'Laptop'
    if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) {
        Write-Host 'Installing psmux (winget marlocarlo.psmux)...'
        if (-not $DryRun) { winget install --id marlocarlo.psmux -e --accept-source-agreements --accept-package-agreements }
    } else { Write-Host 'psmux: installed' }

    $src = Join-Path $R.LaptopDir 'psmux.conf'; $dst = Join-Path $HOME '.psmux.conf'
    if (-not (Test-Path $dst) -or (Get-FileHash $src).Hash -ne (Get-FileHash $dst).Hash) {
        Write-Host "psmux config -> $dst"
        if (-not $DryRun) {
            if ((Test-Path $dst) -and -not (Test-Path "$dst.bak-remoteai")) { Copy-Item $dst "$dst.bak-remoteai" }
            Copy-Item $src $dst -Force
        }
    } else { Write-Host 'psmux config: up to date' }

    $noWarm = if ($cfg.PSMUX_NO_WARM -eq '1') { '1' } else { $null }
    if (-not $DryRun) { [Environment]::SetEnvironmentVariable('PSMUX_NO_WARM', $noWarm, 'User') }

    $docs = [Environment]::GetFolderPath('MyDocuments')
    $aiMux = Join-Path $R.LaptopDir 'ai-mux.ps1'
    $load = ". `"$aiMux`"  # MustardOS_RemoteAI: run AI tools inside psmux"
    foreach ($p in @("$docs\PowerShell\profile.ps1", "$docs\WindowsPowerShell\profile.ps1")) {
        $change = {
            param($t)
            $lines = @($t -split '\r?\n' | Where-Object { $_ -notmatch 'MustardOS_RemoteAI|ai-mux\.ps1' })
            while ($lines.Count -and $lines[-1] -eq '') { $lines = @($lines | Select-Object -SkipLast 1) }
            (@($lines) + $load) -join "`r`n"
        }
        if ($DryRun) { Write-Host "profile: $p" }
        elseif (Edit-TextFile $p $change) { Write-Host "profile updated: $p" } else { Write-Host "profile: up to date ($p)" }
    }

    # task name used by versions before the rename to MustardOS_RemoteAI
    if (-not $DryRun -and (Get-ScheduledTask -TaskName 'RG35xxToWin Start Session' -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName 'RG35xxToWin Start Session' -Confirm:$false
        Write-Host 'old task "RG35xxToWin Start Session" removed'
    }
    if ($DryRun) { Write-Host 'would register the scheduled task' }
    else { & (Join-Path $R.LaptopDir 'register-start-task.ps1') }
}

# ------------------------------------------------------------------------------------------------
function Install-Sshd {
    Write-Step 'OpenSSH Server (administrator)'
    if (-not $cfg.CONSOLE_PUBKEY) { Write-Warning 'CONSOLE_PUBKEY is empty - run the console step first (it creates the key).'; return }
    $script = Join-Path $R.LaptopDir 'setup-sshd.ps1'
    if ($DryRun) { Write-Host "would run (elevated): $script"; return }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) { & $script }
    else {
        Write-Host 'Starting elevated PowerShell (UAC prompt)...'
        $p = Start-Process $cfg.PWSH_EXE -Verb RunAs -Wait -PassThru `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`""
        Get-Content (Join-Path $R.LaptopDir 'setup-sshd.log') -Tail 3 | Where-Object { $_ -match '^(OK|ERROR)' }
    }
}

# ------------------------------------------------------------------------------------------------
# Remote access to the console: PuTTY (plink, password from the config) or Windows OpenSSH (asks).
function Get-ConsoleSsh {
    $target = "$($cfg.CONSOLE_USER)@$($cfg.CONSOLE_HOST)"
    $plink = Get-Command plink -ErrorAction SilentlyContinue
    if ($plink) {
        $a = @('-ssh', '-P', $cfg.CONSOLE_SSH_PORT)
        if ($cfg.CONSOLE_PASSWORD) { $a += @('-pw', $cfg.CONSOLE_PASSWORD) }
        return @{ Exe = $plink.Source; Args = $a; Batch = @('-batch'); Target = $target }
    }
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if (-not $ssh) { throw 'Neither PuTTY (plink) nor OpenSSH client (ssh) found.' }
    return @{ Exe = $ssh.Source; Args = @('-p', $cfg.CONSOLE_SSH_PORT); Batch = @(); Target = $target }
}

function Invoke-Console([hashtable]$S, [string]$Command, [string]$StdinFile, [switch]$Interactive) {
    $a = @() + $S.Args + $(if ($Interactive) { @() } else { $S.Batch }) + @($S.Target, $Command)
    if ($StdinFile) {
        # raw bytes on stdin (binary-safe; PowerShell pipes would re-encode)
        $psi = [Diagnostics.ProcessStartInfo]::new($S.Exe)
        foreach ($x in $a) { $psi.ArgumentList.Add($x) }
        $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true
        $p = [Diagnostics.Process]::Start($psi)
        $fs = [IO.File]::OpenRead($StdinFile)
        try { $fs.CopyTo($p.StandardInput.BaseStream) } finally { $fs.Close(); $p.StandardInput.Close() }
        $p.WaitForExit(); $code = $p.ExitCode
    } else { & $S.Exe @a; $code = $LASTEXITCODE }
    if ($code -ne 0) { throw "Console command failed (exit $code): $Command" }
}

function Install-Console {
    Write-Step 'Console'
    if (-not $cfg.CONSOLE_HOST) { throw 'CONSOLE_HOST is not set in mustardos-remoteai.conf.' }
    if (-not $cfg.LAPTOP_HOST) { throw 'LAPTOP_HOST is not set in mustardos-remoteai.conf.' }
    $base = $cfg.CONSOLE_BASE_DIR.TrimEnd('/'); $apps = $cfg.CONSOLE_APP_DIR.TrimEnd('/')
    foreach ($p in @($base, $apps)) { if ($p -notmatch '^/[^\s'']+$') { throw "Console path must be absolute, without spaces/quotes: '$p'" } }

    # 1. Package: a tree that mirrors the console paths, packed as tar (extracted at / on the console)
    $stage = Join-Path ([IO.Path]::GetTempPath()) 'mustardos-remoteai-deploy'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    $stBase = Join-Path $stage ($base.TrimStart('/') -replace '/', '\')
    $stApps = Join-Path $stage ($apps.TrimStart('/') -replace '/', '\')
    New-Item -ItemType Directory -Force $stBase, $stApps | Out-Null
    $consoleSrc = Join-Path $R.Root 'console'
    Copy-Item (Join-Path $consoleSrc 'mustardos_remoteai\*') $stBase -Recurse
    Copy-Item (Join-Path $consoleSrc 'application\*') $stApps -Recurse
    Get-ChildItem $stApps -Recurse -Filter *.sh | ForEach-Object {
        $t = [IO.File]::ReadAllText($_.FullName) -replace "(?m)^BASE_DIR='[^']*'", "BASE_DIR='$base'"
        [IO.File]::WriteAllText($_.FullName, $t)
    }
    # console copy of the settings: only what the console needs (no passwords, no keys)
    $sq = { param($v) "'" + ("$v" -replace "'", "'\''") + "'" }
    $consoleConf = @(
        '# MustardOS_RemoteAI console settings - GENERATED by install.ps1 on the laptop from mustardos-remoteai.conf.'
        '# Edit mustardos-remoteai.conf there and run: install.ps1 -Steps console'
        "LAPTOP_HOST=$(& $sq $cfg.LAPTOP_HOST)"
        "LAPTOP_USER=$(& $sq $cfg.LAPTOP_USER)"
        "LAPTOP_SSH_PORT=$(& $sq $cfg.LAPTOP_SSH_PORT)"
        "LAPTOP_APP_DIR=$(& $sq $R.LaptopDir)"
        "CONSOLE_BASE_DIR=$(& $sq $base)"
        "CONSOLE_APP_DIR=$(& $sq $apps)"
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $stBase 'mustardos-remoteai.conf'), "$consoleConf`n")
    # LF line endings for everything the console executes or parses
    Get-ChildItem $stage -Recurse -File -Include *.sh, *.ini, *.conf, *.py | ForEach-Object {
        $t = [IO.File]::ReadAllText($_.FullName)
        if ($t.Contains("`r")) { [IO.File]::WriteAllText($_.FullName, ($t -replace "`r`n", "`n")) }
    }
    $tar = Join-Path ([IO.Path]::GetTempPath()) 'mustardos-remoteai-deploy.tar'
    # files only (-n, no directory entries): extracting a directory entry as root would reset /mnt etc.
    $list = Join-Path ([IO.Path]::GetTempPath()) 'mustardos-remoteai-deploy.lst'
    $files = Get-ChildItem $stage -Recurse -File | ForEach-Object {
        [IO.Path]::GetRelativePath($stage, $_.FullName) -replace '\\', '/' }
    [IO.File]::WriteAllText($list, (($files -join "`n") + "`n"))
    & "$env:SystemRoot\System32\tar.exe" --format ustar -n -cf $tar -C $stage -T $list
    if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
    Write-Host "Package: $tar"
    & "$env:SystemRoot\System32\tar.exe" -tf $tar | Where-Object { $_ -notmatch '/$' } | ForEach-Object { "  /$_" }

    $post = "set -e; chmod +x '$base/ssh-laptop.sh' '$base/dropbearmulti' '$apps'/*/*.sh 2>/dev/null || true; " +
            "cd '$base'; [ -f id_ed25519 ] || ./dropbearmulti dropbearkey -t ed25519 -f id_ed25519 >/dev/null; " +
            "./dropbearmulti dropbearkey -y -f id_ed25519 | grep '^ssh-'"
    if ($DryRun) {
        Write-Host "`nDry run - would send the package to $($cfg.CONSOLE_USER)@$($cfg.CONSOLE_HOST), extract it at / and run:`n  $post"
        Write-Host "`nConsole settings file:`n$consoleConf"
        return
    }

    # 2. Upload (first call is interactive so a new console host key can be confirmed)
    $S = Get-ConsoleSsh
    Write-Host "Connecting to $($S.Target)..."
    Invoke-Console $S 'true' -Interactive
    Invoke-Console $S 'tar -xf - -C /' -StdinFile $tar
    $pub = (Invoke-Console $S $post | Select-Object -Last 1)
    Write-Host 'Console files installed.' -ForegroundColor Green
    Write-Host "Console public key: $pub"

    # 3. Console key -> config (used by the sshd step)
    if ($pub -match '^ssh-' -and $pub.Trim() -ne $cfg.CONSOLE_PUBKEY.Trim()) {
        if ($cfg.CONSOLE_PUBKEY) {
            Write-Warning 'The console key differs from CONSOLE_PUBKEY - updating the config; run: install.ps1 -Steps sshd'
        }
        Set-ConfigValue 'CONSOLE_PUBKEY' $pub.Trim()
        Write-Host 'CONSOLE_PUBKEY saved in mustardos-remoteai.conf'
    }
    Remove-Item $stage -Recurse -Force; Remove-Item $tar, $list -Force
}

# ------------------------------------------------------------------------------------------------
Write-Host "MustardOS_RemoteAI installer - config: $($R.ConfigFile)" -ForegroundColor DarkGray
if ('laptop' -in $Steps)  { Install-Laptop }
if ('console' -in $Steps) { Install-Console }
if ('sshd' -in $Steps)    { Install-Sshd }
Write-Host "`nDone." -ForegroundColor Green
