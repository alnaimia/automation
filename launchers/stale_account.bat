@echo off
setlocal

pushd "%~dp0"
set "script=%~dp0..\scripting\stale_accounts.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%script%"

popd
pause
