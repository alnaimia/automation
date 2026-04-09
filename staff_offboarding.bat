@echo off
setlocal

REM Switch to the script folder safely, even if UNC path
pushd "%~dp0"

REM Now the current directory is mapped to a drive letter, so use %CD% to get the full path
set "script=%CD%\source\ad_disable_staff_account.ps1"

powershell -NoProfile -ExecutionPolicy Bypass ^
    "Start-Process PowerShell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File ""%script%""'"

REM Return to the original directory and remove the temporary drive
popd

pause
