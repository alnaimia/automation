@echo off
setlocal
title Stale Account Audit Tool
:: Adjust window size (Width, Height)
mode con: cols=100 lines=30

pushd "%~dp0"
set "script=%~dp0..\scripting\stale_accounts.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%script%"

popd
pause