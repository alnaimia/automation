@echo off
:: Set your server name or IP here
SET SERVER=your-internal-server.domain.com

:: deletes "S:" drive - confirm y
net use S: /del /y 2>nul

:: Remap the network drive using the variable
net use S: \\%SERVER%\Shared /persistent:Yes

