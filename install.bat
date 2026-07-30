@echo off
rem ============================================================
rem  install.bat - bootstrap launcher for the AI dev environment
rem
rem  Just double-click this file. It will:
rem    1. Re-launch itself with administrator privileges (UAC prompt)
rem    2. Download setup.ps1 from GitHub
rem    3. Run it with the execution policy bypassed
rem
rem  NOTE: This file is intentionally ASCII-only. Batch files are read
rem  using the system ANSI code page (CP932 in Japan), so Japanese text
rem  here would be garbled. All Japanese output comes from setup.ps1,
rem  which is UTF-8 with BOM and renders correctly.
rem ============================================================

setlocal enabledelayedexpansion

set "REPO_URL=https://raw.githubusercontent.com/kouki485/setup_windwos/main/setup.ps1"
set "DEST=%TEMP%\setup.ps1"

echo ============================================================
echo  AI Development Environment Setup
echo ============================================================
echo.

rem ---- Step 1: elevate to administrator if needed ----
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator privileges are required. Showing the UAC prompt...
    echo If a dialog appears, please click "Yes".
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" 2>nul
    if !errorLevel! neq 0 (
        echo.
        echo [ERROR] Could not elevate. Right-click this file and choose
        echo         "Run as administrator" instead.
        echo.
        pause
    )
    exit /b
)

echo [OK] Running with administrator privileges.
echo.

rem ---- Step 2: make sure curl.exe exists (bundled with Win10 1803+) ----
where curl.exe >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] curl.exe was not found. This script requires Windows 10
    echo         version 1803 or later. Please update Windows.
    echo.
    pause
    exit /b 1
)

rem ---- Step 3: download setup.ps1 ----
rem curl is used instead of PowerShell's Invoke-RestMethod because curl
rem writes raw bytes, preserving the UTF-8 BOM that PowerShell 5.1 needs
rem in order to read the Japanese text correctly.
echo Downloading the setup script...
if exist "%DEST%" del /f /q "%DEST%" >nul 2>&1
curl.exe -fsSL -o "%DEST%" "%REPO_URL%"

if not exist "%DEST%" (
    echo.
    echo [ERROR] Download failed. Please check your network connection or
    echo         proxy settings, then try again.
    echo         URL: %REPO_URL%
    echo.
    pause
    exit /b 1
)

rem ---- Step 4: verify the BOM so we fail loudly instead of showing
rem      a wall of confusing PowerShell parser errors ----
powershell -NoProfile -Command ^
  "$b=[System.IO.File]::ReadAllBytes('%DEST%'); if ($b.Length -lt 3 -or $b[0] -ne 239 -or $b[1] -ne 187 -or $b[2] -ne 191) { exit 1 } else { exit 0 }"
if %errorLevel% neq 0 (
    echo.
    echo [ERROR] The downloaded file looks corrupted ^(missing UTF-8 BOM^).
    echo         A proxy or security product may have altered it.
    echo         Please contact your administrator.
    echo.
    pause
    exit /b 1
)

echo [OK] Download verified.
echo.

rem ---- Step 5: run it ----
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%"
set "PS_EXIT=%errorLevel%"

echo.
echo ============================================================
if "%PS_EXIT%"=="0" (
    echo  Finished. See the results above.
) else (
    echo  The script exited with code %PS_EXIT%.
    echo  Check the messages above, then run this file again.
    echo  Re-running is safe: already-installed items are skipped.
)
echo ============================================================
echo.
echo A log was saved to your Desktop as ai-setup-log.txt
echo Please send that file to your administrator if you need help.
echo.
echo Press any key to close this window.
pause >nul
endlocal
