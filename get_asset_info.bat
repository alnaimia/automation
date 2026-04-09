:: ============================================================
:: run.bat  —  Wrapper for get_asset_info.ps1
:: Place .ps1 file in subfolder (e.g. source\) or same folder
:: Script elevated as Administrator inside ps.1
:: ============================================================

@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0source\get_asset_info.ps1"
pause