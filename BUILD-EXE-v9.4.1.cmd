@echo off
setlocal
cd /d "%~dp0"
set "BUILDER=%~dp0BUILD-EXE-v9.4.1.ps1"
if not exist "%BUILDER%" (
    echo ERROR: Builder script not found: "%BUILDER%"
    pause
    exit /b 1
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows PowerShell 5.1 not found.
    pause
    exit /b 1
)
echo Building Amnezia Folder Manager v9.4.1...
echo The ps2exe module may need to be installed from PowerShell Gallery.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%BUILDER%" -InstallPS2EXE
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
    echo BUILD FAILED. Exit code: %RC%
) else (
    echo Build completed. Check this folder for Amnezia-Folder-Manager-v9.4.1.exe
)
pause
exit /b %RC%
