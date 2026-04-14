:: ============================================================
:: run.bat  —  Wrapper for get_asset_info.ps1
:: Place .ps1 file in subfolder (e.g. source\) or same folder
:: Script elevated as Administrator inside ps.1
:: ============================================================


@echo off
setlocal

:: 1. Map the UNC path to a temporary drive letter
pushd "%~dp0"

:: 2. Identify the script path (using the drive letter from pushd)
set "script=%~dp0..\scripting\get_asset_info.ps1"

:: 3. Run PowerShell as Admin
powershell -NoProfile -ExecutionPolicy Bypass ^
    "Start-Process PowerShell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%script%""'"

:: 4. Unmap the drive and return
popd

echo.
echo Launch process complete.
pause
