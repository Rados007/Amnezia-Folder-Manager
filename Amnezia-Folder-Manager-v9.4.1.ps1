#Requires -Version 5.1

$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
} catch { }

Add-Type -Namespace Win32 -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
[DllImport("shcore.dll")]
public static extern int SetProcessDpiAwareness(int value);
[DllImport("user32.dll")]
public static extern IntPtr GetDC(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
[DllImport("gdi32.dll")]
public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
'@

try   { [Win32.Dpi]::SetProcessDpiAwareness(2) | Out-Null }
catch { try { [Win32.Dpi]::SetProcessDPIAware() | Out-Null } catch {} }

function Get-DpiScale {
    try {
        $hdc = [Win32.Dpi]::GetDC([IntPtr]::Zero)
        $dpi = [Win32.Dpi]::GetDeviceCaps($hdc, 88)
        [void][Win32.Dpi]::ReleaseDC([IntPtr]::Zero, $hdc)
        if ($dpi -le 0) { return 1.0 }
        return [double]$dpi / 96.0
    } catch { return 1.0 }
}

$script:DpiScale = Get-DpiScale
if     ($script:DpiScale -lt 1.12) { $script:UiScale = 1.0 }
elseif ($script:DpiScale -lt 1.37) { $script:UiScale = 1.25 }
elseif ($script:DpiScale -lt 1.62) { $script:UiScale = 1.5 }
elseif ($script:DpiScale -lt 1.87) { $script:UiScale = 1.75 }
else                               { $script:UiScale = 2.0 }

function Scaled([int]$v) { return [int][Math]::Round($v * $script:UiScale) }

$AppAuthor  = "Rados"
$AppVersion = "v9.4.1"
$RepoOwner  = "Rados007"
$RepoName   = "Amnezia-Folder-Manager"

# Палитра: глубокий тёмный UI в духе Discord / VS Code
$C = @{
    Bg         = [System.Drawing.Color]::FromArgb(49, 51, 56)
    Panel      = [System.Drawing.Color]::FromArgb(43, 45, 49)
    PanelAlt   = [System.Drawing.Color]::FromArgb(30, 31, 34)
    PanelRaised= [System.Drawing.Color]::FromArgb(35, 36, 40)
    Border     = [System.Drawing.Color]::FromArgb(66, 69, 75)
    BorderSoft = [System.Drawing.Color]::FromArgb(58, 60, 65)
    Text       = [System.Drawing.Color]::FromArgb(242, 243, 245)
    TextMuted  = [System.Drawing.Color]::FromArgb(181, 186, 193)
    TextDim    = [System.Drawing.Color]::FromArgb(148, 155, 164)
    TextGreen  = [System.Drawing.Color]::FromArgb(67, 181, 129)
    Accent     = [System.Drawing.Color]::FromArgb(88, 101, 242)
    AccentSoft = [System.Drawing.Color]::FromArgb(71, 82, 196)
    Btn        = [System.Drawing.Color]::FromArgb(66, 70, 77)
    BtnHover   = [System.Drawing.Color]::FromArgb(80, 85, 94)
    Danger     = [System.Drawing.Color]::FromArgb(237, 66, 69)
    DangerHover= [System.Drawing.Color]::FromArgb(200, 50, 53)
    Green      = [System.Drawing.Color]::FromArgb(35, 165, 90)
    GreenHov   = [System.Drawing.Color]::FromArgb(28, 140, 75)
    Selection  = [System.Drawing.Color]::FromArgb(66, 74, 112)
    Highlight  = [System.Drawing.Color]::FromArgb(88, 101, 242)
}

function Set-NodeColor {
    param($node, $color)
    try {
        if ($null -ne $color -and $color -is [System.Drawing.Color]) {
            $node.ForeColor = $color
        } else {
            $node.ForeColor = $C.Text
        }
    } catch { }
}

# ================== MUTEX ==================
$script:mutex = $null
try {
    $script:mutex = New-Object System.Threading.Mutex($false, "Global\AmneziaFolderManager_SingleInstance_v8")
    if (-not $script:mutex.WaitOne(0)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Amnezia Folder Manager уже запущен.`n`nЗакройте предыдущий экземпляр и попробуйте снова.",
            "Повторный запуск",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information)
        try { $script:mutex.Dispose() } catch { }
        exit 0
    }
} catch {
    $script:mutex = $null
}

# ================== ПУТИ ==================

function Get-ScriptDirectory {
    # In a compiled executable, resolve files relative to the EXE rather than
    # the PowerShell compiler's temporary location.
    try {
        $procName = [System.Diagnostics.Process]::GetCurrentProcess().ProcessName
        if ($procName -notmatch '^(powershell|pwsh|powershell_ise)$') {
            $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            if ($exePath) { return Split-Path -Parent $exePath }
        }
    } catch { }
    if ($PSScriptRoot) { return $PSScriptRoot }
    try {
        if ($MyInvocation.MyCommand.Path) {
            return Split-Path -Parent $MyInvocation.MyCommand.Path
        }
    } catch { }
    try {
        $asm = [System.Reflection.Assembly]::GetEntryAssembly()
        if ($asm -and $asm.Location) { return Split-Path -Parent $asm.Location }
    } catch { }
    try {
        $proc = [System.Diagnostics.Process]::GetCurrentProcess()
        if ($proc -and $proc.MainModule -and $proc.MainModule.FileName) {
            return Split-Path -Parent $proc.MainModule.FileName
        }
    } catch { }
    return (Get-Location).Path
}

function Test-DirectoryWritable([string]$dir) {
    try {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $false }
        $probe = Join-Path $dir (".write-test-{0}.tmp" -f ([Guid]::NewGuid().ToString("N")))
        Set-Content -LiteralPath $probe -Value "x" -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

$ScriptDir = Get-ScriptDirectory

# User configuration is independent of installation/EXE location.
# Keep exports beside the program when possible, but ALWAYS persist settings in AppData.
$DataDir = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'AmneziaFolderManager'
if (-not (Test-Path -LiteralPath $DataDir -PathType Container)) {
    New-Item -ItemType Directory -Path $DataDir -Force -ErrorAction Stop | Out-Null
}
if (-not (Test-DirectoryWritable $DataDir)) {
    throw "Cannot write configuration directory: $DataDir"
}
$OutDir = $ScriptDir
if (-not (Test-DirectoryWritable $OutDir)) { $OutDir = $DataDir }

# Migrate v9.2.0 portable settings, but never overwrite existing user settings.
$legacyConfig = Join-Path $ScriptDir 'folders.json'
$legacyBackup = Join-Path $ScriptDir 'folders.json.bak'
$newConfig = Join-Path $DataDir 'folders.json'
if (-not (Test-Path -LiteralPath $newConfig) -and (Test-Path -LiteralPath $legacyConfig)) {
    try {
        $legacyData = Get-Content -LiteralPath $legacyConfig -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($legacyData -and $legacyData.PSObject.Properties['Folders']) {
            Copy-Item -LiteralPath $legacyConfig -Destination $newConfig -ErrorAction Stop
            if (Test-Path -LiteralPath $legacyBackup) {
                Copy-Item -LiteralPath $legacyBackup -Destination (Join-Path $DataDir 'folders.json.bak') -ErrorAction SilentlyContinue
            }
        }
    } catch { Write-Warning "Could not migrate legacy settings: $_" }
}

$LogPath    = Join-Path $DataDir "amnezia-fm.log"
$ConfigPath = Join-Path $DataDir "folders.json"
$BackupPath = Join-Path $DataDir "folders.json.bak"

function Write-Log($msg) {
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] $msg"
        # Keep one bounded log, preserving the newest entries only.
        if (Test-Path -LiteralPath $LogPath) {
            $fi = Get-Item -LiteralPath $LogPath -ErrorAction Stop
            if ($fi.Length -gt 950KB) {
                $lines = @(Get-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction Stop)
                $tail = New-Object 'System.Collections.Generic.List[string]'
                $bytes = 0
                for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                    $bytes += [System.Text.Encoding]::UTF8.GetByteCount($lines[$i]) + 2
                    if ($bytes -gt 700KB) { break }
                    $tail.Insert(0, $lines[$i])
                }
                [System.IO.File]::WriteAllLines($LogPath, [string[]]$tail.ToArray(), ([System.Text.UTF8Encoding]::new($false)))
            }
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch { }
}

Write-Log "=== START $AppVersion (by $AppAuthor) ==="
Write-Log "DPI=$($script:DpiScale) UiScale=$($script:UiScale)"
Write-Log "ScriptDir=$ScriptDir"
Write-Log "DataDir=$DataDir"
Write-Log "OutDir=$OutDir"

# ================== ХЕЛПЕРЫ ПУТЕЙ ==================

function Normalize-FullPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $path }
    try {
        $full = [System.IO.Path]::GetFullPath($path)
        $root = [System.IO.Path]::GetPathRoot($full)
        if ([string]::Equals($full, $root, [System.StringComparison]::OrdinalIgnoreCase)) { return $full }
        return $full.TrimEnd('\')
    } catch { return $path.TrimEnd('\') }
}
function Get-PathKey([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return "" }
    return (Normalize-FullPath $path).ToLowerInvariant()
}

function Test-PathWithinFolder([string]$path, [string]$folder) {
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($folder)) { return $false }
    try {
        $p = Normalize-FullPath $path
        $f = Normalize-FullPath $folder
    } catch { return $false }
    if ([string]::Equals($p, $f, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $prefix = if ($f.EndsWith('\')) { $f } else { $f + '\' }
    return $p.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathInAnyConfiguredFolder([string]$path, $folders) {
    foreach ($folder in @($folders)) {
        if (Test-PathWithinFolder $path $folder) { return $true }
    }
    return $false
}

function Normalize-FolderList($folders) {
    $result = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($folder in @($folders)) {
        if ([string]::IsNullOrWhiteSpace([string]$folder)) { continue }
        $full = Normalize-FullPath ([string]$folder)
        $key = $full.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$result.Add($full)
        }
    }

    $sorted = @($result | Sort-Object Length)
    $final = New-Object System.Collections.Generic.List[string]

    foreach ($folder in $sorted) {
        $covered = $false
        foreach ($parent in $final) {
            if (Test-PathWithinFolder $folder $parent) {
                $covered = $true
                break
            }
        }
        if (-not $covered) { [void]$final.Add($folder) }
    }

    return @($final)
}

# ================== UI СТИЛИ ==================

# Use the contemporary Windows 11 font when installed, with a reliable Windows 10 fallback.
# Resolve the installed family once rather than probing GDI fonts for every control.
$script:UiFontFamily = 'Segoe UI'
try {
    $installedFonts = New-Object System.Drawing.Text.InstalledFontCollection
    if (@($installedFonts.Families | Where-Object { $_.Name -eq 'Segoe UI Variable' }).Count -gt 0) {
        $script:UiFontFamily = 'Segoe UI Variable'
    }
} catch { }

function New-UiFont([double]$size, [string]$weight = "Regular", [string]$family = "") {
    $style = [System.Drawing.FontStyle]::Regular
    if ($weight -eq "Bold") { $style = [System.Drawing.FontStyle]::Bold }
    if ([string]::IsNullOrWhiteSpace($family)) { $family = $script:UiFontFamily }
    foreach ($candidate in @($family, 'Segoe UI', 'Microsoft Sans Serif')) {
        try {
            $f = New-Object System.Drawing.Font($candidate, [single]($size * $script:UiScale), $style)
            if ($f.FontFamily.Name -eq $candidate) { return $f }
            $f.Dispose()
        } catch { }
    }
    return New-Object System.Drawing.Font([System.Drawing.FontFamily]::GenericSansSerif, [single]($size * $script:UiScale), $style)
}

function Get-HoverColor([System.Drawing.Color]$c) {
    $r = [Math]::Min(255, [int]$c.R + 18)
    $g = [Math]::Min(255, [int]$c.G + 18)
    $b = [Math]::Min(255, [int]$c.B + 18)
    return [System.Drawing.Color]::FromArgb($r, $g, $b)
}

function Get-DownColor([System.Drawing.Color]$c) {
    $r = [Math]::Max(0, [int]$c.R - 18)
    $g = [Math]::Max(0, [int]$c.G - 18)
    $b = [Math]::Max(0, [int]$c.B - 18)
    return [System.Drawing.Color]::FromArgb($r, $g, $b)
}

function Style-FlatButton($btn, $normalColor, $textColor, $hoverColor = $null, $borderColor = $null) {
    $btn.FlatStyle = "Flat"
    if ($null -eq $borderColor) {
        $btn.FlatAppearance.BorderSize = 0
    } else {
        $btn.FlatAppearance.BorderSize = 1
        $btn.FlatAppearance.BorderColor = $borderColor
    }
    if ($null -eq $hoverColor) { $hoverColor = Get-HoverColor $normalColor }
    $btn.FlatAppearance.MouseOverBackColor = $hoverColor
    $btn.FlatAppearance.MouseDownBackColor = (Get-DownColor $normalColor)
    $btn.BackColor = $normalColor
    $btn.ForeColor = $textColor
    $btn.Cursor = "Hand"
    $btn.UseVisualStyleBackColor = $false
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $btn.FlatAppearance.BorderSize = 0
}

function Style-PrimaryButton($btn) {
    Style-FlatButton $btn $C.Accent ([System.Drawing.Color]::White) $C.AccentSoft
    $btn.Font = New-UiFont 10 "Bold"
}

function Style-SecondaryButton($btn) {
    Style-FlatButton $btn $C.Btn $C.Text $C.BtnHover $C.BorderSoft
    $btn.Font = New-UiFont 9
}

function Style-DangerButton($btn) {
    Style-FlatButton $btn $C.Danger ([System.Drawing.Color]::White) $C.DangerHover
    $btn.Font = New-UiFont 9 "Bold"
}

function Style-GreenButton($btn) {
    Style-FlatButton $btn $C.Green ([System.Drawing.Color]::White) $C.GreenHov
    $btn.Font = New-UiFont 9 "Bold"
}

function Style-Form($form) {
    $form.BackColor = $C.Bg
    $form.ForeColor = $C.Text
    $form.Font = New-UiFont 9
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
}

function Style-Label($lbl) {
    $lbl.BackColor = $C.Bg
    $lbl.ForeColor = $C.Text
    $lbl.Font = New-UiFont 9
}

function Style-MutedLabel($lbl) {
    $lbl.BackColor = $C.Bg
    $lbl.ForeColor = $C.TextMuted
    $lbl.Font = New-UiFont 8.5
}

function Style-DarkTextBox($ctrl) {
    $ctrl.BackColor = $C.PanelAlt
    $ctrl.ForeColor = $C.Text
    $ctrl.BorderStyle = "FixedSingle"
    $ctrl.Font = New-UiFont 9.5
}

function Style-TreeView($tree) {
    $tree.BackColor = $C.Panel
    $tree.ForeColor = $C.Text
    $tree.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $tree.Font = New-UiFont 9.5
    $tree.ShowLines = $false
    $tree.ShowPlusMinus = $true
    $tree.ShowRootLines = $true
    $tree.HideSelection = $false
    $tree.FullRowSelect = $false
    $tree.LineColor = $C.Border
}

function Set-ButtonOkAction($btn) {
    $btn.Add_Click({
        param($sender, $e)
        try { $f = $sender.FindForm(); if ($f) { $f.DialogResult = [System.Windows.Forms.DialogResult]::OK } } catch { }
        try { $f = $sender.FindForm(); if ($f) { $f.Close() } } catch { }
    })
}

function Set-ButtonCancelAction($btn) {
    $btn.Add_Click({
        param($sender, $e)
        try { $f = $sender.FindForm(); if ($f) { $f.DialogResult = [System.Windows.Forms.DialogResult]::Cancel } } catch { }
        try { $f = $sender.FindForm(); if ($f) { $f.Close() } } catch { }
    })
}

# ================== КОНФИГ ==================

function Load-Config {
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $cfg.PSObject.Properties["Folders"]) {
                $cfg | Add-Member -MemberType NoteProperty -Name "Folders" -Value @() -Force
            }
            if (-not $cfg.PSObject.Properties["Selected"]) {
                $cfg | Add-Member -MemberType NoteProperty -Name "Selected" -Value ([PSCustomObject]@{}) -Force
            }
            if (-not $cfg.PSObject.Properties["LastBackup"]) {
                $cfg | Add-Member -MemberType NoteProperty -Name "LastBackup" -Value "" -Force
            }
            if (-not $cfg.PSObject.Properties["HideIntro"]) {
                $cfg | Add-Member -MemberType NoteProperty -Name "HideIntro" -Value $false -Force
            }
            if (-not $cfg.PSObject.Properties["LastUpdateCheck"]) {
                $cfg | Add-Member -MemberType NoteProperty -Name "LastUpdateCheck" -Value "" -Force
            }
            if (-not $cfg.PSObject.Properties["LatestKnownTag"]) {
                $cfg | Add-Member -MemberType NoteProperty -Name "LatestKnownTag" -Value "" -Force
            }
            if (-not $cfg.PSObject.Properties["WindowGeometry"]) {
                $cfg | Add-Member -MemberType NoteProperty -Name "WindowGeometry" -Value $null -Force
            }
            if (-not $cfg.PSObject.Properties["ExcludedFolders"]) { $cfg | Add-Member NoteProperty ExcludedFolders @() -Force }
            if (-not $cfg.PSObject.Properties["ManagedApps"]) { $cfg | Add-Member NoteProperty ManagedApps @() -Force }
            return $cfg
        } catch {
            Write-Log "Load-Config err: $_"
            if (Test-Path -LiteralPath $BackupPath) {
                try {
                    $recovered = Get-Content -LiteralPath $BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    Write-Log "Конфигурация восстановлена из folders.json.bak"
                    foreach ($kv in @(@("Folders",@()), @("Selected",([PSCustomObject]@{})), @("LastBackup",""), @("ExcludedFolders",@()), @("ManagedApps",@()))) {
                        if (-not $recovered.PSObject.Properties[[string]$kv[0]]) { $recovered | Add-Member NoteProperty ([string]$kv[0]) $kv[1] -Force }
                    }
                    return $recovered
                } catch {
                    Write-Log "Load backup config err: $_"
                }
            }
        }
    }
    return [PSCustomObject]@{
        ExcludedFolders = @()
        ManagedApps     = @()
        Folders         = @()
        Selected        = [PSCustomObject]@{}
        LastBackup      = ""
        HideIntro       = $false
        LastUpdateCheck = ""
        LatestKnownTag  = ""
        WindowGeometry  = $null
    }
}

function Save-Config($cfg) {
    $tmpPath = "$ConfigPath.tmp"
    try {
        $json = ConvertTo-Json -InputObject $cfg -Depth 50 -ErrorAction Stop
        $roundTrip = $json | ConvertFrom-Json -ErrorAction Stop
        if (-not $roundTrip.PSObject.Properties['Folders'] -or -not $roundTrip.PSObject.Properties['Selected']) {
            throw 'Serialized configuration is missing Folders or Selected'
        }
        [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        # Avoid losing the last good config if replacement or process termination fails.
        if (Test-Path -LiteralPath $ConfigPath) {
            [System.IO.File]::Replace($tmpPath, $ConfigPath, $BackupPath)
        } else {
            [System.IO.File]::Move($tmpPath, $ConfigPath)
        }
        $saved = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (@($saved.Folders).Count -ne @($cfg.Folders).Count) {
            throw 'Config verification failed: folder count differs'
        }
        Write-Log ("Config saved: folders={0} selected={1} path={2}" -f @($saved.Folders).Count, @($saved.Selected.PSObject.Properties).Count, $ConfigPath)
        return $true
    } catch {
        Write-Log "Save-Config err: $_"
        return $false
    } finally {
        if (Test-Path -LiteralPath $tmpPath) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
}


# ================== СКАНИРОВАНИЕ ==================

function Test-IsExcluded([string]$path) {
    foreach ($folder in @($script:excludedFolders)) {
        if (Test-PathWithinFolder $path $folder) { return $true }
    }
    return $false
}
function Get-ExeFiles {
    param([string]$folder, $onProgress = $null)
    $result = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $root = Normalize-FullPath $folder
    $rootKey = Get-PathKey $root
    $script:scanState[$rootKey] = 'OK'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $script:scanState[$rootKey] = 'UNAVAILABLE'; return @()
    }
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($root)
    $scanned = 0
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (Test-IsExcluded $current) { continue }
        $scanned++
        if ($onProgress -and ($scanned % 50 -eq 0)) {
            try { & $onProgress $scanned $result.Count } catch { }
        }
        try {
            foreach ($dir in @(Get-ChildItem -LiteralPath $current -Directory -ErrorAction Stop)) {
                if (($dir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if (-not (Test-IsExcluded $dir.FullName)) { $queue.Enqueue($dir.FullName) }
            }
        } catch { $script:scanState[$rootKey] = 'PARTIAL'; Write-Log "Scan folders error: $current — $_" }
        try {
            foreach ($file in @(Get-ChildItem -LiteralPath $current -File -Filter '*.exe' -ErrorAction Stop)) {
                if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                [void]$result.Add($file)
            }
        } catch { $script:scanState[$rootKey] = 'PARTIAL'; Write-Log "Scan files error: $current — $_" }
    }
    if ($onProgress) { try { & $onProgress $scanned $result.Count } catch { } }
    return @($result | Sort-Object -Property FullName -Unique)
}


function Format-Size($bytes) {
    if ($bytes -ge 1TB) { return ("{0:N2} ТБ" -f ($bytes/1TB)) }
    if ($bytes -ge 1GB) { return ("{0:N2} ГБ" -f ($bytes/1GB)) }
    if ($bytes -ge 1MB) { return ("{0:N2} МБ" -f ($bytes/1MB)) }
    if ($bytes -ge 1KB) { return ("{0:N1} КБ" -f ($bytes/1KB)) }
    return "$bytes Б"
}

# ================== КЭШ EXE ==================

$script:exeCache = @{}

function Invalidate-ExeCache {
    $script:exeCache = @{}
    $script:scanState = @{}
    Write-Log "ExeCache invalidated"
}

function Get-CachedExeFiles {
    param(
        [string]$folder,
        $onProgress = $null
    )
    $folderKey = Get-PathKey $folder

    if ($script:exeCache.ContainsKey($folderKey)) {
        $entry = $script:exeCache[$folderKey]
        if ($null -ne $entry.Files) {
            return @($entry.Files)
        }
    }

    $files = @(Get-ExeFiles -folder $folder -onProgress $onProgress)
    # Incomplete scans must be retried; do not cache a partial result.
    if ($script:scanState[$folderKey] -ne 'OK') { return $files }
    $script:exeCache[$folderKey] = @{
        Files = $files
    }
    return $files
}

# ================== ОБНОВЛЕНИЯ ==================

function Test-VersionString([string]$a, [string]$b) {
    try {
        $ca = $a.TrimStart('v','V').Split('.')
        $cb = $b.TrimStart('v','V').Split('.')
        $n = [Math]::Max($ca.Count, $cb.Count)
        for ($i = 0; $i -lt $n; $i++) {
            $x = 0; $y = 0
            if ($i -lt $ca.Count) { [void][int]::TryParse($ca[$i], [ref]$x) }
            if ($i -lt $cb.Count) { [void][int]::TryParse($cb[$i], [ref]$y) }
            if ($x -gt $y) { return $true }
            if ($x -lt $y) { return $false }
        }
        return $false
    } catch { return $false }
}

function Get-LatestRelease {
    try {
        $url = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
        $headers = @{ "User-Agent" = "AmneziaFolderManager" }
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 5 -ErrorAction Stop
        return $resp
    } catch {
        return $null
    }
}

# ================== ИНСТРУКЦИЯ ==================

function Show-IntroWindow($showCheckbox) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Amnezia Folder Manager — инструкция"
    $form.Size = New-Object System.Drawing.Size((Scaled 760), (Scaled 640))
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    Style-Form $form
    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 12))
    $rtb.Size = New-Object System.Drawing.Size((Scaled 720), (Scaled 520))
    $rtb.ReadOnly = $true
    $rtb.BorderStyle = "FixedSingle"
    $rtb.BackColor = $C.PanelAlt
    $rtb.ForeColor = $C.Text
    $rtb.Font = New-UiFont 10
    $rtb.WordWrap = $true
    $rtb.ScrollBars = "Vertical"
    $form.Controls.Add($rtb)

    $colHeading = [System.Drawing.Color]::FromArgb(120, 140, 255)
    $colMuted   = [System.Drawing.Color]::FromArgb(148, 155, 164)
    $colText    = [System.Drawing.Color]::FromArgb(219, 222, 225)
    $fontNormal = New-UiFont 10
    $fontBold   = New-UiFont 10 "Bold"
    $fontHead   = New-UiFont 12 "Bold"
    $fontItalic = New-Object System.Drawing.Font($script:UiFontFamily, [single](9 * $script:UiScale), [System.Drawing.FontStyle]::Italic)

    function Add-Line([string]$text, $font, $color) {
        try { $rtb.SelectionFont  = $font } catch { }
        try { $rtb.SelectionColor = $color } catch { }
        $rtb.AppendText("$text`n")
        try { $rtb.SelectionFont  = $fontNormal } catch { }
        try { $rtb.SelectionColor = $colText } catch { }
    }

    function Add-Heading([string]$text)    { Add-Line $text $fontHead $colHeading }
    function Add-Subheading([string]$text) { Add-Line $text $fontBold $colHeading }
    function Add-Paragraph([string]$text)  { Add-Line $text $fontNormal $colText }
    function Add-Author([string]$text)     { Add-Line $text $fontItalic $colMuted }
    function Add-Spacer { $rtb.AppendText("`n") }

    Add-Heading "Amnezia Folder Manager $AppVersion"
    Add-Author "Автор: $AppAuthor  |  Руководство пользователя"
    Add-Spacer

    Add-Heading "Для чего нужна программа"
    Add-Paragraph "Folder Manager формирует резервную копию AmneziaVPN со списком приложений, которые должны обходить VPN при использовании режима исключений приложений (split tunneling). Она не меняет настройки работающего клиента напрямую: результат нужно импортировать в AmneziaVPN."
    Add-Spacer

    Add-Heading "Быстрый старт — 5 шагов"
    Add-Paragraph "1. В AmneziaVPN экспортируйте актуальную резервную копию подключения. Повторяйте экспорт перед КАЖДЫМ новым обновлением через Folder Manager."
    Add-Paragraph "2. Нажмите «+ Добавить папку» и выберите каталог с программами или играми. Вложенные каталоги сканируются автоматически."
    Add-Paragraph "3. Настройте галочки в дереве: отмеченные EXE утилита будет поддерживать в списке исключений VPN."
    Add-Paragraph "4. Нажмите «Создать backup», вручную выберите только что экспортированный файл и изучите список изменений. Нажмите «Создать backup» в окне подтверждения."
    Add-Paragraph "5. Импортируйте полученный файл Amnezia-UPDATED.backup в AmneziaVPN и проверьте список исключений приложений."
    Add-Spacer

    Add-Heading "Галочки и маршрутизация"
    Add-Paragraph "Галочка у EXE: Folder Manager добавляет его в исключения AmneziaVPN, то есть предполагается работа приложения БЕЗ VPN в соответствующем режиме клиента."
    Add-Paragraph "Снятая галочка: программа не добавляет этот EXE; если он ранее был добавлен самим Folder Manager, при следующем создании backup она может удалить его из управляемых исключений."
    Add-Paragraph "Галочка у папки действует на файлы внутри неё. Поиск сверху фильтрует отображение дерева. Настройки маршрутизации в самом AmneziaVPN также влияют на итоговое поведение."
    Add-Spacer

    Add-Heading "Игру нужно оставить В VPN?"
    Add-Paragraph "Найдите её папку в дереве, нажмите правой кнопкой мыши и выберите «Пропускать эту папку и всё внутри». Все вложенные EXE перестанут сканироваться и автоматически добавляться в исключения VPN."
    Add-Paragraph "Пропущенная папка остаётся видимой с меткой [ПРОПУСК]. Через правую кнопку её можно вернуть в сканирование. Не путайте «пропустить при сканировании» с удалением папки или файлов с диска — ничего с диска не удаляется."
    Add-Paragraph "Ранее добавленные Folder Manager исключения из такой папки убираются из нового backup. Если аналогичный EXE был добавлен вручную в клиенте AmneziaVPN, его запись может остаться: проверьте список в клиенте."
    Add-Spacer

    Add-Heading "Новые и удалённые EXE"
    Add-Paragraph "При обновлении базы или подготовке backup программа заново проверяет отслеживаемые каталоги. Новые найденные EXE по умолчанию отмечаются. Ранее управляемые исключения могут быть убраны из нового backup, если файл удалён, папка исключена или галочка снята."
    Add-Paragraph "Если сканирование папки завершилось с ошибкой или каталог временно недоступен, данные защищаются от очистки по неполному результату. Перед записью backup можно посмотреть планируемые добавления и удаления."
    Add-Spacer

    Add-Heading "Не потеряются ли ручные исключения?"
    Add-Paragraph "Записи, добавленные вручную через AmneziaVPN, сохраняются из выбранного исходного backup, если Folder Manager не распознаёт их как ранее управляемые им записи. Для точного сохранения ручных изменений всегда сначала делайте НОВЫЙ экспорт из самого AmneziaVPN."
    Add-Paragraph "Если EXE с одним путём ранее управлялся Folder Manager, программа не всегда может отличить его от ручной записи. Перед подтверждением внимательно просматривайте удаления."
    Add-Spacer

    Add-Heading "Обновить базу или создать backup?"
    Add-Paragraph "«Обновить базу» (меню правой кнопки мыши в дереве) — пересканировать папки и обновить внутренний список EXE. Файл для AmneziaVPN при этом НЕ создаётся."
    Add-Paragraph "«Создать backup» — выбрать свежий экспорт AmneziaVPN, пересканировать файлы, показать предварительный просмотр, объединить списки и создать итоговый backup для импорта."
    Add-Spacer

    Add-Heading "Файлы и безопасность"
    Add-Paragraph "Amnezia-UPDATED.backup — один итоговый файл, который обновляется при последующих успешных экспортах. Исходный выбранный файл не должен перезаписываться."
    Add-Paragraph "folders.json хранит папки, галочки и правила. folders.json.bak — страховочная копия настроек. amnezia-fm.log — ограниченный журнал диагностики. Не удаляйте folders.json, если хотите сохранить настройки."
    Add-Paragraph "Резервная копия AmneziaVPN может содержать ключи подключения и другие секреты. Не публикуйте её в открытом доступе. Перед импортом нового backup полезно сохранить отдельную рабочую копию из клиента."
    Add-Spacer

    Add-Heading "Если результат не виден в AmneziaVPN"
    Add-Paragraph "Убедитесь, что импортировали именно новый Amnezia-UPDATED.backup, выбрали нужное подключение и открыли раздел исключений приложений. Если список не изменился, сохраните исходный экспорт и журнал, прежде чем повторять операцию."
    Add-Spacer
    Add-Author "© 2026 $AppAuthor"

    $rtb.SelectionStart = 0
    $rtb.SelectionLength = 0

    $chk = $null
    if ($showCheckbox) {
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = "Больше не показывать это окно при запуске"
        $chk.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 545))
        $chk.Width = (Scaled 500)
        $chk.Height = (Scaled 24)
        $chk.BackColor = $C.Bg
        $chk.ForeColor = $C.Text
        $form.Controls.Add($chk)
    }

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Понятно"
    $btnOk.Width = (Scaled 130)
    $btnOk.Height = (Scaled 34)
    $btnOk.Anchor = "Bottom,Right"
    $btnOk.Location = New-Object System.Drawing.Point((Scaled 600), (Scaled 540))
    Style-PrimaryButton $btnOk
    $btnOk.Font = New-UiFont 10 "Bold"
    $form.Controls.Add($btnOk)
    Set-ButtonOkAction $btnOk

    $form.Add_Shown({
        $btnOk.Left = $form.ClientSize.Width - $btnOk.Width - (Scaled 12)
        $btnOk.Top  = $form.ClientSize.Height - $btnOk.Height - (Scaled 12)
        if ($chk) { $chk.Top = $btnOk.Top + [int](($btnOk.Height - $chk.Height) / 2) }
    })

    [void]$form.ShowDialog()
    $checked = $false
    if ($chk -and $form.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        $checked = $chk.Checked
    }
    $form.Dispose()
    return $checked
}

# ================== MAIN ==================
Write-Log "Loading config"
$cfg = Load-Config

$script:folders    = @(Normalize-FolderList $cfg.Folders)
$script:lastBackup = ""
if ($cfg.LastBackup) { $script:lastBackup = [string]$cfg.LastBackup }
$script:hideIntro  = $false
if ($cfg.PSObject.Properties["HideIntro"]) { $script:hideIntro = [bool]$cfg.HideIntro }

$script:selected = [PSCustomObject]@{}
if ($cfg.Selected) {
    foreach ($p in $cfg.Selected.PSObject.Properties) {
        $script:selected | Add-Member -MemberType NoteProperty -Name $p.Name -Value ([bool]$p.Value) -Force
    }
}

$script:excludedFolders = @($cfg.ExcludedFolders | Where-Object { $_ })
$script:managedApps = @($cfg.ManagedApps | Where-Object { $_ })
$script:scanState = @{}
$script:treeUpdating      = $false
$script:saveDebounceTimer = $null
$script:pendingSave       = $false
$script:lastRebuild       = $null
$script:exeCache          = @{}
$script:filterIsPlaceholder = $true
$script:filterPlaceholder  = "поиск по имени..."

if (-not $script:hideIntro) {
    $userChecked = Show-IntroWindow $true
    if ($userChecked) {
        $script:hideIntro = $true
        $cfg.HideIntro = $true
        Save-Config $cfg
        Write-Log "Инструкция отключена пользователем"
    } else {
        Write-Log "Инструкция показана"
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Amnezia Folder Manager $AppVersion — by $AppAuthor"
$form.Size = New-Object System.Drawing.Size((Scaled 1000), (Scaled 840))
$form.MinimumSize = New-Object System.Drawing.Size((Scaled 840), (Scaled 700))
$form.StartPosition = "CenterScreen"
Style-Form $form
try {
    $iconPath = Join-Path $ScriptDir "icon.ico"
    if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
} catch { Write-Log "Не удалось загрузить иконку окна: $_" }
$form.AllowDrop = $true
$form.KeyPreview = $true

$form.Add_KeyDown({
    param($sender, $e)
    # Ctrl+F — фокус в фильтр
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) {
        $e.Handled = $true
        if ($script:filterIsPlaceholder) {
            $txtMainFilter.Text = ""
            $txtMainFilter.ForeColor = $C.Text
            $script:filterIsPlaceholder = $false
        }
        $txtMainFilter.Focus()
        $txtMainFilter.SelectAll()
        return
    }
    # Escape — очистить фильтр, не затрагивая выбранные приложения.
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $txtMainFilter.Focused) {
        $e.Handled = $true
        $txtMainFilter.Text = ""
        return
    }
    # F5 — обновить базу
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        $e.Handled = $true
        Log "=== F5: Обновить всю базу ==="
        $res = Do-UpdateOnly
        Log "Новых EXE: $($res.New); удалено отсутствующих: $($res.Removed)"
        return
    }
    # Delete — удалить выбранную папку
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete) {
        if ($txtMainFilter.Focused) { return }
        $e.Handled = $true
        Remove-SelectedFolder
        return
    }
})

# Восстановление геометрии окна
try {
    if ($cfg.WindowGeometry) {
        $g = $cfg.WindowGeometry
        if ($g.Width -gt 200 -and $g.Height -gt 200) {
            $form.StartPosition = "Manual"
            $form.Width  = [int]$g.Width
            $form.Height = [int]$g.Height
            if ($null -ne $g.Left -and $null -ne $g.Top) {
                $form.Left = [int]$g.Left
                $form.Top  = [int]$g.Top
            }
            if ($g.WindowState -eq "Maximized") {
                $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
            }
        }
    }
} catch { Write-Log "Restore geometry err: $_" }

$form.Add_FormClosing({
    try {
        if ($script:saveDebounceTimer) {
            $script:saveDebounceTimer.Stop()
            $script:saveDebounceTimer.Dispose()
            $script:saveDebounceTimer = $null
        }
    } catch { }
    try {
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
            $cfg.WindowGeometry = [PSCustomObject]@{
                Width       = $form.Width
                Height      = $form.Height
                Left        = $form.Left
                Top         = $form.Top
                WindowState = "Normal"
            }
        } else {
            $cfg.WindowGeometry = [PSCustomObject]@{
                Width       = $form.RestoreBounds.Width
                Height      = $form.RestoreBounds.Height
                Left        = $form.RestoreBounds.Left
                Top         = $form.RestoreBounds.Top
                WindowState = $form.WindowState.ToString()
            }
        }
    } catch { }
    try {
        Save-State
    } catch {
        Write-Log "FormClosing Save-State error: $_"
    }
})

# ---- Верхняя панель (фильтр) ----
$pnlTop = New-Object System.Windows.Forms.Panel
$pnlTop.Location = New-Object System.Drawing.Point(0, 0)
$pnlTop.Size = New-Object System.Drawing.Size((Scaled 1000), (Scaled 48))
$pnlTop.Anchor = "Top,Left,Right"
$pnlTop.BackColor = $C.PanelRaised
$form.Controls.Add($pnlTop)

# Discord-style accent separator under the toolbar. No application state involved.
$pnlAccent = New-Object System.Windows.Forms.Panel
$pnlAccent.Location = New-Object System.Drawing.Point(0, (Scaled 46))
$pnlAccent.Size = New-Object System.Drawing.Size((Scaled 1000), (Scaled 2))
$pnlAccent.Anchor = 'Top,Left,Right'
$pnlAccent.BackColor = $C.Accent
$pnlTop.Controls.Add($pnlAccent)

$lblMainFilter = New-Object System.Windows.Forms.Label
$lblMainFilter.Text = "Поиск"
$lblMainFilter.Location = New-Object System.Drawing.Point((Scaled 14), (Scaled 12))
$lblMainFilter.Size = New-Object System.Drawing.Size((Scaled 70), (Scaled 24))
$lblMainFilter.BackColor = $C.PanelRaised
$lblMainFilter.ForeColor = $C.TextMuted
$lblMainFilter.Font = New-UiFont 10 "Bold"
$lblMainFilter.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlTop.Controls.Add($lblMainFilter)

$txtMainFilter = New-Object System.Windows.Forms.TextBox
$txtMainFilter.Location = New-Object System.Drawing.Point((Scaled 90), (Scaled 10))
$txtMainFilter.Width = (Scaled 400)
$txtMainFilter.Height = (Scaled 28)
Style-DarkTextBox $txtMainFilter
$txtMainFilter.Text = "Найти папку или EXE..."
$txtMainFilter.ForeColor = $C.TextDim
$script:filterIsPlaceholder = $true
$script:filterPlaceholder = "Найти папку или EXE..."
$pnlTop.Controls.Add($txtMainFilter)

$txtMainFilter.Add_GotFocus({
    if ($script:filterIsPlaceholder) {
        $txtMainFilter.Text = ""
        $txtMainFilter.ForeColor = $C.Text
        $script:filterIsPlaceholder = $false
    }
})
$txtMainFilter.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($txtMainFilter.Text)) {
        $script:filterIsPlaceholder = $true
        $txtMainFilter.Text = $script:filterPlaceholder
        $txtMainFilter.ForeColor = $C.TextDim
    }
})

# Маленькая кнопка «?» (инструкция)
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = "?"
$btnHelp.AccessibleName = "Открыть справку"
$btnHelp.Width = (Scaled 34)
$btnHelp.Height = (Scaled 28)
$btnHelp.Location = New-Object System.Drawing.Point((Scaled 720), (Scaled 10))
Style-SecondaryButton $btnHelp
$btnHelp.Font = New-UiFont 11 "Bold"
$pnlTop.Controls.Add($btnHelp)

# ---- Кнопка Добавить (под фильтром, слева) ----
$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = "+  Добавить папку"
$btnAdd.AccessibleName = "Добавить папку в отслеживание"
$btnAdd.Width = (Scaled 180)
$btnAdd.Height = (Scaled 32)
$btnAdd.Anchor = "Top,Left"
$btnAdd.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 56))
Style-PrimaryButton $btnAdd
$btnAdd.Font = New-UiFont 9.5 "Bold"
$form.Controls.Add($btnAdd)

# ---- Навигация и действия в стиле Discord ----
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Обновить список  (F5)"
$btnRefresh.AccessibleName = "Повторно просканировать выбранные папки"
$btnRefresh.Size = New-Object System.Drawing.Size((Scaled 190), (Scaled 32))
$btnRefresh.Location = New-Object System.Drawing.Point((Scaled 202), (Scaled 56))
Style-SecondaryButton $btnRefresh
$form.Controls.Add($btnRefresh)

$lblTreeSection = New-Object System.Windows.Forms.Label
$lblTreeSection.Text = "Приложения / папки"
$lblTreeSection.Location = New-Object System.Drawing.Point((Scaled 14), (Scaled 102))
$lblTreeSection.Size = New-Object System.Drawing.Size((Scaled 290), (Scaled 21))
$lblTreeSection.Font = New-UiFont 9.5 "Bold"
$lblTreeSection.ForeColor = $C.TextMuted
$lblTreeSection.BackColor = $C.Bg
$form.Controls.Add($lblTreeSection)

$lblTreeHint = New-Object System.Windows.Forms.Label
$lblTreeHint.Text = "Галочки определяют, какие EXE попадут в backup"
$lblTreeHint.AutoEllipsis = $true
$lblTreeHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblTreeHint.Location = New-Object System.Drawing.Point((Scaled 430), (Scaled 102))
$lblTreeHint.Size = New-Object System.Drawing.Size((Scaled 538), (Scaled 21))
$lblTreeHint.Font = New-UiFont 8
$lblTreeHint.ForeColor = $C.TextDim
$lblTreeHint.BackColor = $C.Bg
$form.Controls.Add($lblTreeHint)

# ---- Дерево ----
$tree = New-Object System.Windows.Forms.TreeView
$tree.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 130))
$tree.Size = New-Object System.Drawing.Size((Scaled 960), (Scaled 346))
$tree.Anchor = "Top,Left,Right"
$tree.CheckBoxes = $true
$tree.HideSelection = $false
$tree.ShowLines = $false
$tree.ShowRootLines = $true
$tree.ShowPlusMinus = $true
$tree.Indent = Scaled 22
$tree.ItemHeight = Scaled 24
$tree.AllowDrop = $true
Style-TreeView $tree
$form.Controls.Add($tree)

# ---- Панель статистики ----
$pnlStats = New-Object System.Windows.Forms.Panel
$pnlStats.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 484))
$pnlStats.Size = New-Object System.Drawing.Size((Scaled 960), (Scaled 44))
$pnlStats.Anchor = "Top,Left,Right"
$pnlStats.BackColor = $C.Panel
$form.Controls.Add($pnlStats)

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 4))
$lblInfo.Size = New-Object System.Drawing.Size((Scaled 920), (Scaled 20))
$lblInfo.Anchor = "Top,Left,Right"
$lblInfo.Text = "Готово."
$lblInfo.BackColor = $C.Panel
$lblInfo.ForeColor = $C.Text
$lblInfo.Font = New-UiFont 9
$pnlStats.Controls.Add($lblInfo)

$lblLast = New-Object System.Windows.Forms.Label
$lblLast.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 22))
$lblLast.Size = New-Object System.Drawing.Size((Scaled 920), (Scaled 18))
$lblLast.Anchor = "Top,Left,Right"
$lblLast.Text = "Последний использованный backup: (не указан)"
$lblLast.BackColor = $C.Panel
$lblLast.ForeColor = $C.TextMuted
$lblLast.Font = New-UiFont 8
$pnlStats.Controls.Add($lblLast)

# ---- Backup (слева под деревом/статистикой) ----
$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = "Создать backup Amnezia"
$btnBackup.AccessibleName = "Создать резервную копию для AmneziaVPN"
$btnBackup.Width = (Scaled 240)
$btnBackup.Height = (Scaled 40)
$btnBackup.Anchor = "Top,Left"
$btnBackup.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 538))
Style-PrimaryButton $btnBackup
$btnBackup.Font = New-UiFont 11 "Bold"
$form.Controls.Add($btnBackup)

# ---- Журнал ----
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Журнал событий"
$lblLog.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 590))
$lblLog.Size = New-Object System.Drawing.Size((Scaled 160), (Scaled 18))
$lblLog.Anchor = "Top,Left"
Style-MutedLabel $lblLog
$lblLog.Font = New-UiFont 9.5 "Bold"
$form.Controls.Add($lblLog)

$lblLogHint = New-Object System.Windows.Forms.Label
$lblLogHint.Text = "двойной клик — полный лог"
$lblLogHint.Location = New-Object System.Drawing.Point((Scaled 180), (Scaled 590))
$lblLogHint.Size = New-Object System.Drawing.Size((Scaled 280), (Scaled 18))
$lblLogHint.Anchor = "Top,Left"
$lblLogHint.BackColor = $C.Bg
$lblLogHint.ForeColor = $C.TextDim
$lblLogHint.Font = New-UiFont 8
$form.Controls.Add($lblLogHint)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point((Scaled 12), (Scaled 612))
$txtLog.Size = New-Object System.Drawing.Size((Scaled 960), (Scaled 220))
$txtLog.Anchor = "Top,Bottom,Left,Right"
$txtLog.BackColor = $C.PanelAlt
$txtLog.ForeColor = $C.TextMuted
$txtLog.BorderStyle = "FixedSingle"
$txtLog.Font = New-UiFont 9 "Regular" "Consolas"
$txtLog.Cursor = "Hand"
$txtLog.Add_DoubleClick({
    try {
        if (Test-Path -LiteralPath $LogPath) { Start-Process notepad.exe $LogPath }
        else { [void][System.Windows.Forms.MessageBox]::Show("Лог-файл ещё не создан.", "Журнал") }
    } catch { Write-Log "Не удалось открыть лог: $_" }
})
$form.Controls.Add($txtLog)

$script:txtLog = $txtLog

function Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $txtLog.AppendText("[$ts] $msg`r`n")
    Write-Log $msg
}

function Count-Selection {
    $total = 0; $checked = 0
    foreach ($p in $script:selected.PSObject.Properties) {
        $total++
        if ($p.Value) { $checked++ }
    }
    return @{ Total = $total; Checked = $checked }
}

function Folder-Missing($folder) {
    return (-not (Test-Path -LiteralPath $folder -PathType Container))
}

function Update-InfoLabel {
    try {
        $c = Count-Selection
        $lblInfo.Text = "Папок: $($script:folders.Count)    ·    EXE: $($c.Total)    ·    Отмечено: $($c.Checked)"
    } catch { }
}

function Set-UiBusy {
    param([bool]$Busy, [string]$Status)
    try {
        $form.Cursor = if ($Busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
        $btnAdd.Enabled          = -not $Busy
        $btnRefresh.Enabled      = -not $Busy
        $btnBackup.Enabled       = -not $Busy
        $btnHelp.Enabled         = -not $Busy
        $txtMainFilter.Enabled   = -not $Busy

        if ($Busy) {
            if ($Status) {
                $lblInfo.Text = $Status
                try { $lblInfo.Update() } catch { }
                try { $form.Update() } catch { }
            }
        } else {
            Update-InfoLabel
            try { $lblInfo.Update() } catch { }
        }
    } catch { }
}

function Schedule-Save {
    $script:pendingSave = $true
    if ($script:saveDebounceTimer) {
        try { $script:saveDebounceTimer.Stop() } catch { }
    } else {
        $script:saveDebounceTimer = New-Object System.Windows.Forms.Timer
        $script:saveDebounceTimer.Interval = 400
        $script:saveDebounceTimer.Add_Tick({
            $script:saveDebounceTimer.Stop()
            if ($script:pendingSave) {
                $script:pendingSave = $false
                Save-State
            }
        })
    }
    $script:saveDebounceTimer.Start()
}

function Save-State {
    $cfg.Folders    = @($script:folders)
    $cfg.ExcludedFolders = @($script:excludedFolders)
    $cfg.ManagedApps = @($script:managedApps)
    $cfg.Selected   = $script:selected
    $cfg.LastBackup = $script:lastBackup
    $cfg.HideIntro  = $script:hideIntro
    if (-not (Save-Config $cfg)) {
        Log "ОШИБКА: не удалось сохранить конфигурацию: $ConfigPath"
        [void][System.Windows.Forms.MessageBox]::Show(
            "Не удалось сохранить список папок и отметки!`nПуть: $ConfigPath`nПроверьте журнал amnezia-fm.log.",
            'Ошибка сохранения', [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
    return $true
}

function Clean-StaleSelected {
    $toRemove = New-Object 'System.Collections.Generic.List[string]'
    $currentKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($folder in $script:folders) {
        foreach ($fi in @(Get-CachedExeFiles -folder $folder)) { [void]$currentKeys.Add((Get-PathKey $fi.FullName)) }
    }
    foreach ($p in @($script:selected.PSObject.Properties)) {
        if (Test-IsExcluded $p.Name) { continue } # Keep selection for a reversible exclusion.
        if (-not (Test-PathInAnyConfiguredFolder $p.Name $script:folders)) { [void]$toRemove.Add($p.Name); continue }
        $owner = @($script:folders | Where-Object { Test-PathWithinFolder $p.Name $_ } | Select-Object -First 1)
        if ($owner.Count -eq 0) { continue }
        # Do not delete data when the root or any subtree scan was incomplete.
        if ($script:scanState[(Get-PathKey $owner[0])] -ne 'OK') { continue }
        if (-not $currentKeys.Contains((Get-PathKey $p.Name))) { [void]$toRemove.Add($p.Name) }
    }
    foreach ($key in $toRemove) { $script:selected.PSObject.Properties.Remove($key) }
    return $toRemove.Count
}


function Get-FilterText {
    if ($script:filterIsPlaceholder) { return "" }
    return [string]$txtMainFilter.Text
}

function Rebuild-Tree {
    param([string]$filterText = $null)



    if ($null -eq $filterText) {
        $filterText = Get-FilterText
    }

    # Preserve the expansion state across all nesting levels, not just root nodes.
    $expanded = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $expandQueue = New-Object 'System.Collections.Generic.Queue[System.Windows.Forms.TreeNode]'
    foreach ($rootNode in $tree.Nodes) { $expandQueue.Enqueue($rootNode) }
    while ($expandQueue.Count -gt 0) {
        $oldNode = $expandQueue.Dequeue()
        if ($oldNode.IsExpanded -and $oldNode.Tag -and $oldNode.Tag.Path) {
            [void]$expanded.Add((Get-PathKey $oldNode.Tag.Path))
        }
        foreach ($childNode in $oldNode.Nodes) { $expandQueue.Enqueue($childNode) }
    }

    $wasUpdating = $script:treeUpdating
    $script:treeUpdating = $true
    $tree.BeginUpdate()
    try {
        $tree.Nodes.Clear()

        $totalFolders = $script:folders.Count
        $idx = 0
        $filter = if ([string]::IsNullOrWhiteSpace($filterText)) { $null } else { $filterText.Trim().ToLowerInvariant() }

        # Сначала сканируем все папки (с прогрессом), потом быстро строим дерево
        $scanResults = @{}
        foreach ($folder in $script:folders) {
            $idx++
            Set-UiBusy $true ("Сканирование $idx/$totalFolders : $folder ...")
            $progressAction = {
                param($scanned, $found)
                try {
                    $lblInfo.Text = "Сканирование $idx/$totalFolders : $folder  (папок: $scanned, exe: $found)"
                    $lblInfo.Update()
                } catch { }
            }
            $scanResults[$folder] = @(Get-CachedExeFiles -folder $folder -onProgress $progressAction)
        }

        Set-UiBusy $true "Построение дерева..."
        foreach ($folder in $script:folders) {
            $exeList = @($scanResults[$folder])
            $missing = Folder-Missing $folder

            $exeCount = 0
            $checkedCount = 0
            $visibleCount = 0
            $folderNode = New-Object System.Windows.Forms.TreeNode($folder)
            $folderNode.Tag = @{ Type = "Folder"; Path = $folder }

            $dirNodes = @{}
            $dirNodes[(Get-PathKey $folder)] = $folderNode
            $filtered = @($exeList | Where-Object {
                if (-not $filter) { return $true }
                $relPath = $_.FullName.Substring($folder.Length).TrimStart('\')
                return ($relPath.ToLowerInvariant().Contains($filter))
            })
            foreach ($fi in $filtered) {
                $exe = $fi.FullName
                $key = Get-PathKey $exe
                $directory = Split-Path -Parent $exe
                $segments = @()
                $walk = $directory
                while ($walk -and -not [string]::Equals($walk,$folder,[System.StringComparison]::OrdinalIgnoreCase)) {
                    $segments = @($walk) + $segments
                    $parentWalk = Split-Path -Parent $walk
                    if ($walk -eq $parentWalk) { break }
                    $walk = $parentWalk
                }
                $parentNode = $folderNode
                foreach ($dirPath in $segments) {
                    $dk = Get-PathKey $dirPath
                    if (-not $dirNodes.ContainsKey($dk)) {
                        $dirNode = New-Object System.Windows.Forms.TreeNode((Split-Path $dirPath -Leaf))
                        $dirNode.Tag = @{ Type='Subfolder'; Path=$dirPath }
                        [void]$parentNode.Nodes.Add($dirNode)
                        $dirNodes[$dk] = $dirNode
                    }
                    $parentNode = $dirNodes[$dk]
                }
                $line = "$($fi.Name)   [$(Format-Size $fi.Length)]"
                $exeNode = New-Object System.Windows.Forms.TreeNode($line)
                $exeNode.Tag = @{ Type='Exe'; Path=$exe; Key=$key }
                $prop = $script:selected.PSObject.Properties[$key]
                $isChecked = if ($prop) { [bool]$prop.Value } else { $true }
                $exeNode.Checked = $isChecked
                [void]$parentNode.Nodes.Add($exeNode)
                $exeCount++; $visibleCount++
                if ($isChecked) { $checkedCount++ }
            }
            foreach ($excluded in @($script:excludedFolders)) {
                if (-not (Test-PathWithinFolder $excluded $folder)) { continue }
                $parentPath = Split-Path -Parent $excluded
                $parentNode = $folderNode
                $walkPaths = @()
                $walk = $parentPath
                while ($walk -and -not [string]::Equals($walk,$folder,[System.StringComparison]::OrdinalIgnoreCase)) {
                    $walkPaths = @($walk) + $walkPaths
                    $pw = Split-Path -Parent $walk
                    if ($pw -eq $walk) { break }
                    $walk = $pw
                }
                foreach ($dirPath in $walkPaths) {
                    $dk = Get-PathKey $dirPath
                    if (-not $dirNodes.ContainsKey($dk)) {
                        $dn = New-Object System.Windows.Forms.TreeNode((Split-Path $dirPath -Leaf))
                        $dn.Tag = @{ Type='Subfolder'; Path=$dirPath }
                        [void]$parentNode.Nodes.Add($dn)
                        $dirNodes[$dk] = $dn
                    }
                    $parentNode = $dirNodes[$dk]
                }
                if (-not $filter -or $excluded.ToLowerInvariant().Contains($filter)) {
                    $excludedNode = New-Object System.Windows.Forms.TreeNode("[ПРОПУСК] " + (Split-Path $excluded -Leaf))
                    $excludedNode.Tag = @{ Type='Excluded'; Path=$excluded }
                    $excludedNode.Checked = $false
                    Set-NodeColor $excludedNode $C.TextMuted
                    [void]$parentNode.Nodes.Add($excludedNode)
                    $visibleCount++
                }
            }


            # Bottom-up counts: each EXE is visited once, instead of scanning all
            # selected paths for every directory (O(nodes + exe) vs O(nodes * exe)).
            $treeCounts = @{}
            $countStack = New-Object 'System.Collections.Generic.Stack[object]'
            $countStack.Push(@($folderNode, $false))
            while ($countStack.Count -gt 0) {
                $frame = $countStack.Pop()
                $item = $frame[0]
                if (-not $frame[1]) {
                    $countStack.Push(@($item, $true))
                    foreach ($child in $item.Nodes) { $countStack.Push(@($child, $false)) }
                    continue
                }
                $total = 0; $on = 0
                if ($item.Tag -and $item.Tag.Type -eq 'Exe') {
                    $total = 1
                    if ($item.Checked) { $on = 1 }
                } else {
                    foreach ($child in $item.Nodes) {
                        $ck = $child
                        if ($treeCounts.ContainsKey($ck)) {
                            $total += $treeCounts[$ck].Total
                            $on += $treeCounts[$ck].On
                        }
                    }
                    if ($item.Tag -and $item.Tag.Type -ne 'Excluded') {
                        $item.Checked = ($total -gt 0 -and $total -eq $on)
                        if ($item -ne $folderNode -and $total -gt 0 -and $on -gt 0 -and $on -lt $total) {
                            $item.Text = '[ЧАСТЬ] ' + $item.Text
                        }
                    }
                }
                $treeCounts[$item] = @{ Total=$total; On=$on }
            }
            # Счётчик EXE в названии узла
            $title = "$folder  ($exeCount)"
            if ($missing) { $title = "(!) $title" }
            $folderNode.Text = $title

            if ($visibleCount -eq 0 -and $filter) { continue }
            $folderNode.Checked = ($exeCount -gt 0 -and $checkedCount -eq $exeCount)
            if ($missing -or $exeCount -eq 0) { Set-NodeColor $folderNode $C.TextMuted }
            if ($script:scanState[(Get-PathKey $folder)] -eq "PARTIAL") { $folderNode.Text = "[ЧАСТИЧНО] " + $folderNode.Text }

            [void]$tree.Nodes.Add($folderNode)

            # Восстановить раскрытие
            $restoreStack = New-Object 'System.Collections.Generic.Stack[System.Windows.Forms.TreeNode]'
            $restoreStack.Push($folderNode)
            while ($restoreStack.Count -gt 0) {
                $restoreNode = $restoreStack.Pop()
                if ($restoreNode.Tag -and $restoreNode.Tag.Path -and
                    $expanded.Contains((Get-PathKey $restoreNode.Tag.Path))) {
                    $restoreNode.Expand()
                }
                foreach ($childNode in $restoreNode.Nodes) { $restoreStack.Push($childNode) }
            }
        }



        Update-InfoLabel
        if ($script:lastBackup -and $script:lastBackup -ne "") {
            $lblLast.Text = "Последний использованный backup: $($script:lastBackup)"
        } else {
            $lblLast.Text = "Последний использованный backup: (не указан)"
        }
    } finally {
        $tree.EndUpdate()
        $script:treeUpdating = $wasUpdating
        Set-UiBusy $false $null
    }
}

function Compute-BackupStats($backupPath) {
    $j = (Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8) | ConvertFrom-Json
    if ($null -eq $j -or $j -isnot [psobject] -or $j -is [array]) {
        throw "Файл не содержит ожидаемый JSON-объект AmneziaVPN."
    }
    $prop = $j.PSObject.Properties["Conf/ExceptApps"]
    if (-not $prop -or $null -eq $prop.Value) {
        throw "В исходном backup отсутствует поле Conf/ExceptApps. Выберите актуальный экспорт AmneziaVPN с поддерживаемой структурой."
    }
    if ($prop.Value -isnot [array]) {
        throw "Поле Conf/ExceptApps должно быть массивом."
    }
    $apps = @($prop.Value)

    $existing = @{}
    foreach ($a in $apps) {
        if ($a -and $a.appPath) { $existing[(Get-PathKey $a.appPath.ToString())] = $true }
    }

    $newCount = 0; $alreadyCount = 0; $skipCount = 0; $missingCount = 0
    foreach ($p in $script:selected.PSObject.Properties) {
        if (-not $p.Value) { $skipCount++; continue }
        if (-not (Test-Path -LiteralPath $p.Name)) { $missingCount++; continue }
        if ($existing.ContainsKey((Get-PathKey $p.Name))) { $alreadyCount++ } else { $newCount++ }
    }
    return @{
        InBackup = $apps.Count
        New      = $newCount
        Already  = $alreadyCount
        Skipped  = $skipCount
        Missing  = $missingCount
        Existing = $existing
        Apps     = $apps
        Json     = $j
    }
}

function Sync-FolderDatabase([string]$folder) {
    $current = @{}
    foreach ($exe in @(Get-CachedExeFiles -folder $folder)) {
        $current[(Get-PathKey $exe.FullName)] = $exe
    }

    $removed = 0
    $added = 0

    $canPrune = ($script:scanState[(Get-PathKey $folder)] -eq "OK")
    $keys = @($script:selected.PSObject.Properties.Name)
    foreach ($key in $keys) {
        if (-not (Test-PathWithinFolder $key $folder)) { continue }
        if ($canPrune -and -not $current.ContainsKey((Get-PathKey $key))) {
            $script:selected.PSObject.Properties.Remove($key)
            $removed++
        }
    }

    # A partial scan is not authoritative: never mutate selected paths for that root.
    if (-not $canPrune) {
        Write-Log "Sync: partial scan for $folder, keeping the prior selection unchanged"
        return @{ Added = 0; Removed = 0; Current = $current.Count }
    }

    foreach ($key in $current.Keys) {
        if (-not $script:selected.PSObject.Properties[$key]) {
            $script:selected | Add-Member -MemberType NoteProperty -Name $key -Value $true -Force
            $added++
        }
    }

    return @{ Added = $added; Removed = $removed; Current = $current.Count }
}

function Add-OneFolder($folder) {
    $folder = Normalize-FullPath $folder

    foreach ($existingFolder in @($script:folders)) {
        if (Test-PathWithinFolder $folder $existingFolder) {
            [void][System.Windows.Forms.MessageBox]::Show(
                "Эта папка уже покрывается другой добавленной папкой:`n`n$existingFolder",
                "Папка уже покрыта")
            return
        }
        if (Test-PathWithinFolder $existingFolder $folder) {
            [void][System.Windows.Forms.MessageBox]::Show(
                "Нельзя добавить вложенную папку:`n`n$folder`n`nОна уже находится внутри:`n$existingFolder",
                "Вложенная папка")
            return
        }
    }

    if ($script:folders -contains $folder) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Эта папка уже добавлена.", "Папка уже есть",
            [System.Windows.Forms.MessageBoxButtons]::OK)
        return
    }

    Set-UiBusy $true "Сканирование: $folder ..."
    try {
        $exeList = @(Get-CachedExeFiles -folder $folder)
    } finally {
        Set-UiBusy $false $null
    }
    if ($exeList.Count -eq 0) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "В этой папке не найдено ни одного .exe.`n`nВсё равно добавить её?",
            "Пустая папка", [System.Windows.Forms.MessageBoxButtons]::YesNo)
        if ($r -ne "Yes") {
            Log "Папка не добавлена (пустая): $folder"
            return
        }
    }
    $script:folders += $folder
    foreach ($fi in $exeList) {
        $key = $fi.FullName.ToLowerInvariant()
        if (-not $script:selected.PSObject.Properties[$key]) {
            $script:selected | Add-Member -MemberType NoteProperty -Name $key -Value $true -Force
        }
    }
    Invalidate-ExeCache
    Save-State
    Rebuild-Tree
    Log "Добавлена папка: $folder (EXE: $($exeList.Count))"
}

function Do-UpdateOnly {
    Set-UiBusy $true "Обновление базы..."
    try {
        Invalidate-ExeCache
        $newCount = 0
        foreach ($folder in $script:folders) {
            if (-not (Test-Path -LiteralPath $folder)) { continue }
            $exeList = @(Get-CachedExeFiles -folder $folder)
            if ($script:scanState[(Get-PathKey $folder)] -ne 'OK') {
                Write-Log "Update: incomplete scan for $folder; no new paths imported from this folder"
                continue
            }
            foreach ($fi in $exeList) {
                $key = $fi.FullName.ToLowerInvariant()
                if (-not $script:selected.PSObject.Properties[$key]) {
                    $script:selected | Add-Member -MemberType NoteProperty -Name $key -Value $true -Force
                    $newCount++
                }
            }
        }
        $removedCount = Clean-StaleSelected
        Save-State
    } finally {
        Set-UiBusy $false $null
    }
    Rebuild-Tree
    Log "Обновление: новых EXE — $newCount; удалено отсутствующих — $removedCount"
    return @{ New = $newCount; Removed = $removedCount }
}


function Get-BackupPlan($stats) {
    # Preserve every source entry unless there is a known manager-owned path
    # that the user has disabled, excluded, or confirmed stale after a FULL scan.
    $managed = @{}
    foreach ($path in @($script:managedApps)) { if ($path) { $managed[(Get-PathKey ([string]$path))] = $true } }
    $removed = New-Object 'System.Collections.Generic.List[string]'
    $removeReasons = @{}
    $kept = New-Object 'System.Collections.Generic.List[object]'
    $inBackup = @{}
    foreach ($app in @($stats.Apps)) {
        if ($null -eq $app -or -not $app.appPath) { [void]$kept.Add($app); continue }
        $path = [string]$app.appPath
        $key = Get-PathKey $path
        $delete = $false
        $reason = ''
        if ($managed.ContainsKey($key)) {
            if (Test-IsExcluded $path) {
                $delete = $true
                $reason = 'Папка исключена'
            } else {
                $sel = $script:selected.PSObject.Properties[$key]
                if ($sel -and -not [bool]$sel.Value) {
                    $delete = $true
                    $reason = 'Снята галочка'
                } elseif (-not $sel) {
                    $root = @($script:folders | Where-Object { Test-PathWithinFolder $path $_ } | Select-Object -First 1)
                    if ($root.Count -eq 0) {
                        # Removed tracked folder: no longer governed, explicitly deselected from tracking.
                        $delete = $true
                        $reason = 'Папка удалена из отслеживания'
                    } elseif ($script:scanState[(Get-PathKey $root[0])] -eq 'OK') {
                        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $delete = $true; $reason = 'Файл отсутствует' }
                    }
                }
            }
        }
        if ($delete) {
            [void]$removed.Add($path)
            $removeReasons[$key] = $reason
        } else {
            [void]$kept.Add($app)
            $inBackup[$key] = $true
        }
    }
    $adds = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $script:selected.PSObject.Properties) {
        if (-not [bool]$p.Value -or (Test-IsExcluded $p.Name)) { continue }
        # Keep previously-present source entries, but do not introduce new entries from incomplete scans.
        $owners = @($script:folders | Where-Object { Test-PathWithinFolder $p.Name $_ })
        if ($owners.Count -eq 0) { continue }
        if ($script:scanState[(Get-PathKey $owners[0])] -ne 'OK') { continue }
        if (-not (Test-Path -LiteralPath $p.Name -PathType Leaf)) { continue }
        $key = Get-PathKey $p.Name
        if (-not $inBackup.ContainsKey($key)) { [void]$adds.Add($p.Name); $inBackup[$key] = $true }
    }
    return @{ Add=@($adds.ToArray()); Remove=@($removed.ToArray()); RemoveReasons=$removeReasons; Keep=@($kept.ToArray()) }
}


function Show-BackupPreview($backup, $plan, [int]$warningCount) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Подтверждение обновления AmneziaVPN'
    $dlg.StartPosition = 'CenterParent'
    $dlg.Size = [System.Drawing.Size]::new((Scaled 930),(Scaled 640))
    $dlg.MinimumSize = [System.Drawing.Size]::new((Scaled 650),(Scaled 420))
    $dlg.BackColor = $C.Bg
    $dlg.ForeColor = $C.Text
    $dlg.Font = New-UiFont 9
    $dlg.FormBorderStyle = 'Sizable'
    $dlg.MaximizeBox = $true

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.Padding = New-Object System.Windows.Forms.Padding((Scaled 14))
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.RowStyles.Add(([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute,(Scaled 82))))
    [void]$layout.RowStyles.Add(([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent,100)))
    [void]$layout.RowStyles.Add(([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute,(Scaled 55))))
    $dlg.Controls.Add($layout)

    $summary = New-Object System.Windows.Forms.Label
    $summary.Dock = 'Fill'
    $summary.ForeColor = $C.Text
    $summary.AutoEllipsis = $true
    $summary.Font = New-UiFont 9
    $summary.Text = "Добавить: $($plan.Add.Count)     Удалить: $($plan.Remove.Count)     Сохранить из AmneziaVPN: $($plan.Keep.Count)`nПапок с ошибками: $warningCount (их записи защищены)`nИсходный файл: $backup`nРучные и неуправляемые записи сохраняются."
    $layout.Controls.Add($summary,0,0)

    $list = New-Object System.Windows.Forms.ListView
    $list.Dock = 'Fill'
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.GridLines = $false
    $list.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $list.Font = New-UiFont 9
    $list.HideSelection = $false
    $list.BackColor = $C.Panel
    $list.ForeColor = $C.Text
    [void]$list.Columns.Add('Действие',(Scaled 125))
    [void]$list.Columns.Add('EXE',(Scaled 255))
    [void]$list.Columns.Add('Причина',(Scaled 180))
    [void]$list.Columns.Add('Папка',(Scaled 500))
    $list.ShowItemToolTips = $true
    $list.BeginUpdate()
    try {
        foreach ($path in @($plan.Add)) {
            $entry = New-Object System.Windows.Forms.ListViewItem('Добавить')
            [void]$entry.SubItems.Add([System.IO.Path]::GetFileName($path))
            [void]$entry.SubItems.Add('Выбран в Folder Manager')
            [void]$entry.SubItems.Add([System.IO.Path]::GetDirectoryName($path))
            $entry.ToolTipText = $path
            $entry.ForeColor = $C.TextGreen
            [void]$list.Items.Add($entry)
        }
        foreach ($path in @($plan.Remove)) {
            $entry = New-Object System.Windows.Forms.ListViewItem('Удалить')
            [void]$entry.SubItems.Add([System.IO.Path]::GetFileName($path))
            $reason = $plan.RemoveReasons[(Get-PathKey $path)]
            if (-not $reason) { $reason = 'Больше не управляется' }
            [void]$entry.SubItems.Add($reason)
            [void]$entry.SubItems.Add([System.IO.Path]::GetDirectoryName($path))
            $entry.ToolTipText = $path
            $entry.ForeColor = $C.Danger
            [void]$list.Items.Add($entry)
        }
    } finally { $list.EndUpdate() }
    $layout.Controls.Add($list,0,1)

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Fill'
    $buttons.FlowDirection = 'RightToLeft'
    $buttons.WrapContents = $false
    $yes = New-Object System.Windows.Forms.Button
    $yes.Text = 'Создать backup'
    $yes.Width = Scaled 150
    $yes.Height = Scaled 34
    Style-PrimaryButton $yes
    $yes.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $no = New-Object System.Windows.Forms.Button
    $no.Text = 'Отмена'
    $no.Width = Scaled 110
    $no.Height = Scaled 34
    Style-SecondaryButton $no
    $no.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    [void]$buttons.Controls.Add($yes)
    [void]$buttons.Controls.Add($no)
    $layout.Controls.Add($buttons,0,2)
    $dlg.AcceptButton = $yes
    $dlg.CancelButton = $no
    try { return ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) }
    finally { $dlg.Dispose() }
}

function Do-CreateBackup {
    # Always ask for a fresh export. LastBackup is informational only.
    # Select before scanning/saving so cancelling does not alter the local database.
    $notice = [System.Windows.Forms.MessageBox]::Show(
        "Перед каждым созданием файла экспортируйте АКТУАЛЬНЫЙ backup из AmneziaVPN. Если после экспорта вы вручную добавили EXE в клиенте, экспортируйте backup заново.`n`nОткрыть выбор свежего исходного backup?",
        "Требуется актуальный backup AmneziaVPN",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information)
    if ($notice -ne [System.Windows.Forms.DialogResult]::OK) {
        Log "Backup отменён: актуальный экспорт не подтверждён"
        return $false
    }

    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = "Выберите СВЕЖИЙ экспорт AmneziaVPN (обязательно при каждом создании)"
    $ofd.Filter = "Amnezia backup (*.backup)|*.backup|Все файлы (*.*)|*.*"
    $ofd.CheckFileExists = $true
    $ofd.Multiselect = $false
    # Do not preselect a previous backup: the user must deliberately pick a file.
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Log "Backup отменён: исходный файл не выбран"
        return $false
    }
    $backup = $ofd.FileName
    try {
        [void](Compute-BackupStats $backup)
    } catch {
        Log "Ошибка проверки исходного backup: $_"
        [void][System.Windows.Forms.MessageBox]::Show(
            "Невозможно прочитать исходный backup AmneziaVPN:`n$_",
            "Ошибка исходного backup", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }


    Set-UiBusy $true "Сканирование перед backup..."
    try {
        Invalidate-ExeCache
        $newCount = 0
        foreach ($folder in $script:folders) {
            if (-not (Test-Path -LiteralPath $folder)) { continue }
            $exeList = @(Get-CachedExeFiles -folder $folder)
            if ($script:scanState[(Get-PathKey $folder)] -ne 'OK') {
                Write-Log "Update: incomplete scan for $folder; no new paths imported from this folder"
                continue
            }
            foreach ($fi in $exeList) {
                $key = $fi.FullName.ToLowerInvariant()
                if (-not $script:selected.PSObject.Properties[$key]) {
                    $script:selected | Add-Member -MemberType NoteProperty -Name $key -Value $true -Force
                    $newCount++
                }
            }
        }
        $removedCount = Clean-StaleSelected
    } finally {
        Set-UiBusy $false $null
    }
    Rebuild-Tree
    Log "Перед backup: новых EXE — $newCount; удалено отсутствующих — $removedCount"


    try {
        $stats = Compute-BackupStats $backup
        $plan = Get-BackupPlan $stats
        $warningCount = @($script:scanState.Values | Where-Object { $_ -ne 'OK' }).Count
        if (-not (Show-BackupPreview $backup $plan $warningCount)) {
            Log "Backup отменён в предварительном просмотре"
            return $false
        }

        Set-UiBusy $true "Создание backup..."
        try {
            $j = $stats.Json
            $apps = @($plan.Keep)
            $existing = @{}
            foreach ($app in $apps) {
                if ($app -and $app.appPath) { $existing[(Get-PathKey ([string]$app.appPath))] = $true }
            }
            $added = 0
            $addedPaths = @()
            foreach ($path in $plan.Add) {
                if ($existing.ContainsKey((Get-PathKey $path))) { continue }
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
                $fi = Get-Item -LiteralPath $path -ErrorAction Stop
                $apps += [PSCustomObject]@{ appName=$fi.BaseName; packageName=''; appPath=$fi.FullName }
                $existing[(Get-PathKey $fi.FullName)] = $true
                $added++
                $addedPaths += $fi.FullName
            }
            $removedFromBackup = $plan.Remove.Count


            if (-not $j.PSObject.Properties["Conf/ExceptApps"]) {
                $j | Add-Member -MemberType NoteProperty -Name "Conf/ExceptApps" -Value @()
            }
            $j."Conf/ExceptApps" = @($apps)

            $out = Join-Path $OutDir "Amnezia-UPDATED.backup"
            if ([string]::Equals((Normalize-FullPath $out),(Normalize-FullPath $backup),[System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Исходный backup совпадает с выходным. Выберите свежий исходный файл с другим именем.'
            }
            $jsonTemp = Join-Path $OutDir ("Amnezia-UPDATED.{0}.tmp" -f [Guid]::NewGuid().ToString('N'))
            $previousBackup = "$out.previous.backup"
            try {
                # Preserve the existing, proven Amnezia backup serialization (UTF-8 BOM).
                $j | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $jsonTemp -Encoding UTF8 -ErrorAction Stop
                $verified = Get-Content -LiteralPath $jsonTemp -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if (-not $verified.PSObject.Properties['Conf/ExceptApps'] -or $verified.'Conf/ExceptApps' -isnot [array]) { throw 'Проверка выходного backup не пройдена.' }
                if (@($verified.'Conf/ExceptApps').Count -ne @($apps).Count) { throw 'Проверка количества приложений в backup не пройдена.' }
                if (Test-Path -LiteralPath $out) {
                    # File.Replace updates the destination atomically and saves the old file.
                    # If it fails, retain the previous output instead of risking truncation.
                    [System.IO.File]::Replace($jsonTemp, $out, $previousBackup)
                } else {
                    Move-Item -LiteralPath $jsonTemp -Destination $out -ErrorAction Stop
                }
                # Keep only one exported backup after a successful atomic replacement.
                if (Test-Path -LiteralPath $previousBackup) {
                    Remove-Item -LiteralPath $previousBackup -Force -ErrorAction SilentlyContinue
                }
            } finally {
                if (Test-Path -LiteralPath $jsonTemp) { Remove-Item -LiteralPath $jsonTemp -Force -ErrorAction SilentlyContinue }
            }


            $removedKeys = @{}
            foreach ($path in $plan.Remove) { $removedKeys[(Get-PathKey $path)] = $true }
            $script:managedApps = @($script:managedApps + $addedPaths | Where-Object { -not $removedKeys.ContainsKey((Get-PathKey $_)) } | Sort-Object -Unique)
            $script:lastBackup = $backup
            $script:backupStateSaved = [bool](Save-State)
        } finally {
            Set-UiBusy $false $null
        }

        Rebuild-Tree

        Log "Backup создан: $out (добавлено $added, удалено $removedFromBackup)"
        Log "Добавлено новых: $added"
        foreach ($reasonGroup in @($plan.Remove | Group-Object -Property { $plan.RemoveReasons[(Get-PathKey $_)] })) {
            Log "Удаления ($($reasonGroup.Name)): $($reasonGroup.Count)"
        }

        $saveNote = if ($script:backupStateSaved) { 'Конфигурация сохранена.' } else { 'ВНИМАНИЕ: backup создан, но настройки не сохранились. Проверьте журнал.' }
        $msg = @"
Готово!

Отмечено приложений: $(@($script:selected.PSObject.Properties | Where-Object { [bool]$_.Value -and -not (Test-IsExcluded $_.Name) }).Count)
Добавлено новых: $added
Удалено управляемых исключений: $removedFromBackup
Уже было в базе: $($stats.Already)
Не отмечено: $($stats.Skipped)
Отсутствуют на диске: $($stats.Missing)

Backup:
$out

$saveNote
"@
        $r2 = [System.Windows.Forms.MessageBox]::Show(
            $msg + "`n`nОткрыть папку с файлами?",
            "Готово", [System.Windows.Forms.MessageBoxButtons]::YesNo)
        if ($r2 -eq "Yes") { Start-Process explorer.exe "/select,`"$out`"" }
        return $true
    } catch {
        Log "ОШИБКА: $_"
        [void][System.Windows.Forms.MessageBox]::Show(($_ | Out-String), "Ошибка")
        return $false
    }
}

function Rebuild-Database {
    $removed = 0
    $restored = 0

    $script:folders = @(Normalize-FolderList $script:folders)
    Invalidate-ExeCache

    $toRemove = @()
    foreach ($p in $script:selected.PSObject.Properties) {
        if (-not (Test-PathInAnyConfiguredFolder $p.Name $script:folders)) {
            $toRemove += $p.Name
        }
    }

    foreach ($k in $toRemove) {
        if ($script:selected.PSObject.Properties[$k]) {
            $script:selected.PSObject.Properties.Remove($k)
            $removed++
        }
    }

    foreach ($folder in $script:folders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        $exeList = @(Get-CachedExeFiles -folder $folder)
        if ($script:scanState[(Get-PathKey $folder)] -ne 'OK') {
            Write-Log "Rebuild-Database: incomplete scan for $folder; preserving existing selection"
            continue
        }
        foreach ($fi in $exeList) {
            $key = (Get-PathKey $fi.FullName)
            if (-not $script:selected.PSObject.Properties[$key]) {
                $script:selected | Add-Member -MemberType NoteProperty -Name $key -Value $true -Force
                $restored++
            }
        }
    }

    $stale = Clean-StaleSelected
    $removed += $stale

    Save-State
    Rebuild-Tree
    return @{ Removed = $removed; Restored = $restored }
}


function Set-FolderCheckedState([string]$folderPath, [bool]$checked) {
    foreach ($p in $script:selected.PSObject.Properties) {
        if (Test-PathWithinFolder $p.Name $folderPath) { $p.Value = $checked }
    }
}
function Set-TreeChildrenChecked($node, [bool]$checked) {
    foreach ($child in $node.Nodes) {
        if ($child.Tag -and $child.Tag.Type -eq 'Excluded') { continue }
        $child.Checked = $checked
        Set-TreeChildrenChecked $child $checked
    }
}
function Update-ParentChecks($node) {
    while ($node) {
        $total = 0; $checked = 0
        foreach ($p in $script:selected.PSObject.Properties) {
            if (Test-PathWithinFolder $p.Name $node.Tag.Path) {
                $total++; if ($p.Value) { $checked++ }
            }
        }
        $node.Checked = ($total -gt 0 -and $total -eq $checked)
        $node = $node.Parent
    }
}

# ---- Дерево: чекбоксы ----
$tree.Add_AfterCheck({
    param($sender, $e)
    if ($script:treeUpdating) { return }
    $node = $e.Node
    if (-not $node.Tag) { return }
    if ($node.Tag.Type -eq 'Excluded') {
        $script:treeUpdating = $true
        try { $node.Checked = $false } finally { $script:treeUpdating = $false }
        return
    }
    $script:treeUpdating = $true
    try {
        if ($node.Tag.Type -eq 'Exe') {
            $prop = $script:selected.PSObject.Properties[$node.Tag.Key]
            if ($prop) { $prop.Value = $node.Checked }
        } else {
            Set-FolderCheckedState $node.Tag.Path $node.Checked
            Set-TreeChildrenChecked $node $node.Checked
        }
        Update-ParentChecks $node.Parent
    } finally { $script:treeUpdating = $false }
    Schedule-Save
    Update-InfoLabel
})


# ---- Фильтр: debounce prevents complete tree rebuild on every keystroke ----
$script:filterTimer = New-Object System.Windows.Forms.Timer
$script:filterTimer.Interval = 260
$script:filterTimer.Add_Tick({
    $script:filterTimer.Stop()
    if (-not $script:treeUpdating) {
        Rebuild-Tree -filterText (Get-FilterText)
    }
})
$txtMainFilter.Add_TextChanged({
    if ($script:filterIsPlaceholder) { return }
    $script:filterTimer.Stop()
    $script:filterTimer.Start()
})



# ---- ПКМ ----
$menuTree = New-Object System.Windows.Forms.ContextMenuStrip
$menuTree.BackColor = $C.PanelRaised
$menuTree.ForeColor = $C.Text
$menuTree.ShowImageMargin = $false
$menuTree.RenderMode = [System.Windows.Forms.ToolStripRenderMode]::Professional

$miOpenFolder = New-Object System.Windows.Forms.ToolStripMenuItem("Открыть папку")
$miOpenFolder.BackColor = $C.PanelRaised
$miOpenFolder.ForeColor = $C.Text
$menuTree.Items.Add($miOpenFolder) | Out-Null

$miOpenFile = New-Object System.Windows.Forms.ToolStripMenuItem("Открыть папку с файлом")
$miOpenFile.BackColor = $C.PanelRaised
$miOpenFile.ForeColor = $C.Text
$menuTree.Items.Add($miOpenFile) | Out-Null

$miRescan = New-Object System.Windows.Forms.ToolStripMenuItem("Пересканировать")
$miRescan.BackColor = $C.PanelRaised
$miRescan.ForeColor = $C.Text
$menuTree.Items.Add($miRescan) | Out-Null

$miRemoveFolder = New-Object System.Windows.Forms.ToolStripMenuItem("Удалить папку")
$miRemoveFolder.BackColor = $C.PanelRaised
$miRemoveFolder.ForeColor = $C.Danger
$menuTree.Items.Add($miRemoveFolder) | Out-Null

$miExcludeFolder = New-Object System.Windows.Forms.ToolStripMenuItem("Пропускать эту папку и всё внутри")
$menuTree.Items.Add($miExcludeFolder) | Out-Null
$miIncludeFolder = New-Object System.Windows.Forms.ToolStripMenuItem("Вернуть папку в сканирование")
$menuTree.Items.Add($miIncludeFolder) | Out-Null

$menuTree.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$miUpdateAll = New-Object System.Windows.Forms.ToolStripMenuItem("Обновить всю базу")
$miUpdateAll.BackColor = $C.PanelRaised
$miUpdateAll.ForeColor = $C.Text
$menuTree.Items.Add($miUpdateAll) | Out-Null

$menuTree.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$miCheckAll = New-Object System.Windows.Forms.ToolStripMenuItem("Отметить всё")
$miCheckAll.BackColor = $C.PanelRaised
$miCheckAll.ForeColor = $C.Text
$menuTree.Items.Add($miCheckAll) | Out-Null

$miUncheckAll = New-Object System.Windows.Forms.ToolStripMenuItem("Снять все отметки")
$miUncheckAll.BackColor = $C.PanelRaised
$miUncheckAll.ForeColor = $C.Text
$menuTree.Items.Add($miUncheckAll) | Out-Null

$menuTree.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$miExpandAll = New-Object System.Windows.Forms.ToolStripMenuItem("Развернуть всё")
$miExpandAll.BackColor = $C.PanelRaised
$miExpandAll.ForeColor = $C.Text
$menuTree.Items.Add($miExpandAll) | Out-Null

$miCollapseAll = New-Object System.Windows.Forms.ToolStripMenuItem("Свернуть всё")
$miCollapseAll.BackColor = $C.PanelRaised
$miCollapseAll.ForeColor = $C.Text
$menuTree.Items.Add($miCollapseAll) | Out-Null

$tree.ContextMenuStrip = $menuTree

# Активируем только релевантные пункты в зависимости от выбранного узла
$menuTree.Add_Opening({
    $node = $tree.SelectedNode
    $isFolder = ($node -and $node.Tag -and $node.Tag.Type -in @("Folder","Subfolder","Excluded"))
    $isExe    = ($node -and $node.Tag -and $node.Tag.Type -eq "Exe")
    $hasNode  = ($isFolder -or $isExe)
    $hasTree  = ($tree.Nodes.Count -gt 0)

    $miExcludeFolder.Enabled = ($node -and $node.Tag -and $node.Tag.Type -eq "Subfolder")
    $miIncludeFolder.Enabled = ($node -and $node.Tag -and $node.Tag.Type -eq "Excluded")
    $miOpenFolder.Enabled  = $isFolder
    $miOpenFile.Enabled    = $isExe
    $miRescan.Enabled      = $hasNode
    $miRemoveFolder.Enabled = ($node -and $node.Tag -and $node.Tag.Type -eq "Folder")
    $miUpdateAll.Enabled   = $true
    $miCheckAll.Enabled    = $hasTree
    $miUncheckAll.Enabled  = $hasTree
    $miExpandAll.Enabled   = $hasTree
    $miCollapseAll.Enabled = $hasTree
})

$tree.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $hit = $sender.HitTest($e.Location)
        if ($hit -and $hit.Node) {
            $sender.SelectedNode = $hit.Node
            $hit.Node.EnsureVisible()
        }
    }
})

$miOpenFolder.Add_Click({
    $node = $tree.SelectedNode
    if (-not $node) { return }
    if ($node.Tag -and $node.Tag.Type -in @("Folder", "Subfolder", "Excluded")) {
        Start-Process explorer.exe "`"$($node.Tag.Path)`""
    }
})

$miOpenFile.Add_Click({
    $node = $tree.SelectedNode
    if (-not $node) { return }
    if ($node.Tag -and $node.Tag.Type -eq "Exe") {
        Start-Process explorer.exe "/select,`"$($node.Tag.Path)`""
    }
})

$miRescan.Add_Click({
    $node = $tree.SelectedNode
    if (-not $node) { return }
    $folder = $null
    if ($node.Tag -and $node.Tag.Type -eq "Folder") {
        $folder = $node.Tag.Path
    } elseif ($node.Tag -and $node.Tag.Type -in @("Exe", "Subfolder", "Excluded")) {
        $parentNode = $node
        while ($parentNode -and $parentNode.Tag.Type -ne 'Folder') { $parentNode = $parentNode.Parent }
        if ($parentNode) { $folder = $parentNode.Tag.Path }
    }
    if (-not $folder) { return }
    Set-UiBusy $true "Пересканирование: $folder ..."
    try {
        $fk = Get-PathKey $folder
        if ($script:exeCache.ContainsKey($fk)) { $script:exeCache.Remove($fk) }
        $stats = Sync-FolderDatabase $folder
        Save-State
    } finally {
        Set-UiBusy $false $null
    }
    Rebuild-Tree
    Log "Пересканирована папка: $folder | текущих EXE: $($stats.Current), добавлено: $($stats.Added), удалено отсутствующих: $($stats.Removed)"
})

$miRemoveFolder.Add_Click({ Remove-SelectedFolder })
$miExcludeFolder.Add_Click({
    $node = $tree.SelectedNode
    if (-not $node -or $node.Tag.Type -ne 'Subfolder') { return }
    $dir = [string]$node.Tag.Path
    $r = [System.Windows.Forms.MessageBox]::Show("Прекратить сканировать папку и всё внутри?`n$dir`n`nЕё EXE, добавленные Folder Manager, будут исключены из следующего backup.","Исключить папку",[System.Windows.Forms.MessageBoxButtons]::YesNo)
    if ($r -ne 'Yes') { return }
    $script:excludedFolders = @($script:excludedFolders | Where-Object { -not (Test-PathWithinFolder $_ $dir) }) + @($dir)
    Invalidate-ExeCache
    [void](Clean-StaleSelected)
    Save-State
    Rebuild-Tree
})
$miIncludeFolder.Add_Click({
    $node = $tree.SelectedNode
    if (-not $node -or $node.Tag.Type -ne 'Excluded') { return }
    $dir = [string]$node.Tag.Path
    $script:excludedFolders = @($script:excludedFolders | Where-Object { (Get-PathKey $_) -ne (Get-PathKey $dir) })
    Invalidate-ExeCache
    [void](Do-UpdateOnly)
})

$miUpdateAll.Add_Click({
    Log "=== Обновить всю базу ==="
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Пересканировать все папки?`n`nНовые .exe будут добавлены, отсутствующие — удалены.`nBackup НЕ создаётся.",
        "Обновить базу", [System.Windows.Forms.MessageBoxButtons]::YesNo)
    if ($r -ne "Yes") { Log "Обновление отменено"; return }
    $res = Do-UpdateOnly
    Log "Новых EXE: $($res.New); удалено отсутствующих: $($res.Removed)"

    $c = Count-Selection
    $msg = @"
Готово!

Всего в базе: $($c.Total)
Отмечено: $($c.Checked)
Добавлено новых: $($res.New)
Удалено отсутствующих: $($res.Removed)

Конфигурация сохранена.
"@
    [void][System.Windows.Forms.MessageBox]::Show($msg, "Обновление завершено")
})

$miCheckAll.Add_Click({
    foreach ($p in $script:selected.PSObject.Properties) { $p.Value = $true }
    Rebuild-Tree
    Schedule-Save
})
$miUncheckAll.Add_Click({
    foreach ($p in $script:selected.PSObject.Properties) { $p.Value = $false }
    Rebuild-Tree
    Schedule-Save
})


$miExpandAll.Add_Click({ $tree.ExpandAll() })
$miCollapseAll.Add_Click({ $tree.CollapseAll() })

# ---- Кнопки ----
$btnAdd.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Выберите папку игры или программы"
    if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    Add-OneFolder $d.SelectedPath
})

$btnRefresh.Add_Click({
    Log "=== Обновление списка (кнопка) ==="
    $res = Do-UpdateOnly
    Log "Новых EXE: $($res.New); удалено отсутствующих: $($res.Removed)"
})

function Remove-SelectedFolder {
    $node = $tree.SelectedNode
    if (-not $node) {
        [void][System.Windows.Forms.MessageBox]::Show("Выберите папку в дереве.")
        return
    }
    $folder = $null
    if ($node.Tag -and $node.Tag.Type -eq "Folder") { $folder = $node.Tag.Path }
    elseif ($node.Parent -and $node.Parent.Tag -and $node.Parent.Tag.Type -eq "Folder") { $folder = $node.Parent.Tag.Path }
    if (-not $folder) { return }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Удалить папку из списка?`n$folder`n`n(все её .exe тоже удалятся из базы)",
        "Подтверждение", [System.Windows.Forms.MessageBoxButtons]::YesNo)
    if ($r -ne "Yes") { return }

    $script:folders = @(Normalize-FolderList @($script:folders | Where-Object {
        -not [string]::Equals((Normalize-FullPath $_), (Normalize-FullPath $folder), [System.StringComparison]::OrdinalIgnoreCase)
    }))

    [void](Rebuild-Database)
    Invalidate-ExeCache
    Log "Удалена папка: $folder"
}

$btnBackup.Add_Click({
    Log "=== Backup ==="
    [void](Do-CreateBackup)
})

$btnHelp.Add_Click({ [void](Show-IntroWindow $false) })

# ---- Автопроверка обновлений ----
function Check-Updates {
    try {
        $lastStr = [string]$cfg.LastUpdateCheck
        if ($lastStr) {
            $last = [datetime]::Parse($lastStr)
            if (((Get-Date) - $last).TotalHours -lt 6) {
                $cachedTag = [string]$cfg.LatestKnownTag
                if ($cachedTag -and (Test-VersionString $cachedTag $AppVersion)) {
                    return @{ Ok = $true; Latest = $cachedTag; Cached = $true; HasUpdate = $true }
                }
                return @{ Ok = $true; Latest = $cachedTag; Cached = $true; HasUpdate = $false }
            }
        }
    } catch { }

    Log "Проверяю обновления на GitHub..."
    $resp = Get-LatestRelease
    if (-not $resp) {
        Log "Не удалось проверить обновления"
        return @{ Ok = $false; Latest = $null; HasUpdate = $false }
    }
    $latestTag = [string]$resp.tag_name
    if ([string]::IsNullOrWhiteSpace($latestTag)) {
        Log "Ответ GitHub без tag_name"
        return @{ Ok = $false; Latest = $null; HasUpdate = $false }
    }

    try {
        $newLastCheck = (Get-Date).ToString("o")
        if ($cfg.LastUpdateCheck -ne $newLastCheck -or $cfg.LatestKnownTag -ne $latestTag) {
            $cfg.LastUpdateCheck = $newLastCheck
            $cfg.LatestKnownTag  = $latestTag
            [void](Save-Config $cfg)
        }
    } catch { }

    $hasUpdate = Test-VersionString $latestTag $AppVersion
    if ($hasUpdate) {
        Log "Доступна новая версия: $latestTag"
    } else {
        Log "Установлена последняя версия ($AppVersion)"
    }
    return @{ Ok = $true; Latest = $latestTag; Url = $resp.html_url; HasUpdate = $hasUpdate }
}

# ---- Drag&Drop ----
$tree.Add_DragEnter({
    param($sender, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    } else {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::None
    }
})
$tree.Add_DragDrop({
    param($sender, $e)
    $paths = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            Add-OneFolder $p
        } else {
            Log "Пропуск (не папка): $p"
        }
    }
})

# ---- Выравнивание ----
function Update-Layout {
    # Все размеры рассчитываются из доступного пространства окна.
    # Это предотвращает уход журнала за нижний край при небольшом экране.
    $w = $form.ClientSize.Width
    $h = $form.ClientSize.Height
    if ($w -lt (Scaled 600) -or $h -lt (Scaled 450)) { return }

    $pad = Scaled 12
    $contentW = [Math]::Max((Scaled 350), $w - 2 * $pad)
    $pnlTop.Width = $w
    $pnlAccent.Width = $w

    $helpW = Scaled 34
    $filterLeft = Scaled 90
    $rightPad = Scaled 14
    $txtMainFilter.Left = $filterLeft
    $txtMainFilter.Width = [Math]::Max((Scaled 180), $w - $filterLeft - $helpW - $rightPad - (Scaled 10))
    $btnHelp.Left = $txtMainFilter.Right + (Scaled 10)
    $btnHelp.Width = $helpW

    $btnAdd.Left = $pad
    $btnRefresh.Left = $btnAdd.Right + (Scaled 10)
    # Keep both action buttons visible at the minimum supported window width.
    $btnRefresh.Width = [Math]::Min((Scaled 190), [Math]::Max((Scaled 140), $contentW - $btnAdd.Width - (Scaled 10)))
    $btnBackup.Left = $pad

    $tree.Left = $pad
    $tree.Width = $contentW
    $lblTreeSection.Left = $pad + (Scaled 2)
    # At narrow widths hide the explanatory text instead of overlapping the heading.
    $lblTreeHint.Visible = ($contentW -gt (Scaled 620))
    $lblTreeHint.Left = [Math]::Min((Scaled 430), [int]($w * 0.49))
    $lblTreeHint.Width = [Math]::Max((Scaled 120), $w - $lblTreeHint.Left - $pad)
    $tree.Top = Scaled 130

    # Журнал получает не менее 110 px, дерево — оставшееся место.
    $minLogH = Scaled 110
    $desiredLogH = Scaled 185
    $logH = [Math]::Max($minLogH, [Math]::Min($desiredLogH, [int]($h * 0.27)))
    $bottomPad = Scaled 12
    $txtLog.Left = $pad
    $txtLog.Width = $contentW
    $txtLog.Height = $logH
    $txtLog.Top = $h - $bottomPad - $logH
    $lblLog.Top = $txtLog.Top - (Scaled 23)
    $lblLogHint.Top = $lblLog.Top
    $btnBackup.Top = $lblLog.Top - (Scaled 51)
    $pnlStats.Left = $pad
    $pnlStats.Top = $btnBackup.Top - (Scaled 54)
    $pnlStats.Width = $contentW
    $lblInfo.Width = [Math]::Max((Scaled 100), $contentW - (Scaled 24))
    $lblLast.Width = $lblInfo.Width
    $tree.Height = [Math]::Max((Scaled 130), $pnlStats.Top - $tree.Top - (Scaled 8))
}

$form.Add_Shown({ Update-Layout })
$form.Add_Resize({ Update-Layout })

# ---- Запуск ----
Rebuild-Tree
Log "Загружено. Папок: $($script:folders.Count), отмечено EXE: $((Count-Selection).Checked)"
Log "Масштаб интерфейса: $($script:UiScale)x (DPI: $($script:DpiScale))"
Log "Автор: $AppAuthor"

$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 2000
$updateTimer.Add_Tick({
    $updateTimer.Stop()
    $updateTimer.Dispose()
    try {
        $res = Check-Updates
        if ($res.Ok -and $res.HasUpdate) {
            $msg = "Доступна новая версия: $($res.Latest)`nУ вас установлена: $AppVersion`n`nОткрыть страницу загрузки?"
            $r = [System.Windows.Forms.MessageBox]::Show($msg, "Есть обновление",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information)
            if ($r -eq "Yes") {
                $url = $res.Url
                if (-not $url) { $url = "https://github.com/$RepoOwner/$RepoName/releases/latest" }
                Start-Process $url
                Log "Открыл страницу релиза"
            }
        }
    } catch { Write-Log "Check-Updates error: $_" }
})
$form.Add_Shown({
    try { $updateTimer.Start() } catch { }
})

Write-Log "Showing main window"
[void]$form.ShowDialog()

if ($script:pendingSave) {
    $script:pendingSave = $false
    Save-State
}

try {
    if ($script:mutex) {
        $script:mutex.ReleaseMutex()
        $script:mutex.Dispose()
    }
} catch { }

Write-Log "=== END ==="
exit 0
