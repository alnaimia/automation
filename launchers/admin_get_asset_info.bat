@echo off
setlocal

REM Switch to the script folder safely, even if UNC path
pushd "%~dp0"

set "script=%~dp0..\scripting\get_asset_info.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process PowerShell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%script%\"'"

REM Return to the original directory and remove the temporary drive
popd

pause
