@echo off
setlocal

pushd "%~dp0"
set "script=%CD%\source\stale_accounts.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%script%"

popd
pause
