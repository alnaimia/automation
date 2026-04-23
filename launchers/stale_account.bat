@echo off
setlocal
title Stale Account Audit Tool

:: Adjust window size for better readability of table data
mode con: cols=120 lines=40

REM Switch to the launcher folder
pushd "%~dp0"

REM Define path to the script
set "script=%~dp0..\scripting\stale_accounts.ps1"

echo ---------------------------------------------------------
echo  Running Stale Account Audit...
echo  Directory: %~dp0
echo ---------------------------------------------------------
echo.

REM Run the script directly.
powershell -NoProfile -ExecutionPolicy Bypass -File "%script%"

echo.
echo ---------------------------------------------------------
echo  Audit Complete.
echo ---------------------------------------------------------

REM Return to original directory
popd
pause