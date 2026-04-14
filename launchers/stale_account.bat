@echo off
setlocal

pushd "%~dp0"
set "script=%~dp0..\source\stale_accounts.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%script%"

popd
pause
