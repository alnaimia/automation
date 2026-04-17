# ============================================================
# get_asset_info.ps1
# Collects hardware/software info and writes to log_files directory
# Self-elevates to Administrator if needed
# ============================================================

# ---- Self-elevate to Administrator ----
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Restarting with administrative privileges..."
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

# ---- Logging Setup ----
$LogDir    = Join-Path (Split-Path $PSScriptRoot -Parent) "log_files"
$DateStamp = Get-Date -Format "yyyy-MM-dd"
$LogFile   = Join-Path $LogDir "asset_info_$DateStamp.log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# ---- Gather data -------------------------------------------
Write-Progress -Activity "Collecting asset information" -Status "Please wait..." -PercentComplete -1

$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = Get-CimInstance Win32_Processor
$ram  = Get-CimInstance Win32_PhysicalMemory
$disk = Get-CimInstance Win32_DiskDrive

Write-Progress -Activity "Collecting asset information" -Completed

# ---- Screen size -------------------------------------------
$monitor = Get-CimInstance WmiMonitorBasicDisplayParams `
            -Namespace root\wmi `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

$screenInch = if ($monitor) {
    $w = $monitor.MaxHorizontalImageSize / 2.54
    $h = $monitor.MaxVerticalImageSize   / 2.54
    "$([math]::Round([math]::Sqrt($w*$w + $h*$h), 1)) in"
} else {
    "N/A"
}

# ---- CPU ---------------------------------------------------
$cpuName = ($cpu | Select-Object -First 1).Name

# ---- RAM total ---------------------------------------------
$ramGB = [math]::Round(
    ($ram | Measure-Object Capacity -Sum).Sum / 1GB, 0
)

# ---- Storage -----------------------------------------------
$storageList = $disk | ForEach-Object {
    $size  = if ($_.Size)      { [math]::Round($_.Size / 1GB, 0) } else { "Unknown" }
    $media = if ($_.MediaType) { $_.MediaType }                    else { "Unknown"  }
    "$size GB ($media - $($_.Model))"
}

# ---- Network adapters --------------------------------------
$physicalPCI = Get-CimInstance Win32_NetworkAdapter | Where-Object {
    $_.PhysicalAdapter -eq $true -and
    $_.MACAddress                -and
    $_.PNPDeviceID -like "PCI\*"
}

$wifiAdapter = $physicalPCI | Where-Object {
    $_.Name -match "Wi-Fi|Wireless|802\.11|WLAN"
} | Select-Object -First 1

$lanAdapter = $physicalPCI | Where-Object {
    $_.Name -notmatch "Wi-Fi|Wireless|802\.11|WLAN"
} | Select-Object -First 1

$wifiMAC = if ($wifiAdapter) { $wifiAdapter.MACAddress } else { "N/A" }
$lanMAC  = if ($lanAdapter)  { $lanAdapter.MACAddress  } else { "N/A (no built-in LAN port detected)" }

# ---- Build log output --------------------------------------
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$separator = "=" * 50
$storageFormatted = ($storageList | ForEach-Object { "   $_" }) -join "`n"

$output = @"
$separator
ASSET INFORMATION LOG
Captured: $timestamp
$separator

Laptop Name   : $($cs.Name)
Make          : $($cs.Manufacturer)
Model         : $($cs.Model)
Serial / Tag  : $($bios.SerialNumber)

Screen Size   : $screenInch
OS            : $($os.Caption) (Build $($os.BuildNumber))

Processor     : $cpuName
RAM           : $ramGB GB
Storage       :
$storageFormatted

WiFi MAC      : $wifiMAC
LAN  MAC      : $lanMAC

$separator
"@

# ---- Write to file & Display -------------------------------
Add-Content -Path $LogFile -Value $output -Encoding UTF8

Write-Host $output 
Write-Host ""
Write-Host "Done! Results appended to: $LogFile"
Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Yellow
$null = Read-Host
