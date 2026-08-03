@echo off
rem ============================================================
rem  Start_Windows.bat - local launcher for the extracted package
rem
rem  Double-click this file after unzipping. It runs the bundled
rem  windows\setup.ps1 (no GitHub download required).
rem
rem  ASCII-only on purpose: batch files are read with the system
rem  ANSI code page (CP932 in Japan). Japanese text comes from
rem  setup.ps1 (UTF-8 with BOM).
rem ============================================================

setlocal

set "ROOT=%~dp0"
set "SETUP=%ROOT%windows\setup.ps1"
set "SETUP_AI_DEST=%SETUP%"

echo ============================================================
echo  AI Development Environment Setup (Windows)
echo ============================================================
echo.

if not exist "%SETUP%" (
    echo [ERROR] windows\setup.ps1 was not found.
    echo         Please unzip the whole folder, then double-click
    echo         this file again from inside that folder.
    echo.
    pause
    exit /b 1
)

rem Verify UTF-8 BOM so PowerShell 5.1 reads Japanese correctly.
powershell -NoProfile -Command ^
  "$b=[System.IO.File]::ReadAllBytes($env:SETUP_AI_DEST); if ($b.Length -lt 3 -or $b[0] -ne 239 -or $b[1] -ne 187 -or $b[2] -ne 191) { exit 1 } else { exit 0 }"
if %errorLevel% neq 0 (
    echo [ERROR] windows\setup.ps1 looks corrupted ^(missing UTF-8 BOM^).
    echo         Please re-download and unzip the package.
    echo.
    pause
    exit /b 1
)

echo [OK] Found bundled setup script.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SETUP%"
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
endlocal & exit /b %PS_EXIT%
