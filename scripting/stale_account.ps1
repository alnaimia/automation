# =============================================================================
# Stale Account Detection Script
# Audits login activity and outputs to clean, copy-pasteable paths.
# =============================================================================

Import-Module ActiveDirectory

# -----------------------------
# Config & Paths
# -----------------------------
$InactivityThresholdDays = 90

# 1. Resolve Paths
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ParentDir = (Get-Item $ScriptDir).Parent.FullName
$LogDir    = Join-Path $ParentDir "log_files"

# Ensure the log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$DateStamp = Get-Date -Format "yyyy-MM-dd"
$LogFile   = Join-Path $LogDir "stale_accounts_$DateStamp.log"
$CsvFile   = Join-Path $LogDir "stale_accounts_$DateStamp.csv"

# OUs to scan (Adjust these to your specific AD structure)
$TargetOUs = @(
    "OU=Staff,DC=add_company,DC=ac,DC=uk",
    "OU=Students,DC=add_company,DC=ac,DC=uk"
)

# -----------------------------
# Helper Functions
# -----------------------------

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$timestamp - $Message"
}

function Get-StaleUsers {
    param([Parameter(Mandatory)][string]$SearchBase)
    $thresholdDate = (Get-Date).AddDays(-$InactivityThresholdDays)

    Get-ADUser -Filter * `
        -SearchBase $SearchBase `
        -Properties Enabled, LastLogonDate, Description, DistinguishedName |
    Where-Object {
        ($null -eq $_.LastLogonDate) -or
        ($_.LastLogonDate -lt $thresholdDate)
    }
}

# -----------------------------
# Main Workflow
# -----------------------------

Clear-Host
Write-Host "--- Active Directory Stale Account Audit ---" -ForegroundColor Cyan
Write-Host "Threshold: $InactivityThresholdDays days"
Write-Log "===== Stale Account Scan Started ====="

$CutoffDate = (Get-Date).AddDays(-$InactivityThresholdDays).ToString("yyyy-MM-dd")
$CsvRows = [System.Collections.Generic.List[PSObject]]::new()

foreach ($ou in $TargetOUs) {
    Write-Host "Scanning: $ou... " -NoNewline
    Write-Log "Scanning OU: $ou"

    try {
        $staleUsers = @(Get-StaleUsers -SearchBase $ou)
        
        if ($staleUsers.Count -eq 0) {
            Write-Host "Done (0 found)" -ForegroundColor Gray
            Write-Log "No stale accounts found in $ou"
        } else {
            Write-Host "Done ($($staleUsers.Count) found)" -ForegroundColor Yellow
            Write-Log "Found $($staleUsers.Count) stale account(s) in $ou"
        }
    }
    catch {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Log "ERROR scanning OU: $ou | $_"
        continue
    }

    foreach ($user in $staleUsers) {
        # Determine Login Status
        $neverLoggedIn    = ($null -eq $user.LastLogonDate)
        $lastLogonClean   = if ($neverLoggedIn) { "" } else { $user.LastLogonDate }
        $lastLogonDisplay = if ($neverLoggedIn) { "Never Logged In" } else { $user.LastLogonDate }
        $desc             = if ($user.Description) { $user.Description } else { "No description" }

        # Audit Trail for the .txt file
        Write-Log "STALE: $($user.SamAccountName) | Enabled: $($user.Enabled) | LastLogon: $lastLogonDisplay | Desc: $desc"

        # Data for the .csv file
        $CsvRows.Add([PSCustomObject]@{
            SamAccountName    = $user.SamAccountName
            Enabled           = $user.Enabled
            NeverLoggedIn     = $neverLoggedIn
            LastLogonDate     = $lastLogonClean
            Description       = $desc
            DistinguishedName = $user.DistinguishedName
            OU                = $ou
            ScanCutoffDate    = $CutoffDate
        })
    }
}

# -----------------------------
# Export and Summary
# -----------------------------

Write-Host "`nScan Complete!" -ForegroundColor Cyan

if ($CsvRows.Count -gt 0) {
    $CsvRows | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8 -Append
    
    Write-Host "Total stale accounts found: " -NoNewline
    Write-Host "$($CsvRows.Count)" -ForegroundColor Yellow
    
    Write-Host "CSV Result: " -NoNewline
    Write-Host "$CsvFile" -ForegroundColor White
} else {
    Write-Host "No stale accounts detected across all OUs." -ForegroundColor Green
    Write-Log "No stale accounts found in this run."
}

Write-Host "Log file:   " -NoNewline
Write-Host "$LogFile" -ForegroundColor Gray

Write-Log "===== Stale Account Scan Complete | Total Found: $($CsvRows.Count) ====="

Write-Host "`nPress Enter to exit..." -ForegroundColor Cyan
$null = Read-Host
