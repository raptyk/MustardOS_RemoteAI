# Session menu for the console (started over SSH by the "Connect to Claude/Agy" app).
# Author: Patryk Strzelecki <patryk@strzelecki.info>
# Lists psmux sessions (AI tools from mustardos-remoteai.conf and others), attaches to them or starts new ones.
. (Join-Path $PSScriptRoot 'ai-mux.ps1')
$Tools = $RemoteAI.Tools
$MinNameWidth = $RemoteAI.MinNameWidth
$lastDirFile = $RemoteAI.LastDirFile

function Get-Tag([string]$name) {
    foreach ($t in $Tools.Keys) { if ($name -like "$t-*") { return $t } }
    return 'other'
}

# Terminal width in characters (over SSH: the console's muxterm size, e.g. 91); fallback 80.
function Get-TermWidth {
    try { $w = $Host.UI.RawUI.WindowSize.Width; if ($w -ge 20) { return $w } } catch { }
    try { $w = [Console]::WindowWidth; if ($w -ge 20) { return $w } } catch { }
    return 80
}

# Shortens a name to $Width characters, with "..." at the end when it is longer.
function Limit-Name([string]$Name, [int]$Width) {
    if ($Name.Length -le $Width) { return $Name }
    if ($Width -le 3) { return $Name.Substring(0, $Width) }
    return $Name.Substring(0, $Width - 3) + '...'
}

# Prints the entries numbered 1..n in columns (top to bottom, then left to right, like ls), no paging.
# As many columns as fit while every name keeps its full length, or at least $MinNameWidth characters;
# longer names end with "...". The last column never touches the right edge (no auto-wrap).
function Write-Columns($Items) {
    $n = $Items.Count
    if ($n -eq 0) { return }
    $width = Get-TermWidth
    $numW = "$n".Length
    $gap = 2
    $longest = ($Items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $want = [Math]::Min($longest, $MinNameWidth)
    $cols = 1
    for ($c = $n; $c -ge 1; $c--) {
        $cellW = [Math]::Floor(($width - 1 - $gap * ($c - 1)) / $c)
        if ($cellW - $numW - 1 -ge $want) { $cols = $c; break }
    }
    $rows = [Math]::Ceiling($n / $cols)
    $cols = [Math]::Ceiling($n / $rows)                     # drop empty trailing columns
    $cellW = [Math]::Floor(($width - 1 - $gap * ($cols - 1)) / $cols)
    $nameW = [Math]::Max(1, [Math]::Min($cellW - $numW - 1, $longest))
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $i = $c * $rows + $r
            if ($i -ge $n) { break }
            $last = ($c -eq $cols - 1) -or (($c + 1) * $rows + $r -ge $n)
            Write-Host ("{0,$numW} " -f ($i + 1)) -ForegroundColor DarkCyan -NoNewline
            $name = Limit-Name $Items[$i].Name $nameW
            if (-not $last) { $name = $name.PadRight($nameW + $gap) }
            Write-Host $name -ForegroundColor Cyan -NoNewline
        }
        Write-Host ''
    }
}

# Directory browser: start at PROJECTS_ROOT, walk down any depth, pick with Enter.
function Select-ProjectDir([string]$Start) {
    $cur = if ($Start -and (Test-Path -LiteralPath $Start -PathType Container)) { $Start } else { $HOME }
    $filter = ''
    $last = if (Test-Path $lastDirFile) { (Get-Content $lastDirFile -Raw).Trim() } else { '' }
    while ($true) {
        $all = @(Get-ChildItem -LiteralPath $cur -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Name.StartsWith('.') } | Sort-Object Name)
        $list = if ($filter) { @($all | Where-Object { $_.Name -like "*$filter*" }) } else { $all }
        if ($filter -and $list.Count -eq 1) { $cur = $list[0].FullName; $filter = ''; continue }
        Clear-Host
        Write-Host (Limit-Name $cur ((Get-TermWidth) - 1)) -ForegroundColor Yellow
        if ($filter) { Write-Host "filter: *$filter*  ($($list.Count))" -ForegroundColor DarkYellow }
        Write-Columns $list
        if (-not $list) { Write-Host '     (no subdirectories)' -ForegroundColor DarkGray }
        Write-Host ' nr=open  Enter=START HERE  ..=up  text=filter  /=clear' -ForegroundColor DarkGray
        $hint = if ($last) { "  l=last ($last)" } else { '' }
        Write-Host " q=cancel$hint" -ForegroundColor DarkGray
        $in = (Read-Host '>').Trim()
        switch -Regex ($in) {
            '^$'      { return $cur }
            '^q$'     { return $null }
            '^l$'     { if ($last -and (Test-Path -LiteralPath $last)) { $cur = $last; $filter = '' }; break }
            '^\.\.$'  { $p = Split-Path $cur -Parent; if ($p) { $cur = $p }; $filter = ''; break }
            '^/$'     { $filter = ''; break }
            '^\d+$'   { $n = [int]$in; if ($n -ge 1 -and $n -le $list.Count) { $cur = $list[$n - 1].FullName; $filter = '' }; break }
            default   { $filter = $in }
        }
    }
}

# Over SSH the session is created by the scheduled task inside the interactive Windows logon
# (access to Credential Manager - needed by agy), then attached. Fallback: start it here.
function New-PickerSession([string]$Tool, [string]$Dir) {
    $name = Get-AiSessionName $Tool $Dir
    $taskName = $RemoteAI.TaskName
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($env:SSH_CONNECTION -and $task) {
        @{ Tool = $Tool; Dir = $Dir; Name = $name } | ConvertTo-Json | Set-Content $RemoteAI.RequestFile
        Start-ScheduledTask -TaskName $taskName
        Write-Host "Starting $name on the laptop..." -ForegroundColor DarkGray
        for ($i = 0; $i -lt $RemoteAI.StartTimeout * 2; $i++) {
            Start-Sleep -Milliseconds 500
            if ((Get-AiSessionList) -contains $name) { psmux attach -t $name; return }
        }
        Write-Host 'The laptop did not start the session (is a user logged in on the laptop?).' -ForegroundColor Red
        Write-Host 'See laptop\start-session.log. Starting it in this SSH session instead...' -ForegroundColor Red
        Start-Sleep 3
    }
    Start-AiSession -Tool $Tool -Dir $Dir -Name $name
}

function Select-Tool {
    $first = @($Tools.Keys)[0]
    if ($Tools.Count -eq 1) { return $first }
    $keys = ($Tools.GetEnumerator() | ForEach-Object { "$($_.Value.Key) = $($_.Value.Name)" }) -join '   '
    $in = (Read-Host "Tool: $keys  [Enter = $($Tools[$first].Name)]").Trim()
    if (-not $in) { return $first }
    foreach ($e in $Tools.GetEnumerator()) { if ($e.Value.Key -eq $in -or $e.Key -eq $in) { return $e.Key } }
    return $null
}

# Session list as one string - compared to detect changes while the menu waits for input.
function Get-SessionSnapshot {
    return ((psmux ls -F '#{session_name}|#{session_attached}|#{pane_current_path}' 2>$null | Where-Object { $_ }) -join "`n")
}

# Like Read-Host '>', but returns $null (= redraw the menu) when the session list changes while nothing is typed,
# so a session started on the laptop shows up on the console without pressing anything.
function Read-MenuChoice([string]$Snapshot) {
    try { $null = [Console]::KeyAvailable } catch { return (Read-Host '>') }   # no console (redirected input)
    Write-Host -NoNewline '>: '
    $buf = ''; $next = (Get-Date).AddSeconds($RefreshSeconds)
    while ($true) {
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Enter') { Write-Host ''; return $buf }
            if ($k.Key -eq 'Backspace') {
                if ($buf.Length -gt 0) { $buf = $buf.Substring(0, $buf.Length - 1); Write-Host -NoNewline "`b `b" }
            }
            elseif ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) { $buf += $k.KeyChar; Write-Host -NoNewline $k.KeyChar }
            continue
        }
        if ($buf -eq '' -and (Get-Date) -ge $next) {
            if ((Get-SessionSnapshot) -ne $Snapshot) { return $null }
            $next = (Get-Date).AddSeconds($RefreshSeconds)
        }
        Start-Sleep -Milliseconds 100
    }
}
$RefreshSeconds = 3

while ($true) {
    Clear-Host
    $snapshot = Get-SessionSnapshot
    $rows = @($snapshot -split "`n" |
        Where-Object { $_ } | ForEach-Object {
            $p = $_ -split '\|', 3
            [pscustomobject]@{ Name = $p[0]; Att = [int]$p[1]; Dir = $p[2]; Tag = Get-Tag $p[0] }
        } | Sort-Object Tag, Name)
    Write-Host 'MustardOS_RemoteAI - by Patryk Strzelecki <patryk@strzelecki.info>' -ForegroundColor DarkGray
    Write-Host '=== Laptop sessions (psmux) ===' -ForegroundColor Yellow
    if (-not $rows) { Write-Host '  (no sessions)' -ForegroundColor DarkGray }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        $flag = if ($r.Att -gt 0) { '*' } else { ' ' }
        Write-Host ("{0,2}{1} [{2}] {3}" -f ($i + 1), $flag, $r.Tag, $r.Name) -ForegroundColor Cyan
        Write-Host ("      {0}" -f $r.Dir) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host ' nr = attach   n = new session   s = PowerShell   Enter = refresh   q = quit'
    Write-Host ' Detach from a session: F8 or F12 (on the PC also Ctrl+b, d)   (* = also open elsewhere)' -ForegroundColor DarkGray
    Write-Host (' The list refreshes by itself every {0} s.' -f $RefreshSeconds) -ForegroundColor DarkGray
    $c = Read-MenuChoice $snapshot
    if ($null -eq $c) { continue }
    $c = $c.Trim()

    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $rows.Count) {
        psmux attach -t $rows[[int]$c - 1].Name
    }
    elseif ($c -eq 'n') {
        $tool = Select-Tool
        if (-not $tool) { continue }
        $dir = Select-ProjectDir $RemoteAI.ProjectsRoot
        if (-not $dir) { continue }
        Set-Content $lastDirFile $dir
        New-PickerSession -Tool $tool -Dir $dir
    }
    elseif ($c -eq 's') { pwsh -NoLogo }
    elseif ($c -eq 'q') { exit }
}
