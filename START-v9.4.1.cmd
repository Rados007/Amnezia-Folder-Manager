@echo off
setlocal
set "SCRIPT=%~dp0Amnezia-Folder-Manager-v9.4.1.ps1"
if not exist "%SCRIPT%" (
  echo PowerShell script not found: "%SCRIPT%"
  pause
  exit /b 1
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo Windows PowerShell 5.1 was not found.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo Program exited with error code %RC%.
  pause
)
exit /b %RC%
