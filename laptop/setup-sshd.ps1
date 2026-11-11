# Installs and configures Windows OpenSSH Server for the console. RUN AS ADMINISTRATOR
# (install.ps1 starts it elevated). Safe to run again, e.g. after changing the console key, IP or port.
# Everything comes from mustardos-remoteai.conf: LAPTOP_USER, LAPTOP_SSH_PORT, CONSOLE_HOST, CONSOLE_PUBKEY, PWSH_EXE.
# Parameters override the file:  setup-sshd.ps1 [-PubKey 'ssh-ed25519 ...' | -PubKeyFile file] [-ConsoleIp ip]
# Author: Patryk Strzelecki <patryk@strzelecki.info>
param(
    [string]$PubKey,
    [string]$PubKeyFile,
    [string]$ConsoleIp
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$cfg = $RemoteAI.Config
$log = Join-Path $PSScriptRoot 'setup-sshd.log'
Start-Transcript -Path $log -Append | Out-Null
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run as administrator.'
    }
    $user = $cfg.LAPTOP_USER
    $port = [int]$cfg.LAPTOP_SSH_PORT
    if (-not $ConsoleIp) { $ConsoleIp = $cfg.CONSOLE_HOST }
    if ($PubKeyFile) { $PubKey = Get-Content $PubKeyFile -Raw }
    if (-not $PubKey) { $PubKey = $cfg.CONSOLE_PUBKEY }
    $PubKey = "$PubKey".Trim()
    if ($PubKey -notmatch '^(ssh-|ecdsa-)\S+ \S+') {
        throw 'No valid console public key: set CONSOLE_PUBKEY in mustardos-remoteai.conf (install.ps1 -Steps console fills it in).'
    }

    # 1. Install the Windows feature (may require a reboot before the service appears)
    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
    if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }

    # 2. First start creates C:\ProgramData\ssh\sshd_config and host keys
    Set-Service sshd -StartupType Automatic
    Start-Service sshd; Stop-Service sshd

    # 3. Default shell: PowerShell 7
    New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
        -Value $cfg.PWSH_EXE -PropertyType String -Force | Out-Null

    # 4. Keys only, one user only, port (inserted before the first "Match" block)
    $sshCfg = 'C:\ProgramData\ssh\sshd_config'
    if (-not (Test-Path "$sshCfg.bak-remoteai")) { Copy-Item $sshCfg "$sshCfg.bak-remoteai" }
    $c = Get-Content $sshCfg
    $c = $c | Where-Object { $_ -notmatch '^\s*#?\s*(PasswordAuthentication|PubkeyAuthentication|AllowUsers|Port)\b' -and $_ -notin @('# MustardOS_RemoteAI', '# RG35xxToWin') }
    $i = [Array]::FindIndex([string[]]$c, [Predicate[string]]{ param($l) $l -match '^\s*Match\b' })
    $add = @('# MustardOS_RemoteAI', "Port $port", 'PubkeyAuthentication yes', 'PasswordAuthentication no', "AllowUsers $user")
    if ($i -lt 0) { $c = $c + $add } elseif ($i -eq 0) { $c = $add + $c } else { $c = $c[0..($i-1)] + $add + $c[$i..($c.Count-1)] }
    Set-Content -Path $sshCfg -Value $c -Encoding ascii

    # 5. Console key. Administrators: C:\ProgramData\ssh\administrators_authorized_keys (sshd ignores
    #    ~\.ssh\authorized_keys for them); other users: <profile>\.ssh\authorized_keys
    $isAdmin = $false
    try {
        $isAdmin = [bool](Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop |
            Where-Object { ($_.Name -split '\\')[-1] -eq $user })
    } catch {
        $isAdmin = [bool]((net localgroup administrators) -match "(^|\\)$([regex]::Escape($user))$")
    }
    if ($isAdmin) {
        $ak = 'C:\ProgramData\ssh\administrators_authorized_keys'
    } else {
        $prof = (Get-CimInstance Win32_UserProfile | Where-Object { (Split-Path $_.LocalPath -Leaf) -eq $user } |
            Select-Object -First 1).LocalPath
        if (-not $prof) { $prof = Join-Path (Split-Path $env:USERPROFILE -Parent) $user }
        New-Item -ItemType Directory -Force (Join-Path $prof '.ssh') | Out-Null
        $ak = Join-Path $prof '.ssh\authorized_keys'
    }
    $existing = if (Test-Path $ak) { Get-Content $ak } else { @() }
    if ($existing -notcontains $PubKey) { Add-Content -Path $ak -Value $PubKey -Encoding ascii }
    if ($isAdmin) { icacls $ak /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null }
    else { icacls $ak /inheritance:r /grant "${user}:F" /grant '*S-1-5-18:F' | Out-Null }

    # 6. Firewall: SSH port only from the console (if CONSOLE_HOST is set), Private profile only
    $rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
    }
    $remote = if ($ConsoleIp) { $ConsoleIp } else { 'Any' }
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Private -LocalPort $port -RemoteAddress $remote -Enabled True

    Start-Service sshd
    "OK: sshd running on port $port, user '$user' (key in $ak), firewall rule limited to $remote"
} catch {
    'ERROR: ' + $_
} finally {
    Stop-Transcript | Out-Null
}
