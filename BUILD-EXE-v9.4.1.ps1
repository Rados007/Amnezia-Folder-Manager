#Requires -Version 5.1
# Run on Windows PowerShell 5.1 (not PowerShell 7), in this folder.
param([switch]$InstallPS2EXE)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $root 'Amnezia-Folder-Manager-v9.4.1.ps1'
$target = Join-Path $root 'Amnezia-Folder-Manager-v9.4.1.exe'
if (-not (Test-Path -LiteralPath $source)) { throw "Missing source: $source" }
# Validate parser errors BEFORE attempting EXE compilation.
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Error $_.ToString() }
    throw 'PowerShell source contains syntax errors. EXE build aborted.'
}
Write-Host 'PowerShell syntax: OK' -ForegroundColor Green
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    if (-not $InstallPS2EXE) {
        throw 'Module ps2exe is missing. Install it separately with Install-Module ps2exe -Scope CurrentUser, or rerun BUILD-EXE-v9.4.1.ps1 -InstallPS2EXE.'
    }
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe -ErrorAction Stop
$params = @{
    inputFile = $source
    outputFile = $target
    noConsole = $true
    STA = $true
    title = 'Amnezia Folder Manager'
    product = 'Amnezia Folder Manager'
    version = '9.4.1.0'
    description = 'Folder-based application list manager for AmneziaVPN'
}
$ico = Join-Path $root 'icon.ico'
if (Test-Path -LiteralPath $ico) { $params.iconFile = $ico }
Invoke-ps2exe @params
if (-not (Test-Path -LiteralPath $target)) { throw 'Compiler did not produce the expected executable.' }
Write-Host "EXE created: $target" -ForegroundColor Green
Write-Host 'IMPORTANT: Test UI, config persistence, backup and actual import into AmneziaVPN before distribution.'
