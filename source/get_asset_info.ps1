# ============================================================
# get_asset_info.ps1
# Collects hardware/software info and writes to log.txt
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

# ---- Paths (log goes to parent folder, not /source) ----
$RootDir = Split-Path -Parent $PSScriptRoot
$LogFile = Join-Path $RootDir "log.txt"

# ---- Gather data -------------------------------------------
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = Get-CimInstance Win32_Processor
$ram  = Get-CimInstance Win32_PhysicalMemory
$disk = Get-CimInstance Win32_DiskDrive

$nics = Get-CimInstance Win32_NetworkAdapterConfiguration |
        Where-Object { $_.MACAddress }

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
    $size = if ($_.Size) {
        [math]::Round($_.Size / 1GB, 0)
    } else {
        "Unknown"
    }

    $media = if ($_.MediaType) {
        $_.MediaType
    } else {
        "Unknown"
    }

    "$size GB ($media - $($_.Model))"
}

# ---- Network adapters --------------------------------------
$wifi = $nics |
    Where-Object { $_.Description -match "Wi-Fi|Wireless|802\.11" } |
    Select-Object -First 1

$lan = $nics |
    Where-Object {
        $_.Description -match "Ethernet|LAN" -and
        $_.Description -notmatch "Virtual|Hyper-V|vEthernet"
    } |
    Select-Object -First 1

# ---- Build log output --------------------------------------
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$separator = "=" * 50

$storageFormatted = ($storageList | ForEach-Object { "  $_" }) -join "`n"

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

WiFi MAC      : $(if ($wifi) { $wifi.MACAddress } else { "N/A" })
LAN  MAC      : $(if ($lan)  { $lan.MACAddress  } else { "N/A" })

$separator
"@

# ---- Write to file -----------------------------------------
Add-Content -Path $LogFile -Value $output -Encoding UTF8

Write-Host ""
Write-Host "Done. Log saved to: $LogFile"
Write-Host ""