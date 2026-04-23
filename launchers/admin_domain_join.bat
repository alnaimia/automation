@echo off
setlocal

REM Switch to the script folder safely, even if UNC path
pushd "%~dp0"

REM Define the relative path to the PS1 script
set "script=%~dp0..\scripting\domain_join.ps1"

echo Requesting elevation and running script...

REM Launch PowerShell elevated and pass the file path
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process PowerShell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%script%\"'"

REM Return to the original directory and remove the temporary drive
popd

pause